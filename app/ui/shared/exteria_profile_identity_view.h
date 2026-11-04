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
/* how much taller than EXTERIA_IDENTITY_HEIGHT the block is at this width: the badges after a long name move to the next line, and the block grows by those lines */
- (CGFloat)extraHeightForWidth:(CGFloat)width;
/* the account the name is of, which the plate of a mark reads to say something of its own about this person */
@property (nonatomic, assign) long long userId;
- (void)setName:(NSString *)name developer:(NSUInteger)marks;
/* the same with the mark of the account after the name: its emoji status, else the Premium star */
- (void)setName:(NSString *)name badge:(long long)badge developer:(NSUInteger)marks;
/* the name is drawn again, for a status picture that landed after it was laid out */
- (void)redrawName;
- (void)setUploading:(BOOL)uploading;
/* the ring that cuts the camera out of the photo; it has to be the color behind the block (the default is the modern screen color) */
- (void)setBadgeRingColor:(UIColor *)color;

@end
