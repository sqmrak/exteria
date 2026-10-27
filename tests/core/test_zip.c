#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include "exteria_zip.h"
#include "test_util.h"
#include "zip_fixture.h"

static char g_dir[64];

static void path_of(char *out, size_t cap, const char *name) {
    snprintf(out, cap, "%s/%s", g_dir, name);
}

static const exteria_zip_entry *find(const exteria_zip *zip, const char *name) {
    size_t i;
    for (i = 0; i < exteria_zip_count(zip); ++i) {
        if (!strcmp(exteria_zip_entry_at(zip, i)->name, name)) return exteria_zip_entry_at(zip, i);
    }
    return NULL;
}

static exteria_status open_one(const fx_entry *e, size_t count, exteria_zip **zip) {
    char path[128];
    path_of(path, sizeof(path), "a.zip");
    CHECK(fx_write_zip(path, e, count));
    return exteria_zip_open(path, zip);
}

static uint8_t *pattern(size_t len) {
    uint8_t *p = (uint8_t *)malloc(len);
    size_t i;
    for (i = 0; i < len; ++i) p[i] = (uint8_t)((i % 251u) ^ (i / 997u));
    return p;
}

static void roundtrip(void) {
    uint8_t *big = pattern(300000);
    static const uint8_t small[] = "stored bytes";
    fx_entry entries[] = {
        {"Payload/", NULL, 0, 0, 0, 0, 0, 0, 0, 0},
        {"Payload/App/", NULL, 0, 0, 0, 0, 0, 0, 0, 0},
        {"Payload/App/big.bin", big, 300000, 1, 0, 0, 0, 0, 0, 0},
        {"Payload/App/small.txt", small, sizeof(small) - 1, 0, 0, 0, 0, 0, 0, 0},
        {"Payload/App/run", small, sizeof(small) - 1, 1, 0755, 0, 0, 0, 0, 0},
        {"Payload/App/empty", NULL, 0, 0, 0, 0, 0, 0, 0, 0},
        {"Payload/App/empty-deflated", NULL, 0, 1, 0, 0, 0, 0, 0, 0}
    };
    exteria_zip *zip = NULL;
    char out[128];
    struct stat st;
    const exteria_zip_entry *e;
    FILE *f;
    uint8_t *back;
    size_t i;
    CHECK_EQ_INT(open_one(entries, 7, &zip), EXTERIA_OK);
    if (!zip) return;
    CHECK_EQ_INT(exteria_zip_count(zip), 7);
    e = find(zip, "Payload/");
    CHECK(e && e->is_dir);
    e = find(zip, "Payload/App/big.bin");
    CHECK(e && !e->is_dir && e->deflated && e->size == 300000 && e->packed < e->size && e->mode == 0644);
    CHECK(find(zip, "Payload/App/run") && find(zip, "Payload/App/run")->mode == 0755);
    CHECK(exteria_zip_entry_at(zip, 7) == NULL);
    path_of(out, sizeof(out), "big.out");
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/App/big.bin"), out, NULL, NULL), EXTERIA_OK);
    back = (uint8_t *)malloc(300000);
    f = fopen(out, "rb");
    CHECK(f && fread(back, 1, 300000, f) == 300000);
    if (f) fclose(f);
    CHECK_MEM(back, big, 300000);
    free(back);
    CHECK_EQ_INT(stat(out, &st), 0);
    CHECK_EQ_INT(st.st_size, 300000);
    /* a file that is already there is never overwritten */
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/App/big.bin"), out, NULL, NULL), EXTERIA_E_STATE);
    path_of(out, sizeof(out), "small.out");
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/App/small.txt"), out, NULL, NULL), EXTERIA_OK);
    path_of(out, sizeof(out), "empty.out");
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/App/empty"), out, NULL, NULL), EXTERIA_OK);
    CHECK_EQ_INT(stat(out, &st), 0);
    CHECK_EQ_INT(st.st_size, 0);
    path_of(out, sizeof(out), "empty2.out");
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/App/empty-deflated"), out, NULL, NULL), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zip_extract(zip, find(zip, "Payload/"), out, NULL, NULL), EXTERIA_E_ARG);
    for (i = 0; i < 7; ++i) CHECK(exteria_zip_entry_at(zip, i) != NULL);
    exteria_zip_close(zip);
    free(big);
}

/* stored blocks make a read of 16384 packed bytes inflate to exactly 16384 bytes after the first header: the call ends with its input spent and
   its output full, and the next call has nothing to do until more input comes. zlib answers that one with Z_BUF_ERROR, which is no failure */
