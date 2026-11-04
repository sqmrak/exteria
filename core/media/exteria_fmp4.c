#include "exteria_fmp4.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* the largest init segment and fragment header that are read into memory; real ones are a few kilobytes to a few hundred */
#define FMP4_MOOV_MAX (32u * 1024u * 1024u)
#define FMP4_MOOF_MAX (8u * 1024u * 1024u)
#define FMP4_FTYP_MAX 65536u
/* bounds of what the tables may hold: a sample is 16 bytes in memory and four in the file */
#define FMP4_SAMPLES_MAX 1000000u
#define FMP4_CHUNKS_MAX 262144u
#define FMP4_TRACKS_MAX 8u
#define FMP4_BOXES_MAX 4000000u
#define FMP4_OUT_MOOV_MAX (64u * 1024u * 1024u)
#define FMP4_COPY_BLOCK 65536u

#define FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))
#define BOX_FTYP FOURCC('f', 't', 'y', 'p')
/* some streams of the Telegram servers name the movie box hoov; it has the layout of a moov, as the first tweak for this found */
#define BOX_MOOV FOURCC('m', 'o', 'o', 'v')
#define BOX_HOOV FOURCC('h', 'o', 'o', 'v')
#define BOX_MOOF FOURCC('m', 'o', 'o', 'f')
#define BOX_MVHD FOURCC('m', 'v', 'h', 'd')
#define BOX_MVEX FOURCC('m', 'v', 'e', 'x')
#define BOX_TREX FOURCC('t', 'r', 'e', 'x')
#define BOX_TRAK FOURCC('t', 'r', 'a', 'k')
#define BOX_TKHD FOURCC('t', 'k', 'h', 'd')
#define BOX_MDIA FOURCC('m', 'd', 'i', 'a')
#define BOX_MDHD FOURCC('m', 'd', 'h', 'd')
#define BOX_MINF FOURCC('m', 'i', 'n', 'f')
#define BOX_STBL FOURCC('s', 't', 'b', 'l')
#define BOX_STSD FOURCC('s', 't', 's', 'd')
#define BOX_TRAF FOURCC('t', 'r', 'a', 'f')
#define BOX_TFHD FOURCC('t', 'f', 'h', 'd')
#define BOX_TRUN FOURCC('t', 'r', 'u', 'n')

static int get32(const uint8_t *d, size_t len, size_t off, uint32_t *out) {
    if (off > len || len - off < 4) return 0;
    *out = ((uint32_t)d[off] << 24) | ((uint32_t)d[off + 1] << 16) | ((uint32_t)d[off + 2] << 8) | (uint32_t)d[off + 3];
    return 1;
}

static int get64(const uint8_t *d, size_t len, size_t off, uint64_t *out) {
    uint32_t hi, lo;
    if (!get32(d, len, off, &hi) || !get32(d, len, off + 4, &lo)) return 0;
    *out = ((uint64_t)hi << 32) | lo;
    return 1;
}

static void put32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static void put64(uint8_t *p, uint64_t v) {
    put32(p, (uint32_t)(v >> 32));
    put32(p + 4, (uint32_t)v);
}

typedef struct {
    uint32_t type;
    size_t start;   /* the first byte of the box */
    size_t body;    /* the first byte after its header */
    size_t end;     /* one past its last byte */
} mbox;

/* the box that starts at *pos inside d[0, limit): 1 for a box, 0 at the end, -1 for a header or size that does not fit */
static int next_box(const uint8_t *d, size_t limit, size_t *pos, mbox *box) {
    uint32_t size32, type;
    uint64_t size;
    size_t header = 8;
    if (*pos >= limit) return 0;
    if (limit - *pos < 8) return -1;
    if (!get32(d, limit, *pos, &size32) || !get32(d, limit, *pos + 4, &type)) return -1;
    size = size32;
    if (size32 == 1) {
        if (limit - *pos < 16 || !get64(d, limit, *pos + 8, &size)) return -1;
        header = 16;
    } else if (size32 == 0) {
        size = limit - *pos;
    }
    if (size < header || size > limit - *pos) return -1;
    box->type = type;
    box->start = *pos;
    box->body = *pos + header;
    box->end = *pos + (size_t)size;
    *pos = box->end;
    return 1;
}

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
    int failed;
} wbuf;

static void wb_reserve(wbuf *w, size_t more) {
    size_t cap;
    uint8_t *grown;
    if (w->failed) return;
    if (more > FMP4_OUT_MOOV_MAX || w->len > FMP4_OUT_MOOV_MAX - more) { w->failed = 1; return; }
    if (w->len + more <= w->cap) return;
    cap = w->cap ? w->cap : 4096;
    while (cap < w->len + more) cap *= 2;
    grown = realloc(w->data, cap);
    if (!grown) { w->failed = 1; return; }
    w->data = grown;
    w->cap = cap;
}

