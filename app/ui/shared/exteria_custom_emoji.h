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
#define EXTERIA_PROMOTION_DOCUMENT (-7LL)
#define EXTERIA_BUG_HUNTER_DOCUMENT (-8LL)
#define EXTERIA_TELEGRAM_VERIFIED_DOCUMENT (-9LL)
#define EXTERIA_OFFICIAL_TESTER_DOCUMENT (-10LL)
/* the shield of the official manager of @sqmrak */
#define EXTERIA_MANAGER_DOCUMENT (-11LL)
/* the gear and chevron of ExteriaVideoFix, for its author */
#define EXTERIA_VIDEO_FIX_DOCUMENT (-12LL)
/* the magnifier and net full of bugs, for the testers who see flaws in everything */
#define EXTERIA_FLAW_SEER_DOCUMENT (-13LL)
#define EXTERIA_CAUTION_BADGE_RATIO 2.7

@interface ExteriaCustomEmoji : NSObject

/* the picture when it is in memory, nil while it is not loaded */
+ (UIImage *)imageForDocument:(long long)document;

/* the still picture at full size, even for an animated emoji, whose frames (imageForDocument:) are drawn at half the size of the still to keep a screenful of them light; for a picture
   that is drawn large and does not move, such as the icon of a forum topic */
+ (UIImage *)stillImageForDocument:(long long)document;

/* whether a loader should fetch the picture now: it is not in memory, not on its way, and did not fail in the last minute */
+ (BOOL)needsLoad:(long long)document;
+ (void)beginLoad:(long long)document;
/* a load that ended without telling anything about the document, such as a request that failed: it is asked for again at the next need, not after the retry pause */
+ (void)abandonLoad:(long long)document;
/* ends a load; a nil image marks the document as failed for a minute */
+ (void)finishLoad:(long long)document image:(UIImage *)image;

/* the side in points an emoji is drawn at, times the screen scale, is what a loader should decode to */
+ (CGFloat)pictureSide;

/* animated emoji: a document with frames keeps its frames here, and imageForDocument: answers with the frame the clock names. only the frames of a few dozen documents are held
   (a bounded cache, cost counted in bytes); a document without frames is still the one picture it was */
+ (void)setAnimationFrames:(NSArray *)frames duration:(NSTimeInterval)duration forDocument:(long long)document;
+ (BOOL)hasAnimationForDocument:(long long)document;
/* a view that has just drawn an animated emoji asks to be drawn again on the next tick; it is forgotten after the tick, and draws itself in again only while it still shows one */
+ (void)keepAnimatingView:(UIView *)view;
@end

/* counts the animated pictures handed out: a view compares the count before and after it draws to know it showed one */
NSUInteger ExteriaCustomEmojiAnimatedDraws(void);
