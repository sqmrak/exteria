#import <UIKit/UIKit.h>

/* the glossy speech bubble of the classic chat, cut from the old Messages pictures and colored with the accent. a bubble with a tail has 6 points
   of tail on the side it leans to (the left for the ones that came in, the right for the ones sent) and the body fills the rest; one without a tail
   is the plain bubble. the image stretches with its corners and tail kept, and is made once for each color it is asked for */
#define EXTERIA_CLASSIC_BUBBLE_TAIL 6.0
/* the radius of the corners of the bubble pictures, which a photo or a video that runs to the edge of the bubble takes for its own outer corners */
#define EXTERIA_CLASSIC_BUBBLE_CORNER 12.0

UIImage *ExteriaClassicBubbleImage(BOOL outgoing, BOOL tail);

/* the light of the bubble drawn over its picture at the real size of the bubble: the lit rows, the step at the middle and the capsule of gloss, inside the rim. bounds is
   the whole picture, tail included; nothing is drawn where the body is too small to hold it */
void ExteriaClassicBubbleGloss(CGContextRef context, CGRect bounds, BOOL outgoing, BOOL tail);
