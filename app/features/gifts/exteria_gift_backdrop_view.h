#import <UIKit/UIKit.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"

/* a unique gift's background: a radial blend from the center color to the edge color, the pattern symbol repeated
   in rings around the middle */
@interface ExteriaGiftBackdropView : UIView

@property (nonatomic, assign) uint32_t centerColor;
@property (nonatomic, assign) uint32_t edgeColor;
@property (nonatomic, assign) uint32_t patternColor;
/* the symbol already tinted with the pattern color; nil draws none */
@property (nonatomic, retain) UIImage *symbol;
/* the ground of a gift the app makes itself: soft shapes in the manner of Material 3 Expressive (a scalloped cookie, a flower, a clover, a burst, a squircle, a
   pill) in the pattern color, where a gift of the server has its symbol repeated */
@property (nonatomic, assign) BOOL expressive;
/* where the gift sits, as a fraction of the bounds */
@property (nonatomic, assign) CGPoint focus;

@end

/* the number ribbon across the top right corner of a unique gift. It is a view of its own so that it can stand above the picture of the gift, which a large
   model otherwise covers it with */
@interface ExteriaGiftRibbonView : UIView

/* the edge color of the backdrop, which the band is a darker shade of */
@property (nonatomic, assign) uint32_t edgeColor;
/* the line on the ribbon, nil for no ribbon */
@property (nonatomic, copy) NSString *text;

@end

/* the first frame of a pattern sticker as a tinted symbol, from the shared cache; the completion runs on the main
   thread with nil when the sticker cannot be had */
void ExteriaGiftLoadPatternSymbol(ExteriaMediaCache *media, ExteriaMedia *pattern, uint32_t color, void (^completion)(UIImage *symbol));

UIColor *ExteriaGiftRgb(uint32_t rgb);
