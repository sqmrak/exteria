#import "exteria_reaction_artwork.h"

#import "exteria_custom_emoji.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_image_decoder.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_media_cache.h"
#import "exteria_message.h"

NSString *const ExteriaReactionArtworkDidLoadNotification = @"ExteriaReactionArtworkDidLoad";

static NSMutableDictionary *sArt;

@implementation ExteriaReactionArtwork

@synthesize emoji = _emoji;
@synthesize icon = _icon;
@synthesize appear = _appear;
@synthesize select = _select;
@synthesize activate = _activate;
@synthesize effect = _effect;
@synthesize around = _around;

- (id)initWithEmoji:(NSString *)emoji icon:(ExteriaCustomEmojiDocument *)icon appear:(ExteriaCustomEmojiDocument *)appear
            select:(ExteriaCustomEmojiDocument *)select activate:(ExteriaCustomEmojiDocument *)activate
            effect:(ExteriaCustomEmojiDocument *)effect around:(ExteriaCustomEmojiDocument *)around {
    self = [super init];
    if (!self) return nil;
    _emoji = [emoji copy];
    _icon = [icon retain];
    _appear = [appear retain];
    _select = [select retain];
    _activate = [activate retain];
    _effect = [effect retain];
    _around = [around retain];
    return self;
}

- (void)dealloc {
    [_emoji release];
    [_icon release];
    [_appear release];
    [_select release];
    [_activate release];
    [_effect release];
    [_around release];
    [super dealloc];
}

+ (ExteriaReactionArtwork *)artForEmoji:(NSString *)emoji {
    return emoji ? [sArt objectForKey:emoji] : nil;
}

+ (BOOL)hasCatalog {
    return sArt != nil;
}

+ (void)setCatalog:(NSArray *)catalog {
    NSMutableDictionary *next = [[NSMutableDictionary alloc] initWithCapacity:catalog.count];
    NSMutableDictionary *icons = [NSMutableDictionary dictionaryWithCapacity:catalog.count];
    for (ExteriaReactionArtwork *art in catalog) {
        [next setObject:art forKey:art.emoji];
        [icons setObject:art.emoji forKey:[NSNumber numberWithLongLong:art.icon.documentId]];
    }
    [sArt release];
    sArt = next;
    [ExteriaReaction rememberCustomTexts:icons];
}

+ (UIImageView *)attachStillOfArtwork:(ExteriaReactionArtwork *)artwork toButton:(UIButton *)button side:(CGFloat)side media:(ExteriaMediaCache *)media {
    if (!artwork.icon.file || !media) return nil;
    UIImageView *still = [[[UIImageView alloc] initWithFrame:CGRectMake(0, 0, side, side)] autorelease];
    still.tag = EXTERIA_REACTION_STILL_TAG;
    still.contentMode = UIViewContentModeScaleAspectFit;
    still.userInteractionEnabled = NO;
    still.hidden = YES;
    still.center = CGPointMake(button.bounds.size.width / 2, button.bounds.size.height / 2);
    [button addSubview:still];
    /* the same side as the picture of the custom emoji path, so the cache of the images holds one decode for both */
    [media loadImageForFile:artwork.icon.file maxSide:[ExteriaCustomEmoji pictureSide] completion:^(UIImage *image) {
        if (!image || !still.superview) return;
        still.image = image;
        BOOL animating = NO;
        for (UIView *view in button.subviews) if ([view isKindOfClass:[ExteriaLottieView class]] && !view.hidden) animating = YES;
        still.hidden = animating;
        [button viewWithTag:EXTERIA_REACTION_LABEL_TAG].hidden = YES;
    }];
    return still;
}

+ (void)showRestingViewInButton:(UIButton *)button {
    UIImageView *still = (UIImageView *)[button viewWithTag:EXTERIA_REACTION_STILL_TAG];
    if (still.image) {
        still.hidden = NO;
        [button viewWithTag:EXTERIA_REACTION_LABEL_TAG].hidden = YES;
    } else {
        [button viewWithTag:EXTERIA_REACTION_LABEL_TAG].hidden = NO;
    }
}

+ (void)animationViewForDocument:(ExteriaCustomEmojiDocument *)document media:(ExteriaMediaCache *)media completion:(void (^)(ExteriaLottieView *))completion {
    void (^done)(ExteriaLottieView *) = [completion copy];
    if (!document || document.format != EXTERIA_STICKER_ANIMATED || !document.file || !media || ExteriaReduceMotionEnabled()) {
        done(nil);
        [done release];
        return;
    }
    NSString *key = document.file.key;
    [media loadDataForFile:document.file completion:^(NSData *data) {
        ExteriaLottieView *view = nil;
        if (data && ExteriaFileFormatOfData(data) == ExteriaFileFormatGzip) view = [[[ExteriaLottieView alloc] initWithPackedData:data key:key] autorelease];
        else NSLog(@"exteria: reaction animation %lld is not a lottie file", document.documentId);
        done(view);
        [done release];
    }];
}

+ (void)loadWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    static BOOL loading;
    if (sArt || loading || !session || !media) return;
    loading = YES;
    [session loadReactionArt:^(NSArray *art, NSString *errorName) {
        loading = NO;
        if (!art) {
            NSLog(@"exteria: reaction art not loaded: %@", errorName);
            return;
        }
        [ExteriaReactionArtwork setCatalog:art];
        NSMutableArray *icons = [NSMutableArray arrayWithCapacity:art.count];
        for (ExteriaReactionArtwork *item in art) [icons addObject:item.icon];
        [ExteriaCustomEmojiLoader loadPicturesOfDocuments:icons media:media picture:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaReactionArtworkDidLoadNotification object:nil];
    }];
}

@end
