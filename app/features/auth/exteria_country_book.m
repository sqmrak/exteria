#import "exteria_country_book.h"

#import "exteria_flag_sprite.h"
#import "exteria_phone.h"

@interface ExteriaCountry () {
    NSString *_iso;
    NSString *_code;
    NSString *_name;
    NSString *_pattern;
    NSInteger _flag;
    NSUInteger _entry;
}
- (id)initWithEntry:(const exteria_country *)entry index:(NSUInteger)index flag:(NSInteger)flag;
- (NSComparisonResult)compareName:(ExteriaCountry *)other;
@property (nonatomic, readonly) NSInteger flag;
@property (nonatomic, readonly) NSUInteger entry;
@end

@implementation ExteriaCountry

@synthesize iso = _iso;
@synthesize code = _code;
@synthesize name = _name;
@synthesize pattern = _pattern;
@synthesize flag = _flag;
@synthesize entry = _entry;

- (id)initWithEntry:(const exteria_country *)entry index:(NSUInteger)index flag:(NSInteger)flag {
    self = [super init];
    if (!self) return nil;
    _iso = [[NSString stringWithUTF8String:entry->iso] retain];
    _code = [[NSString stringWithUTF8String:entry->code] retain];
    _pattern = [[NSString stringWithUTF8String:entry->pattern] retain];
    /* the list spells names its own way; the system knows them in every language */
    NSString *local = [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:_iso];
    NSString *listed = [NSString stringWithUTF8String:entry->name];
    _name = [(local.length && ![local isEqualToString:_iso] ? local : listed) retain];
    _flag = flag;
    _entry = index;
    return self;
}

- (NSComparisonResult)compareName:(ExteriaCountry *)other {
    return [_name localizedCaseInsensitiveCompare:other.name];
}

- (void)dealloc {
    [_iso release];
    [_code release];
    [_name release];
    [_pattern release];
    [super dealloc];
}

@end

@interface ExteriaCountryBook () {
    exteria_country *_table;
    size_t _tableCount;
    NSArray *_countries;
    NSMutableDictionary *_byISO;
    NSMutableDictionary *_flags;
    NSMutableArray *_entries;
    CGImageRef _sprite;
}
@end

@implementation ExteriaCountryBook

@synthesize countries = _countries;

static NSString *ExteriaBundleText(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
    return path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    NSString *list = ExteriaBundleText(@"countries");
    NSString *flagOrder = ExteriaBundleText(@"flags");
    NSData *listData = [list dataUsingEncoding:NSUTF8StringEncoding];
    _table = calloc(EXTERIA_COUNTRY_MAX, sizeof(exteria_country));
    exteria_status status = listData && _table
        ? exteria_country_parse(listData.bytes, listData.length, _table, EXTERIA_COUNTRY_MAX, &_tableCount)
        : EXTERIA_E_NOTFOUND;
    UIImage *sprite = [UIImage imageNamed:@"flag_sprite"];
    if (status != EXTERIA_OK || !flagOrder || !sprite) {
        NSLog(@"exteria: country list did not load (%s)", exteria_status_name(status));
        [self release];
        return nil;
    }
    _sprite = CGImageRetain(sprite.CGImage);
    NSMutableDictionary *flagIndex = [NSMutableDictionary dictionary];
    NSArray *isos = [flagOrder componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSUInteger i = 0; i < isos.count; ++i) {
        [flagIndex setObject:[NSNumber numberWithUnsignedInteger:i] forKey:[isos objectAtIndex:i]];
    }
    _byISO = [[NSMutableDictionary alloc] init];
    _flags = [[NSMutableDictionary alloc] init];
    _entries = [[NSMutableArray alloc] init];
    for (size_t i = 0; i < _tableCount; ++i) {
        NSNumber *flag = [flagIndex objectForKey:[NSString stringWithUTF8String:_table[i].iso]];
        ExteriaCountry *country = [[[ExteriaCountry alloc] initWithEntry:&_table[i] index:i
                                                                    flag:flag ? [flag integerValue] : -1] autorelease];
        [_entries addObject:country];
        if (![_byISO objectForKey:country.iso]) [_byISO setObject:country forKey:country.iso];
    }
    _countries = [[_entries sortedArrayUsingSelector:@selector(compareName:)] retain];
    return self;
}

- (void)dealloc {
    free(_table);
    if (_sprite) CGImageRelease(_sprite);
    [_countries release];
    [_byISO release];
    [_flags release];
    [_entries release];
    [super dealloc];
}

- (ExteriaCountry *)countryForISO:(NSString *)iso {
    return [_byISO objectForKey:iso];
}

- (ExteriaCountry *)countryForDigits:(NSString *)digits codeLength:(NSUInteger *)codeLength {
    size_t used = 0;
    const exteria_country *hit = exteria_country_match(_table, _tableCount, digits.UTF8String, &used);
    if (codeLength) *codeLength = used;
    return hit ? [_entries objectAtIndex:(NSUInteger)(hit - _table)] : nil;
}

- (ExteriaCountry *)localCountry {
    NSString *iso = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    ExteriaCountry *country = iso ? [_byISO objectForKey:[iso uppercaseString]] : nil;
    return country ? country : [_byISO objectForKey:@"US"];
}

- (UIImage *)flagForCountry:(ExteriaCountry *)country {
    if (!country || country.flag < 0) return nil;
    NSNumber *key = [NSNumber numberWithInteger:country.flag];
    UIImage *flag = [_flags objectForKey:key];
    if (!flag) {
        NSInteger column = country.flag % EXTERIA_FLAG_COLUMNS;
        NSInteger row = country.flag / EXTERIA_FLAG_COLUMNS;
        CGRect tile = CGRectMake(column * EXTERIA_FLAG_TILE_WIDTH, row * EXTERIA_FLAG_TILE_HEIGHT,
                                 EXTERIA_FLAG_TILE_WIDTH, EXTERIA_FLAG_TILE_HEIGHT);
        CGImageRef cut = CGImageCreateWithImageInRect(_sprite, tile);
        if (!cut) return nil;
        /* the tile holds twice the pixels of the largest flag on screen */
        flag = [UIImage imageWithCGImage:cut scale:2.0 orientation:UIImageOrientationUp];
        CGImageRelease(cut);
        [_flags setObject:flag forKey:key];
    }
    return flag;
}

@end
