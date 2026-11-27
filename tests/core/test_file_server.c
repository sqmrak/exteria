#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "exteria_file_server.h"
#include "test_util.h"

static char g_dir[64];

#define PARSE(text) exteria_file_request_parse(text, sizeof(text) - 1, &r)

static void test_parse(void) {
    exteria_file_request r;
    static const char get[] = "GET /Exteria.ipa HTTP/1.1\r\nHost: 127.0.0.1\r\nRANGE: bytes=10-19\r\n\r\n";
    CHECK_EQ_INT(exteria_file_request_parse(get, sizeof(get) - 1, &r), EXTERIA_OK);
    CHECK(!strcmp(r.name, "Exteria.ipa"));
    CHECK_EQ_INT(r.head, 0);
    CHECK_EQ_INT(r.ranged, 1);
    CHECK_EQ_INT(r.first, 10);
    CHECK_EQ_INT(r.last, 19);
    CHECK_EQ_INT(PARSE("HEAD /manifest.plist?x=1 HTTP/1.0\r\n\r\n"), EXTERIA_OK);
    CHECK(!strcmp(r.name, "manifest.plist"));
    CHECK_EQ_INT(r.head, 1);
    CHECK_EQ_INT(r.ranged, 0);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: bytes=5-\r\n\r\n"), EXTERIA_OK);
    CHECK(r.ranged && !r.suffix && r.first == 5 && r.last == UINT64_MAX);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: bytes=-7\r\n\r\n"), EXTERIA_OK);
    CHECK(r.ranged && r.suffix && r.last == 7);
    /* a list of ranges, a reversed one and another unit are ignored and the whole file goes out */
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: bytes=0-1,4-5\r\n\r\n"), EXTERIA_OK);
    CHECK_EQ_INT(r.ranged, 0);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: bytes=9-3\r\n\r\n"), EXTERIA_OK);
    CHECK_EQ_INT(r.ranged, 0);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: items=0-1\r\n\r\n"), EXTERIA_OK);
    CHECK_EQ_INT(r.ranged, 0);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nRange: bytes=99999999999999999999-\r\n\r\n"), EXTERIA_OK);
    CHECK_EQ_INT(r.ranged, 0);

    CHECK_EQ_INT(PARSE("POST /a HTTP/1.1\r\n\r\n"), EXTERIA_E_UNSUPPORTED);
    CHECK_EQ_INT(PARSE("GET /../etc/passwd HTTP/1.1\r\n\r\n"), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(PARSE("GET /.. HTTP/1.1\r\n\r\n"), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(PARSE("GET / HTTP/1.1\r\n\r\n"), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(PARSE("GET /a%2fb HTTP/1.1\r\n\r\n"), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(PARSE("GET http://x/a HTTP/1.1\r\n\r\n"), EXTERIA_E_NOTFOUND);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(PARSE("GET /a\r\n\r\n"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(PARSE("GET /a HTTP/2.0\r\n\r\n"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(PARSE("GET /a HTTP/1.1\r\nno colon\r\n\r\n"), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(PARSE(""), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_file_request_parse(NULL, 0, &r), EXTERIA_E_ARG);
}

static void test_span(void) {
    exteria_file_request r;
    uint64_t offset, length;
    memset(&r, 0, sizeof(r));
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_OK);
    CHECK(offset == 0 && length == 100);
    CHECK_EQ_INT(exteria_file_request_span(&r, 0, &offset, &length), EXTERIA_OK);
    CHECK(length == 0);
    r.ranged = 1;
    r.first = 90;
    r.last = UINT64_MAX;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_OK);
    CHECK(offset == 90 && length == 10);
    r.first = 0;
    r.last = 500;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_OK);
    CHECK(offset == 0 && length == 100);
    r.first = 100;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_E_LIMIT);
    r.suffix = 1;
    r.last = 30;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_OK);
    CHECK(offset == 70 && length == 30);
    r.last = 300;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_OK);
    CHECK(offset == 0 && length == 100);
    r.last = 0;
    CHECK_EQ_INT(exteria_file_request_span(&r, 100, &offset, &length), EXTERIA_E_LIMIT);
    r.last = 5;
    CHECK_EQ_INT(exteria_file_request_span(&r, 0, &offset, &length), EXTERIA_E_LIMIT);
}

/* one request on a fresh connection, the whole answer up to the close */
static size_t ask(uint16_t port, const char *request, char *out, size_t cap) {
    struct sockaddr_in addr;
    size_t len = 0;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || write(fd, request, strlen(request)) != (ssize_t)strlen(request)) {
        close(fd);
        return 0;
    }
    for (;;) {
        ssize_t got = read(fd, out + len, cap - 1 - len);
        if (got <= 0) break;
        len += (size_t)got;
        if (len == cap - 1) break;
    }
    out[len] = '\0';
    close(fd);
    return len;
}

static const char *body_of(const char *reply) {
    const char *p = strstr(reply, "\r\n\r\n");
    return p ? p + 4 : "";
}

static void test_serve(void) {
    char ipa[128], manifest[128], missing[128];
    static char reply[300000];
    static char content[200000];
    exteria_served_file files[3];
    exteria_file_server *server = NULL;
    uint16_t port = 0;
    size_t i, len;
    FILE *f;
    for (i = 0; i < sizeof(content); ++i) content[i] = (char)('a' + i % 26);
    snprintf(ipa, sizeof(ipa), "%s/Exteria.ipa", g_dir);
    snprintf(manifest, sizeof(manifest), "%s/manifest.plist", g_dir);
    snprintf(missing, sizeof(missing), "%s/gone", g_dir);
    f = fopen(ipa, "wb");
    CHECK(f && fwrite(content, 1, sizeof(content), f) == sizeof(content));
    if (f) fclose(f);
    f = fopen(manifest, "wb");
    CHECK(f && fputs("<plist/>", f) >= 0);
    if (f) fclose(f);
    files[0].name = "Exteria.ipa";
    files[0].path = ipa;
    files[0].content_type = "application/octet-stream";
    files[1].name = "manifest.plist";
    files[1].path = manifest;
    files[1].content_type = "text/xml";
    files[2].name = "gone";
    files[2].path = missing;
    files[2].content_type = NULL;
    CHECK_EQ_INT(exteria_file_server_start(files, 3, &server, &port), EXTERIA_OK);
    if (!server) return;
    CHECK(port != 0);

    len = ask(port, "GET /Exteria.ipa HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 200 OK\r\n", 17));
    CHECK(strstr(reply, "Content-Length: 200000\r\n") != NULL);
    CHECK_EQ_INT(len - (size_t)(body_of(reply) - reply), sizeof(content));
    CHECK_MEM(body_of(reply), content, sizeof(content));

    ask(port, "GET /manifest.plist HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(strstr(reply, "Content-Type: text/xml\r\n") != NULL);
    CHECK(!strcmp(body_of(reply), "<plist/>"));

    ask(port, "HEAD /Exteria.ipa HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(strstr(reply, "Content-Length: 200000\r\n") != NULL);
    CHECK_EQ_INT(strlen(body_of(reply)), 0);

    ask(port, "GET /Exteria.ipa HTTP/1.1\r\nRange: bytes=26-51\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 206 ", 13));
    CHECK(strstr(reply, "Content-Range: bytes 26-51/200000\r\n") != NULL);
    CHECK(!strcmp(body_of(reply), "abcdefghijklmnopqrstuvwxyz"));

    ask(port, "GET /Exteria.ipa HTTP/1.1\r\nRange: bytes=200000-\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 416 ", 13));
    CHECK(strstr(reply, "Content-Range: bytes */200000\r\n") != NULL);

    ask(port, "GET /other HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 404 ", 13));
    /* a listed name whose file is gone is not found, not an empty 200 */
    ask(port, "GET /gone HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 404 ", 13));
    ask(port, "GET /../Exteria.ipa HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 404 ", 13));
    ask(port, "PUT /Exteria.ipa HTTP/1.1\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 405 ", 13));
    CHECK(strstr(reply, "Allow: GET, HEAD\r\n") != NULL);
    ask(port, "garbage\r\n\r\n", reply, sizeof(reply));
    CHECK(!strncmp(reply, "HTTP/1.1 400 ", 13));

    /* a client that connects and says nothing must not hold stop for the read timeout */
    {
        struct sockaddr_in addr;
        int idle = socket(AF_INET, SOCK_STREAM, 0);
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons(port);
        CHECK(idle >= 0 && connect(idle, (struct sockaddr *)&addr, sizeof(addr)) == 0);
        usleep(50000);
        {
            time_t before = time(NULL);
            exteria_file_server_stop(server);
            CHECK(time(NULL) - before <= 1);
        }
        if (idle >= 0) close(idle);
    }
    unlink(ipa);
    unlink(manifest);
}

