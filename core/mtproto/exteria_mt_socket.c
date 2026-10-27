#include "exteria_mt_socket.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include <stdlib.h>

#include "exteria_clock.h"
#include "exteria_faketls.h"
#include "exteria_random.h"
#include "exteria_mt_traffic.h"
#include "exteria_socks.h"

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

struct exteria_mt_faketls {
    exteria_faketls_reader reader;
};

void exteria_mt_socket_init(exteria_mt_socket *s) {
    s->fd = -1;
    s->tls = NULL;
}

void exteria_mt_socket_close(exteria_mt_socket *s) {
    if (s->fd >= 0) close(s->fd);
    s->fd = -1;
    free(s->tls);
    s->tls = NULL;
}

static exteria_status set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return EXTERIA_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) return EXTERIA_E_IO;
    return EXTERIA_OK;
}

static int remaining_ms(uint64_t deadline) {
    uint64_t now = exteria_system_clock.monotonic_ms(NULL);
    if (now >= deadline) return 0;
    return deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
}

/* poll restarts after a signal with the time that is left, so a signal storm cannot stretch a timeout */
static exteria_status wait_fd(int fd, short events, uint64_t deadline) {
    for (;;) {
        struct pollfd p;
        int rc;
        p.fd = fd;
        p.events = events;
        p.revents = 0;
        rc = poll(&p, 1, remaining_ms(deadline));
        if (rc < 0) {
            if (errno == EINTR) continue;
            return EXTERIA_E_IO;
        }
        if (rc == 0) return EXTERIA_E_TIMEOUT;
        if (p.revents & POLLNVAL) return EXTERIA_E_IO;
        if (p.revents & (events | POLLERR | POLLHUP)) return EXTERIA_OK;
    }
}

static exteria_status connect_one(const struct addrinfo *ai, uint64_t deadline, int *out_fd) {
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    exteria_status s;
    int err = 0;
    socklen_t len = sizeof(err);
    if (fd < 0) return EXTERIA_E_IO;
#ifdef SO_NOSIGPIPE
    {
        /* ios has no MSG_NOSIGNAL, a write to a closed peer would kill the process */
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) { close(fd); return EXTERIA_E_IO; }
    }
#endif
    s = set_nonblocking(fd);
    if (s != EXTERIA_OK) {
        close(fd);
        return s;
    }
    if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        if (errno != EINPROGRESS && errno != EINTR) {
            close(fd);
            return EXTERIA_E_IO;
        }
        s = wait_fd(fd, POLLOUT, deadline);
        if (s != EXTERIA_OK) {
            close(fd);
            return s;
        }
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0 || err != 0) {
            close(fd);
            errno = err;
            return EXTERIA_E_IO;
        }
    }
    {
        int one = 1;
        (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
    *out_fd = fd;
    return EXTERIA_OK;
}

exteria_status exteria_mt_socket_connect(exteria_mt_socket *s, const char *host, uint16_t port, int timeout_ms) {
    struct addrinfo hints, *list = NULL, *ai;
    char service[8];
    uint64_t deadline;
    exteria_status last = EXTERIA_E_IO;
    if (!s || !host || !*host || !port || timeout_ms <= 0) return EXTERIA_E_ARG;
    if (s->fd >= 0) return EXTERIA_E_STATE;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(service, sizeof(service), "%u", (unsigned)port);
    if (getaddrinfo(host, service, &hints, &list) != 0 || !list) return EXTERIA_E_IO;
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (ai = list; ai; ai = ai->ai_next) {
        int fd = -1;
        last = connect_one(ai, deadline, &fd);
        if (last == EXTERIA_OK) {
            s->fd = fd;
            break;
        }
        if (remaining_ms(deadline) == 0) {
            last = EXTERIA_E_TIMEOUT;
            break;
        }
    }
    freeaddrinfo(list);
    return last;
}

exteria_status exteria_mt_socket_adopt(exteria_mt_socket *s, int fd) {
    if (!s || fd < 0) return EXTERIA_E_ARG;
    if (s->fd >= 0) return EXTERIA_E_STATE;
    s->fd = fd;
    return EXTERIA_OK;
}

static exteria_status raw_write_all(exteria_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms) {
    uint64_t deadline;
    if (!s || s->fd < 0 || (len && !data) || timeout_ms <= 0) return EXTERIA_E_ARG;
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    while (len) {
        ssize_t n = send(s->fd, data, len, MSG_NOSIGNAL);
        if (n < 0) {
            exteria_status w;
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) return EXTERIA_E_IO;
            w = wait_fd(s->fd, POLLOUT, deadline);
            if (w != EXTERIA_OK) return w;
            continue;
        }
        if (n == 0) return EXTERIA_E_EOF;
        exteria_traffic_add((uint64_t)n, 0);
        data += n;
        len -= (size_t)n;
    }
    return EXTERIA_OK;
}