static void wb_put(wbuf *w, const void *bytes, size_t n) {
    wb_reserve(w, n);
    if (w->failed || !n) return;
    memcpy(w->data + w->len, bytes, n);
    w->len += n;
}

static void wb_u32(wbuf *w, uint32_t v) {
    uint8_t b[4];
    put32(b, v);
    wb_put(w, b, 4);
}

/* a box header with its size to be patched by wb_end; returns where the size sits */
static size_t wb_begin(wbuf *w, uint32_t type) {
    size_t at = w->len;
    wb_u32(w, 0);
    wb_u32(w, type);
    return at;
}

static void wb_end(wbuf *w, size_t at) {
    size_t size = w->len - at;
    if (w->failed) return;
    if (size > 0xFFFFFFFFu) { w->failed = 1; return; }
    put32(w->data + at, (uint32_t)size);
}

typedef struct {
    uint32_t duration;
    uint32_t size;
    int32_t cto;
    uint8_t sync;
} sample;

typedef struct {
    uint32_t id;
    uint32_t timescale;
    uint32_t def_sdi;
    uint32_t def_duration;
    uint32_t def_size;
    uint32_t def_flags;
    uint64_t duration;      /* in the timescale of the track */
    sample *samples;
    size_t count;
    size_t cap;
    int has_cto;
    int negative_cto;
    size_t sync_count;
} track;

typedef struct {
    uint32_t track;         /* index into tracks */
    uint32_t samples;
    uint32_t sdi;           /* the sample description the run uses */
    uint64_t src;           /* where its bytes are in the input */
    uint64_t length;
    uint64_t dst;           /* where they go in the output */
} chunk;

typedef struct {
    FILE *in;
    uint64_t file_size;
    uint8_t *ftyp;
    size_t ftyp_len;
    uint8_t *moov;
    size_t moov_len;
    uint32_t movie_timescale;
    track tracks[FMP4_TRACKS_MAX];
    size_t ntracks;
    chunk *chunks;
    size_t nchunks;
    size_t chunk_cap;
    size_t total_samples;
    uint64_t movie_duration;
} remux;

static void remux_free(remux *r) {
    size_t i;
    for (i = 0; i < r->ntracks; ++i) free(r->tracks[i].samples);
    free(r->chunks);
    free(r->ftyp);
    free(r->moov);
}

static track *track_by_id(remux *r, uint32_t id) {
    size_t i;
    for (i = 0; i < r->ntracks; ++i) if (r->tracks[i].id == id) return &r->tracks[i];
    return NULL;
}

static exteria_status add_sample(remux *r, track *t, uint32_t duration, uint32_t size, int32_t cto, int sync) {
    if (r->total_samples >= FMP4_SAMPLES_MAX) return EXTERIA_E_LIMIT;
    if (t->count == t->cap) {
        size_t cap = t->cap ? t->cap * 2 : 512;
        sample *grown;
        if (cap > FMP4_SAMPLES_MAX) cap = FMP4_SAMPLES_MAX;
        grown = realloc(t->samples, cap * sizeof(sample));
        if (!grown) return EXTERIA_E_NOMEM;
        t->samples = grown;
        t->cap = cap;
    }
    t->samples[t->count].duration = duration;
    t->samples[t->count].size = size;
    t->samples[t->count].cto = cto;
    t->samples[t->count].sync = (uint8_t)(sync ? 1 : 0);
    ++t->count;
    ++r->total_samples;
    t->duration += duration;
    if (cto) t->has_cto = 1;
    if (cto < 0) t->negative_cto = 1;
    if (sync) ++t->sync_count;
    return EXTERIA_OK;
}

static exteria_status add_chunk(remux *r, uint32_t track_index, uint32_t samples, uint32_t sdi, uint64_t src, uint64_t length) {
    if (r->nchunks >= FMP4_CHUNKS_MAX) return EXTERIA_E_LIMIT;
    if (r->nchunks == r->chunk_cap) {
        size_t cap = r->chunk_cap ? r->chunk_cap * 2 : 256;
        chunk *grown;
        if (cap > FMP4_CHUNKS_MAX) cap = FMP4_CHUNKS_MAX;
        grown = realloc(r->chunks, cap * sizeof(chunk));
        if (!grown) return EXTERIA_E_NOMEM;
        r->chunks = grown;
        r->chunk_cap = cap;
    }
    r->chunks[r->nchunks].track = track_index;
    r->chunks[r->nchunks].samples = samples;
    r->chunks[r->nchunks].sdi = sdi;
    r->chunks[r->nchunks].src = src;
    r->chunks[r->nchunks].length = length;
    r->chunks[r->nchunks].dst = 0;
    ++r->nchunks;
    return EXTERIA_OK;
}

