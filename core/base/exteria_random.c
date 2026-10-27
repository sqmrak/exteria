#include "exteria_random.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

exteria_status exteria_random(void *buf, size_t n) {
    uint8_t *p = (uint8_t *)buf;
    int fd;
    if (n && !buf) return EXTERIA_E_ARG;
    if (!n) return EXTERIA_OK;
    fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return EXTERIA_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) { close(fd); return EXTERIA_E_IO; }
    while (n) {
        ssize_t got = read(fd, p, n);
        if (got < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return EXTERIA_E_IO;
        }
        if (got == 0) {
            close(fd);
            return EXTERIA_E_EOF;
        }
        p += got;
        n -= (size_t)got;
    }
    close(fd);
    return EXTERIA_OK;
}

exteria_status exteria_random_u64(uint64_t *out) {
    uint8_t b[8];
    exteria_status s;
    uint64_t v = 0;
    int i;
    if (!out) return EXTERIA_E_ARG;
    *out = 0;
    s = exteria_random(b, sizeof(b));
    if (s != EXTERIA_OK) {
        return s;
    }
    for (i = 0; i < 8; ++i) v = (v << 8) | b[i];
    *out = v;
    return EXTERIA_OK;
}
