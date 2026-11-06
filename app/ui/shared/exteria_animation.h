#import <UIKit/UIKit.h>

#include "exteria_motion.h"

/* retarget from the visible layer so dismissing during entry never jumps */
void ExteriaAnimateView(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        exteria_motion_curve curve, void (^completion)(BOOL finished));
void ExteriaAnimateViewAfter(UIView *view, CGAffineTransform transform, CGFloat alpha,
                             exteria_motion_curve curve, NSTimeInterval delay, void (^completion)(BOOL finished));
/* a card with rounded corners that clip its rows, or with a shadow, is drawn off screen again on every frame it moves, and an old gpu cannot keep up with that. drawn once
   into a bitmap it moves and fades as a picture; the bitmap is dropped when the move ends, because a card that changes inside a cache is drawn twice */
void ExteriaCacheForMotion(UIView *view);
void ExteriaUncacheAfterMotion(UIView *view);
/* gives the shadow of a card its shape, so it is not worked out from the alpha of the card and its rows on every frame */
void ExteriaSetShadowPath(UIView *card, CGFloat radius);
/* puts a view where frame says without disturbing its transform: the frame of a view that is being scaled or moved by an animation is not the place it stands in, and a layout pass
   that wrote it moved the card by the size of the move for one frame. bounds and center do not depend on the transform */
void ExteriaPlaceView(UIView *view, CGRect frame);
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

/* the curve every popup, menu, dialog and sheet comes and goes on, so none has a motion of its own: the emphasized curves of material 3 in the modern theme, the
   plain ease out and ease in of the system in the classic one */
exteria_motion_curve ExteriaPopupCurve(BOOL entering);
/* the size a popup that scales in starts from and leaves to: a small step in the modern theme, a smaller one in the classic */
CGFloat ExteriaPopupScale(void);