/* the track id, from a tkhd body that is version 0 or 1 */
static int tkhd_id(const uint8_t *d, size_t len, const mbox *b, uint32_t *id) {
    uint32_t version;
    if (!get32(d, len, b->body, &version)) return 0;
    return get32(d, len, b->body + ((version >> 24) == 1 ? 20 : 12), id);
}

static int mdhd_timescale(const uint8_t *d, size_t len, const mbox *b, uint32_t *scale) {
    uint32_t version;
    if (!get32(d, len, b->body, &version)) return 0;
    return get32(d, len, b->body + ((version >> 24) == 1 ? 20 : 12), scale);
}

static exteria_status read_trak(remux *r, const uint8_t *d, const mbox *trak) {
    size_t pos = trak->body;
    mbox b;
    int got;
    uint32_t id = 0, scale = 0;
    int have_id = 0, have_scale = 0;
    while ((got = next_box(d, trak->end, &pos, &b)) > 0) {
        if (b.type == BOX_TKHD) have_id = tkhd_id(d, trak->end, &b, &id);
        else if (b.type == BOX_MDIA) {
            size_t mpos = b.body;
            mbox m;
            while (next_box(d, b.end, &mpos, &m) > 0) if (m.type == BOX_MDHD) have_scale = mdhd_timescale(d, b.end, &m, &scale);
        }
    }
    if (got < 0 || !have_id || !have_scale || !id || !scale) return EXTERIA_E_MALFORMED;
    if (track_by_id(r, id)) return EXTERIA_E_MALFORMED;
    if (r->ntracks >= FMP4_TRACKS_MAX) return EXTERIA_E_LIMIT;
    memset(&r->tracks[r->ntracks], 0, sizeof(track));
    r->tracks[r->ntracks].id = id;
    r->tracks[r->ntracks].timescale = scale;
    r->tracks[r->ntracks].def_sdi = 1;
    ++r->ntracks;
    return EXTERIA_OK;
}

static exteria_status read_moov(remux *r) {
    const uint8_t *d = r->moov;
    size_t pos, len = r->moov_len;
    mbox b;
    int got, have_movie_scale = 0;
    exteria_status status;
    /* the header of the moov is whatever size the box carries; its children start after it */
    {
        mbox top;
        size_t p = 0;
        if (next_box(d, len, &p, &top) <= 0) return EXTERIA_E_MALFORMED;
        pos = top.body;
    }
    while ((got = next_box(d, len, &pos, &b)) > 0) {
        if (b.type == BOX_MVHD) {
            uint32_t version;
            if (!get32(d, len, b.body, &version) || !get32(d, len, b.body + ((version >> 24) == 1 ? 20 : 12), &r->movie_timescale)) return EXTERIA_E_MALFORMED;
            have_movie_scale = 1;
        } else if (b.type == BOX_TRAK) {
            status = read_trak(r, d, &b);
            if (status != EXTERIA_OK) return status;
        }
    }
    if (got < 0 || !have_movie_scale || !r->movie_timescale || !r->ntracks) return EXTERIA_E_MALFORMED;
    /* the defaults of the fragments come after the tracks are known, since the mvex may stand before them */
    {
        size_t p = 0;
        mbox top;
        next_box(d, len, &p, &top);
        pos = top.body;
        while (next_box(d, len, &pos, &b) > 0) {
            size_t xpos;
            mbox x;
            if (b.type != BOX_MVEX) continue;
            xpos = b.body;
            while (next_box(d, b.end, &xpos, &x) > 0) {
                uint32_t id, sdi, duration, size, flags;
                track *t;
                if (x.type != BOX_TREX) continue;
                if (!get32(d, x.end, x.body + 4, &id) || !get32(d, x.end, x.body + 8, &sdi) || !get32(d, x.end, x.body + 12, &duration) ||
                    !get32(d, x.end, x.body + 16, &size) || !get32(d, x.end, x.body + 20, &flags)) return EXTERIA_E_MALFORMED;
                t = track_by_id(r, id);
                if (!t) continue;
                t->def_sdi = sdi ? sdi : 1;
                t->def_duration = duration;
                t->def_size = size;
                t->def_flags = flags;
            }
        }
    }
    return EXTERIA_OK;
}

#define TFHD_BASE_OFFSET 0x000001u
#define TFHD_SDI 0x000002u
#define TFHD_DURATION 0x000008u
#define TFHD_SIZE 0x000010u
#define TFHD_FLAGS 0x000020u
#define TFHD_BASE_IS_MOOF 0x020000u

#define TRUN_DATA_OFFSET 0x000001u
#define TRUN_FIRST_FLAGS 0x000004u
#define TRUN_DURATION 0x000100u
#define TRUN_SIZE 0x000200u
#define TRUN_FLAGS 0x000400u
#define TRUN_CTO 0x000800u
#define SAMPLE_NON_SYNC 0x00010000u

