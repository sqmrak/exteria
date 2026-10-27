#import "exteria_files.h"

#import <errno.h>
#import <fcntl.h>
#import <unistd.h>

NSString *ExteriaFilePath(NSString *directory, NSString *name) {
    return [directory stringByAppendingPathComponent:name];
}

NSString *ExteriaSessionPath(NSString *directory, int32_t dc) {
    return ExteriaFilePath(directory, [NSString stringWithFormat:@"session-%d.bin", (int)dc]);
}

NSString *ExteriaAccountPath(NSString *directory) {
    return ExteriaFilePath(directory, @"account.bin");
}

/* the file is written aside and renamed, so a crash never leaves half a key behind */
exteria_status ExteriaWriteFile(NSString *path, const uint8_t *data, size_t len) {
    NSString *temporary = [path stringByAppendingString:@".tmp"];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return EXTERIA_E_STORAGE;
    size_t done = 0;
    while (done < len) {
        ssize_t n = write(fd, data + done, len - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            close(fd);
            unlink(temporary.fileSystemRepresentation);
            return EXTERIA_E_STORAGE;
        }
        done += (size_t)n;
    }
    BOOL synced = fsync(fd) == 0;
    BOOL closed = close(fd) == 0;
    if (!synced || !closed || rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        return EXTERIA_E_STORAGE;
    }
    return EXTERIA_OK;
}

/* a missing file is EXTERIA_E_NOTFOUND; buf holds cap bytes and one more is read to catch a longer file */
exteria_status ExteriaReadFile(NSString *path, uint8_t *buf, size_t cap, size_t *len) {
    *len = 0;
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return errno == ENOENT ? EXTERIA_E_NOTFOUND : EXTERIA_E_STORAGE;
    size_t total = 0;
    for (;;) {
        ssize_t n = read(fd, buf + total, cap - total);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) {
            close(fd);
            return EXTERIA_E_STORAGE;
        }
        if (n == 0) break;
        total += (size_t)n;
        if (total == cap) break;
    }
    close(fd);
    *len = total;
    return EXTERIA_OK;
}
