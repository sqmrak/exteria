#import <UIKit/UIKit.h>

BOOL ExteriaPhotosAvailable(void);
void ExteriaRecentPhotos(NSUInteger limit, void (^completion)(NSArray *assets, NSString *error));
NSURL *ExteriaPhotoURL(id asset);
BOOL ExteriaPhotoURLIsVideo(NSURL *url);
/* the length in seconds of the video this asset is, 0 for a picture */
NSTimeInterval ExteriaPhotoVideoDuration(id asset);
void ExteriaPhotoThumbnail(id asset, CGFloat side, void (^completion)(UIImage *image));
int ExteriaPhotoPreview(NSURL *url, void (^completion)(UIImage *image, NSURL *movie, NSString *error));
/* the file as the library holds it, not the version shrunk for the screen: its bytes, the extension of its type
   and its name */
int ExteriaPhotoOriginal(NSURL *url, void (^completion)(NSData *data, NSString *extension, NSString *name, NSString *error));
void ExteriaCancelPhotoRequest(int request);
