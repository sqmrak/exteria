#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_media_cache.h"
#import "exteria_session.h"
#import "exteria_rating_view.h"

/* the photo of a profile opened wide, the content of the head of the screen: the round photo grows to the width of the screen and pushes what is under it down, so it scrolls with the screen; the name and
   the status stand on its lower edge, and when there are two photos or more a strip for each runs along the top, the shown photo's one white, and the photos are paged by a swipe or a tap on the sides.
   The screen puts the view in its head, sets its frame (a circle over the round photo, then the wide frame), and calls the three steps below around the move */
@interface ExteriaProfileHeroView : UIView <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, readonly) ExteriaEmojiLabel *name;
@property (nonatomic, readonly) UILabel *status;
/* the room the words leave under them for the cards the screen puts on the lower edge; a screen with none sets a small one so the name stands on the edge */
@property (nonatomic, assign) CGFloat bottomRoom;
/* where the strips run along the top of the view: under the status bar, which the photo reaches up to */
@property (nonatomic, assign) CGFloat stripTop;
/* the badge of the rating to the left of the status ("[rating] online"); level 0 leaves it out; a tap on it runs the action of the target */
- (void)setRatingLevel:(int32_t)level target:(id)target action:(SEL)action;

/* the public photo of the signed in person, the photo those who may not see the main ones get: it comes as the last page after the profile photos, and a small round
   picture with its name at the right end of the status line jumps to it, and from it back to the first photo. nil leaves both out; set it before or after the list of photos came */
@property (nonatomic, retain) ExteriaMedia *publicPhoto;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media;
/* the photo alone, one picture that follows the frame, with the words and the strips hidden: the state the view is in while it moves */
- (void)beginMove;
/* the words and the strips come in, the pages take the place of the single picture, and the list of the photos is asked for */
- (void)finishOpen;
/* the words and the strips go, and the single picture takes the place of the pages, before the view shrinks */
- (void)beginClose;
/* the corner follows a move of the frame, which a view animation does not carry */
- (void)animateCornerTo:(CGFloat)radius duration:(NSTimeInterval)duration;
/* the height the wide photo takes in a head of the given width, in a screen of the given height */
+ (CGFloat)heightForWidth:(CGFloat)width screenHeight:(CGFloat)screenHeight;

@end
