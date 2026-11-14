#include "exteria_hello.h"

#include <string.h>

#define RECORD_HEADER 5u
#define RECORD_MAX 16384u
#define HANDSHAKE_CLIENT_HELLO 1u
#define RECORD_HANDSHAKE 22u
/* record header, handshake header, version and random: the session id length follows */
#define HELLO_FIXED 43u
#define EXTENSION_SERVER_NAME 0u

static size_t be16(const uint8_t *p) {
    return ((size_t)p[0] << 8) | p[1];
}

/* steps over a vector whose length takes width bytes. even is 1 for the cipher suites, which come in pairs */
static int skip_vector(const uint8_t *in, size_t len, size_t *pos, size_t width, int even) {
    size_t n;
    if (len - *pos < width) return 0;
    n = width == 1 ? in[*pos] : be16(in + *pos);
    *pos += width;
    if (n > len - *pos || (even && (n & 1u))) return 0;
    *pos += n;
    return 1;
}

/* the offset of the cut inside the server name, or 0 when the hello has none that can be cut */
static size_t name_cut(const uint8_t *in, size_t len, int midpoint) {
    size_t pos = HELLO_FIXED, end;
    if (pos >= len) return 0;
    if (!skip_vector(in, len, &pos, 1, 0) || !skip_vector(in, len, &pos, 2, 1) || !skip_vector(in, len, &pos, 1, 0)) return 0;
    if (len - pos < 2 || be16(in + pos) != len - pos - 2) return 0;
    pos += 2;
    end = len;
    while (end - pos >= 4) {
        size_t type = be16(in + pos), n = be16(in + pos + 2);
        pos += 4;
        if (n > end - pos) return 0;
        if (type == EXTENSION_SERVER_NAME) {
            /* list length, one host_name entry (type 0) with its own length, and a name of two bytes or more */
            if (n <= 6 || be16(in + pos) != n - 2 || in[pos + 2] != 0 || be16(in + pos + 3) != n - 5) return 0;
            return pos + 5 + (midpoint ? (n - 5) / 2 : 1);
        }
        pos += n;
    }
    return 0;
}

exteria_status exteria_hello_split(const uint8_t *input, size_t length, uint8_t *output, size_t capacity,
                               size_t *output_length, size_t *record_cut, int midpoint) {
    size_t record, cut;
    if (output_length) *output_length = 0;
    if (record_cut) *record_cut = 0;
    if (!input || !output || !output_length || !record_cut) return EXTERIA_E_ARG;
    if (length < HELLO_FIXED + 1 || input[0] != RECORD_HANDSHAKE || input[5] != HANDSHAKE_CLIENT_HELLO) return EXTERIA_E_MALFORMED;
    record = be16(input + 3);
    if (record + RECORD_HEADER != length || record > RECORD_MAX) return EXTERIA_E_MALFORMED;
    if ((((size_t)input[6] << 16) | ((size_t)input[7] << 8) | input[8]) != record - 4) return EXTERIA_E_MALFORMED;
    cut = name_cut(input, length, midpoint);
    if (cut <= RECORD_HEADER || cut >= length) return EXTERIA_E_MALFORMED;
    if (capacity < length || capacity - length < EXTERIA_HELLO_GROWTH) return EXTERIA_E_LIMIT;
    memcpy(output, input, cut);
    output[3] = (uint8_t)((cut - RECORD_HEADER) >> 8);
    output[4] = (uint8_t)(cut - RECORD_HEADER);
    memcpy(output + cut, input, 3);
    output[cut + 3] = (uint8_t)((length - cut) >> 8);
    output[cut + 4] = (uint8_t)(length - cut);
    memcpy(output + cut + RECORD_HEADER, input + cut, length - cut);
    *output_length = length + RECORD_HEADER;
    *record_cut = cut;
    return EXTERIA_OK;
}
