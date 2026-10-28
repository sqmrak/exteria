#include "exteria_socks.h"
#include "exteria_mt_socket.h"
#include "test_util.h"
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void fragmented_reply(void) {
    exteria_socks s;
    exteria_writer out;
    size_t consumed, i;
    const uint8_t greeting[] = {5, 1, 0};
    const uint8_t method[] = {5, 0};
    const uint8_t request[] = {5, 1, 0, 1, 127, 0, 0, 1, 1, 187};
    const uint8_t reply[] = {5, 0, 0, 3, 3, 'p', 'x', 'y', 1, 187, 0xaa, 0xbb};
    exteria_writer_init(&out, 1024);
    CHECK_EQ_INT(exteria_socks_start(&s, "127.0.0.1", 443, NULL, NULL, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, sizeof(greeting));
    CHECK_MEM(out.data, greeting, sizeof(greeting));
    out.len = 0;
    for (i = 0; i < sizeof(method); ++i) {
        CHECK_EQ_INT(exteria_socks_feed(&s, method + i, 1, &consumed, &out), EXTERIA_OK);
        CHECK_EQ_INT(consumed, 1);
    }
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_CONNECT);
    CHECK_EQ_INT(out.len, sizeof(request));
    CHECK_MEM(out.data, request, sizeof(request));
    out.len = 0;
    for (i = 0; i < 9; ++i) {
        CHECK_EQ_INT(exteria_socks_feed(&s, reply + i, 1, &consumed, &out), EXTERIA_OK);
        CHECK_EQ_INT(consumed, 1);
        CHECK_EQ_INT(s.state, EXTERIA_SOCKS_CONNECT);
    }
    CHECK_EQ_INT(exteria_socks_feed(&s, reply + 9, 3, &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(consumed, 1);
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_READY);
    CHECK_EQ_INT(out.len, 0);
    exteria_socks_free(&s);
    exteria_writer_free(&out);
}

static void credentials_and_rejection(void) {
    exteria_socks s;
    exteria_writer out;
    size_t consumed, i;
    const uint8_t credentials[] = {1, 1, 'u', 1, 'p'};
    const uint8_t method[] = {5, 2};
    const uint8_t authenticated[] = {1, 0};
    const uint8_t downgrade[] = {5, 0};
    const uint8_t malformed[][5] = {
        {5, 0, 1, 1, 0}, {5, 0, 0, 2, 0}, {5, 0, 0, 3, 0}, {4, 0, 0, 1, 0}, {5, 5, 0, 1, 0}
    };
    exteria_writer_init(&out, 1024);
    CHECK_EQ_INT(exteria_socks_start(&s, "::1", 443, "u", "p", &out), EXTERIA_OK);
    CHECK_EQ_INT(out.data[2], 2);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_feed(&s, method, sizeof(method), &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, sizeof(credentials));
    CHECK_MEM(out.data, credentials, sizeof(credentials));
    for (i = 0; i < sizeof(s.credentials); ++i) CHECK_EQ_INT(s.credentials[i], 0);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_feed(&s, authenticated, sizeof(authenticated), &consumed, &out), EXTERIA_OK);
    CHECK_EQ_INT(out.len, 22);
    CHECK_EQ_INT(out.data[3], 4);
    exteria_socks_free(&s);
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_start(&s, "proxy.example", 443, "u", "p", &out), EXTERIA_OK);
    CHECK_EQ_INT(exteria_socks_feed(&s, downgrade, sizeof(downgrade), &consumed, &out), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(s.state, EXTERIA_SOCKS_FAILED);
    for (i = 0; i < sizeof(s.credentials); ++i) CHECK_EQ_INT(s.credentials[i], 0);
    exteria_socks_free(&s);
    for (i = 0; i < sizeof(malformed) / sizeof(malformed[0]); ++i) {
        out.len = 0;
        CHECK_EQ_INT(exteria_socks_start(&s, "proxy.example", 443, NULL, NULL, &out), EXTERIA_OK);
        CHECK_EQ_INT(exteria_socks_feed(&s, downgrade, sizeof(downgrade), &consumed, &out), EXTERIA_OK);
        CHECK(exteria_socks_feed(&s, malformed[i], sizeof(malformed[i]), &consumed, &out) != EXTERIA_OK);
        CHECK_EQ_INT(s.state, EXTERIA_SOCKS_FAILED);
        exteria_socks_free(&s);
    }
    out.len = 0;
    CHECK_EQ_INT(exteria_socks_start(&s, "bad host", 443, NULL, NULL, &out), EXTERIA_E_ARG);
    CHECK_EQ_INT(out.len, 0);
    exteria_writer_free(&out);
}

static void connected_socket(void) {
    int pair[2], status = 0;
    pid_t child;
    exteria_mt_socket socket;
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        uint8_t in[10];
        const uint8_t method[] = {5, 0};
        const uint8_t reply[] = {5, 0, 0, 1, 127, 0, 0, 1, 0, 1};
        close(pair[0]);
        if (recv(pair[1], in, 3, MSG_WAITALL) != 3 || in[0] != 5 || write(pair[1], method, 2) != 2 ||
            recv(pair[1], in, 10, MSG_WAITALL) != 10 || in[3] != 1 || in[4] != 127 ||
            write(pair[1], reply, sizeof(reply)) != (ssize_t)sizeof(reply)) _exit(1);
        close(pair[1]);
        _exit(0);
    }
    close(pair[1]);
    exteria_mt_socket_init(&socket);
    CHECK_EQ_INT(exteria_mt_socket_adopt(&socket, pair[0]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_socket_negotiate_socks5(&socket, NULL, NULL, "127.0.0.1", 443, 2000), EXTERIA_OK);
    CHECK(socket.fd >= 0);
    exteria_mt_socket_close(&socket);
    CHECK_EQ_INT(waitpid(child, &status, 0), child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    CHECK_EQ_INT(exteria_mt_socket_adopt(&socket, pair[0]), EXTERIA_OK);
    CHECK_EQ_INT(exteria_mt_socket_negotiate_socks5(&socket, NULL, NULL, "bad host", 443, 2000), EXTERIA_E_ARG);
    CHECK_EQ_INT(socket.fd, -1);
    close(pair[1]);
}

int main(void) {
    fragmented_reply();
    credentials_and_rejection();
    connected_socket();
    return test_finish("socks");
}
