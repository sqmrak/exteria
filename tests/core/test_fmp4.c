#include "test_util.h"
#include "exteria_fmp4.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
} bytes;

static void put(bytes *b, const void *p, size_t n) {
    if (b->len + n > b->cap) {
        b->cap = (b->len + n) * 2 + 64;
        b->data = realloc(b->data, b->cap);
    }
    memcpy(b->data + b->len, p, n);
    b->len += n;
}

static void u32(bytes *b, uint32_t v) {
    uint8_t x[4] = {(uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v};
    put(b, x, 4);
}

static void zeros(bytes *b, size_t n) {
    uint8_t z[64] = {0};
    while (n) {
        size_t k = n > sizeof(z) ? sizeof(z) : n;
        put(b, z, k);
        n -= k;
    }
}

static size_t open_box(bytes *b, const char *type) {
    size_t at = b->len;
    u32(b, 0);
    put(b, type, 4);
    return at;
}

static void close_box(bytes *b, size_t at) {
    uint32_t size = (uint32_t)(b->len - at);
    b->data[at] = (uint8_t)(size >> 24);
    b->data[at + 1] = (uint8_t)(size >> 16);
    b->data[at + 2] = (uint8_t)(size >> 8);
    b->data[at + 3] = (uint8_t)size;
}

/* one track of the init segment, with the empty tables a fragmented file has */
static void init_track(bytes *b, uint32_t id, uint32_t timescale) {
    size_t trak = open_box(b, "trak"), x, mdia, minf, stbl;
    x = open_box(b, "tkhd"); u32(b, 0); u32(b, 0); u32(b, 0); u32(b, id); u32(b, 0); u32(b, 0); zeros(b, 60); close_box(b, x);
    mdia = open_box(b, "mdia");
    x = open_box(b, "mdhd"); u32(b, 0); u32(b, 0); u32(b, 0); u32(b, timescale); u32(b, 0); u32(b, 0); close_box(b, x);
    x = open_box(b, "hdlr"); zeros(b, 24); close_box(b, x);
    minf = open_box(b, "minf");
    stbl = open_box(b, "stbl");
    x = open_box(b, "stsd"); u32(b, 0); u32(b, 1); u32(b, 16); put(b, "avc1", 4); zeros(b, 8); close_box(b, x);
    x = open_box(b, "stts"); u32(b, 0); u32(b, 0); close_box(b, x);
    x = open_box(b, "stsc"); u32(b, 0); u32(b, 0); close_box(b, x);
    x = open_box(b, "stsz"); u32(b, 0); u32(b, 0); u32(b, 0); close_box(b, x);
    x = open_box(b, "stco"); u32(b, 0); u32(b, 0); close_box(b, x);
    close_box(b, stbl);
    close_box(b, minf);
    close_box(b, mdia);
    close_box(b, trak);
}

static void init_trex(bytes *b, uint32_t id) {
    size_t x = open_box(b, "trex");
    u32(b, 0); u32(b, id); u32(b, 1); u32(b, 512); u32(b, 0); u32(b, 0x00010000u);
    close_box(b, x);
}

static void ftyp_box(bytes *b) {
    size_t x = open_box(b, "ftyp");
    put(b, "isom", 4); u32(b, 0); put(b, "isom", 4); put(b, "iso6", 4);
    close_box(b, x);
}

static void init_segment(bytes *b, const char *moov_name) {
    size_t moov = open_box(b, moov_name), x, mvex;
    x = open_box(b, "mvhd"); u32(b, 0); u32(b, 0); u32(b, 0); u32(b, 1000); u32(b, 0); zeros(b, 80); close_box(b, x);
    init_track(b, 1, 12800);
    init_track(b, 2, 44100);
    mvex = open_box(b, "mvex");
    init_trex(b, 1);
    init_trex(b, 2);
    close_box(b, mvex);
    close_box(b, moov);
}

/* a run of samples: sizes, each sample filled with its own byte; video has delays and only the first sample is a sync point */
typedef struct {
    uint32_t track;
    uint32_t count;
    const uint32_t *sizes;
    uint8_t fill;
    int video;
    int data_offset_flag;
    int32_t data_offset_extra;
} run;

static void write_trun(bytes *b, const run *r, uint32_t data_offset) {
    size_t x = open_box(b, "trun");
    uint32_t i;
    u32(b, (r->data_offset_flag ? 0x000f01u : 0x000f00u));
    u32(b, r->count);
    if (r->data_offset_flag) u32(b, data_offset + (uint32_t)r->data_offset_extra);
    for (i = 0; i < r->count; ++i) {
        u32(b, r->video ? 512u : 1024u);
        u32(b, r->sizes[i]);
        u32(b, r->video && i ? 0x00010000u : 0u);
        u32(b, r->video ? (i % 2) * 256u : 0u);
    }
    close_box(b, x);
}

/* a moof of several trafs, each with the runs given, and the mdat that follows with the bytes of every sample; the offsets are relative to the moof */
static void fragment(bytes *b, const run *runs, size_t nruns) {
    bytes moof = {0};
    size_t pass, i, x, mfhd;
    uint32_t moof_size = 0;
    for (pass = 0; pass < 2; ++pass) {
        uint32_t cursor = moof_size + 8;
        moof.len = 0;
        x = open_box(&moof, "moof");
        mfhd = open_box(&moof, "mfhd"); u32(&moof, 0); u32(&moof, 1); close_box(&moof, mfhd);
        for (i = 0; i < nruns; ++i) {
            size_t traf = open_box(&moof, "traf"), tfhd = open_box(&moof, "tfhd"), tfdt;
            uint32_t j, total = 0;
            u32(&moof, 0x020000u); u32(&moof, runs[i].track);
            close_box(&moof, tfhd);
            tfdt = open_box(&moof, "tfdt"); u32(&moof, 0); u32(&moof, 0); close_box(&moof, tfdt);
            write_trun(&moof, &runs[i], cursor);
            for (j = 0; j < runs[i].count; ++j) total += runs[i].sizes[j];
            cursor += total;
            close_box(&moof, traf);
        }
        close_box(&moof, x);
        moof_size = (uint32_t)moof.len;
    }
    put(b, moof.data, moof.len);
    free(moof.data);
    x = open_box(b, "mdat");
    for (i = 0; i < nruns; ++i) {
        uint32_t j;
        for (j = 0; j < runs[i].count; ++j) {
            uint32_t k;
            for (k = 0; k < runs[i].sizes[j]; ++k) {
                uint8_t v = (uint8_t)(runs[i].fill + j);
                put(b, &v, 1);
            }
        }
    }
    close_box(b, x);
}

static int write_file(const char *path, const bytes *b) {
    int ok;
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    ok = fwrite(b->data, 1, b->len, f) == b->len;
    return fclose(f) == 0 && ok;
}

static uint8_t *read_file(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    uint8_t *data;
    long size;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    data = malloc((size_t)size + 1);
    if (fread(data, 1, (size_t)size, f) != (size_t)size) { fclose(f); free(data); return NULL; }
    fclose(f);
    *len = (size_t)size;
    return data;
}

static uint32_t rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3]; }

