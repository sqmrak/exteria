#ifndef EXTERIA_UPDATE_H
#define EXTERIA_UPDATE_H

#include <stdint.h>

#include "exteria_status.h"

/* puts the files of a downloaded ipa into the app bundle that is running it. Only files that differ are written: they are inflated into
   a folder inside the bundle (so the final rename stays on one volume, and the small system partition of old phones holds just the
   changes), checked by length and crc, and only then moved over the old ones, the executable and Info.plist last. Files the ipa no
   longer has are left where they are */

typedef enum exteria_update_phase {
    EXTERIA_UPDATE_COMPARE,     /* reading the installed files to find the ones that differ; total is the bytes of the ipa's files */
    EXTERIA_UPDATE_STAGE,       /* inflating the changed files; total is their bytes */
    EXTERIA_UPDATE_COMMIT       /* moving them into place; total is their count, and the call cannot stop it */
} exteria_update_phase;

/* a return other than EXTERIA_OK stops the update before the first file is moved, and is returned as it is */
typedef exteria_status (*exteria_update_progress)(void *ctx, exteria_update_phase phase, uint64_t done, uint64_t total);

/* the ipa must hold Payload/<app_name>/ with the executable and Info.plist inside; EXTERIA_E_MALFORMED or EXTERIA_E_UNSUPPORTED for anything
   else, EXTERIA_E_STORAGE when the bundle's volume cannot hold the changes (checked before any file is written), EXTERIA_E_STATE when the
   bundle folder is not writable by this process. progress may be NULL */
exteria_status exteria_update_apply(const char *ipa_path, const char *bundle_path, const char *app_name, const char *executable,
                                    exteria_update_progress progress, void *ctx);

#endif
