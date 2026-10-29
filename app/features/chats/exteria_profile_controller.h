#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_sticker_library.h"

@class ExteriaProfileController;

@protocol ExteriaProfileControllerDelegate <NSObject>
/* the user confirmed; the answer arrives once the server has ended the session */
- (void)profileController:(ExteriaProfileController *)controller requestsSignOut:(void (^)(NSString *errorName))completion;
/* the settings button: the app shows its settings tab */
@end

/* who is signed in: photo, name and status, the buttons for a photo, the profile and the settings, the phone, the
   bio and the username, and under them our stories */
@interface ExteriaProfileController : UIViewController {
    id<ExteriaProfileControllerDelegate> _delegate;
}

@property (nonatomic, assign) id<ExteriaProfileControllerDelegate> delegate;
@property (nonatomic, assign) CGFloat bottomInset;
@property (nonatomic, retain) ExteriaAvatarCache *avatars;
/* the pictures of stories and gifts load from here */
@property (nonatomic, retain) ExteriaMediaCache *media;
/* a chat opened from the profile, such as the personal channel, needs this for its sticker panel */
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session;

@end
