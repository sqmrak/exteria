#include "exteria_file_server.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#define IO_TIMEOUT_MS 30000
#define BODY_CHUNK 65536
#define PATH_MAX_LEN 1024
#define TYPE_MAX_LEN 64

/* linux has no SO_NOSIGPIPE and darwin has no MSG_NOSIGNAL; a client that hangs up must not kill the app with SIGPIPE */
#ifdef MSG_NOSIGNAL
#define SEND_FLAGS MSG_NOSIGNAL
#else
#define SEND_FLAGS 0
#endif

typedef struct served_entry {
    char name[EXTERIA_FILE_SERVER_NAME_MAX];
    char path[PATH_MAX_LEN];
    char type[TYPE_MAX_LEN];
} served_entry;

struct exteria_file_server {
    served_entry files[EXTERIA_FILE_SERVER_MAX_FILES];
    size_t count;
    int listen_fd;
    int wake[2];
    pthread_t thread;
    char chunk[BODY_CHUNK];
};

static int name_char_ok(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
}

static int name_ok(const char *name, size_t len) {
    size_t i;
    if (len == 0 || len >= EXTERIA_FILE_SERVER_NAME_MAX) return 0;
    if ((len == 1 && name[0] == '.') || (len == 2 && name[0] == '.' && name[1] == '.')) return 0;
    for (i = 0; i < len; ++i)
        if (!name_char_ok(name[i])) return 0;
    return 1;
}

static int ascii_lower(int c) {
    return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
}

/* digits only, no sign and no overflow; *end is left after the last digit */
static int parse_u64(const char *p, const char *limit, uint64_t *out, const char **end) {
    uint64_t value = 0;
    const char *start = p;
    while (p < limit && *p >= '0' && *p <= '9') {
        unsigned digit = (unsigned)(*p - '0');
        if (value > (UINT64_MAX - digit) / 10) return 0;
        value = value * 10 + digit;
        ++p;
    }
    if (p == start) return 0;
    *out = value;
    *end = p;
    return 1;
}

/* a range that does not parse, or more than one range, is ignored as RFC 9110 allows, and the whole file is sent */
static void parse_range(const char *value, const char *limit, exteria_file_request *out) {
    uint64_t a = 0, b = 0;
    const char *p = value;
    while (p < limit && (*p == ' ' || *p == '\t')) ++p;
    while (limit > p && (limit[-1] == ' ' || limit[-1] == '\t')) --limit;
    if (limit - p < 7 || strncmp(p, "bytes=", 6) != 0) return;
    p += 6;
    if (*p == '-') {
        if (!parse_u64(p + 1, limit, &b, &p) || p != limit) return;
        out->ranged = 1;
        out->suffix = 1;
        out->first = 0;
        out->last = b;
        return;
    }
    if (!parse_u64(p, limit, &a, &p) || p >= limit || *p != '-') return;
    ++p;
    if (p == limit) {
        b = UINT64_MAX;
    } else if (!parse_u64(p, limit, &b, &p) || p != limit || b < a) {
        return;
    }
    out->ranged = 1;
    out->first = a;
    out->last = b;
}

