#import <Foundation/Foundation.h>
#import "exteria_session.h"

/* the pictures the server draws one ordinary reaction with; around is nil for a reaction that has no short burst */
/* posted on the main thread when the catalog is in, so a screen builds the chips it already shows again with the server's icons */
extern NSString *const ExteriaReactionArtworkDidLoadNotification;

@class ExteriaMediaCache, ExteriaLottieView;
@interface ExteriaReactionArtwork : NSObject {
    NSString *_emoji;
    ExteriaCustomEmojiDocument *_icon;
    ExteriaCustomEmojiDocument *_appear;
    ExteriaCustomEmojiDocument *_select;
    ExteriaCustomEmojiDocument *_activate;
    ExteriaCustomEmojiDocument *_effect;
    ExteriaCustomEmojiDocument *_around;
}
@property (nonatomic, readonly, copy) NSString *emoji;
/* the still picture a chip and a menu show */
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *icon;
/* lottie: the pop of the picker, the press, the reaction flying to the message, the large burst beside it, the short burst of a double tap */
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *appear;
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *select;
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *activate;
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *effect;
@property (nonatomic, readonly, retain) ExteriaCustomEmojiDocument *around;

/* the art of an ordinary emoji reaction once the catalog is in, nil before and for an emoji the server does not draw */
+ (ExteriaReactionArtwork *)artForEmoji:(NSString *)emoji;
/* replaces what is known with the catalog and teaches ExteriaReaction the document of each still icon, so a chip draws it in the place of the emoji */
+ (void)setCatalog:(NSArray *)catalog;
+ (BOOL)hasCatalog;
/* asks the server once (a call in flight or a catalog in hand is not asked for again), then loads the still icons so the chips of the screens draw them */
+ (void)loadWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;
/* a lottie view of one of the animations, ready to play, once its file is in hand; the completion runs on the main thread, with nil for a document that is not a lottie
   file, a file that cannot be fetched, or while reduced motion is on */
+ (void)animationViewForDocument:(ExteriaCustomEmojiDocument *)document media:(ExteriaMediaCache *)media completion:(void (^)(ExteriaLottieView *view))completion;
- (id)initWithEmoji:(NSString *)emoji icon:(ExteriaCustomEmojiDocument *)icon appear:(ExteriaCustomEmojiDocument *)appear
            select:(ExteriaCustomEmojiDocument *)select activate:(ExteriaCustomEmojiDocument *)activate
            effect:(ExteriaCustomEmojiDocument *)effect around:(ExteriaCustomEmojiDocument *)around;
@end
