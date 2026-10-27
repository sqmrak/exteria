#include "exteria_http.h"
#include "test_util.h"

static exteria_status parse(const char *text, int eof, int *status, size_t *body_len, char *body, size_t cap) {
    exteria_http_response r;
    exteria_status s = exteria_http_parse_response((const uint8_t *)text, strlen(text), eof, &r, (uint8_t *)body, cap);
    if (status) *status = r.status;
    if (body_len) *body_len = r.body_len;
    return s;
}

static void framed_by_length(void) {
    char body[64];
    int status = 0;
    size_t n = 0;
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX: y\r\n\r\nhello", 0, &status, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(status, 200);
    CHECK_EQ_INT(n, 5);
    CHECK_MEM(body, "hello", 5);
    /* extra bytes after the body are not part of it */
    CHECK_EQ_INT(parse("HTTP/1.0 201 Created\r\ncontent-length: 2\r\n\r\nokEXTRA", 0, &status, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(n, 2);
    CHECK_EQ_INT(status, 201);
    /* a body cut short is not complete, even at the end of the connection */
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhel", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhel", 1, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", 0, &status, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(n, 0);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 70\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(parse("HTTP/1.1 204 No Content\r\n\r\n", 0, &status, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(status, 204);
    /* the same length twice is fine, two different ones are not */
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nab", 0, NULL, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nabc", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: +2\r\n\r\nab", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 1234567890\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
}

static void framed_by_chunks(void) {
    char body[64];
    size_t n = 0;
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6;ext=1\r\n world\r\n0\r\n\r\n", 0, NULL, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(n, 11);
    CHECK_MEM(body, "hello world", 11);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: Chunked\r\n\r\nA\r\n0123456789\r\n0\r\nTrailer: x\r\n\r\n", 0, NULL, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(n, 10);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\r\n0\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX0\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n123456789\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n80\r\n", 0, NULL, NULL, body, 16), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n0\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n0\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
}

static void framed_by_close(void) {
    char body[64];
    size_t n = 0;
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nrest of it", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nrest of it", 1, NULL, &n, body, sizeof(body)), EXTERIA_OK);
    CHECK_EQ_INT(n, 10);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\n\r\nxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", 1, NULL, NULL, body, 8), EXTERIA_E_LIMIT);
}

static void malformed_heads(void) {
    char body[16];
    CHECK_EQ_INT(parse("", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200", 1, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("<html>captive portal</html>\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/2 200\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 2000 OK\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 20x OK\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 99 OK\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 600 X\r\nContent-Length: 0\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 100 Continue\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200OK\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nNoColonHere\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\n Folded: line\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nBad Name: x\r\n\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n", 0, NULL, NULL, body, sizeof(body)), EXTERIA_E_TRUNCATED);
    CHECK_EQ_INT(parse("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n", 1, NULL, NULL, body, sizeof(body)), EXTERIA_E_MALFORMED);
    CHECK_EQ_INT(exteria_http_parse_response(NULL, 0, 0, NULL, NULL, 0), EXTERIA_E_ARG);
}

static void header_limit(void) {
    static uint8_t big[EXTERIA_HTTP_MAX_HEADERS + 2000];
    exteria_http_response r;
    uint8_t body[4];
    size_t n = 17;
    memcpy(big, "HTTP/1.1 200 OK\r\n", 17);
    while (n + 20 < sizeof(big)) {
        memcpy(big + n, "X-Filler: aaaaaaaa\r\n", 20);
        n += 20;
    }
    CHECK_EQ_INT(exteria_http_parse_response(big, n, 0, &r, body, sizeof(body)), EXTERIA_E_LIMIT);
}

int main(void) {
    framed_by_length();
    framed_by_chunks();
    framed_by_close();
    malformed_heads();
    header_limit();
    return test_finish("test_shiro_http");
}
