/* a public dc cannot be a deterministic dependency of host tests.
   Asks for a login code for a number that cannot exist, so no message is sent: the answer shows whether the
   api id and hash are accepted and whether the client, the transport and the auth state machine work end to end.
   a PHONE_MIGRATE answer counts as success: it comes from the server after the credentials were accepted.
   usage: EXTERIA_API_ID=... EXTERIA_API_HASH=... probe_login [dc] [number] */
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_client.h"
#include "exteria_mt_socket.h"
#include "exteria_session_file.h"

typedef struct probe {
    exteria_mt_socket sock;
    exteria_mt_session_state session;
    int have_session;
    int done;
    exteria_auth_state state;
    exteria_status status;
    char error[128];
} probe;

static exteria_status send_bytes(void *ctx, int32_t dc, const uint8_t *data, size_t len) {
    probe *p = ctx;
    (void)dc;
    return exteria_mt_socket_write_all(&p->sock, data, len, 10000);
}

static exteria_status load(void *ctx, int32_t dc, exteria_mt_session_state *out) {
    probe *p = ctx;
    (void)dc;
    if (!p->have_session) return EXTERIA_E_NOTFOUND;
    *out = p->session;
    return EXTERIA_OK;
}

static exteria_status save(void *ctx, int32_t dc, const exteria_mt_session_state *s) {
    probe *p = ctx;
    (void)dc;
    p->session = *s;
    p->have_session = 1;
    return EXTERIA_OK;
}

static void auth(void *ctx, exteria_auth_state state, exteria_status status, const exteria_tl_value *value, const char *error) {
    probe *p = ctx;
    (void)value;
    p->state = state;
    p->status = status;
    snprintf(p->error, sizeof(p->error), "%s", error ? error : "");
    /* starting a login cancels the previous one, which reports a clean idle first; a refused request reports idle with its error */
    if (state != EXTERIA_AUTH_WAITING && (state != EXTERIA_AUTH_IDLE || status != EXTERIA_OK)) p->done = 1;
}

static void report(void *ctx, exteria_status status, const char *boundary) {
    (void)ctx;
    fprintf(stderr, "client error at %s: %s\n", boundary, exteria_status_name(status));
}

int main(int argc, char **argv) {
    const char *hash = getenv("EXTERIA_API_HASH");
    const char *id = getenv("EXTERIA_API_ID");
    int dc = argc > 1 ? atoi(argv[1]) : 2;
    const char *number = argc > 2 ? argv[2] : "+99966123456";
    probe p;
    exteria_client client;
    exteria_client_events events;
    exteria_mt_client_config config;
    exteria_status status;
    int rounds;
    if (!id || !hash) {
        fprintf(stderr, "set EXTERIA_API_ID and EXTERIA_API_HASH\n");
        return 1;
    }
    memset(&p, 0, sizeof(p));
    exteria_mt_socket_init(&p.sock);
    memset(&events, 0, sizeof(events));
    events.ctx = &p;
    events.send = send_bytes;
    events.load_session = load;
    events.save_session = save;
    events.auth = auth;
    events.error = report;
    memset(&config, 0, sizeof(config));
    config.dc_id = dc;
    config.transport = EXTERIA_MT_INTERMEDIATE;
    config.obfuscation.enabled = 1;
    config.obfuscation.dc_id = (int16_t)dc;
    config.api_id = atoi(id);
    config.device_model = "probe";
    config.system_version = "host";
    config.app_version = "0.1.0";
    config.lang_pack = "ios";
    config.lang_code = "en";
    status = exteria_client_init(&client, &config, hash, &events);
    if (status != EXTERIA_OK) { printf("init failed: %s\n", exteria_status_name(status)); return 2; }
    status = exteria_mt_socket_connect(&p.sock, exteria_dc_host(dc), exteria_dc_port(), 10000);
    if (status != EXTERIA_OK) { printf("connect failed: %s\n", exteria_status_name(status)); return 3; }
    status = exteria_client_connect(&client);
    if (status != EXTERIA_OK) { printf("client connect failed: %s\n", exteria_status_name(status)); return 4; }
    status = exteria_auth_phone(&client.auth, number, NULL);
    if (status != EXTERIA_OK) { printf("auth_phone failed: %s\n", exteria_status_name(status)); return 5; }
    for (rounds = 0; rounds < 200 && !p.done; ++rounds) {
        struct pollfd fd;
        uint8_t buf[16384];
        size_t got = 0;
        uint32_t next = 0;
        fd.fd = p.sock.fd;
        fd.events = POLLIN;
        fd.revents = 0;
        if (poll(&fd, 1, 500) > 0) {
            status = exteria_mt_socket_read(&p.sock, buf, sizeof(buf), &got, 0);
            if (status == EXTERIA_OK) status = exteria_client_feed(&client, buf, got);
            if (status != EXTERIA_OK && status != EXTERIA_E_RETRY && status != EXTERIA_E_TIMEOUT) {
                printf("link failed: %s\n", exteria_status_name(status));
                return 6;
            }
        }
        (void)exteria_client_tick(&client, &next);

    }
    printf("auth state %d, status %s, error \"%s\"\n", (int)p.state, exteria_status_name(p.status), p.error);
    exteria_client_free(&client);
    exteria_mt_socket_close(&p.sock);
    return p.done ? 0 : 7;
}
