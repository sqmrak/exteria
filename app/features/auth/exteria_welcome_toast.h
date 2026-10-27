#import <UIKit/UIKit.h>

/* what the card asks of an animated sticker; ExteriaLottieView answers both calls without declaring the protocol */
@protocol ExteriaToastSticker <NSObject>
- (void)setLoaded:(BOOL)loaded;
- (void)setPlaying:(BOOL)playing;
@end

/* a card that drops from the top of the login screen over everything else: an animated sticker, a title, a few
   lines and up to two buttons */
@interface ExteriaWelcomeToast : UIView

@property (nonatomic, retain) UIView *sticker;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *messageText;
/* the filled button; nil title leaves it out */
@property (nonatomic, copy) NSString *primaryTitle;
/* the plain text button beside it */
@property (nonatomic, copy) NSString *secondaryTitle;
@property (nonatomic, copy) void (^primaryHandler)(void);
@property (nonatomic, copy) void (^secondaryHandler)(void);
/* runs once, after the card has left, whatever the reason */
@property (nonatomic, copy) void (^dismissHandler)(void);
/* seconds after which the card leaves by itself; zero keeps it until it is dismissed */
@property (nonatomic, assign) NSTimeInterval lifetime;
/* the filled button shows this while it is busy and cannot be pressed; nil makes it live again */
@property (nonatomic, copy) NSString *busyTitle;

/* the height of what the card has to stay under, such as the status bar; a screen that turns sets it again and calls refresh */
@property (nonatomic, assign) CGFloat inset;

/* fits the card to the host and drops it in */
- (void)showInView:(UIView *)host inset:(CGFloat)inset;
/* the text and buttons changed while the card is up: it fits itself again, keeping its place */
- (void)refresh;
- (void)dismiss;
@property (nonatomic, readonly) BOOL isShown;

@end
