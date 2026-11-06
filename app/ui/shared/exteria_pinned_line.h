#import <UIKit/UIKit.h>

/* the strip at the left of the pinned bar: one segment per pinned message, three in view at a time, the shown one in full color */
@interface ExteriaPinnedLine : UIView {
    NSInteger _position;
    NSInteger _total;
}

/* position counts from the oldest pin, zero based; a total of zero draws nothing */
- (void)setPosition:(NSInteger)position total:(NSInteger)total;

@end