/* the first child box of that type inside [from, to) of d; returns its start or SIZE_MAX */
static size_t child(const uint8_t *d, size_t from, size_t to, const char *type, size_t *end) {
    size_t p = from;
    while (p + 8 <= to) {
        uint32_t size = rd32(d + p);
        if (size < 8 || p + size > to) return SIZE_MAX;
        if (!memcmp(d + p + 4, type, 4)) { if (end) *end = p + size; return p; }
        p += size;
    }
    return SIZE_MAX;
}

typedef struct {
    uint32_t count;
    uint32_t offset[16];
    uint32_t size[16];
    uint32_t duration_total;
    uint32_t mdhd_duration;
    uint32_t tkhd_duration;
    uint32_t sync_count;
    int has_stss;
    int has_ctts;
} table;

static int read_track(const uint8_t *d, size_t len, uint32_t track_id, table *t) {
    size_t moov_end = 0, moov = child(d, 0, len, "moov", &moov_end), p, trak_end = 0, trak, tkhd_end = 0, tkhd;
    memset(t, 0, sizeof(*t));
    if (moov == SIZE_MAX) return 0;
    p = moov + 8;
    for (;;) {
        trak = child(d, p, moov_end, "trak", &trak_end);
        if (trak == SIZE_MAX) return 0;
        tkhd = child(d, trak + 8, trak_end, "tkhd", &tkhd_end);
        if (tkhd != SIZE_MAX && rd32(d + tkhd + 8 + 12) == track_id) break;
        p = trak_end;
    }
    {
        size_t mdia_end = 0, mdia = child(d, trak + 8, trak_end, "mdia", &mdia_end);
        size_t mdhd = child(d, mdia + 8, mdia_end, "mdhd", NULL);
        size_t minf_end = 0, minf = child(d, mdia + 8, mdia_end, "minf", &minf_end);
        size_t stbl_end = 0, stbl = child(d, minf + 8, minf_end, "stbl", &stbl_end);
        size_t stts = child(d, stbl + 8, stbl_end, "stts", NULL), stsc = child(d, stbl + 8, stbl_end, "stsc", NULL);
        size_t stsz = child(d, stbl + 8, stbl_end, "stsz", NULL), stco = child(d, stbl + 8, stbl_end, "stco", NULL);
        size_t stss = child(d, stbl + 8, stbl_end, "stss", NULL), ctts = child(d, stbl + 8, stbl_end, "ctts", NULL);
        uint32_t runs, i, n, sample = 0, chunk, chunks;
        t->tkhd_duration = rd32(d + tkhd + 8 + 20);
        t->mdhd_duration = rd32(d + mdhd + 8 + 16);
        t->has_stss = stss != SIZE_MAX;
        t->has_ctts = ctts != SIZE_MAX;
        if (t->has_stss) t->sync_count = rd32(d + stss + 12);
        runs = rd32(d + stts + 12);
        for (i = 0; i < runs; ++i) t->duration_total += rd32(d + stts + 16 + i * 8) * rd32(d + stts + 20 + i * 8);
        t->count = rd32(d + stsz + 16);
        for (i = 0; i < t->count && i < 16; ++i) t->size[i] = rd32(d + stsz + 20 + i * 4);
        chunks = rd32(d + stco + 12);
        runs = rd32(d + stsc + 12);
        for (chunk = 1; chunk <= chunks; ++chunk) {
            uint32_t per = 0, off = rd32(d + stco + 16 + (chunk - 1) * 4);
            for (i = 0; i < runs; ++i) if (rd32(d + stsc + 16 + i * 12) <= chunk) per = rd32(d + stsc + 20 + i * 12);
            for (n = 0; n < per && sample < 16; ++n) {
                t->offset[sample] = off;
                off += t->size[sample];
                ++sample;
            }
        }
    }
    return 1;
}