static void test_start_refusals(void) {
    exteria_served_file file;
    exteria_file_server *server = (exteria_file_server *)1;
    uint16_t port = 1;
    file.name = "../x";
    file.path = "/tmp/x";
    file.content_type = NULL;
    CHECK_EQ_INT(exteria_file_server_start(&file, 1, &server, &port), EXTERIA_E_ARG);
    CHECK(server == NULL && port == 0);
    file.name = "a/b";
    CHECK_EQ_INT(exteria_file_server_start(&file, 1, &server, &port), EXTERIA_E_ARG);
    file.name = "ok";
    file.content_type = "text/plain\r\nX-Evil: 1";
    CHECK_EQ_INT(exteria_file_server_start(&file, 1, &server, &port), EXTERIA_E_ARG);
    file.content_type = NULL;
    file.path = NULL;
    CHECK_EQ_INT(exteria_file_server_start(&file, 1, &server, &port), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_file_server_start(&file, 0, &server, &port), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_file_server_start(&file, EXTERIA_FILE_SERVER_MAX_FILES + 1, &server, &port), EXTERIA_E_ARG);
    exteria_file_server_stop(NULL);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    snprintf(g_dir, sizeof(g_dir), "/tmp/exteria-files-XXXXXX");
    if (!mkdtemp(g_dir)) return 1;
    test_parse();
    test_span();
    test_serve();
    test_start_refusals();
    rmdir(g_dir);
    return test_finish("test_file_server");
}
