#import <UIKit/UIKit.h>

extern NSString *const ExteriaCustomEmojiDidLoadNotification;

/* the pictures of custom emoji by the document that draws them, for the text layout to put in a line; only the
   first frame of an animated one is kept, drawn small */
/* the stand-in document of the Telegram Premium star that follows the name of a Premium user who has no emoji
   status; draws this one itself, so it never needs a load */
#define EXTERIA_PREMIUM_STAR_DOCUMENT (-1LL)
/* the hammer after the name of a person who took part in the development of Exteria; a bundled picture, drawn by imageForDocument: like the star */
#define EXTERIA_DEVELOPER_DOCUMENT (-2LL)
/* the fox tail of the developer of Senko, drawn the same way */
#define EXTERIA_SENKO_DOCUMENT (-3LL)
/* the net of the testers */
#define EXTERIA_TESTER_DOCUMENT (-4LL)
/* the crossed hammers of the lead developer */
#define EXTERIA_LEAD_DOCUMENT (-5LL)
#define EXTERIA_CAUTION_DOCUMENT (-6LL)
#define EXTERIA_CAUTION_BADGE_RATIO 2.7

@interface ExteriaCustomEmoji : NSObject

/* the picture when it is in memory, nil while it is not loaded */
+ (UIImage *)imageForDocument:(long long)document;

/* whether a loader should fetch the picture now: it is not in memory, not on its way, and did not fail before */
+ (BOOL)needsLoad:(long long)document;
+ (void)beginLoad:(long long)document;
/* ends a load; a nil image marks the document as failed */
+ (void)finishLoad:(long long)document image:(UIImage *)image;

/* the side in points an emoji is drawn at, times the screen scale, is what a loader should decode to */
+ (CGFloat)pictureSide;

@end
