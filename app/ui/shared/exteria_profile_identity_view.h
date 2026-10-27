#import <UIKit/UIKit.h>

#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"

/* the identity block of the Settings and Profile screens, one view so that both lay out the same */

#define EXTERIA_IDENTITY_AVATAR 108.0
/* the height of the block: the photo, the gap, the name, the line under it */
#define EXTERIA_IDENTITY_HEIGHT 192.0
/* where the photo starts under a 44 point bar: the same on both screens */
#define EXTERIA_IDENTITY_TOP 14.0
#define EXTERIA_IDENTITY_BAR 44.0

@interface ExteriaProfileIdentityView : UIView

@property (nonatomic, readonly) ExteriaAvatarView *avatar;
/* a tap on the photo */
@property (nonatomic, readonly) UIControl *avatarHit;
/* the blue camera that adds a photo */
@property (nonatomic, readonly) UIControl *badge;
@property (nonatomic, readonly) ExteriaEmojiLabel *name;
@property (nonatomic, readonly) UILabel *line;

/* the name, with the hammer of the developers after it when the person is one; a tap on the hammer says why it is there */
- (void)setName:(NSString *)name developer:(NSUInteger)marks;
- (void)setUploading:(BOOL)uploading;
/* the ring that cuts the camera out of the photo; it has to be the color behind the block (the default is the modern screen color) */
- (void)setBadgeRingColor:(UIColor *)color;

@end