static void temp_path(char *path, size_t cap, const char *tag) {
    snprintf(path, cap, "/tmp/exteria-fmp4-%s-%d", tag, (int)getpid());
}

static void check_samples(const uint8_t *d, size_t len, const table *t, const uint32_t *sizes, uint32_t count, const uint8_t *fills) {
    uint32_t i, k;
    CHECK_EQ_INT(t->count, count);
    for (i = 0; i < count && i < 16; ++i) {
        CHECK_EQ_INT(t->size[i], sizes[i]);
        CHECK(t->offset[i] + t->size[i] <= len);
        for (k = 0; k < sizes[i] && t->offset[i] + k < len; ++k) {
            if (d[t->offset[i] + k] != fills[i]) { CHECK(d[t->offset[i] + k] == fills[i]); break; }
        }
    }
}

static const uint32_t video1[3] = {10, 20, 30}, audio1[2] = {5, 6}, video2a[1] = {7}, video2b[1] = {8}, audio2[1] = {9};

static void build_file(bytes *file, const char *moov_name) {
    run first[2] = {{1, 3, video1, 0x10, 1, 1, 0}, {2, 2, audio1, 0x40, 0, 1, 0}};
    run second[3] = {{1, 1, video2a, 0x20, 1, 1, 0}, {1, 1, video2b, 0x30, 1, 1, 0}, {2, 1, audio2, 0x50, 0, 1, 0}};
    memset(file, 0, sizeof(*file));
    ftyp_box(file);
    init_segment(file, moov_name);
    fragment(file, first, 2);
    fragment(file, second, 3);
}

static void test_remux(const char *moov_name) {
    bytes file;
    char in[128], out[128];
    uint8_t *result;
    size_t len = 0;
    table video, audio;
    static const uint8_t video_fill[5] = {0x10, 0x11, 0x12, 0x20, 0x30}, audio_fill[3] = {0x40, 0x41, 0x50};
    static const uint32_t video_sizes[5] = {10, 20, 30, 7, 8}, audio_sizes[3] = {5, 6, 9};
    temp_path(in, sizeof(in), "in");
    temp_path(out, sizeof(out), "out");
    build_file(&file, moov_name);
    CHECK(write_file(in, &file));
    CHECK_EQ_INT(exteria_fmp4_scan(in), EXTERIA_OK);
    CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_OK);
    result = read_file(out, &len);
    CHECK(result != NULL);
    if (result) {
        /* the plain form: the file type, the movie box with its tables and the one mdat */
        CHECK(!memcmp(result + 4, "ftyp", 4));
        CHECK(read_track(result, len, 1, &video));
        CHECK(read_track(result, len, 2, &audio));
        check_samples(result, len, &video, video_sizes, 5, video_fill);
        check_samples(result, len, &audio, audio_sizes, 3, audio_fill);
        /* the lengths, which the fragments left at zero: 5 x 512 at 12800 and 3 x 1024 at 44100, the movie at 1000 */
        CHECK_EQ_INT(video.mdhd_duration, 2560);
        CHECK_EQ_INT(video.duration_total, 2560);
        CHECK_EQ_INT(video.tkhd_duration, 200);
        CHECK_EQ_INT(audio.mdhd_duration, 3072);
        CHECK_EQ_INT(audio.tkhd_duration, 69);
        /* video has non sync samples and picture delays, audio has neither; the first sample of each of the three runs of video is a sync point */
        CHECK(video.has_stss && video.has_ctts);
        CHECK_EQ_INT(video.sync_count, 3);
        CHECK(!audio.has_stss && !audio.has_ctts);
        /* no moof is left, and the file is one mdat after the movie box */
        CHECK(exteria_fmp4_scan(out) == EXTERIA_E_NOTFOUND);
        {
            size_t mdat = child(result, 0, len, "mdat", NULL);
            CHECK(mdat != SIZE_MAX);
            if (mdat != SIZE_MAX) {
                CHECK_EQ_INT(rd32(result + mdat), 8 + 10 + 20 + 30 + 7 + 8 + 5 + 6 + 9);
                CHECK_EQ_INT(mdat + rd32(result + mdat), len);
            }
        }
    }
    free(result);
    free(file.data);
    unlink(in);
    unlink(out);
}