typedef struct {
    track *t;
    uint32_t index;
    uint32_t sdi;
    uint32_t duration;
    uint32_t size;
    uint32_t flags;
    uint64_t base;
    uint64_t cursor;
} traf_state;

static exteria_status read_tfhd(remux *r, const uint8_t *d, const mbox *b, uint64_t moof_offset, uint64_t *implicit_base, traf_state *s) {
    uint32_t head, id, flags;
    size_t at;
    track *t;
    size_t i;
    if (!get32(d, b->end, b->body, &head) || !get32(d, b->end, b->body + 4, &id)) return EXTERIA_E_MALFORMED;
    flags = head & 0x00FFFFFFu;
    t = track_by_id(r, id);
    if (!t) return EXTERIA_E_MALFORMED;
    memset(s, 0, sizeof(*s));
    s->t = t;
    for (i = 0; i < r->ntracks; ++i) if (&r->tracks[i] == t) s->index = (uint32_t)i;
    s->sdi = t->def_sdi;
    s->duration = t->def_duration;
    s->size = t->def_size;
    s->flags = t->def_flags;
    at = b->body + 8;
    if (flags & TFHD_BASE_OFFSET) {
        uint64_t base;
        if (!get64(d, b->end, at, &base)) return EXTERIA_E_MALFORMED;
        s->base = base;
        at += 8;
    } else if (flags & TFHD_BASE_IS_MOOF) {
        s->base = moof_offset;
    } else {
        /* the first run of the first fragment starts at the moof, and one that has no base of its own follows the data of the one before it */
        s->base = *implicit_base;
    }
    if (flags & TFHD_SDI) {
        if (!get32(d, b->end, at, &s->sdi)) return EXTERIA_E_MALFORMED;
        at += 4;
    }
    if (flags & TFHD_DURATION) {
        if (!get32(d, b->end, at, &s->duration)) return EXTERIA_E_MALFORMED;
        at += 4;
    }
    if (flags & TFHD_SIZE) {
        if (!get32(d, b->end, at, &s->size)) return EXTERIA_E_MALFORMED;
        at += 4;
    }
    if (flags & TFHD_FLAGS) {
        if (!get32(d, b->end, at, &s->flags)) return EXTERIA_E_MALFORMED;
    }
    if (!s->sdi) s->sdi = 1;
    s->cursor = s->base;
    return EXTERIA_OK;
}

static exteria_status read_trun(remux *r, const uint8_t *d, const mbox *b, traf_state *s) {
    uint32_t head, count, flags, first_flags = 0, per_sample = 0, i;
    int32_t data_offset = 0;
    size_t at, remaining;
    uint64_t bytes = 0, pos;
    exteria_status status;
    int version;
    if (!get32(d, b->end, b->body, &head) || !get32(d, b->end, b->body + 4, &count)) return EXTERIA_E_MALFORMED;
    flags = head & 0x00FFFFFFu;
    version = (int)(head >> 24);
    at = b->body + 8;
    if (flags & TRUN_DATA_OFFSET) {
        uint32_t raw;
        if (!get32(d, b->end, at, &raw)) return EXTERIA_E_MALFORMED;
        data_offset = (int32_t)raw;
        at += 4;
    }
    if (flags & TRUN_FIRST_FLAGS) {
        if (!get32(d, b->end, at, &first_flags)) return EXTERIA_E_MALFORMED;
        at += 4;
    }
    if (flags & TRUN_DURATION) per_sample += 4;
    if (flags & TRUN_SIZE) per_sample += 4;
    if (flags & TRUN_FLAGS) per_sample += 4;
    if (flags & TRUN_CTO) per_sample += 4;
    /* a count the box cannot hold is a damaged box, and a count with no fields at all is bounded by the sample budget */
    remaining = b->end - at;
    if (per_sample && count > remaining / per_sample) return EXTERIA_E_MALFORMED;
    if (count > FMP4_SAMPLES_MAX) return EXTERIA_E_LIMIT;
    for (i = 0; i < count; ++i) {
        uint32_t duration = s->duration, size = s->size, sample_flags = s->flags, cto_raw = 0;
        int32_t cto;
        if (i == 0 && (flags & TRUN_FIRST_FLAGS)) sample_flags = first_flags;
        if (flags & TRUN_DURATION) { get32(d, b->end, at, &duration); at += 4; }
        if (flags & TRUN_SIZE) { get32(d, b->end, at, &size); at += 4; }
        if (flags & TRUN_FLAGS) { get32(d, b->end, at, &sample_flags); at += 4; }
        if (flags & TRUN_CTO) { get32(d, b->end, at, &cto_raw); at += 4; }
        /* version 0 offsets are unsigned, but none of the real ones is beyond what fits a signed one, and one that is cannot be a picture delay */
        cto = (int32_t)cto_raw;
        if (version == 0 && cto < 0) return EXTERIA_E_MALFORMED;
        status = add_sample(r, s->t, duration, size, cto, !(sample_flags & SAMPLE_NON_SYNC));
        if (status != EXTERIA_OK) return status;
        bytes += size;
    }
    if (flags & TRUN_DATA_OFFSET) {
        int64_t where;
        if (s->base > (uint64_t)INT64_MAX) return EXTERIA_E_MALFORMED;
        where = (int64_t)s->base + data_offset;
        if (where < 0) return EXTERIA_E_MALFORMED;
        pos = (uint64_t)where;
    } else {
        pos = s->cursor;
    }
    if (pos > r->file_size || bytes > r->file_size - pos) return EXTERIA_E_MALFORMED;
    s->cursor = pos + bytes;
    if (!count) return EXTERIA_OK;
    return add_chunk(r, s->index, count, s->sdi, pos, bytes);
}