exteria_status exteria_file_request_parse(const char *head, size_t len, exteria_file_request *out) {
    const char *p, *end, *line_end, *method_end, *target, *target_end, *name_end;
    int head_method;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!head) return EXTERIA_E_ARG;
    end = head + len;
    line_end = NULL;
    for (p = head; p + 1 < end; ++p) {
        if (p[0] == '\r' && p[1] == '\n') {
            line_end = p;
            break;
        }
    }
    if (!line_end) return EXTERIA_E_MALFORMED;
    method_end = memchr(head, ' ', (size_t)(line_end - head));
    if (!method_end || method_end == head) return EXTERIA_E_MALFORMED;
    target = method_end + 1;
    target_end = memchr(target, ' ', (size_t)(line_end - target));
    if (!target_end || target_end == target) return EXTERIA_E_MALFORMED;
    if (line_end - (target_end + 1) != 8 || strncmp(target_end + 1, "HTTP/1.", 7) != 0) return EXTERIA_E_MALFORMED;
    if (method_end - head == 3 && strncmp(head, "GET", 3) == 0) head_method = 0;
    else if (method_end - head == 4 && strncmp(head, "HEAD", 4) == 0) head_method = 1;
    else return EXTERIA_E_UNSUPPORTED;
    out->head = head_method;

    p = line_end + 2;
    while (p < end) {
        const char *colon;
        const char *next = NULL;
        const char *q;
        for (q = p; q + 1 < end; ++q) {
            if (q[0] == '\r' && q[1] == '\n') {
                next = q;
                break;
            }
        }
        if (!next) return EXTERIA_E_MALFORMED;
        if (next == p) break;
        colon = memchr(p, ':', (size_t)(next - p));
        if (!colon || colon == p) return EXTERIA_E_MALFORMED;
        if (colon - p == 5) {
            static const char range[] = "range";
            int i, same = 1;
            for (i = 0; i < 5; ++i)
                if (ascii_lower((unsigned char)p[i]) != range[i]) same = 0;
            if (same) parse_range(colon + 1, next, out);
        }
        p = next + 2;
    }

    if (*target != '/') return EXTERIA_E_NOTFOUND;
    ++target;
    name_end = memchr(target, '?', (size_t)(target_end - target));
    if (!name_end) name_end = target_end;
    if (!name_ok(target, (size_t)(name_end - target))) return EXTERIA_E_NOTFOUND;
    memcpy(out->name, target, (size_t)(name_end - target));
    out->name[name_end - target] = '\0';
    return EXTERIA_OK;
}

exteria_status exteria_file_request_span(const exteria_file_request *request, uint64_t size, uint64_t *offset, uint64_t *length) {
    uint64_t last;
    if (!request || !offset || !length) return EXTERIA_E_ARG;
    *offset = 0;
    *length = 0;
    if (!request->ranged) {
        *length = size;
        return EXTERIA_OK;
    }
    if (request->suffix) {
        if (request->last == 0 || size == 0) return EXTERIA_E_LIMIT;
        *length = request->last < size ? request->last : size;
        *offset = size - *length;
        return EXTERIA_OK;
    }
    if (request->first >= size) return EXTERIA_E_LIMIT;
    last = request->last < size - 1 ? request->last : size - 1;
    *offset = request->first;
    *length = last - request->first + 1;
    return EXTERIA_OK;
}

/* waits for the client socket or for stop; 0 on stop, on a client silent past the timeout and on a poll failure, so stop never waits on a client */
static int wait_client(exteria_file_server *server, int fd, short events) {
    for (;;) {
        struct pollfd fds[2];
        int ready;
        fds[0].fd = fd;
        fds[0].events = events;
        fds[0].revents = 0;
        fds[1].fd = server->wake[0];
        fds[1].events = POLLIN;
        fds[1].revents = 0;
        ready = poll(fds, 2, IO_TIMEOUT_MS);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0 || fds[1].revents) return 0;
        return 1;
    }
}

static int send_all(exteria_file_server *server, int fd, const void *data, size_t len) {
    const char *p = (const char *)data;
    while (len > 0) {
        ssize_t sent = send(fd, p, len, SEND_FLAGS);
        if (sent < 0 && errno == EINTR) continue;
        if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (!wait_client(server, fd, POLLOUT)) return 0;
            continue;
        }
        if (sent <= 0) return 0;
        p += sent;
        len -= (size_t)sent;
    }
    return 1;
}

static void send_status(exteria_file_server *server, int fd, int code, const char *reason, const char *extra) {
    char head[256];
    int n = snprintf(head, sizeof(head), "HTTP/1.1 %d %s\r\n%sContent-Length: 0\r\nConnection: close\r\n\r\n", code, reason, extra ? extra : "");
    if (n > 0 && (size_t)n < sizeof(head)) (void)send_all(server, fd, head, (size_t)n);
}

