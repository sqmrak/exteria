#ifndef EXTERIA_ZIP_H
#define EXTERIA_ZIP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* a reader for the zip of an ipa, kept to what `zip -qrX` writes: stored and deflate entries, no zip64, no encryption, no links.
   The archive is read from a file with explicit offsets and never held in memory; every name, size and offset is checked before use */

#define EXTERIA_ZIP_MAX_ENTRIES 4096u
#define EXTERIA_ZIP_NAME_MAX 256u
#define EXTERIA_ZIP_MAX_ENTRY_SIZE (128u * 1024u * 1024u)
#define EXTERIA_ZIP_MAX_TOTAL_SIZE (256u * 1024u * 1024u)

typedef struct exteria_zip exteria_zip;

typedef struct exteria_zip_entry {
    char name[EXTERIA_ZIP_NAME_MAX];    /* relative, no "..", no leading slash; a directory ends with a slash */
    uint32_t crc32;
    uint32_t size;                      /* uncompressed */
    uint32_t packed;
    uint32_t mode;                      /* the unix permission bits, 0644 when the archive does not say */
    uint32_t offset;                    /* of the local header */
    int deflated;
    int is_dir;
} exteria_zip_entry;

/* EXTERIA_E_MALFORMED for a broken or unsafe archive, EXTERIA_E_UNSUPPORTED for a valid feature this reader leaves out */
exteria_status exteria_zip_open(const char *path, exteria_zip **out);
void exteria_zip_close(exteria_zip *zip);
size_t exteria_zip_count(const exteria_zip *zip);
const exteria_zip_entry *exteria_zip_entry_at(const exteria_zip *zip, size_t index);

/* inflates one file entry to dest, which must not exist, checking its length and crc; a partial file is removed on failure.
   progress, when set, gets the bytes written so far, and a return other than EXTERIA_OK stops the extraction with that status */
typedef exteria_status (*exteria_zip_progress)(void *ctx, uint32_t written);
exteria_status exteria_zip_extract(const exteria_zip *zip, const exteria_zip_entry *entry, const char *dest, exteria_zip_progress progress, void *ctx);

/* 1 when the file at path has the entry's size and crc, 0 when it differs or is absent; a read failure is an error */
exteria_status exteria_zip_entry_matches(const exteria_zip_entry *entry, const char *path, int *same);

#endif