static void input_ends_with_full_output(void) {
    uint8_t *data = pattern(200000);
    fx_entry e[1] = {{"stored-blocks", data, 200000, 2, 0, 0, 0, 0, 0, 0}};
    exteria_zip *zip = NULL;
    char out[128];
    uint8_t *back = (uint8_t *)malloc(200000);
    FILE *f;
    CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
    if (!zip) return;
    path_of(out, sizeof(out), "blocks.out");
    CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_OK);
    f = fopen(out, "rb");
    CHECK(f && fread(back, 1, 200000, f) == 200000);
    if (f) fclose(f);
    CHECK_MEM(back, data, 200000);
    exteria_zip_close(zip);
    free(back);
    free(data);
}

static void unsafe_names(void) {
    static const char *const names[] = {"../x", "/abs", "a/../b", "a//b", "a\\b", ".", "a/./b", "", "ctl\x01x", "dir/.."};
    static const uint8_t data[] = "x";
    size_t i;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        fx_entry e[2] = {{"ok", data, 1, 0, 0, 0, 0, 0, 0, 0}, {names[i], data, 1, 0, 0, 0, 0, 0, 0, 0}};
        exteria_zip *zip = NULL;
        CHECK_EQ_INT(open_one(e, 2, &zip), EXTERIA_E_MALFORMED);
        CHECK(zip == NULL);
    }
}

