#ifndef EXTERIA_ZIPW_H
#define EXTERIA_ZIPW_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* a writer for the zip that the logs of the app are exported in: stored entries only, no zip64, no encryption, so what it writes is what
   exteria_zip_open reads and what every unzip tool takes. an entry is added whole from memory; the archive is on disk only after finish */

typedef struct exteria_zipw exteria_zipw;

/* creates the file, which must not exist yet (EXTERIA_E_STATE when it does) */
exteria_status exteria_zipw_begin(const char *path, exteria_zipw **out);
/* name is relative with no "..", no leading slash and no backslash, shorter than EXTERIA_ZIP_NAME_MAX; EXTERIA_E_LIMIT past 65534 entries or 4 GB */
exteria_status exteria_zipw_add(exteria_zipw *zip, const char *name, const uint8_t *data, size_t len, uint32_t mode);
/* writes the directory and closes the file; the writer is gone afterwards, whatever the result, and a failed archive is removed */
exteria_status exteria_zipw_finish(exteria_zipw *zip);
/* drops an archive that is not wanted: closes and removes the file */
void exteria_zipw_abort(exteria_zipw *zip);

#endif