static exteria_status raw_read(exteria_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms) {
    uint64_t deadline;
    if (got) *got = 0;
    if (!s || s->fd < 0 || !buf || cap == 0 || !got || timeout_ms < 0) return EXTERIA_E_ARG;
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (;;) {
        ssize_t n = recv(s->fd, buf, cap, 0);
        if (n > 0) {
            *got = (size_t)n;
            exteria_traffic_add(0, (uint64_t)n);
            return EXTERIA_OK;
        }
        if (n == 0) return EXTERIA_E_EOF;
        if (errno == EINTR) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) return EXTERIA_E_IO;
        {
            exteria_status w = wait_fd(s->fd, POLLIN, deadline);
            if (w != EXTERIA_OK) return w;
        }
    }
}

exteria_status exteria_mt_socket_write_all(exteria_mt_socket *s, const uint8_t *data, size_t len, int timeout_ms) {
    exteria_writer records;
    exteria_status status;
    if (!s || s->fd < 0 || (len && !data) || timeout_ms <= 0) return EXTERIA_E_ARG;
    if (!s->tls) return raw_write_all(s, data, len, timeout_ms);
    exteria_writer_init(&records, len + (len / EXTERIA_FAKETLS_RECORD_MAX + 1) * 5);
    status = exteria_faketls_wrap(data, len, &records);
    if (status == EXTERIA_OK) status = raw_write_all(s, records.data, records.len, timeout_ms);
    exteria_wipe(records.data, records.cap);
    exteria_writer_free(&records);
    return status;
}

/* the records come out as payload that is never longer than what was read, so a buffer of the caller's size always holds it; a read that only brought a
   header or a change cipher spec goes on waiting for payload within the time that is left */
exteria_status exteria_mt_socket_read(exteria_mt_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms) {
    uint8_t chunk[4096];
    uint64_t deadline;
    if (got) *got = 0;
    if (!s || s->fd < 0 || !buf || cap == 0 || !got || timeout_ms < 0) return EXTERIA_E_ARG;
    if (!s->tls) return raw_read(s, buf, cap, got, timeout_ms);
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (;;) {
        size_t raw = 0, payload = 0;
        exteria_status status = raw_read(s, chunk, cap < sizeof(chunk) ? cap : sizeof(chunk), &raw, remaining_ms(deadline));
        if (status != EXTERIA_OK) return status;
        status = exteria_faketls_unwrap(&s->tls->reader, chunk, raw, buf, cap, &payload);
        if (status != EXTERIA_OK) return status;
        if (payload) {
            *got = payload;
            return EXTERIA_OK;
        }
    }
}

