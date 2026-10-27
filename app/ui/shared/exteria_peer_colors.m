#import "exteria_peer_colors.h"

static NSString *const ExteriaServerNameColorsKey = @"exteria.namecolors";

/* red, orange, violet, green, cyan, blue, pink: the avatar_nameInMessage colors, for the light theme and for its
   night themes */
static const uint32_t ExteriaLightNames[] = {0xCC5049, 0xD67722, 0x955CDB, 0x40A920, 0x309EBA, 0x368AD1, 0xC7508B};
static const uint32_t ExteriaDarkNames[] = {0xE88878, 0xE8AB5A, 0x8C8DEA, 0x7DD071, 0x53CCC6, 0x5CADEA, 0xE8749A};
#define BUILT_IN (sizeof(ExteriaLightNames) / sizeof(ExteriaLightNames[0]))

static UIColor *ExteriaNameRGB(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

NSUInteger ExteriaBuiltInNameColorCount(void) {
    return BUILT_IN;
}

NSInteger ExteriaDefaultNameColorId(long long userId) {
    return (NSInteger)((NSUInteger)(userId < 0 ? -userId : userId) % BUILT_IN);
}

NSArray *ExteriaServerNameColors(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaServerNameColorsKey];
    return [stored isKindOfClass:[NSArray class]] ? stored : [NSArray array];
}

void ExteriaStoreServerNameColors(NSArray *colors) {
    [[NSUserDefaults standardUserDefaults] setObject:colors forKey:ExteriaServerNameColorsKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the name colors of the server were not saved");
}

UIColor *ExteriaNameColor(NSInteger colorId, long long userId, BOOL dark) {
    if (colorId >= 0 && (NSUInteger)colorId < BUILT_IN) return ExteriaNameRGB(dark ? ExteriaDarkNames[colorId] : ExteriaLightNames[colorId]);
    if (colorId >= (NSInteger)BUILT_IN) {
        for (NSDictionary *option in ExteriaServerNameColors()) {
            if ([[option objectForKey:@"id"] integerValue] != colorId) continue;
            return ExteriaNameRGB((uint32_t)[[option objectForKey:dark ? @"dark" : @"light"] unsignedIntegerValue]);
        }
    }
    NSInteger fallback = ExteriaDefaultNameColorId(userId);
    return ExteriaNameRGB(dark ? ExteriaDarkNames[fallback] : ExteriaLightNames[fallback]);
}