static exteria_status read_moof(remux *r, const uint8_t *d, size_t len, uint64_t moof_offset) {
    mbox top, b;
    size_t pos = 0;
    int got;
    uint64_t implicit_base = moof_offset;
    if (next_box(d, len, &pos, &top) <= 0) return EXTERIA_E_MALFORMED;
    pos = top.body;
    while ((got = next_box(d, len, &pos, &b)) > 0) {
        size_t tpos;
        mbox x;
        traf_state state;
        int have_tfhd = 0, g;
        exteria_status status;
        if (b.type != BOX_TRAF) continue;
        tpos = b.body;
        while ((g = next_box(d, b.end, &tpos, &x)) > 0) {
            if (x.type == BOX_TFHD) {
                status = read_tfhd(r, d, &x, moof_offset, &implicit_base, &state);
                if (status != EXTERIA_OK) return status;
                have_tfhd = 1;
            } else if (x.type == BOX_TRUN) {
                if (!have_tfhd) return EXTERIA_E_MALFORMED;
                status = read_trun(r, d, &x, &state);
                if (status != EXTERIA_OK) return status;
            }
        }
        if (g < 0) return EXTERIA_E_MALFORMED;
        if (have_tfhd) implicit_base = state.cursor;
    }
    return got < 0 ? EXTERIA_E_MALFORMED : EXTERIA_OK;
}

static int read_exact_at(FILE *f, uint64_t at, void *buffer, size_t n) {
    if (fseeko(f, (off_t)at, SEEK_SET) != 0) return 0;
    return n == 0 || fread(buffer, 1, n, f) == n;
}

static exteria_status file_size_of(FILE *f, uint64_t *size) {
    off_t end;
    if (fseeko(f, 0, SEEK_END) != 0) return EXTERIA_E_IO;
    end = ftello(f);
    if (end < 0) return EXTERIA_E_IO;
    *size = (uint64_t)end;
    return EXTERIA_OK;
}

/* the box header at a file offset: its type and size, 0 at the end of the file, -1 for a size that does not fit */
static int file_box(FILE *f, uint64_t file_size, uint64_t at, uint32_t *type, uint64_t *size, size_t *header) {
    uint8_t h[16];
    uint64_t room;
    uint32_t size32;
    if (at >= file_size) return 0;
    room = file_size - at;
    if (room < 8) return -1;
    if (!read_exact_at(f, at, h, 8)) return -1;
    size32 = ((uint32_t)h[0] << 24) | ((uint32_t)h[1] << 16) | ((uint32_t)h[2] << 8) | (uint32_t)h[3];
    *type = ((uint32_t)h[4] << 24) | ((uint32_t)h[5] << 16) | ((uint32_t)h[6] << 8) | (uint32_t)h[7];
    *header = 8;
    *size = size32;
    if (size32 == 1) {
        if (room < 16 || fread(h + 8, 1, 8, f) != 8) return -1;
        get64(h, 16, 8, size);
        *header = 16;
    } else if (size32 == 0) {
        *size = room;
    }
    if (*size < *header || *size > room) return -1;
    return 1;
}

exteria_status exteria_fmp4_scan(const char *path) {
    FILE *f;
    uint64_t file_size, at = 0, size;
    uint32_t type;
    size_t header, boxes = 0;
    int got;
    exteria_status status = EXTERIA_E_NOTFOUND;
    if (!path) return EXTERIA_E_ARG;
    f = fopen(path, "rb");
    if (!f) return EXTERIA_E_IO;
    if (file_size_of(f, &file_size) != EXTERIA_OK) { fclose(f); return EXTERIA_E_IO; }
    while ((got = file_box(f, file_size, at, &type, &size, &header)) > 0) {
        if (type == BOX_MOOF) { status = EXTERIA_OK; break; }
        at += size;
        if (++boxes > FMP4_BOXES_MAX) { status = EXTERIA_E_LIMIT; break; }
    }
    if (got < 0 && status != EXTERIA_OK) status = EXTERIA_E_MALFORMED;
    fclose(f);
    return status;
}