exteria_status exteria_mt_socket_start_faketls(exteria_mt_socket *s, const uint8_t secret[16], const char *domain, int timeout_ms) {
    uint8_t entropy[EXTERIA_FAKETLS_ENTROPY_LEN], hello[EXTERIA_FAKETLS_HELLO_LEN], random[32];
    uint8_t *reply = NULL;
    size_t have = 0, total = 0;
    uint64_t deadline, now_ms;
    exteria_status status;
    if (!s || s->fd < 0 || !secret || !domain || timeout_ms <= 0) return EXTERIA_E_ARG;
    if (s->tls) return EXTERIA_E_STATE;
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    now_ms = exteria_system_clock.realtime_ms(NULL);
    status = exteria_random(entropy, sizeof(entropy));
    if (status == EXTERIA_OK) status = exteria_faketls_hello(secret, domain, (uint32_t)(now_ms / 1000u), entropy, hello, random);
    exteria_wipe(entropy, sizeof(entropy));
    if (status == EXTERIA_OK) status = raw_write_all(s, hello, sizeof(hello), timeout_ms);
    if (status == EXTERIA_OK) {
        reply = malloc(EXTERIA_FAKETLS_REPLY_MAX);
        if (!reply) status = EXTERIA_E_NOMEM;
    }
    /* the reply is read to the exact end of its three records, so none of the stream behind it is taken */
    while (status == EXTERIA_OK) {
        size_t want, got = 0;
        status = exteria_faketls_reply_progress(reply, have, &total);
        if (status == EXTERIA_OK) break;
        if (status != EXTERIA_E_RETRY) break;
        want = total > have ? total - have : (have < 5 ? 5 - have : 1);
        if (have + want > EXTERIA_FAKETLS_REPLY_MAX) {
            status = EXTERIA_E_MALFORMED;
            break;
        }
        {
            int left = remaining_ms(deadline);
            if (!left) {
                status = EXTERIA_E_TIMEOUT;
                break;
            }
            status = raw_read(s, reply + have, want, &got, left);
        }
        if (status == EXTERIA_OK) have += got;
    }
    if (status == EXTERIA_OK) status = exteria_faketls_check_reply(secret, random, reply, have);
    if (status == EXTERIA_OK) {
        s->tls = calloc(1, sizeof(*s->tls));
        if (!s->tls) status = EXTERIA_E_NOMEM;
    }
    free(reply);
    if (status != EXTERIA_OK) exteria_mt_socket_close(s);
    return status;
}

exteria_status exteria_mt_socket_connect_socks5(exteria_mt_socket *s, const char *proxy_host, uint16_t proxy_port,
                                                const char *user, const char *pass,
                                                const char *dest_host, uint16_t dest_port, int timeout_ms) {
    exteria_socks proxy;
    exteria_writer out;
    uint64_t deadline;
    exteria_status status;
    if (!s || timeout_ms <= 0) return EXTERIA_E_ARG;
    deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    exteria_writer_init(&out, 1024);
    status = exteria_socks_start(&proxy, dest_host, dest_port, user, pass, &out);
    if (status != EXTERIA_OK) goto done;
    status = exteria_mt_socket_connect(s, proxy_host, proxy_port, timeout_ms);
    if (status != EXTERIA_OK) goto done;
    while (status == EXTERIA_OK && proxy.state != EXTERIA_SOCKS_READY) {
        uint8_t bytes[262];
        size_t got = 0, used = 0;
        int left = remaining_ms(deadline);
        if (!left) { status = EXTERIA_E_TIMEOUT; break; }
        if (out.len) status = exteria_mt_socket_write_all(s, out.data, out.len, left);
        exteria_wipe(out.data, out.len);
        out.len = 0;
        left = remaining_ms(deadline);
        if (status == EXTERIA_OK && !left) status = EXTERIA_E_TIMEOUT;
        if (status == EXTERIA_OK) status = exteria_mt_socket_read(s, bytes, proxy.need - proxy.response_len, &got, left);
        if (status == EXTERIA_OK) status = exteria_socks_feed(&proxy, bytes, got, &used, &out);
        if (status == EXTERIA_OK && used != got) status = EXTERIA_E_MALFORMED;
    }
    if (status != EXTERIA_OK) exteria_mt_socket_close(s);
done:
    if (out.data) exteria_wipe(out.data, out.cap);
    exteria_writer_free(&out);
    exteria_socks_free(&proxy);
    return status;
}