static void refused_archives(void) {
    static const uint8_t data[] = "0123456789";
    exteria_zip *zip = NULL;
    {
        fx_entry e[2] = {{"a", data, 10, 0, 0, 0, 0, 0, 0, 0}, {"b/../a", data, 10, 0, 0, 0, 0, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 2, &zip), EXTERIA_E_MALFORMED);
    }
    {
        fx_entry e[2] = {{"dup", data, 10, 0, 0, 0, 0, 0, 0, 0}, {"dup", data, 5, 0, 0, 0, 0, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 2, &zip), EXTERIA_E_MALFORMED);
    }
    {
        fx_entry e[1] = {{"link", data, 10, 0, 0, 1, 0, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_E_UNSUPPORTED);
    }
    {
        fx_entry e[1] = {{"secret", data, 10, 0, 0, 0, 0, 1, 0, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_E_UNSUPPORTED);
    }
    {
        fx_entry e[1] = {{"huge", data, 10, 0, 0, 0, 0, 0, EXTERIA_ZIP_MAX_ENTRY_SIZE + 1u, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_E_LIMIT);
    }
    {
        /* each entry is inside the cap and together they are not */
        fx_entry e[3] = {{"a", data, 10, 0, 0, 0, 0, 0, 100u * 1024u * 1024u, 0}, {"b", data, 10, 0, 0, 0, 0, 0, 100u * 1024u * 1024u, 0},
                         {"c", data, 10, 0, 0, 0, 0, 0, 100u * 1024u * 1024u, 0}};
        CHECK_EQ_INT(open_one(e, 3, &zip), EXTERIA_E_LIMIT);
    }
    {
        char path[128];
        uint8_t junk[100];
        memset(junk, 0x41, sizeof(junk));
        path_of(path, sizeof(path), "junk.zip");
        CHECK(fx_write(path, junk, sizeof(junk)));
        CHECK_EQ_INT(exteria_zip_open(path, &zip), EXTERIA_E_MALFORMED);
        CHECK(fx_write(path, junk, 0));
        CHECK_EQ_INT(exteria_zip_open(path, &zip), EXTERIA_E_MALFORMED);
        path_of(path, sizeof(path), "absent.zip");
        CHECK_EQ_INT(exteria_zip_open(path, &zip), EXTERIA_E_NOTFOUND);
        CHECK_EQ_INT(exteria_zip_open(g_dir, &zip), EXTERIA_E_MALFORMED);
    }
    CHECK_EQ_INT(exteria_zip_open(NULL, &zip), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zip_open("x", NULL), EXTERIA_E_ARG);
    {
        /* a cut archive loses its end record; one with the central directory pointing past the file is refused too */
        size_t len = 0, cut;
        fx_entry e[1] = {{"a", data, 10, 0, 0, 0, 0, 0, 0, 0}};
        uint8_t *zipbytes = fx_build(e, 1, &len);
        char path[128];
        path_of(path, sizeof(path), "cut.zip");
        for (cut = 1; cut < len; cut += 7) {
            CHECK(fx_write(path, zipbytes, len - cut));
            CHECK(exteria_zip_open(path, &zip) != EXTERIA_OK);
        }
        zipbytes[len - 6] = 0xFF;
        zipbytes[len - 5] = 0xFF;
        CHECK(fx_write(path, zipbytes, len));
        CHECK(exteria_zip_open(path, &zip) != EXTERIA_OK);
        free(zipbytes);
    }
}

static exteria_status stop_at(void *ctx, uint32_t written) {
    return written >= *(uint32_t *)ctx ? EXTERIA_E_RETRY : EXTERIA_OK;
}

static void damaged_data(void) {
    uint8_t *data = pattern(70000);
    exteria_zip *zip = NULL;
    char out[128];
    uint32_t limit = 20000;
    path_of(out, sizeof(out), "bad.out");
    {
        fx_entry e[1] = {{"crc", data, 70000, 1, 0, 0, 1, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        exteria_zip_close(zip);
    }
    {
        fx_entry e[1] = {{"stored-crc", data, 70000, 0, 0, 0, 1, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        exteria_zip_close(zip);
    }
    {
        /* the headers say 1000 bytes and the stream inflates to 70000 */
        fx_entry e[1] = {{"bomb", data, 70000, 1, 0, 0, 0, 0, 1000, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        exteria_zip_close(zip);
    }
    {
        /* the headers say more than the stream holds */
        fx_entry e[1] = {{"short", data, 1000, 1, 0, 0, 0, 0, 70000, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        exteria_zip_close(zip);
    }
    {
        fx_entry e[1] = {{"cutstream", data, 70000, 1, 0, 0, 0, 0, 0, 1}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, NULL, NULL), EXTERIA_E_MALFORMED);
        CHECK(access(out, F_OK) != 0);
        exteria_zip_close(zip);
    }
    {
        /* a caller that stops the extraction gets its own status back and no file */
        fx_entry e[1] = {{"stop", data, 70000, 1, 0, 0, 0, 0, 0, 0}};
        CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), out, stop_at, &limit), EXTERIA_E_RETRY);
        CHECK(access(out, F_OK) != 0);
        CHECK_EQ_INT(exteria_zip_extract(zip, exteria_zip_entry_at(zip, 0), "/nonexistent-folder/x", NULL, NULL), EXTERIA_E_IO);
        exteria_zip_close(zip);
    }
    free(data);
}

static void same_file(void) {
    static const uint8_t data[] = "version one of a file";
    static const uint8_t other[] = "version two of a file";
    static const uint8_t longer[] = "version one of a file, longer";
    fx_entry e[1] = {{"f", data, sizeof(data) - 1, 0, 0, 0, 0, 0, 0, 0}};
    exteria_zip *zip = NULL;
    char path[128];
    int same = -1;
    CHECK_EQ_INT(open_one(e, 1, &zip), EXTERIA_OK);
    path_of(path, sizeof(path), "installed");
    CHECK(fx_write(path, data, sizeof(data) - 1));
    CHECK_EQ_INT(exteria_zip_entry_matches(exteria_zip_entry_at(zip, 0), path, &same), EXTERIA_OK);
    CHECK_EQ_INT(same, 1);
    CHECK(fx_write(path, other, sizeof(other) - 1));
    CHECK_EQ_INT(exteria_zip_entry_matches(exteria_zip_entry_at(zip, 0), path, &same), EXTERIA_OK);
    CHECK_EQ_INT(same, 0);
    CHECK(fx_write(path, longer, sizeof(longer) - 1));
    CHECK_EQ_INT(exteria_zip_entry_matches(exteria_zip_entry_at(zip, 0), path, &same), EXTERIA_OK);
    CHECK_EQ_INT(same, 0);
    path_of(path, sizeof(path), "missing");
    CHECK_EQ_INT(exteria_zip_entry_matches(exteria_zip_entry_at(zip, 0), path, &same), EXTERIA_OK);
    CHECK_EQ_INT(same, 0);
    CHECK_EQ_INT(exteria_zip_entry_matches(exteria_zip_entry_at(zip, 0), g_dir, &same), EXTERIA_OK);
    CHECK_EQ_INT(same, 0);
    CHECK_EQ_INT(exteria_zip_entry_matches(NULL, path, &same), EXTERIA_E_ARG);
    exteria_zip_close(zip);
}

int main(void) {
    snprintf(g_dir, sizeof(g_dir), "/tmp/exteria-zip-XXXXXX");
    if (!mkdtemp(g_dir)) {
        perror("mkdtemp");
        return 2;
    }
    roundtrip();
    input_ends_with_full_output();
    unsafe_names();
    refused_archives();
    damaged_data();
    same_file();
    {
        char cmd[96];
        snprintf(cmd, sizeof(cmd), "rm -rf %s", g_dir);
        if (system(cmd) != 0) fprintf(stderr, "could not remove %s\n", g_dir);
    }
    return test_finish("test_zip");
}
