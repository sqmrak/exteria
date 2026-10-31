#include <sys/stat.h>
#include <unistd.h>

#include "exteria_zip.h"
#include "exteria_zipw.h"
#include "test_util.h"

static char g_dir[64];

static void path_of(char *out, size_t cap, const char *name) {
    snprintf(out, cap, "%s/%s", g_dir, name);
}

static void test_roundtrip(void) {
    char path[128], out[128];
    exteria_zipw *zip = NULL;
    exteria_zip *read = NULL;
    uint8_t big[70000];
    uint8_t back[70000];
    size_t i;
    FILE *f;
    for (i = 0; i < sizeof(big); ++i) big[i] = (uint8_t)(i * 31u + i / 251u);
    path_of(path, sizeof(path), "a.zip");
    CHECK_EQ_INT(exteria_zipw_begin(path, &zip), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_add(zip, "exteria.log", (const uint8_t *)"line one\nline two\n", 18, 0644), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_add(zip, "logs/big.bin", big, sizeof(big), 0600), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_add(zip, "empty.txt", NULL, 0, 0644), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_finish(zip), EXTERIA_OK);
    /* what the writer made is what the reader of the updater takes */
    CHECK_EQ_INT(exteria_zip_open(path, &read), EXTERIA_OK);
    if (!read) return;
    CHECK_EQ_INT(exteria_zip_count(read), 3);
    CHECK(!strcmp(exteria_zip_entry_at(read, 0)->name, "exteria.log"));
    CHECK_EQ_INT(exteria_zip_entry_at(read, 0)->size, 18);
    CHECK_EQ_INT(exteria_zip_entry_at(read, 1)->mode & 0777, 0600);
    path_of(out, sizeof(out), "big.out");
    CHECK_EQ_INT(exteria_zip_extract(read, exteria_zip_entry_at(read, 1), out, NULL, NULL), EXTERIA_OK);
    f = fopen(out, "rb");
    CHECK(f && fread(back, 1, sizeof(back), f) == sizeof(back));
    if (f) fclose(f);
    CHECK_MEM(back, big, sizeof(big));
    path_of(out, sizeof(out), "log.out");
    CHECK_EQ_INT(exteria_zip_extract(read, exteria_zip_entry_at(read, 0), out, NULL, NULL), EXTERIA_OK);
    path_of(out, sizeof(out), "empty.out");
    CHECK_EQ_INT(exteria_zip_extract(read, exteria_zip_entry_at(read, 2), out, NULL, NULL), EXTERIA_OK);
    exteria_zip_close(read);
}

static void test_refusals(void) {
    char path[128];
    exteria_zipw *zip = NULL;
    path_of(path, sizeof(path), "a.zip");
    /* a file that is there is never overwritten */
    CHECK_EQ_INT(exteria_zipw_begin(path, &zip), EXTERIA_E_STATE);
    path_of(path, sizeof(path), "b.zip");
    CHECK_EQ_INT(exteria_zipw_begin(path, &zip), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_add(zip, "../evil", (const uint8_t *)"x", 1, 0644), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_add(zip, "a/../evil", (const uint8_t *)"x", 1, 0644), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_add(zip, "/abs", (const uint8_t *)"x", 1, 0644), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_add(zip, "back\\slash", (const uint8_t *)"x", 1, 0644), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_add(zip, "", (const uint8_t *)"x", 1, 0644), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_add(zip, "ok..name", (const uint8_t *)"x", 1, 0644), EXTERIA_OK);
    CHECK_EQ_INT(exteria_zipw_add(zip, "nodata", NULL, 4, 0644), EXTERIA_E_ARG);
    /* an abandoned archive leaves no file behind */
    exteria_zipw_abort(zip);
    CHECK(access(path, F_OK) != 0);
    CHECK_EQ_INT(exteria_zipw_begin(NULL, &zip), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_zipw_finish(NULL), EXTERIA_E_ARG);
}

int main(void) {
    snprintf(g_dir, sizeof(g_dir), "/tmp/exteria-zipw-XXXXXX");
    if (!mkdtemp(g_dir)) return 1;
    test_roundtrip();
    test_refusals();
    return test_finish("test_zipw");
}
