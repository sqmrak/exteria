#import <UIKit/UIKit.h>

#import "exteria_attach_sheet.h"

/* picks a picture from the library and hands over a square jpeg ready to become a profile photo */
@interface ExteriaProfilePhotoPicker : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate, ExteriaAttachSheetDelegate>

/* host presents the picker; picked runs on the main thread with the path of a temporary jpeg, which the receiver
   deletes */
+ (void)pickFrom:(UIViewController *)host picked:(void (^)(NSString *path))picked unavailable:(void (^)(void))unavailable;
/* the same for a story: the whole picture is kept, shrunk to at most 1280 points on its long side, and not cut to a square */
+ (void)pickWholeFrom:(UIViewController *)host picked:(void (^)(NSString *path))picked unavailable:(void (^)(void))unavailable;

/* the sheet of the paperclip with only the grid of the library under "choose a photo or a video": a tap on a picture ends in picked with the path of a square jpeg, a tap on a video with the path
   of a square mp4 of ten seconds at most (video is YES); the receiver deletes the file. failed runs when the entry could not be read or made. The sheet stands over host, and the picker lives as
   long as the sheet does */
+ (void)pickWithSheetIn:(UIView *)host picked:(void (^)(NSString *path, BOOL video))picked failed:(void (^)(void))failed;

/* the middle square of a picture, shrunk and written as a jpeg off the main thread; completion runs on the main thread with the path, which the receiver deletes, or nil */
+ (void)squarePathFromImage:(UIImage *)image completion:(void (^)(NSString *path))completion;
/* what an entry of the gallery sheet is: its picture, or for a video the address of its movie (and no picture), or nothing at all when it could not be read; completion runs on the main thread */
+ (void)loadAssetURL:(NSURL *)url completion:(void (^)(UIImage *image, NSURL *movie))completion;
/* a movie as a profile video: the middle square of it, at most 640 points, ten seconds, without sound, as an mp4 under two megabytes when the encoder can; nil path when it cannot be made */
+ (void)squareVideoPathFromURL:(NSURL *)movie completion:(void (^)(NSString *path))completion;

@end
