#import <Foundation/Foundation.h>

#include "exteria_session_file.h"

/* the session files of one account directory, sealed with a key that belongs to the device. both the main link and
   the media links read and write them through these two calls */

/* EXTERIA_E_NOTFOUND when there is no usable file: a missing one, or one that is damaged or sealed with a key
   that is gone (it is deleted then, and a new handshake replaces it). EXTERIA_E_STORAGE while the keychain is
   locked before the first unlock, the file is left alone then. a file from before sealing is read and sealed
   again in place */
exteria_status ExteriaSessionLoad(NSString *directory, int32_t dc, exteria_mt_session_state *out);
exteria_status ExteriaSessionStore(NSString *directory, int32_t dc, const exteria_mt_session_state *state);
