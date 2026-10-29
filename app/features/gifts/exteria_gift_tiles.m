#import "exteria_gift_tiles.h"

#import "exteria_custom_gift.h"
#import "exteria_person.h"
#import "exteria_time.h"

/* 156375 as "#156,375", the way the original client writes a gift number */
static NSString *ExteriaGiftNumberText(int32_t number) {
    NSString *digits = [NSString stringWithFormat:@"%d", (int)number];
    NSMutableString *text = [NSMutableString stringWithString:@"#"];
    for (NSUInteger i = 0; i < digits.length; ++i) {
        if (i > 0 && (digits.length - i) % 3 == 0) [text appendString:@","];
        [text appendString:[digits substringWithRange:NSMakeRange(i, 1)]];
    }
    return text;
}

ExteriaGiftTileInfo *ExteriaTileForSavedGift(ExteriaSavedGift *saved, BOOL mine) {
    ExteriaStarGift *gift = saved.gift;
    ExteriaGiftTileInfo *tile = [[[ExteriaGiftTileInfo alloc] init] autorelease];
    tile.card = YES;
    tile.unique = gift.unique;
    tile.sticker = gift.sticker;
    tile.hasBackdrop = gift.hasBackdropColors;
    tile.backdropCenter = gift.backdropCenter;
    tile.backdropEdge = gift.backdropEdge;
    tile.patternColor = gift.backdropPattern;
    tile.patternSticker = gift.patternSticker;
    if (gift.unique) {
        tile.ribbon = saved.customImageName ? ExteriaCustomGiftNumberText(gift.number) : ExteriaGiftNumberText(gift.number);
        tile.expressive = saved.customImageName != nil;
    } else {
        /* a sender that is missing from the answer is as anonymous to the person as one who hid their name */
        tile.anonymous = saved.nameHidden || saved.fromId == 0;
        tile.fromPhoto = saved.fromPhoto;
        tile.fromSeed = (NSUInteger)saved.fromId;
        tile.fromInitials = ExteriaInitialsOfName(saved.fromName);
    }
    if (saved.customImageName) tile.localImage = [UIImage imageNamed:saved.customImageName];
    tile.pinned = saved.pinned;
    tile.hiddenMark = mine && saved.hidden;
    return tile;
}

ExteriaGiftTileInfo *ExteriaTileForCatalogGift(ExteriaStarGift *gift) {
    ExteriaGiftTileInfo *tile = [[[ExteriaGiftTileInfo alloc] init] autorelease];
    tile.sticker = gift.sticker;
    if (gift.soldOut) tile.title = NSLocalizedString(@"gifts.soldout", nil);
    else tile.starsAmount = gift.stars;
    if (gift.limited && !gift.soldOut) tile.caption = [NSString stringWithFormat:NSLocalizedString(@"gifts.left", nil), (int)gift.remains, (int)gift.total];
    else if (gift.limited) tile.caption = NSLocalizedString(@"gifts.limited", nil);
    tile.dimmed = !gift.canBuy;
    return tile;
}

ExteriaGiftTileInfo *ExteriaTileForStory(ExteriaStory *story) {
    ExteriaGiftTileInfo *tile = [[[ExteriaGiftTileInfo alloc] init] autorelease];
    ExteriaMedia *media = story.media;
    /* a photo is its own picture; a video shows its thumbnail, because the file itself is not a picture */
    tile.pictureFile = media.kind == EXTERIA_PREVIEW_VIDEO ? media.previewFile : media.file;
    tile.title = ExteriaDayText(story.date);
    if (story.views > 0) tile.caption = [NSString stringWithFormat:NSLocalizedString(@"story.views", nil), (int)story.views];
    if (media.kind == EXTERIA_PREVIEW_VIDEO) tile.badge = @"▶";
    tile.dimmed = NO;
    return tile;
}
