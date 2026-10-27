#import <Foundation/Foundation.h>

#include "exteria_messages.h"
#include "exteria_photos.h"

@class ExteriaPhoto;

/* photos, stickers and thumbnails are well under this; a file that fills the part is longer than the part and fails
   with FILE_TOO_BIG instead of arriving cut */
#define EXTERIA_REMOTE_FILE_PART (256 * 1024)

/* where a file lives on the servers: a profile photo, a document or photo size of a message */
@interface ExteriaRemoteFile : NSObject {
    int32_t _dc;
    NSString *_key;
    int _kind;
    exteria_photo_ref _photo;
    exteria_media_ref _media;
    exteria_sticker_set_row _set;
}

/* nil when the ref carries nothing to fetch */
+ (ExteriaRemoteFile *)fileForPhoto:(ExteriaPhoto *)photo;
+ (ExteriaRemoteFile *)fileForMedia:(const exteria_media_ref *)ref;
+ (ExteriaRemoteFile *)fileForStickerSet:(const exteria_sticker_set_row *)set;

@property (nonatomic, readonly) int32_t dc;
/* one file, one key, usable as a file name: the same bytes always get the same key, and different bytes never share one */
@property (nonatomic, readonly, copy) NSString *key;

/* takes the file reference of another handle on the same file (a message read again after the server let the old reference expire); NO when it is not the
   same file */
- (BOOL)adoptReferenceOf:(ExteriaRemoteFile *)fresh;

/* the InputFileLocation of the file, built in arena */
- (exteria_status)buildLocation:(exteria_arena *)arena into:(exteria_tl_value **)out;

@end
