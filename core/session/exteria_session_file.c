#include "exteria_session_file.h"

#include <string.h>

#include "exteria_crypto.h"
#include "exteria_random.h"

static const uint8_t session_magic[4] = {'E', 'X', 'S', '1'};
static const uint8_t sealed_magic[4] = {'E', 'X', 'E', '1'};
static const uint8_t account_magic[4] = {'E', 'X', 'A', '1'};

static const char *const dc_hosts[EXTERIA_DC_MAX] = {
    "149.154.175.50", "149.154.167.51", "149.154.175.100", "149.154.167.91", "149.154.171.5"
};

const char *exteria_dc_host(int32_t dc_id) {
    if (dc_id < 1 || dc_id > EXTERIA_DC_MAX) return NULL;
    return dc_hosts[dc_id - 1];
}

uint16_t exteria_dc_port(void) {
    return 443;
}

exteria_status exteria_session_pack(int32_t dc_id, const exteria_mt_session_state *session,
                                    uint8_t *out, size_t cap, size_t *len) {
    if (len) *len = 0;
    if (!session || !out || !len || !exteria_dc_host(dc_id)) return EXTERIA_E_ARG;
    if (cap < EXTERIA_SESSION_FILE_LEN) return EXTERIA_E_LIMIT;
    memcpy(out, session_magic, 4);
    exteria_put_u32le(out + 4, (uint32_t)dc_id);
    memcpy(out + 8, session->auth_key, EXTERIA_MT_AUTH_KEY_LEN);
    exteria_put_u64le(out + 8 + EXTERIA_MT_AUTH_KEY_LEN, session->server_salt);
    exteria_put_u64le(out + 16 + EXTERIA_MT_AUTH_KEY_LEN, (uint64_t)session->time_offset_ms);
    *len = EXTERIA_SESSION_FILE_LEN;
    return EXTERIA_OK;
}

exteria_status exteria_session_unpack(const uint8_t *data, size_t len, int32_t expected_dc,
                                      exteria_mt_session_state *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!data || !exteria_dc_host(expected_dc)) return EXTERIA_E_ARG;
    if (len != EXTERIA_SESSION_FILE_LEN || memcmp(data, session_magic, 4) != 0) return EXTERIA_E_MALFORMED;
    /* a key stored for another data center would fail the handshake with a confusing error */
    if (exteria_get_u32le(data + 4) != (uint32_t)expected_dc) return EXTERIA_E_MALFORMED;
    memcpy(out->auth_key, data + 8, EXTERIA_MT_AUTH_KEY_LEN);
    out->server_salt = exteria_get_u64le(data + 8 + EXTERIA_MT_AUTH_KEY_LEN);
    out->time_offset_ms = (int64_t)exteria_get_u64le(data + 16 + EXTERIA_MT_AUTH_KEY_LEN);
    return EXTERIA_OK;
}

static void seal_ad(int32_t dc_id, uint8_t ad[8]) {
    memcpy(ad, sealed_magic, 4);
    exteria_put_u32le(ad + 4, (uint32_t)dc_id);
}

exteria_status exteria_session_seal(const uint8_t key[EXTERIA_SESSION_KEY_LEN], int32_t dc_id,
                                    const exteria_mt_session_state *session, uint8_t *out, size_t cap, size_t *len) {
    uint8_t plain[EXTERIA_SESSION_FILE_LEN];
    uint8_t ad[8];
    size_t plain_len = 0;
    exteria_status status;
    if (len) *len = 0;
    if (!key || !out || !len) return EXTERIA_E_ARG;
    if (cap < EXTERIA_SESSION_SEALED_LEN) return EXTERIA_E_LIMIT;
    status = exteria_session_pack(dc_id, session, plain, sizeof(plain), &plain_len);
    if (status == EXTERIA_OK) status = exteria_random(out + 4, EXTERIA_CHACHA_NONCE_LEN);
    if (status == EXTERIA_OK) {
        memcpy(out, sealed_magic, 4);
        seal_ad(dc_id, ad);
        status = exteria_chacha20poly1305_seal(key, out + 4, ad, sizeof(ad), plain, plain_len, out + 16,
                                               out + 16 + plain_len);
    }
    exteria_wipe(plain, sizeof(plain));
    if (status != EXTERIA_OK) {
        exteria_wipe(out, EXTERIA_SESSION_SEALED_LEN);
        return status;
    }
    *len = EXTERIA_SESSION_SEALED_LEN;
    return EXTERIA_OK;
}

exteria_status exteria_session_open(const uint8_t key[EXTERIA_SESSION_KEY_LEN], const uint8_t *data, size_t len,
                                    int32_t expected_dc, exteria_mt_session_state *out, int *plain) {
    uint8_t buf[EXTERIA_SESSION_FILE_LEN];
    uint8_t ad[8];
    exteria_status status;
    if (plain) *plain = 0;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!key || !plain || !data || !exteria_dc_host(expected_dc)) return EXTERIA_E_ARG;
    if (len == EXTERIA_SESSION_FILE_LEN) {
        status = exteria_session_unpack(data, len, expected_dc, out);
        if (status == EXTERIA_OK) *plain = 1;
        return status;
    }
    if (len != EXTERIA_SESSION_SEALED_LEN || memcmp(data, sealed_magic, 4) != 0) return EXTERIA_E_MALFORMED;
    seal_ad(expected_dc, ad);
    status = exteria_chacha20poly1305_open(key, data + 4, ad, sizeof(ad), data + 16, EXTERIA_SESSION_FILE_LEN, buf,
                                           data + 16 + EXTERIA_SESSION_FILE_LEN);
    if (status == EXTERIA_OK) status = exteria_session_unpack(buf, sizeof(buf), expected_dc, out);
    exteria_wipe(buf, sizeof(buf));
    if (status != EXTERIA_OK) memset(out, 0, sizeof(*out));
    return status;
}

exteria_status exteria_account_pack(int32_t dc_id, int64_t account_id, uint8_t *out, size_t cap, size_t *len) {
    if (len) *len = 0;
    if (!out || !len || !exteria_dc_host(dc_id) || account_id <= 0) return EXTERIA_E_ARG;
    if (cap < EXTERIA_ACCOUNT_FILE_LEN) return EXTERIA_E_LIMIT;
    memcpy(out, account_magic, 4);
    exteria_put_u32le(out + 4, (uint32_t)dc_id);
    exteria_put_u64le(out + 8, (uint64_t)account_id);
    *len = EXTERIA_ACCOUNT_FILE_LEN;
    return EXTERIA_OK;
}

exteria_status exteria_account_unpack(const uint8_t *data, size_t len, int32_t *dc_id, int64_t *account_id) {
    uint32_t dc;
    int64_t account;
    if (dc_id) *dc_id = 0;
    if (account_id) *account_id = 0;
    if (!data || !dc_id || !account_id) return EXTERIA_E_ARG;
    if (len != EXTERIA_ACCOUNT_FILE_LEN || memcmp(data, account_magic, 4) != 0) return EXTERIA_E_MALFORMED;
    dc = exteria_get_u32le(data + 4);
    account = (int64_t)exteria_get_u64le(data + 8);
    if (dc < 1 || dc > EXTERIA_DC_MAX || account <= 0) return EXTERIA_E_MALFORMED;
    *dc_id = (int32_t)dc;
    *account_id = account;
    return EXTERIA_OK;
}
