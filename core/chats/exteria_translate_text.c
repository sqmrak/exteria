#include "exteria_translate_text.h"

#include <string.h>

#define RUNS_MAX 1024u

exteria_status exteria_tr_restore_newlines(const char *original, const char *translated, char *out, size_t cap) {
    unsigned counts[RUNS_MAX];
    size_t runs = 0, i = 0, used = 0, run_index = 0;
    if (out && cap) out[0] = 0;
    if (!original || !translated || !out || !cap) return EXTERIA_E_ARG;
    while (original[i]) {
        if (original[i] == '\n') {
            unsigned n = 0;
            while (original[i] == '\n') {
                ++n;
                ++i;
            }
            if (runs < RUNS_MAX) counts[runs++] = n;
        } else {
            ++i;
        }
    }
    if (!runs) {
        size_t length = strlen(translated);
        if (length + 1 > cap) return EXTERIA_E_LIMIT;
        memcpy(out, translated, length + 1);
        return EXTERIA_OK;
    }
    for (i = 0; translated[i];) {
        if (translated[i] == '\n') {
            size_t run = 0, k, want;
            int joint;
            while (translated[i] == '\n') {
                ++run;
                ++i;
            }
            /* a run at the very start or end of the text has no part before or after it to be a joint of */
            joint = i > run && translated[i];
            want = (joint && run_index < runs) ? counts[run_index] : run;
            if (joint) ++run_index;
            if (used + want + 1 > cap) {
                out[0] = 0;
                return EXTERIA_E_LIMIT;
            }
            for (k = 0; k < want; ++k) out[used++] = '\n';
        } else {
            if (used + 2 > cap) {
                out[0] = 0;
                return EXTERIA_E_LIMIT;
            }
            out[used++] = translated[i++];
        }
    }
    out[used] = 0;
    return EXTERIA_OK;
}
