#import "exteria_person.h"
#import "exteria_text_filter.h"

#import "exteria_photo.h"

static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

long long ExteriaLiveEmojiStatus(long long document, int32_t until) {
    if (document <= 0) return 0;
    return until == 0 || until > (int32_t)time(NULL) ? document : 0;
}

NSString *ExteriaInitialsOfName(NSString *name) {
    NSMutableString *letters = [NSMutableString string];
    NSArray *words = [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *word in words) {
        if (!word.length) continue;
        NSRange first = [word rangeOfComposedCharacterSequenceAtIndex:0];
        NSString *letter = [[word substringWithRange:first] uppercaseString];
        /* a leading symbol or emoji makes a poor monogram */
        if (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:[letter characterAtIndex:0]]) continue;
        [letters appendString:letter];
        if ([letters length] >= 2) break;
    }
    return letters;
}

@implementation ExteriaPerson

@synthesize userId = _userId;
@synthesize accessHash = _accessHash;
@synthesize bot = _bot;
@synthesize botInline = _botInline;
@synthesize botInlineGeo = _botInlineGeo;
@synthesize botPlaceholder = _botPlaceholder;
@synthesize verified = _verified;
@synthesize contact = _contact;
@synthesize mutual = _mutual;
@synthesize premium = _premium;
@synthesize emojiStatus = _emojiStatus;
@synthesize nameColor = _nameColor;
@synthesize presence = _presence;
@synthesize seen = _seen;
@synthesize name = _name;
@synthesize username = _username;
@synthesize phone = _phone;
@synthesize initials = _initials;
@synthesize photo = _photo;

- (id)initWithRow:(const exteria_person_row *)row {
    self = [super init];
    if (!self) return nil;
    _userId = row->id;
    _accessHash = row->access_hash;
    _bot = row->bot;
    _botInline = row->bot_inline;
    _botInlineGeo = row->bot_inline_geo;
    _botPlaceholder = [ExteriaUtf8(row->bot_placeholder) copy];
    _verified = row->verified;
    _contact = row->contact;
    _mutual = row->mutual;
    _premium = row->premium;
    _emojiStatus = ExteriaLiveEmojiStatus(row->emoji_status, row->emoji_status_until);
    _nameColor = row->has_name_color ? row->name_color : -1;
    _presence = row->presence;
    _seen = row->seen;
    _name = [(row->deleted || !row->name[0] ? NSLocalizedString(@"chats.deleted", nil) : ExteriaFilteredText(ExteriaUtf8(row->name))) copy];
    _username = [ExteriaUtf8(row->username) copy];
    _phone = [ExteriaUtf8(row->phone) copy];
    _initials = [(row->deleted ? @"" : ExteriaInitialsOfName(_name)) copy];
    _photo = [[ExteriaPhoto photoWithRef:&row->photo] retain];
    _hasProfileColor = row->has_profile_color != 0;
    _profileColorId = row->profile_color_id;
    _profileColorEmoji = row->profile_color_emoji;
    _hasBackdrop = row->has_backdrop != 0;
    _backdropCenter = row->backdrop_center;
    _backdropEdge = row->backdrop_edge;
    _backdropPattern = row->backdrop_pattern;
    _backdropText = row->backdrop_text;
    _backdropPatternDocument = row->backdrop_pattern_document;
    _backdropTitle = [ExteriaUtf8(row->backdrop_title) copy];
    return self;
}

- (BOOL)hasProfileColor { return _hasProfileColor; }
- (NSInteger)profileColorId { return _profileColorId; }
- (long long)profileColorEmoji { return _profileColorEmoji; }
- (BOOL)hasBackdrop { return _hasBackdrop; }
- (uint32_t)backdropCenter { return _backdropCenter; }
- (uint32_t)backdropEdge { return _backdropEdge; }
- (uint32_t)backdropPattern { return _backdropPattern; }
- (uint32_t)backdropText { return _backdropText; }
- (long long)backdropPatternDocument { return _backdropPatternDocument; }
- (NSString *)backdropTitle { return _backdropTitle; }

- (BOOL)deleted {
    return _presence == EXTERIA_PRESENCE_DELETED;
}

- (void)dealloc {
    [_name release];
    [_username release];
    [_phone release];
    [_botPlaceholder release];
    [_initials release];
    [_photo release];
    [_backdropTitle release];
    [super dealloc];
}

@end
