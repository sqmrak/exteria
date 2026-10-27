#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

/* the height a bar of this kind is laid out in, and the room its ends keep for the handle */
#define ExteriaWaveProgressHeight 28.0
#define ExteriaWaveProgressInset 6.0

/* the progress bar of Material 3 Expressive: what is done is a wave that travels while the bar is active and lies flat when it is not, a
   pill handle marks the place, and what is left is a plain line. It is a slider when the user may touch it (the song of the music card) and
   a plain indicator when its user interaction is turned off (the update notice) */
@interface ExteriaWaveProgress : UIControl {
    CAShapeLayer *_rest;
    CALayer *_clip;
    CAShapeLayer *_wave;
    CALayer *_thumb;
    float _value;
    BOOL _waving;
    BOOL _dragging;
    CGSize _laidSize;
    BOOL _observing;
}
@property (nonatomic, assign) float value;
@property (nonatomic, assign) BOOL waving;
/* a value that follows playback glides to the new place over the half second between ticks */
- (void)setValue:(float)value gliding:(BOOL)gliding;
@end
