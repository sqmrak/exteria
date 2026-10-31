#import <UIKit/UIKit.h>

#include "exteria_motion.h"

/* retarget from the visible layer so dismissing during entry never jumps */
void ExteriaAnimateView(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        exteria_motion_curve curve, void (^completion)(BOOL finished));
void ExteriaAnimateViewAfter(UIView *view, CGAffineTransform transform, CGFloat alpha,
                             exteria_motion_curve curve, NSTimeInterval delay, void (^completion)(BOOL finished));
void ExteriaAnimatePosition(UIView *view, CGPoint position, exteria_motion_curve curve);
/* the view is already in its final state; this plays the way in from the given transform and alpha without
   touching it, the way ChatListItemAnimator brings in a new row */
void ExteriaAnimateEnter(UIView *view, CGAffineTransform from, CGFloat fromAlpha, exteria_motion_curve curve);
/* stops an enter that is still running, for a view that is reused */
void ExteriaCancelEnter(UIView *view);
/* the press feedback of ButtonBounce: the control shrinks by depth (0.05 is five percent) within 60 ms while a
   finger is on it and springs back past its size when the finger leaves */
void ExteriaAttachBounce(UIControl *control, CGFloat depth);

/* the rate a display link asks for, in frames a second: the link that is left alone runs at the full rate of the screen, 120 on the phones and tablets that have it, and
   the ones that only need to draw a 30 or a 60 frame say so; an old system that has no such call gets the interval of its 60 */
void ExteriaSetFrameRate(CADisplayLink *link, NSInteger framesPerSecond);
