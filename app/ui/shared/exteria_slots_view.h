#import <UIKit/UIKit.h>

/* the slot machine of the 🎰 message: five animations laid over one another (the machine, the three reels, the lever), each stood on the frame that core/chats/exteria_dice.c works out for
   the moment of the throw. a machine whose result is not known waits with its reels spinning; one with a result plays the throw from its start and stops on the last frame */
@interface ExteriaSlotsView : UIView

/* data holds the five animations in layer order, as the plan of the throw names them (the machine, left, center, right, lever); result is the value of the throw, 1 to 64, and 0 for a
   machine that waits. keyBase only names the layers in the log */
- (id)initWithLayers:(NSArray *)data result:(int32_t)result keyBase:(NSString *)keyBase;
/* the documents of the set that the five layers are, in layer order, for a throw that ended on result (0 for the waiting machine); nil for a result that is not a throw */
+ (NSArray *)documentIndexesForResult:(int32_t)result;

/* called once, when the machine itself has its first frame, so a caller can take away the picture that stood in */
@property (nonatomic, copy) void (^firstFrameHandler)(void);

/* the waiting machine loops, the throw plays from its first frame; a stopped view keeps the frame it is on */
- (void)setActive:(BOOL)active;
- (void)playThrow;
/* the last frame of the throw, or the first of the waiting machine, without playing */
- (void)showRest;

@end
