#include "exteria_socks.h"

#include <arpa/inet.h>
#include <string.h>

static exteria_status connect_request(exteria_socks *s, exteria_writer *out) {
    const uint8_t prefix[] = {5, 1, 0};
    size_t mark = out->len;
    exteria_status status = exteria_wr_bytes(out, prefix, sizeof(prefix));
    if (status == EXTERIA_OK) status = exteria_wr_bytes(out, s->target, s->target_len);
    if (status == EXTERIA_OK) { s->state = EXTERIA_SOCKS_CONNECT; s->need = 4; }
    else out->len = mark;
    return status;
}

exteria_status exteria_socks_start(exteria_socks *s, const char *host, uint16_t port,
                                  const char *username, const char *password, exteria_writer *out) {
    uint8_t address[16], greeting[] = {5, 1, 0};
    size_t len, user_len, pass_len, pos = 0;
    exteria_status status;
    if (!s) return EXTERIA_E_ARG;
    memset(s, 0, sizeof(*s));
    s->state = EXTERIA_SOCKS_FAILED;
    if (!host || !*host || !port || !out) return EXTERIA_E_ARG;
    len = strlen(host);
    if (inet_pton(AF_INET, host, address) == 1) {
        s->target[pos++] = 1;
        memcpy(s->target + pos, address, 4); pos += 4;
    } else if (inet_pton(AF_INET6, host, address) == 1) {
        s->target[pos++] = 4;
        memcpy(s->target + pos, address, 16); pos += 16;
    } else {
        size_t i;
        if (len > 255) return EXTERIA_E_LIMIT;
        for (i = 0; i < len; ++i) if ((unsigned char)host[i] <= 32 || (unsigned char)host[i] >= 127) return EXTERIA_E_ARG;
        s->target[pos++] = 3; s->target[pos++] = (uint8_t)len;
        memcpy(s->target + pos, host, len); pos += len;
    }
    s->target[pos++] = (uint8_t)(port >> 8);
    s->target[pos++] = (uint8_t)port;
    s->target_len = pos;
    if (username || password) {
        if (!username || !password) return EXTERIA_E_ARG;
        user_len = strlen(username); pass_len = strlen(password);
        if (!user_len || !pass_len || user_len > 255 || pass_len > 255) return EXTERIA_E_LIMIT;
        greeting[2] = 2;
        s->credentials[0] = 1;
        s->credentials[1] = (uint8_t)user_len;
        memcpy(s->credentials + 2, username, user_len);
        s->credentials[2 + user_len] = (uint8_t)pass_len;
        memcpy(s->credentials + 3 + user_len, password, pass_len);
        s->credentials_len = 3 + user_len + pass_len;
    }
    status = exteria_wr_bytes(out, greeting, sizeof(greeting));
    if (status == EXTERIA_OK) { s->state = EXTERIA_SOCKS_METHOD; s->need = 2; }
    return status;
}

exteria_status exteria_socks_feed(exteria_socks *s, const uint8_t *data, size_t len,
                                 size_t *consumed, exteria_writer *out) {
    exteria_status status = EXTERIA_OK;
    if (!consumed) return EXTERIA_E_ARG;
    *consumed = 0;
    if (!s || !out || (!data && len)) return EXTERIA_E_ARG;
    if (s->state == EXTERIA_SOCKS_FAILED) return EXTERIA_E_STATE;
    while (*consumed < len && s->state != EXTERIA_SOCKS_READY) {
        size_t take = s->need - s->response_len;
        if (take > len - *consumed) take = len - *consumed;
        if (s->need > sizeof(s->response)) { status = EXTERIA_E_LIMIT; break; }
        memcpy(s->response + s->response_len, data + *consumed, take);
        s->response_len += take;
        *consumed += take;
        if (s->response_len < s->need) break;
        if (s->state == EXTERIA_SOCKS_METHOD) {
            if (s->response[0] != 5 || s->response[1] != (s->credentials_len ? 2 : 0)) { status = EXTERIA_E_SECURITY; break; }
            if (s->credentials_len) {
                status = exteria_wr_bytes(out, s->credentials, s->credentials_len);
                exteria_wipe(s->credentials, sizeof(s->credentials));
                s->credentials_len = 0;
                s->state = EXTERIA_SOCKS_AUTH;
                s->need = 2;
            } else status = connect_request(s, out);
            s->response_len = 0;
        } else if (s->state == EXTERIA_SOCKS_AUTH) {
            if (s->response[0] != 1 || s->response[1] != 0) { status = EXTERIA_E_SECURITY; break; }
            status = connect_request(s, out);
            s->response_len = 0;
        } else if (s->state == EXTERIA_SOCKS_CONNECT) {
            if (s->response_len == 4) {
                s->reply = s->response[1];
                if (s->response[0] != 5 || s->response[2] || s->reply) { status = EXTERIA_E_IO; break; }
                if (s->response[3] == 1) s->need = 10;
                else if (s->response[3] == 4) s->need = 22;
                else if (s->response[3] == 3) s->need = 5;
                else { status = EXTERIA_E_MALFORMED; break; }
            } else if (s->response_len == 5 && s->response[3] == 3) {
                if (!s->response[4]) { status = EXTERIA_E_MALFORMED; break; }
                s->need = (size_t)s->response[4] + 7;
            } else s->state = EXTERIA_SOCKS_READY;
        }
        if (status != EXTERIA_OK) break;
    }
    if (status != EXTERIA_OK) { s->state = EXTERIA_SOCKS_FAILED; exteria_wipe(s->credentials, sizeof(s->credentials)); }
    return status;
}

void exteria_socks_free(exteria_socks *s) {
    if (s) exteria_wipe(s, sizeof(*s));
}