static void test_refusals(void) {
    bytes file;
    char in[128], out[128];
    size_t cut;
    temp_path(in, sizeof(in), "bad");
    temp_path(out, sizeof(out), "badout");
    /* not fragmented: a movie box and an mdat only */
    {
        bytes plain = {0};
        size_t mdat;
        ftyp_box(&plain);
        init_segment(&plain, "moov");
        mdat = open_box(&plain, "mdat"); zeros(&plain, 100); close_box(&plain, mdat);
        CHECK(write_file(in, &plain));
        CHECK_EQ_INT(exteria_fmp4_scan(in), EXTERIA_E_NOTFOUND);
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_NOTFOUND);
        CHECK(access(out, F_OK) != 0);
        free(plain.data);
    }
    build_file(&file, "moov");
    /* cut in the middle of a box, at several places: never a crash, and no output left */
    for (cut = 1; cut < file.len; cut += 7) {
        bytes part = file;
        exteria_status status;
        part.len = cut;
        CHECK(write_file(in, &part));
        status = exteria_fmp4_remux(in, out);
        if (status != EXTERIA_OK) CHECK(access(out, F_OK) != 0);
        unlink(out);
    }
    /* a run that points past the end of the file */
    {
        bytes bad = {0};
        run r = {1, 1, video2a, 0x20, 1, 1, 100000};
        ftyp_box(&bad);
        init_segment(&bad, "moov");
        fragment(&bad, &r, 1);
        CHECK(write_file(in, &bad));
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        free(bad.data);
    }
    /* a run that points before the start of the file */
    {
        bytes bad = {0};
        run r = {1, 1, video2a, 0x20, 1, 1, -100000};
        ftyp_box(&bad);
        init_segment(&bad, "moov");
        fragment(&bad, &r, 1);
        CHECK(write_file(in, &bad));
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_MALFORMED);
        free(bad.data);
    }
    /* a fragment of a track that the movie box does not have */
    {
        bytes bad = {0};
        run r = {9, 1, video2a, 0x20, 1, 1, 0};
        ftyp_box(&bad);
        init_segment(&bad, "moov");
        fragment(&bad, &r, 1);
        CHECK(write_file(in, &bad));
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_MALFORMED);
        free(bad.data);
    }
    /* a fragment before the movie box */
    {
        bytes bad = {0};
        run r = {1, 1, video2a, 0x20, 1, 1, 0};
        ftyp_box(&bad);
        fragment(&bad, &r, 1);
        init_segment(&bad, "moov");
        CHECK(write_file(in, &bad));
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_UNSUPPORTED);
        free(bad.data);
    }
    /* a count of samples that the box cannot hold */
    {
        bytes bad = {0};
        run r = {1, 1, video2a, 0x20, 1, 1, 0};
        size_t at;
        ftyp_box(&bad);
        init_segment(&bad, "moov");
        fragment(&bad, &r, 1);
        /* the sample count of the only trun is the second word after its tag */
        for (at = 0; at + 16 < bad.len; ++at) {
            if (!memcmp(bad.data + at + 4, "trun", 4)) { bad.data[at + 12] = 0x7f; break; }
        }
        CHECK(write_file(in, &bad));
        CHECK_EQ_INT(exteria_fmp4_remux(in, out), EXTERIA_E_MALFORMED);
        free(bad.data);
    }
    /* arguments */
    CHECK_EQ_INT(exteria_fmp4_remux(NULL, out), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_fmp4_remux(in, in), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_fmp4_remux("/nonexistent/exteria-fmp4", out), EXTERIA_E_IO);
    CHECK_EQ_INT(exteria_fmp4_scan("/nonexistent/exteria-fmp4"), EXTERIA_E_IO);
    free(file.data);
    unlink(in);
    unlink(out);
}

int main(void) {
    test_remux("moov");
    test_remux("hoov");
    test_refusals();
    return test_finish("test_fmp4");
}