/* the head ends at the first empty line; NULL from a client that sends more than the limit, stops early or stays silent past the timeout */
static size_t read_head(exteria_file_server *server, int fd, char *buf, size_t cap) {
    size_t len = 0;
    while (len < cap) {
        ssize_t got;
        if (!wait_client(server, fd, POLLIN)) return 0;
        got = recv(fd, buf + len, cap - len, 0);
        if (got < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (got <= 0) return 0;
        len += (size_t)got;
        if (len >= 4) {
            size_t i;
            for (i = 3; i < len; ++i)
                if (buf[i - 3] == '\r' && buf[i - 2] == '\n' && buf[i - 1] == '\r' && buf[i] == '\n') return i + 1;
        }
    }
    return 0;
}

static const served_entry *find_entry(const exteria_file_server *server, const char *name) {
    size_t i;
    for (i = 0; i < server->count; ++i)
        if (strcmp(server->files[i].name, name) == 0) return &server->files[i];
    return NULL;
}

static void send_body(exteria_file_server *server, int client, int file, uint64_t offset, uint64_t length) {
    char *chunk = server->chunk;
    if (lseek(file, (off_t)offset, SEEK_SET) == (off_t)-1) return;
    while (length > 0) {
        size_t want = length < BODY_CHUNK ? (size_t)length : BODY_CHUNK;
        ssize_t got = read(file, chunk, want);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) return;
        if (!send_all(server, client, chunk, (size_t)got)) return;
        length -= (uint64_t)got;
    }
}

static void serve_client(exteria_file_server *server, int client) {
    char head[EXTERIA_FILE_SERVER_HEAD_MAX];
    char reply[512];
    exteria_file_request request;
    const served_entry *entry;
    struct stat info;
    uint64_t offset = 0, length = 0, size;
    exteria_status status;
    int file, n;
    size_t len = read_head(server, client, head, sizeof(head));
    if (len == 0) return;
    status = exteria_file_request_parse(head, len, &request);
    if (status == EXTERIA_E_UNSUPPORTED) {
        send_status(server, client, 405, "Method Not Allowed", "Allow: GET, HEAD\r\n");
        return;
    }
    if (status == EXTERIA_E_NOTFOUND) {
        send_status(server, client, 404, "Not Found", NULL);
        return;
    }
    if (status != EXTERIA_OK) {
        send_status(server, client, 400, "Bad Request", NULL);
        return;
    }
    entry = find_entry(server, request.name);
    if (!entry) {
        send_status(server, client, 404, "Not Found", NULL);
        return;
    }
    file = open(entry->path, O_RDONLY);
    if (file < 0) {
        send_status(server, client, 404, "Not Found", NULL);
        return;
    }
    if (fstat(file, &info) != 0 || !S_ISREG(info.st_mode)) {
        close(file);
        send_status(server, client, 404, "Not Found", NULL);
        return;
    }
    size = (uint64_t)info.st_size;
    status = exteria_file_request_span(&request, size, &offset, &length);
    if (status != EXTERIA_OK) {
        char extra[64];
        snprintf(extra, sizeof(extra), "Content-Range: bytes */%llu\r\n", (unsigned long long)size);
        close(file);
        send_status(server, client, 416, "Range Not Satisfiable", extra);
        return;
    }
    if (request.ranged)
        n = snprintf(reply, sizeof(reply), "HTTP/1.1 206 Partial Content\r\nContent-Type: %s\r\nContent-Length: %llu\r\n"
                     "Content-Range: bytes %llu-%llu/%llu\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n",
                     entry->type, (unsigned long long)length, (unsigned long long)offset, (unsigned long long)(offset + length - 1),
                     (unsigned long long)size);
    else
        n = snprintf(reply, sizeof(reply), "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %llu\r\nAccept-Ranges: bytes\r\n"
                     "Connection: close\r\n\r\n", entry->type, (unsigned long long)length);
    if (n > 0 && (size_t)n < sizeof(reply) && send_all(server, client, reply, (size_t)n) && !request.head)
        send_body(server, client, file, offset, length);
    close(file);
}

/* nonblocking, so every wait goes through wait_client and can see stop */
static int prepare_client(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) return 0;
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    {
        int one = 1;
        (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    }
#endif
    return 1;
}

