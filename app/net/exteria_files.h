#import <Foundation/Foundation.h>

#include "exteria_status.h"

/* the files the session keeps in its directory: one key file per data center, and the account file */
NSString *ExteriaFilePath(NSString *directory, NSString *name);
NSString *ExteriaSessionPath(NSString *directory, int32_t dc);
NSString *ExteriaAccountPath(NSString *directory);

/* the file is written aside and renamed, so a crash never leaves half of it behind; mode 0600 */
exteria_status ExteriaWriteFile(NSString *path, const uint8_t *data, size_t len);
/* a missing file is EXTERIA_E_NOTFOUND; buf holds cap bytes and the read stops there, so a caller that
   wants to catch a longer file passes one byte more than it expects */
exteria_status ExteriaReadFile(NSString *path, uint8_t *buf, size_t cap, size_t *len);