typedef struct {
    remux *r;
    const track *current;
    wbuf *out;
} builder;

static void copy_raw(builder *b, const uint8_t *d, const mbox *x) {
    wb_put(b->out, d + x->start, x->end - x->start);
}

/* the length of the movie, the track and the media, which a fragmented file leaves at zero: the version says how wide the field is */
static void patch_duration(wbuf *w, size_t box_start, size_t body_offset_v0, size_t body_offset_v1, uint64_t duration) {
    size_t body = box_start + 8;
    int version;
    if (w->failed) return;
    version = w->data[body] == 1;
    if (version) {
        if (w->len < body + body_offset_v1 + 8) { w->failed = 1; return; }
        put64(w->data + body + body_offset_v1, duration);
    } else {
        if (w->len < body + body_offset_v0 + 4 || duration > 0xFFFFFFFFu) { w->failed = 1; return; }
        put32(w->data + body + body_offset_v0, (uint32_t)duration);
    }
}

static uint64_t scale_duration(uint64_t duration, uint32_t from, uint32_t to) {
    return (duration / from) * to + ((duration % from) * to) / from;
}

static void put_stbl(builder *b, const uint8_t *d, const mbox *stbl) {
    const track *t = b->current;
    wbuf *w = b->out;
    size_t pos = stbl->body, at, i, run;
    mbox x;
    int have_stsd = 0;
    size_t start = wb_begin(w, BOX_STBL);
    while (next_box(d, stbl->end, &pos, &x) > 0) {
        if (x.type == BOX_STSD) { copy_raw(b, d, &x); have_stsd = 1; }
    }
    if (!have_stsd) { w->failed = 1; return; }
    /* stts: runs of one duration */
    at = wb_begin(w, FOURCC('s', 't', 't', 's'));
    wb_u32(w, 0);
    {
        uint32_t runs = 0;
        size_t count_at;
        count_at = w->len;
        wb_u32(w, 0);
        for (i = 0; i < t->count; ) {
            uint32_t duration = t->samples[i].duration;
            uint32_t n = 0;
            while (i < t->count && t->samples[i].duration == duration) { ++n; ++i; }
            wb_u32(w, n);
            wb_u32(w, duration);
            ++runs;
        }
        if (!w->failed) put32(w->data + count_at, runs);
    }
    wb_end(w, at);
    /* stss: only when some samples are not sync points, since it says all are when it is missing */
    if (t->sync_count > 0 && t->sync_count < t->count) {
        at = wb_begin(w, FOURCC('s', 't', 's', 's'));
        wb_u32(w, 0);
        wb_u32(w, (uint32_t)t->sync_count);
        for (i = 0; i < t->count; ++i) if (t->samples[i].sync) wb_u32(w, (uint32_t)(i + 1));
        wb_end(w, at);
    }
    if (t->has_cto) {
        uint32_t runs = 0;
        size_t count_at;
        at = wb_begin(w, FOURCC('c', 't', 't', 's'));
        wb_u32(w, t->negative_cto ? 0x01000000u : 0);
        count_at = w->len;
        wb_u32(w, 0);
        for (i = 0; i < t->count; ) {
            int32_t cto = t->samples[i].cto;
            uint32_t n = 0;
            while (i < t->count && t->samples[i].cto == cto) { ++n; ++i; }
            wb_u32(w, n);
            wb_u32(w, (uint32_t)cto);
            ++runs;
        }
        if (!w->failed) put32(w->data + count_at, runs);
        wb_end(w, at);
    }
    /* stsc: runs of chunks that hold the same number of samples of the same description */
    {
        uint32_t runs = 0, chunk_number = 0, last_samples = 0, last_sdi = 0;
        size_t count_at;
        at = wb_begin(w, FOURCC('s', 't', 's', 'c'));
        wb_u32(w, 0);
        count_at = w->len;
        wb_u32(w, 0);
        for (run = 0; run < b->r->nchunks; ++run) {
            const chunk *c = &b->r->chunks[run];
            if (&b->r->tracks[c->track] != t) continue;
            ++chunk_number;
            if (runs && c->samples == last_samples && c->sdi == last_sdi) continue;
            wb_u32(w, chunk_number);
            wb_u32(w, c->samples);
            wb_u32(w, c->sdi);
            last_samples = c->samples;
            last_sdi = c->sdi;
            ++runs;
        }
        if (!w->failed) put32(w->data + count_at, runs);
        wb_end(w, at);
    }
    at = wb_begin(w, FOURCC('s', 't', 's', 'z'));
    wb_u32(w, 0);
    wb_u32(w, 0);
    wb_u32(w, (uint32_t)t->count);
    for (i = 0; i < t->count; ++i) wb_u32(w, t->samples[i].size);
    wb_end(w, at);
    {
        uint32_t chunks = 0;
        size_t count_at;
        at = wb_begin(w, FOURCC('s', 't', 'c', 'o'));
        wb_u32(w, 0);
        count_at = w->len;
        wb_u32(w, 0);
        for (run = 0; run < b->r->nchunks; ++run) {
            const chunk *c = &b->r->chunks[run];
            if (&b->r->tracks[c->track] != t) continue;
            if (c->dst > 0xFFFFFFFFu) { w->failed = 1; return; }
            wb_u32(w, (uint32_t)c->dst);
            ++chunks;
        }
        if (!w->failed) put32(w->data + count_at, chunks);
        wb_end(w, at);
    }
    wb_end(w, start);
}