static void *serve_loop(void *arg) {
    exteria_file_server *server = (exteria_file_server *)arg;
    /* the byte stop writes to the wake pipe is the only signal between the threads, it stays unread so every later poll sees it */
    for (;;) {
        struct pollfd fds[2];
        int ready, client;
        fds[0].fd = server->listen_fd;
        fds[0].events = POLLIN;
        fds[0].revents = 0;
        fds[1].fd = server->wake[0];
        fds[1].events = POLLIN;
        fds[1].revents = 0;
        ready = poll(fds, 2, -1);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0 || fds[1].revents) break;
        if (!(fds[0].revents & POLLIN)) continue;
        client = accept(server->listen_fd, NULL, NULL);
        if (client < 0) continue;
        if (prepare_client(client)) serve_client(server, client);
        close(client);
    }
    return NULL;
}

static void close_fds(exteria_file_server *server) {
    if (server->listen_fd >= 0) close(server->listen_fd);
    if (server->wake[0] >= 0) close(server->wake[0]);
    if (server->wake[1] >= 0) close(server->wake[1]);
}

static int copy_bounded(char *dst, size_t cap, const char *src) {
    size_t len = src ? strlen(src) : 0;
    if (!src || len >= cap) return 0;
    memcpy(dst, src, len + 1);
    return 1;
}

exteria_status exteria_file_server_start(const exteria_served_file *files, size_t count, exteria_file_server **out, uint16_t *port) {
    exteria_file_server *server;
    struct sockaddr_in addr;
    socklen_t addr_len = sizeof(addr);
    size_t i;
    if (out) *out = NULL;
    if (port) *port = 0;
    if (!files || !out || !port || count == 0 || count > EXTERIA_FILE_SERVER_MAX_FILES) return EXTERIA_E_ARG;
    server = (exteria_file_server *)calloc(1, sizeof(*server));
    if (!server) return EXTERIA_E_NOMEM;
    server->listen_fd = -1;
    server->wake[0] = server->wake[1] = -1;
    for (i = 0; i < count; ++i) {
        served_entry *entry = &server->files[i];
        if (!files[i].name || !name_ok(files[i].name, strlen(files[i].name)) || !copy_bounded(entry->name, sizeof(entry->name), files[i].name) ||
            !copy_bounded(entry->path, sizeof(entry->path), files[i].path) ||
            !copy_bounded(entry->type, sizeof(entry->type), files[i].content_type ? files[i].content_type : "application/octet-stream") ||
            strpbrk(entry->type, "\r\n")) {
            free(server);
            return EXTERIA_E_ARG;
        }
    }
    server->count = count;
    if (pipe(server->wake) != 0) {
        server->wake[0] = server->wake[1] = -1;
        free(server);
        return EXTERIA_E_IO;
    }
    server->listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (server->listen_fd < 0 || bind(server->listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(server->listen_fd, 8) != 0 ||
        getsockname(server->listen_fd, (struct sockaddr *)&addr, &addr_len) != 0) {
        close_fds(server);
        free(server);
        return EXTERIA_E_IO;
    }
    (void)fcntl(server->listen_fd, F_SETFD, FD_CLOEXEC);
    /* a client gone between poll and accept would otherwise leave accept blocked and stop waiting on it */
    if (fcntl(server->listen_fd, F_SETFL, fcntl(server->listen_fd, F_GETFL, 0) | O_NONBLOCK) != 0) {
        close_fds(server);
        free(server);
        return EXTERIA_E_IO;
    }
    if (pthread_create(&server->thread, NULL, serve_loop, server) != 0) {
        close_fds(server);
        free(server);
        return EXTERIA_E_IO;
    }
    *port = ntohs(addr.sin_port);
    *out = server;
    return EXTERIA_OK;
}

void exteria_file_server_stop(exteria_file_server *server) {
    char byte = 1;
    if (!server) return;
    while (write(server->wake[1], &byte, 1) < 0 && errno == EINTR) {
    }
    pthread_join(server->thread, NULL);
    close_fds(server);
    free(server);
}
