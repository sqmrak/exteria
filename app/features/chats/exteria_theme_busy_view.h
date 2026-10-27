#import <UIKit/UIKit.h>

/* what the person sees while the screens are made again after a change of the theme: the old screen slightly
   darkened, the duck of the animated sticker painting at an easel, and a line under it */
@interface ExteriaThemeBusyView : UIView

- (id)initWithFrame:(CGRect)frame;
/* the same view with another animated sticker of the bundle (a name without the extension), as the cleaning of the cache shows its duck with the mop */
- (id)initWithFrame:(CGRect)frame animation:(NSString *)animation;
/* the line under the duck; the theme's own until another change of the screens (the app icon) sets its own */
@property (nonatomic, copy) NSString *text;
/* runs the block once the duck has drawn its first frame, so the person sees it before the work stops the main thread; a duck that is slow to come
   is not waited for longer than a moment */
- (void)whenReady:(void (^)(void))block;
/* the duck starts and stops, because an animation that nobody sees costs a decoder thread */
- (void)startAnimating;
- (void)stopAnimating;

@end