static void put_children(builder *b, const uint8_t *d, const mbox *parent, uint32_t parent_type);

static void put_container(builder *b, const uint8_t *d, const mbox *x, uint32_t type) {
    size_t start = wb_begin(b->out, type);
    put_children(b, d, x, x->type);
    wb_end(b->out, start);
}

static void put_children(builder *b, const uint8_t *d, const mbox *parent, uint32_t parent_type) {
    size_t pos = parent->body;
    mbox x;
    while (next_box(d, parent->end, &pos, &x) > 0) {
        size_t start;
        if (parent_type == BOX_MOOV || parent_type == BOX_HOOV) {
            if (x.type == BOX_MVEX) continue;
            if (x.type == BOX_MVHD) {
                start = b->out->len;
                copy_raw(b, d, &x);
                patch_duration(b->out, start, 16, 24, b->r->movie_duration);
            } else if (x.type == BOX_TRAK) {
                uint32_t id = 0;
                size_t p = x.body;
                mbox y;
                const track *saved = b->current;
                while (next_box(d, x.end, &p, &y) > 0) if (y.type == BOX_TKHD) tkhd_id(d, x.end, &y, &id);
                b->current = track_by_id(b->r, id);
                if (!b->current) { b->out->failed = 1; return; }
                put_container(b, d, &x, BOX_TRAK);
                b->current = saved;
            } else {
                copy_raw(b, d, &x);
            }
        } else if (parent_type == BOX_TRAK) {
            if (x.type == BOX_TKHD) {
                start = b->out->len;
                copy_raw(b, d, &x);
                patch_duration(b->out, start, 20, 28, scale_duration(b->current->duration, b->current->timescale, b->r->movie_timescale));
            } else if (x.type == BOX_MDIA) {
                put_container(b, d, &x, BOX_MDIA);
            } else {
                copy_raw(b, d, &x);
            }
        } else if (parent_type == BOX_MDIA) {
            if (x.type == BOX_MDHD) {
                start = b->out->len;
                copy_raw(b, d, &x);
                patch_duration(b->out, start, 16, 24, b->current->duration);
            } else if (x.type == BOX_MINF) {
                put_container(b, d, &x, BOX_MINF);
            } else {
                copy_raw(b, d, &x);
            }
        } else if (parent_type == BOX_MINF) {
            if (x.type == BOX_STBL) put_stbl(b, d, &x);
            else copy_raw(b, d, &x);
        } else {
            copy_raw(b, d, &x);
        }
        if (b->out->failed) return;
    }
}

static exteria_status build_moov(remux *r, wbuf *out) {
    builder b;
    mbox top;
    size_t pos = 0, start;
    memset(out, 0, sizeof(*out));
    if (next_box(r->moov, r->moov_len, &pos, &top) <= 0) return EXTERIA_E_MALFORMED;
    b.r = r;
    b.current = NULL;
    b.out = out;
    start = wb_begin(out, BOX_MOOV);
    put_children(&b, r->moov, &top, BOX_MOOV);
    wb_end(out, start);
    if (out->failed) {
        free(out->data);
        memset(out, 0, sizeof(*out));
        return EXTERIA_E_LIMIT;
    }
    return EXTERIA_OK;
}

