#ifndef EXTERIA_FILE_SERVER_H
#define EXTERIA_FILE_SERVER_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* serves a few files of this process over plain http on 127.0.0.1, so installd can take an ipa through an itms-services manifest the way
   it takes one from a web site. one thread answers one connection at a time and closes it after the response; GET and HEAD of an exact
   name, with a single byte range */

#define EXTERIA_FILE_SERVER_MAX_FILES 4
#define EXTERIA_FILE_SERVER_NAME_MAX 64
#define EXTERIA_FILE_SERVER_HEAD_MAX 4096

typedef struct exteria_served_file {
    const char *name;           /* the url path without the leading slash: letters, digits and ._- */
    const char *path;
    const char *content_type;
} exteria_served_file;

typedef struct exteria_file_server exteria_file_server;

/* listens on an unused port of the loopback address; *port is set on success, *out is NULL on every failure */
exteria_status exteria_file_server_start(const exteria_served_file *files, size_t count, exteria_file_server **out, uint16_t *port);
/* stops the thread, waits for it and closes every descriptor; NULL is allowed */
void exteria_file_server_stop(exteria_file_server *server);

typedef struct exteria_file_request {
    int head;                   /* HEAD, no body is sent */
    char name[EXTERIA_FILE_SERVER_NAME_MAX];
    int ranged;
    int suffix;                 /* bytes=-N: the last first bytes */
    uint64_t first;
    uint64_t last;              /* UINT64_MAX for bytes=N- */
} exteria_file_request;

/* reads the request line and the Range header of a complete head. EXTERIA_E_UNSUPPORTED for a method other than GET or HEAD,
   EXTERIA_E_NOTFOUND for a path that is not one plain name, EXTERIA_E_MALFORMED for anything else that does not parse */
exteria_status exteria_file_request_parse(const char *head, size_t len, exteria_file_request *out);

/* the bytes a request covers in a file of size bytes; EXTERIA_E_LIMIT when a range does not fit the file (416) */
exteria_status exteria_file_request_span(const exteria_file_request *request, uint64_t size, uint64_t *offset, uint64_t *length);

#endif
