#import "exteria_topic_icon.h"

#import "exteria_custom_emoji.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

/* a forum offers a handful of icon colors, so the hashes drawn so far stay kept */
static NSMutableDictionary *ExteriaHashImages(void) {
    static NSMutableDictionary *images;
    if (!images) images = [[NSMutableDictionary alloc] init];
    return images;
}

static UIImage *ExteriaHashImage(int32_t rgb) {
    NSNumber *key = [NSNumber numberWithInt:rgb];
    UIImage *image = [ExteriaHashImages() objectForKey:key];
    if (image) return image;
    UIColor *color = rgb ? [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1]
                         : ExteriaColorAccent();
    CGSize size = CGSizeMake(EXTERIA_TOPIC_ICON_SIDE, EXTERIA_TOPIC_ICON_SIDE);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [color set];
    NSString *hash = @"#";
    UIFont *font = ExteriaFontBold(EXTERIA_TOPIC_ICON_SIDE);
    CGSize fit = ExteriaStringSize(hash, font);
    ExteriaDrawStringIn(hash, font, CGRectMake(0, (size.height - fit.height) / 2, size.width, fit.height), ExteriaStringClip, ExteriaTextAlignmentCenter);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [ExteriaHashImages() setObject:image forKey:key];
    return image;
}

UIImage *ExteriaTopicIconImageOf(long long emoji, int32_t rgb) {
    if (emoji) {
        /* drawn 48 points wide, so the still at full size and not the half-size frame of an animated emoji, which was stretched to twice its pixels */
        UIImage *picture = [ExteriaCustomEmoji stillImageForDocument:emoji];
        if (picture) return picture;
    }
    return ExteriaHashImage(rgb);
}

UIImage *ExteriaTopicIconImage(ExteriaDialog *topic) {
    return ExteriaTopicIconImageOf(topic.topicIconEmoji, topic.topicIconColor);
}
