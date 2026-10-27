#import <UIKit/UIKit.h>

#import "exteria_message.h"

/* the lock screen and the control center show what plays and send its buttons back; both live in MediaPlayer,
   which is linked weakly and looked up by name, so a system without a piece of it simply goes without */

/* the song on the lock screen; rate is 0 while it is paused, and the elapsed time moves on its own at the rate while it plays */
void ExteriaNowPlayingShow(NSString *title, NSString *performer, UIImage *cover, NSTimeInterval position, NSTimeInterval duration, float rate);
void ExteriaNowPlayingClear(void);

/* asks for the remote buttons for as long as a song plays */
void ExteriaRemoteControlsStart(id target, SEL play, SEL pause, SEL toggle, SEL next, SEL previous);
void ExteriaRemoteControlsStop(id target);
