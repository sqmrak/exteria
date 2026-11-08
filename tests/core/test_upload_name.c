#include "test_util.h"
#include "exteria_messages.h"
#include <string.h>

/* every byte of a result after a cut must still be a whole utf-8 text */
static int valid_utf8(const char *text) {
    const unsigned char *p = (const unsigned char *)text;
    while (*p) {
        int more = *p < 0x80 ? 0 : (*p >> 5) == 6 ? 1 : (*p >> 4) == 14 ? 2 : (*p >> 3) == 30 ? 3 : -1;
        if (more < 0) return 0;
        ++p;
        for (int i = 0; i < more; ++i, ++p) if ((*p & 0xC0) != 0x80) return 0;
    }
    return 1;
}

int main(void) {
    char out[EXTERIA_UPLOAD_NAME_MAX], small[16];
    /* a name that fits stays as it is */
    CHECK_EQ_INT(exteria_upload_fit_name("report.pdf", out, sizeof(out)), EXTERIA_OK);
    CHECK(!strcmp(out, "report.pdf"));
    CHECK_EQ_INT(exteria_upload_fit_name("", out, sizeof(out)), EXTERIA_OK);
    CHECK(out[0] == 0);
    /* one byte under the limit fits, the limit itself does not and is cut with the extension kept */
    char name[600];
    memset(name, 'a', 255); strcpy(name + 255, ".pdf");
    CHECK_EQ_INT(exteria_upload_fit_name(name, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) == 255 && !strcmp(out + strlen(out) - 4, ".pdf"));
    memset(name, 'b', 255); name[255] = 0;
    CHECK_EQ_INT(exteria_upload_fit_name(name, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) == 255);
    /* a Cyrillic name of 255 characters is 510 bytes: cut at a character, extension kept */
    char cyr[700] = {0};
    for (int i = 0; i < 255; ++i) strcat(cyr, "\xd0\xb4");
    strcat(cyr, ".mp4");
    CHECK_EQ_INT(exteria_upload_fit_name(cyr, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) < EXTERIA_UPLOAD_NAME_MAX && valid_utf8(out) && !strcmp(out + strlen(out) - 4, ".mp4"));
    CHECK(strlen(out) >= EXTERIA_UPLOAD_NAME_MAX - 3);
    /* three byte characters, no extension */
    char han[800] = {0};
    for (int i = 0; i < 200; ++i) strcat(han, "\xe4\xb8\xad");
    CHECK_EQ_INT(exteria_upload_fit_name(han, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) <= 255 && valid_utf8(out) && strlen(out) % 3 == 0);
    /* a dot that begins the name is not an extension, and an enormous extension is cut with the rest */
    memset(name, 'c', 400); name[0] = '.'; name[400] = 0;
    CHECK_EQ_INT(exteria_upload_fit_name(name, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) == 255 && out[0] == '.');
    strcpy(name, "x."); memset(name + 2, 'e', 400); name[402] = 0;
    CHECK_EQ_INT(exteria_upload_fit_name(name, out, sizeof(out)), EXTERIA_OK);
    CHECK(strlen(out) == 255 && out[0] == 'x');
    /* a small buffer */
    CHECK_EQ_INT(exteria_upload_fit_name("long-name-of-a-file.mkv", small, sizeof(small)), EXTERIA_OK);
    CHECK(strlen(small) == 15 && !strcmp(small + 11, ".mkv") && !strncmp(small, "long-name-o", 11));
    /* arguments that cannot be served */
    CHECK_EQ_INT(exteria_upload_fit_name(NULL, out, sizeof(out)), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_upload_fit_name("a", NULL, 8), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_upload_fit_name("a", out, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_upload_fit_name("a", out, 0), EXTERIA_E_ARG);
    /* no room for even one whole character */
    char tiny[3];
    CHECK_EQ_INT(exteria_upload_fit_name("\xd0\xb4\xd0\xb4\xd0\xb4\xd0\xb4", tiny, 2), EXTERIA_E_ARG);
    CHECK(tiny[0] == 0);
    return test_finish("test_upload_name");
}