static exteria_status scan_file(remux *r) {
    uint64_t at = 0, size;
    uint32_t type;
    size_t header, boxes = 0;
    int got;
    while ((got = file_box(r->in, r->file_size, at, &type, &size, &header)) > 0) {
        exteria_status status = EXTERIA_OK;
        if (++boxes > FMP4_BOXES_MAX) return EXTERIA_E_LIMIT;
        if (type == BOX_FTYP && !r->ftyp) {
            if (size > FMP4_FTYP_MAX) return EXTERIA_E_MALFORMED;
            r->ftyp = malloc((size_t)size);
            if (!r->ftyp) return EXTERIA_E_NOMEM;
            if (!read_exact_at(r->in, at, r->ftyp, (size_t)size)) return EXTERIA_E_IO;
            r->ftyp_len = (size_t)size;
        } else if ((type == BOX_MOOV || type == BOX_HOOV) && !r->moov) {
            if (size > FMP4_MOOV_MAX) return EXTERIA_E_LIMIT;
            r->moov = malloc((size_t)size);
            if (!r->moov) return EXTERIA_E_NOMEM;
            if (!read_exact_at(r->in, at, r->moov, (size_t)size)) return EXTERIA_E_IO;
            r->moov_len = (size_t)size;
            status = read_moov(r);
        } else if (type == BOX_MOOF) {
            uint8_t *fragment;
            /* a fragment before the movie box says nothing about the tracks it belongs to */
            if (!r->moov) return EXTERIA_E_UNSUPPORTED;
            if (size > FMP4_MOOF_MAX) return EXTERIA_E_LIMIT;
            fragment = malloc((size_t)size);
            if (!fragment) return EXTERIA_E_NOMEM;
            if (!read_exact_at(r->in, at, fragment, (size_t)size)) { free(fragment); return EXTERIA_E_IO; }
            status = read_moof(r, fragment, (size_t)size, at);
            free(fragment);
        }
        if (status != EXTERIA_OK) return status;
        at += size;
    }
    return got < 0 ? EXTERIA_E_MALFORMED : EXTERIA_OK;
}

static int write_all(FILE *f, const void *data, size_t n) {
    return n == 0 || fwrite(data, 1, n, f) == n;
}

static exteria_status write_output(remux *r, FILE *out, const wbuf *moov, uint64_t payload) {
    uint8_t header[8];
    uint8_t *block;
    size_t i;
    if (!write_all(out, r->ftyp, r->ftyp_len) || !write_all(out, moov->data, moov->len)) return EXTERIA_E_IO;
    put32(header, (uint32_t)(payload + 8));
    memcpy(header + 4, "mdat", 4);
    if (!write_all(out, header, 8)) return EXTERIA_E_IO;
    block = malloc(FMP4_COPY_BLOCK);
    if (!block) return EXTERIA_E_NOMEM;
    for (i = 0; i < r->nchunks; ++i) {
        uint64_t left = r->chunks[i].length, at = r->chunks[i].src;
        while (left) {
            size_t n = left > FMP4_COPY_BLOCK ? FMP4_COPY_BLOCK : (size_t)left;
            if (!read_exact_at(r->in, at, block, n) || !write_all(out, block, n)) { free(block); return EXTERIA_E_IO; }
            at += n;
            left -= n;
        }
    }
    free(block);
    return EXTERIA_OK;
}

exteria_status exteria_fmp4_remux(const char *in_path, const char *out_path) {
    remux r;
    wbuf moov;
    FILE *out;
    exteria_status status;
    uint64_t payload = 0, cursor;
    size_t i;
    if (!in_path || !out_path || !strcmp(in_path, out_path)) return EXTERIA_E_ARG;
    memset(&r, 0, sizeof(r));
    memset(&moov, 0, sizeof(moov));
    r.in = fopen(in_path, "rb");
    if (!r.in) return EXTERIA_E_IO;
    status = file_size_of(r.in, &r.file_size);
    if (status == EXTERIA_OK) status = scan_file(&r);
    if (status == EXTERIA_OK && (!r.moov || !r.nchunks)) status = EXTERIA_E_NOTFOUND;
    if (status != EXTERIA_OK) goto done;
    for (i = 0; i < r.ntracks; ++i) {
        uint64_t as_movie = scale_duration(r.tracks[i].duration, r.tracks[i].timescale, r.movie_timescale);
        if (as_movie > r.movie_duration) r.movie_duration = as_movie;
    }
    for (i = 0; i < r.nchunks; ++i) payload += r.chunks[i].length;
    /* the first run gives the size of the movie box, which does not depend on the offsets it holds, so the offsets can be set and the box built again */
    status = build_moov(&r, &moov);
    if (status != EXTERIA_OK) goto done;
    cursor = r.ftyp_len + moov.len + 8;
    if (payload > 0xFFFFFFFFu - 8u || cursor + payload > 0xFFFFFFFFu) { status = EXTERIA_E_LIMIT; goto done; }
    for (i = 0; i < r.nchunks; ++i) {
        r.chunks[i].dst = cursor;
        cursor += r.chunks[i].length;
    }
    {
        size_t first_size = moov.len;
        free(moov.data);
        status = build_moov(&r, &moov);
        if (status != EXTERIA_OK) goto done;
        if (moov.len != first_size) { status = EXTERIA_E_MALFORMED; goto done; }
    }
    out = fopen(out_path, "wb");
    if (!out) { status = EXTERIA_E_IO; goto done; }
    status = write_output(&r, out, &moov, payload);
    if (fclose(out) != 0 && status == EXTERIA_OK) status = EXTERIA_E_IO;
    if (status != EXTERIA_OK) remove(out_path);
done:
    free(moov.data);
    if (r.in) fclose(r.in);
    remux_free(&r);
    return status;
}
