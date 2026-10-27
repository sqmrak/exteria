#include "exteria_tgc_cipher.h"
#include "test_util.h"

/* packets made by an independent implementation of the tgcalls scheme (python hashlib and the openssl command
   line), with the key byte i = (i * 7 + 3) mod 256 */
static const uint8_t caller_packet[31] = {
    0x17, 0xF4, 0xC2, 0xBD, 0xFF, 0xA1, 0xEE, 0xFD, 0x3B, 0x1F, 0x8C, 0xEA,
    0xC2, 0x22, 0xFE, 0x8E, 0xFA, 0x4F, 0x37, 0x7B, 0x8D, 0x25, 0x14, 0x72,
    0xD7, 0x56, 0x05, 0xA8, 0xF3, 0x73, 0xA6,
};
static const uint8_t callee_packet[42] = {
    0x1F, 0x10, 0xC1, 0x95, 0x20, 0x11, 0xFE, 0x0D, 0xDA, 0x6C, 0x27, 0x35,
    0x5A, 0x4D, 0x9F, 0x62, 0x14, 0xAF, 0x66, 0xFA, 0xCE, 0xE4, 0xEA, 0x2A,
    0xE9, 0x00, 0x4C, 0xA8, 0xE5, 0xC3, 0xC8, 0x40, 0x8B, 0x51, 0x74, 0xD7,
    0xD9, 0xD6, 0x9C, 0xB7, 0xAA, 0x67,
};
static const uint8_t flagged_packet[25] = {
    0x0F, 0x9F, 0x9B, 0xC9, 0x6E, 0x52, 0x20, 0xF7, 0x83, 0xBA, 0x80, 0x69,
    0xF0, 0x03, 0x41, 0x26, 0x22, 0x1A, 0x6C, 0x38, 0xED, 0x76, 0xAF, 0xFC,
    0x3C,
};

static uint8_t key[EXTERIA_TGC_KEY_LEN];

static void make_key(void) {
    int i;
    for (i = 0; i < EXTERIA_TGC_KEY_LEN; ++i) key[i] = (uint8_t)(i * 7 + 3);
}

static void known_answers(void) {
    exteria_tgc_cipher caller, callee;
    uint8_t out[64], sealed[64];
    size_t n = 0;
    CHECK_EQ_INT(exteria_tgc_cipher_init(&caller, key, 1), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_cipher_init(&callee, key, 0), EXTERIA_OK);
    /* the callee opens what the caller sealed, and the caller seals the very same bytes */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&callee, caller_packet, sizeof(caller_packet), out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 11);
    CHECK(memcmp(out, "hello, call", 11) == 0);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&caller, (const uint8_t *)"hello, call", 11, sealed, sizeof(sealed), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, sizeof(caller_packet));
    CHECK(memcmp(sealed, caller_packet, n) == 0);

    CHECK_EQ_INT(exteria_tgc_cipher_open(&caller, callee_packet, sizeof(callee_packet), out, sizeof(out), &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 22);
    CHECK(memcmp(out, "{\"@type\":\"MediaState\"}", 22) == 0);

    /* the flag bits of the counter are not part of the number: this opens as counter 5 and a second copy is a repeat */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&callee, flagged_packet, sizeof(flagged_packet), out, sizeof(out), &n), EXTERIA_OK);
    CHECK(memcmp(out, "flags", 5) == 0);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&callee, flagged_packet, sizeof(flagged_packet), out, sizeof(out), &n), EXTERIA_E_RETRY);
}

static void round_trips_and_direction(void) {
    exteria_tgc_cipher caller, callee, other;
    uint8_t sealed[EXTERIA_TGC_PACKET_MAX], out[EXTERIA_TGC_SIGNAL_MAX], plain[EXTERIA_TGC_SIGNAL_MAX];
    size_t n = 0, m = 0, i;
    exteria_tgc_cipher_init(&caller, key, 1);
    exteria_tgc_cipher_init(&callee, key, 0);
    exteria_tgc_cipher_init(&other, key, 1);
    for (i = 0; i < sizeof(plain); ++i) plain[i] = (uint8_t)(i * 13u + 1u);
    {
        static const size_t sizes[] = {1, 2, 15, 16, 17, 1000, EXTERIA_TGC_SIGNAL_MAX};
        size_t s;
        for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); ++s) {
            CHECK_EQ_INT(exteria_tgc_cipher_seal(&caller, plain, sizes[s], sealed, sizeof(sealed), &n), EXTERIA_OK);
            CHECK_EQ_INT(n, sizes[s] + 20);
            CHECK_EQ_INT(exteria_tgc_cipher_open(&callee, sealed, n, out, sizeof(out), &m), EXTERIA_OK);
            CHECK_EQ_INT(m, sizes[s]);
            CHECK(memcmp(out, plain, m) == 0);
            CHECK_EQ_INT(exteria_tgc_cipher_seal(&callee, plain, sizes[s], sealed, sizeof(sealed), &n), EXTERIA_OK);
            CHECK_EQ_INT(exteria_tgc_cipher_open(&caller, sealed, n, out, sizeof(out), &m), EXTERIA_OK);
            CHECK(memcmp(out, plain, m) == 0);
        }
    }
    /* a side cannot open its own packets: the keys of the two directions differ */
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&caller, plain, 20, sealed, sizeof(sealed), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&other, sealed, n, out, sizeof(out), &m), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(m, 0);
    /* and the sealed bytes differ for the same plaintext at the next counter */
    {
        uint8_t again[64];
        size_t k = 0;
        CHECK_EQ_INT(exteria_tgc_cipher_seal(&caller, plain, 20, again, sizeof(again), &k), EXTERIA_OK);
        CHECK(memcmp(again, sealed, n) != 0);
    }
}

