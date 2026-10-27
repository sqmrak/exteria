#import <UIKit/UIKit.h>

#import "exteria_photo.h"
#import "exteria_session.h"

/* profile photos for the lists: a bounded memory cache over a folder on disk, and one download per photo however
   many rows ask for it; disk reads and decodes run on a private queue */
@interface ExteriaAvatarCache : NSObject

- (id)initWithSession:(ExteriaSession *)session directory:(NSString *)directory;

/* the image if memory has it, nil otherwise; never touches the disk or the network */
- (UIImage *)cachedImageForPhoto:(ExteriaPhoto *)photo;

/* the completion runs on the main thread, once, with the image or nil when the photo could not be had; a photo
   that failed is not asked for again for a while */
- (void)loadImageForPhoto:(ExteriaPhoto *)photo completion:(void (^)(UIImage *image))completion;

/* keeps the picture of this photo in memory for good, whatever the budget evicts: the account's own face is drawn
   on four screens and a tab, and a decode each time they appear is what made it blink in */
- (void)pinPhoto:(ExteriaPhoto *)photo;

/* what the photos on disk take, and a way to drop them all; the memory copies go too, and loads still running finish
   with nil. clear returns after the files are gone, so diskBytes right after it reads zero */
- (unsigned long long)diskBytes;
- (void)clear;

@end
