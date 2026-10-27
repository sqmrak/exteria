/* a public dc cannot be a deterministic dependency of host tests */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_mt_handshake.h"
#include "exteria_mt_socket.h"
#include "exteria_mt_transport.h"

static int send_frame(exteria_mt_socket *sock, exteria_mt_transport *t, const uint8_t *packet, size_t len) {
    exteria_writer w;
    exteria_status s;
    exteria_writer_init(&w, 1 << 16);
    s = exteria_mt_transport_wrap(t, packet, len, 0, &w);
    if (s == EXTERIA_OK) s = exteria_mt_socket_write_all(sock, w.data, w.len, 10000);
    exteria_writer_free(&w);
    return (int)s;
}

static int recv_frame(exteria_mt_socket *sock, exteria_mt_transport *t, exteria_mt_frame *f) {
    uint8_t buf[4096];
    for (;;) {
        exteria_status s = exteria_mt_transport_next(t, f);
        size_t got = 0;
        if (s == EXTERIA_OK) return 0;
        if (s != EXTERIA_E_TRUNCATED) return (int)s;
        s = exteria_mt_socket_read(sock, buf, sizeof(buf), &got, 10000);
        if (s != EXTERIA_OK) return (int)s;
        s = exteria_mt_transport_feed(t, buf, got);
        if (s != EXTERIA_OK) return (int)s;
    }
}

int main(int argc, char **argv) {
    const char *host = argc > 1 ? argv[1] : "149.154.167.40";
    int is_test = argc > 2 ? atoi(argv[2]) : 1;
    int obfuscated = argc > 3 ? atoi(argv[3]) : 1;
    exteria_mt_socket sock;
    exteria_mt_transport t;
    exteria_mt_obfuscation obf;
    exteria_mt_handshake hs;
    exteria_mt_hs_config cfg;
    exteria_writer out, first;
    exteria_mt_frame f;
    exteria_status s;
    int rc;
    memset(&obf, 0, sizeof(obf));
    obf.enabled = obfuscated;
    obf.dc_id = (int16_t)(is_test ? 10002 : 2);
    memset(&cfg, 0, sizeof(cfg));
    cfg.dc_id = 2;
    cfg.is_test = is_test;
    exteria_mt_socket_init(&sock);
    exteria_mt_transport_init(&t);
    exteria_writer_init(&out, 1 << 16);
    exteria_writer_init(&first, 1 << 16);
    s = exteria_mt_socket_connect(&sock, host, 443, 10000);
    if (s != EXTERIA_OK) {
        printf("connect failed: %s\n", exteria_status_name(s));
        return 2;
    }
    s = exteria_mt_transport_start(&t, EXTERIA_MT_INTERMEDIATE, &obf, &first);
    if (s != EXTERIA_OK) return 3;
    exteria_mt_hs_init(&hs, &cfg);
    s = exteria_mt_hs_start(&hs, &out);
    if (s != EXTERIA_OK) return 4;
    if (exteria_mt_transport_wrap(&t, out.data, out.len, 0, &first) != EXTERIA_OK) return 5;
    if (exteria_mt_socket_write_all(&sock, first.data, first.len, 10000) != EXTERIA_OK) return 6;
    while (hs.state != EXTERIA_MT_HS_DONE && hs.state != EXTERIA_MT_HS_FAILED) {
        rc = recv_frame(&sock, &t, &f);
        if (rc != 0) {
            printf("receive failed in state %d: %s\n", (int)hs.state, exteria_status_name((exteria_status)rc));
            return 7;
        }
        if (f.kind == EXTERIA_MT_FRAME_ERROR) {
            printf("transport error %d\n", (int)f.error_code);
            return 8;
        }
        out.len = 0;
        s = exteria_mt_hs_receive(&hs, f.data, f.len, exteria_mt_transport_padded(&t), &out);
        if (s != EXTERIA_OK) {
            printf("handshake failed: %s\n", exteria_status_name(s));
            return 9;
        }
        if (out.len && send_frame(&sock, &t, out.data, out.len) != 0) return 10;
    }
    {
        const exteria_mt_hs_result *r = exteria_mt_hs_result_get(&hs);
        if (!r) return 11;
        printf("handshake ok, key id %016llx salt %016llx time offset %lld ms\n",
               (unsigned long long)r->key.id, (unsigned long long)r->server_salt, (long long)r->time_offset_ms);
    }
    exteria_mt_socket_close(&sock);
    exteria_mt_transport_free(&t);
    exteria_writer_free(&out);
    exteria_writer_free(&first);
    return 0;
}
