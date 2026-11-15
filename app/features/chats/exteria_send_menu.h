#import <UIKit/UIKit.h>

typedef enum {
    ExteriaSendMenuSilent = 0,
    ExteriaSendMenuLater,
    ExteriaSendMenuEffect
} ExteriaSendMenuChoice;

/* what a hold on the send button opens, as in Telegram: a card right over the button with the effects to send with (a private chat, when the list is in), then send without a sound and
   send later. it is a view over the screen and not a sheet from the bottom, since the keyboard stands in a window above the application's and a sheet at the bottom was never seen */
@interface ExteriaSendMenu : UIView
/* anchor is the send button in the coordinates of host; effects are ExteriaMessageEffect items, nil or empty for a chat that takes none */
+ (void)presentAboveRect:(CGRect)anchor inView:(UIView *)host effects:(NSArray *)effects handler:(void (^)(ExteriaSendMenuChoice choice, long long effectId))handler;
@end
