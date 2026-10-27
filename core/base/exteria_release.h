#ifndef EXTERIA_RELEASE_H
#define EXTERIA_RELEASE_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

#define EXTERIA_RELEASE_TAG_MAX 80
#define EXTERIA_RELEASE_BODY_MAX 16384

#define EXTERIA_RELEASE_URL_MAX 384
/* the only place an update is fetched from; a url from the release json that does not start with it is never taken */
#define EXTERIA_RELEASE_DOWNLOAD_PREFIX "https://github.com/sqmrak/exteria/releases/download/"

typedef struct exteria_release {
    char tag[EXTERIA_RELEASE_TAG_MAX];
    char body[EXTERIA_RELEASE_BODY_MAX];
    /* the assets Exteria-<tag>.ipa and Exteria-<tag>.ipa.sha256, empty when the release lacks one or its url is foreign */
    char ipa_url[EXTERIA_RELEASE_URL_MAX];
    char sha_url[EXTERIA_RELEASE_URL_MAX];
    uint64_t ipa_size;
} exteria_release;

#define EXTERIA_RELEASE_HOST_MAX 64

/* splits an absolute https url of the release download path or of the hosts GitHub redirects it to (github.com and githubusercontent.com),
   with no credentials and no port other than 443; a relative url, plain http or any other host is EXTERIA_E_SECURITY. path keeps the query */
exteria_status exteria_release_url_split(const char *url, char *host, size_t host_cap, char *path, size_t path_cap);

/* the digest from a .sha256 asset: 64 hex digits, as `sha256sum` writes them (followed by a name) or alone, with an optional line end */
exteria_status exteria_release_parse_sha256(const char *text, size_t length, uint8_t out[32]);

exteria_status exteria_release_parse(const char *json, size_t length, exteria_release *out);
exteria_status exteria_release_compare(const char *remote, const char *installed, int *newer);

#endif
