#import "exteria_folder_icon.h"

/* the bits of the rules of a folder, in the order of exteria_folders.h */
enum {
    ExteriaFolderRuleContacts = 1u << 0,
    ExteriaFolderRuleNonContacts = 1u << 1,
    ExteriaFolderRuleGroups = 1u << 2,
    ExteriaFolderRuleBroadcasts = 1u << 3,
    ExteriaFolderRuleBots = 1u << 4,
    ExteriaFolderRuleExcludeMuted = 1u << 5,
    ExteriaFolderRuleExcludeRead = 1u << 6,
    ExteriaFolderRuleKinds = 0x1F
};

static NSString *ExteriaStrippedEmoticon(NSString *emoticon) {
    return [emoticon stringByReplacingOccurrencesOfString:@"️" withString:@""];
}

NSString *ExteriaFolderIconName(NSString *emoticon, uint32_t flags) {
    static NSDictionary *names;
    if (!names) {
        names = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @"cat", @"\U0001F431", @"book", @"\U0001F4D5", @"money", @"\U0001F4B0", @"game", @"\U0001F3AE", @"light", @"\U0001F4A1", @"like", @"\U0001F44C",
                 @"note", @"\U0001F3B5", @"palette", @"\U0001F3A8", @"travel", @"✈", @"sport", @"⚽", @"favorite", @"⭐", @"study", @"\U0001F393",
                 @"airplane", @"\U0001F6EB", @"private", @"\U0001F464", @"group", @"\U0001F465", @"all", @"\U0001F4AC", @"unread", @"✅", @"bots", @"\U0001F916",
                 @"crown", @"\U0001F451", @"flower", @"\U0001F339", @"home", @"\U0001F3E0", @"love", @"❤", @"mask", @"\U0001F3AD", @"party", @"\U0001F378",
                 @"trade", @"\U0001F4C8", @"work", @"\U0001F4BC", @"unmuted", @"\U0001F514", @"channels", @"\U0001F4E2", @"custom", @"\U0001F4C1", @"setup", @"\U0001F4CB", nil];
    }
    NSString *named = emoticon.length ? [names objectForKey:ExteriaStrippedEmoticon(emoticon)] : nil;
    if (named) return named;
    if (emoticon.length) return @"custom";
    /* no emoticon: the rules say what the folder holds */
    uint32_t kinds = flags & ExteriaFolderRuleKinds;
    if (kinds == ExteriaFolderRuleKinds) {
        if (flags & ExteriaFolderRuleExcludeRead) return @"unread";
        if (flags & ExteriaFolderRuleExcludeMuted) return @"unmuted";
    } else if (kinds && !(kinds & ~(ExteriaFolderRuleContacts | ExteriaFolderRuleNonContacts))) {
        return @"private";
    } else if (kinds == ExteriaFolderRuleGroups) {
        return @"group";
    } else if (kinds == ExteriaFolderRuleBots) {
        return @"bots";
    } else if (kinds == ExteriaFolderRuleBroadcasts) {
        return @"channels";
    }
    return @"custom";
}

UIImage *ExteriaFolderIconImage(NSString *name, CGFloat side, UIColor *color) {
    static NSCache *cache;
    static NSCache *masks;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 96;
        masks = [[NSCache alloc] init];
    }
    if (!name.length) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&a];
        r = g = b = white;
    }
    NSString *key = [NSString stringWithFormat:@"%@/%g/%g,%g,%g,%g/%g", name, (double)side, (double)r, (double)g, (double)b, (double)a, (double)[UIScreen mainScreen].scale];
    UIImage *image = [[[cache objectForKey:key] retain] autorelease];
    if (image) return image;
    /* imageNamed picks the @2x and @3x of the bundle by the screen */
    UIImage *mask = [masks objectForKey:name];
    if (!mask) {
        mask = [UIImage imageNamed:[@"folder_" stringByAppendingString:name]];
        if (mask) [masks setObject:mask forKey:name];
    }
    if (!mask) return nil;
    CGRect rect = CGRectMake(0, 0, side, side);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    /* the picture is gray with an alpha, which a clip mask does not take: it is drawn, and the color is poured over its alpha only */
    [mask drawInRect:rect];
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, rect);
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [cache setObject:image forKey:key];
    return image;
}
