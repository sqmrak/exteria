#import "exteria_community_badge.h"

#import "exteria_symbol.h"
#import "exteria_theme.h"

UIImage *ExteriaCommunityBadgeImage(void) {
    static UIImage *badge;
    if (badge) return badge;
    CGFloat side = EXTERIA_COMMUNITY_BADGE_SIDE;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    /* a ring in the screen color keeps the badge apart from the avatar under it */
    [ExteriaColorScreen() set];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
    [ExteriaColorAccent() set];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2, 2, side - 4, side - 4)] fill];
    CGFloat arrow = side * 0.7;
    [ExteriaSymbolImage(ExteriaSymbolArrowDown, arrow, [UIColor whiteColor]) drawAtPoint:CGPointMake((side - arrow) / 2, (side - arrow) / 2)];
    badge = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    return badge;
}