static void tampering(void) {
    exteria_tgc_cipher a, b;
    uint8_t sealed[64], out[64], copy[64];
    size_t n = 0, m = 0, i;
    exteria_tgc_cipher_init(&a, key, 1);
    exteria_tgc_cipher_init(&b, key, 0);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, (const uint8_t *)"0123456789", 10, sealed, sizeof(sealed), &n), EXTERIA_OK);
    for (i = 0; i < n; ++i) {
        memcpy(copy, sealed, n);
        copy[i] ^= 0x01;
        CHECK_EQ_INT(exteria_tgc_cipher_open(&b, copy, n, out, sizeof(out), &m), EXTERIA_E_SECURITY);
    }
    /* a failed packet used up nothing: the real one still opens, once */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, n, out, sizeof(out), &m), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, n, out, sizeof(out), &m), EXTERIA_E_RETRY);
    /* truncated and extended */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, n - 1, out, sizeof(out), &m), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, 20, out, sizeof(out), &m), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, 0, out, sizeof(out), &m), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, EXTERIA_TGC_PACKET_MAX + 1, out, sizeof(out), &m), EXTERIA_E_MALFORMED);
}

static void replay_window(void) {
    exteria_tgc_cipher a, b;
    uint8_t sealed[200][40], out[40];
    size_t lens[200], m = 0;
    int i;
    exteria_tgc_cipher_init(&a, key, 1);
    exteria_tgc_cipher_init(&b, key, 0);
    for (i = 0; i < 200; ++i) CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, (const uint8_t *)"x", 1, sealed[i], 40, &lens[i]), EXTERIA_OK);
    /* counters 1..200 sit at indexes 0..199; deliver 100 first, then those within 63 behind it in reverse order */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[99], lens[99], out, sizeof(out), &m), EXTERIA_OK);
    for (i = 98; i >= 36; --i) CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[i], lens[i], out, sizeof(out), &m), EXTERIA_OK);
    /* counter 36 is 64 behind 100: too old, and so is everything before it */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[35], lens[35], out, sizeof(out), &m), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[0], lens[0], out, sizeof(out), &m), EXTERIA_E_RETRY);
    /* every one already seen is refused */
    for (i = 36; i <= 99; ++i) CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[i], lens[i], out, sizeof(out), &m), EXTERIA_E_RETRY);
    /* a jump of more than the window forgets the old ones and keeps the new one */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[199], lens[199], out, sizeof(out), &m), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[199], lens[199], out, sizeof(out), &m), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[100], lens[100], out, sizeof(out), &m), EXTERIA_E_RETRY);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed[150], lens[150], out, sizeof(out), &m), EXTERIA_OK);
}

static void limits(void) {
    exteria_tgc_cipher a, b;
    uint8_t plain[EXTERIA_TGC_SIGNAL_MAX + 1] = {0}, sealed[64], out[16], big[EXTERIA_TGC_PACKET_MAX];
    size_t n = 7, m = 7;
    exteria_tgc_cipher_init(&a, key, 1);
    exteria_tgc_cipher_init(&b, key, 0);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, 0, sealed, sizeof(sealed), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, sizeof(plain), big, sizeof(big), &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, 10, sealed, 29, &n), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, 10, sealed, 30, &n), EXTERIA_OK);
    CHECK_EQ_INT(n, 30);
    /* a packet that does not fit the output is refused without being counted as seen */
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, n, out, 9, &m), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(m, 0);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, sealed, n, out, 10, &m), EXTERIA_OK);
    /* the counter runs out at its 30 bit limit */
    a.sent = EXTERIA_TGC_COUNTER_MAX - 1;
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, 1, sealed, sizeof(sealed), &n), EXTERIA_OK);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(&a, plain, 1, sealed, sizeof(sealed), &n), EXTERIA_E_STATE);
    CHECK_EQ_INT(n, 0);
    /* null arguments */
    CHECK_EQ_INT(exteria_tgc_cipher_init(NULL, key, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_cipher_init(&a, NULL, 1), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_cipher_seal(NULL, plain, 1, sealed, sizeof(sealed), &n), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_tgc_cipher_open(&b, NULL, 30, out, sizeof(out), &m), EXTERIA_E_ARG);
    exteria_tgc_cipher_wipe(&a);
    CHECK_EQ_INT(a.key[0], 0);
    exteria_tgc_cipher_wipe(NULL);
}

int main(void) {
    make_key();
    known_answers();
    round_trips_and_direction();
    tampering();
    replay_window();
    limits();
    return test_finish("test_tgc_cipher");
}
