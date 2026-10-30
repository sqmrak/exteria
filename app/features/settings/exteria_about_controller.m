#import "exteria_about_controller.h"
#import "exteria_general_settings_controller.h"
#import "exteria_more_settings_controller.h"
#import "exteria_link_router.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_extras_controller.h"
#import "exteria_developers.h"
#import "exteria_gift_screen.h"
#import "exteria_custom_emoji.h"
#import "exteria_pill_tabs_view.h"
#import "exteria_person.h"
#import "exteria_session_bots.h"
#import "exteria_settings_pages.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define ICON_SIDE 88.0
#define HEADER_HEIGHT 196.0
#define PILL_HEIGHT 20.0
#define PERSON_TILE 36.0
#define LEAD_TILE 42.0

static NSString *const ExteriaChannelAddress = @"https://t.me/sqmrakdev";
static NSString *const ExteriaSourceAddress = @"https://github.com/sqmrak/exteria";

typedef struct {
    long long userId;
    NSString *role;
    /* the outline of the picture: a circle pressed in by lobes dents of the given depth, as the shapes of the material 3 expressive set are */
    int lobes;
    CGFloat depth;
    /* the app this person made, with the picture of its icon, or nil */
    NSString *app;
    NSString *appIcon;
} ExteriaCredit;

static const ExteriaCredit ExteriaCredits[] = {
    {8202789099LL, @"about.lead", 9, 0.10, @"Senko", @"app_senko"},
    {5435278149LL, @"about.backend", 4, 0.14, @"LegacyGram", @"app_legacygram"},
    {8510741400LL, @"about.frontend", 8, 0.16, @"MintAI", @"app_mintai"},
    {588487063LL, @"about.backend", 12, 0.08, @"TeleGloss", @"app_telegloss"},
    {8796163695LL, @"about.backend", 5, 0.12, @"Twelve", @"app_twelve"},
    {5191291829LL, @"about.frontend", 6, 0.14, @"iChatter", @"app_ichatter"},
    {5390055485LL, @"about.frontend", 7, 0.12, @"iKlassika", @"app_iklassika"},
    {6233584668LL, @"about.backend", 10, 0.10, @"FlowGram", @"app_flowgram"},
    {1448306214LL, @"about.backend", 3, 0.12, @"OneGram", @"app_onegram"},
};

/* the slice the running code was built for, which is what the version line shows */
static NSString *ExteriaSliceName(void) {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__arm__)
    return @"armv7";
#else
    return @"host";
#endif
}

/* the picture drawn inside a wavy circle, r = R (1 - depth / 2 + depth / 2 cos(lobes angle)), so the outline touches the square at every lobe */
static UIImage *ExteriaShapedPicture(UIImage *source, int lobes, CGFloat depth, CGFloat side) {
    if (!source) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    CGFloat radius = side / 2;
    UIBezierPath *outline = [UIBezierPath bezierPath];
    const int steps = 180;
    for (int i = 0; i <= steps; ++i) {
        CGFloat angle = (CGFloat)i * 2 * (CGFloat)M_PI / steps;
        CGFloat reach = radius * (1 - depth / 2 + depth / 2 * cos(lobes * angle));
        CGPoint point = CGPointMake(radius + reach * cos(angle), radius + reach * sin(angle));
        if (i == 0) [outline moveToPoint:point];
        else [outline addLineToPoint:point];
    }
    [outline closePath];
    [outline addClip];
    [source drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *ExteriaBundledPicture(NSString *name) {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!image) NSLog(@"exteria: about picture %@ is missing from the bundle", name);
    return image;
}

/* the picture a person stands behind until the server's one arrives: a colored square with the first letter of the name, drawn here, since no picture of a person
   is kept in the app */
static UIImage *ExteriaInitialPicture(NSString *name, CGFloat side) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat hue = (CGFloat)(name.hash % 360) / 360;
    [[UIColor colorWithHue:hue saturation:0.45 brightness:0.78 alpha:1] setFill];
    CGContextFillRect(context, CGRectMake(0, 0, side, side));
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    UIFont *font = ExteriaFontBold(side * 0.5);
    [[UIColor whiteColor] set];
    CGSize size = ExteriaStringSize(letter, font);
    ExteriaDrawStringIn(letter, font, CGRectMake(0, (side - size.height) / 2, side, size.height), ExteriaStringTailTruncate, ExteriaTextAlignmentCenter);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/* the icon of the app in a circle */
static UIImage *ExteriaRoundIcon(CGFloat side) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Icon-83.5@2x" ofType:@"png"];
    UIImage *source = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!source) return ExteriaSettingsMarkTile(side);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] addClip];
    [source drawInRect:CGRectMake(0, 0, side, side)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface ExteriaCreditView : UIControl {
    UIImageView *_picture;
    UILabel *_name;
    UILabel *_role;
    UILabel *_made;
    UIImageView *_appIcon;
    NSMutableArray *_marks;
    long long _userId;
}
@property (nonatomic, assign) long long userId;
- (id)initWithName:(NSString *)name role:(NSString *)role made:(NSString *)made picture:(UIImage *)picture appIcon:(UIImage *)icon marks:(NSUInteger)marks;
@end

@implementation ExteriaCreditView
@synthesize userId = _userId;

- (id)initWithName:(NSString *)name role:(NSString *)role made:(NSString *)made picture:(UIImage *)picture appIcon:(UIImage *)icon marks:(NSUInteger)marks {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 12;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = role.length ? [NSString stringWithFormat:@"@%@, %@", name, role] : [@"@" stringByAppendingString:name];
    _picture = [[UIImageView alloc] initWithImage:picture];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_picture];
    _name = [[UILabel alloc] init];
    _name.backgroundColor = [UIColor clearColor];
    _name.font = ExteriaFontSemibold(16);
    _name.textColor = ExteriaColorTitle();
    _name.text = [@"@" stringByAppendingString:name];
    _name.adjustsFontSizeToFitWidth = YES;
    _name.minimumFontSize = 10;
    [self addSubview:_name];
    _role = [[UILabel alloc] init];
    _role.backgroundColor = [UIColor clearColor];
    _role.font = ExteriaFontRegular(13);
    _role.textColor = ExteriaColorSecondary();
    _role.text = role;
    [self addSubview:_role];
    _made = [[UILabel alloc] init];
    _made.backgroundColor = [UIColor clearColor];
    _made.font = ExteriaFontRegular(13);
    _made.textColor = ExteriaColorAccent();
    _made.text = made;
    [self addSubview:_made];
    _appIcon = [[UIImageView alloc] initWithImage:icon];
    _appIcon.contentMode = UIViewContentModeScaleAspectFit;
    _appIcon.layer.cornerRadius = 5;
    _appIcon.clipsToBounds = YES;
    [self addSubview:_appIcon];
    _marks = [[NSMutableArray alloc] init];
    const NSUInteger bits[] = {ExteriaMarkDeveloper, ExteriaMarkLead, ExteriaMarkSenko, ExteriaMarkOfficialTester, ExteriaMarkBugHunter, ExteriaMarkManager, ExteriaMarkPromotion};
    const long long documents[] = {EXTERIA_DEVELOPER_DOCUMENT, EXTERIA_LEAD_DOCUMENT, EXTERIA_SENKO_DOCUMENT, EXTERIA_OFFICIAL_TESTER_DOCUMENT, EXTERIA_BUG_HUNTER_DOCUMENT, EXTERIA_MANAGER_DOCUMENT, EXTERIA_PROMOTION_DOCUMENT};
    for (NSUInteger i = 0; i < sizeof(bits) / sizeof(bits[0]); ++i) {
        if (!(marks & bits[i])) continue;
        UIImage *image = [ExteriaCustomEmoji imageForDocument:documents[i]];
        if (!image) continue;
        UIImageView *badge = [[[UIImageView alloc] initWithImage:image] autorelease];
        badge.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:badge];
        [_marks addObject:badge];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _picture.frame = CGRectMake(12, (height - LEAD_TILE) / 2, LEAD_TILE, LEAD_TILE);
    CGFloat right = width - 12;
    _appIcon.frame = CGRectMake(right - 26, (height - 26) / 2, 26, 26);
    if (_appIcon.image) right -= 34;
    CGFloat badges = _marks.count * 20;
    CGFloat left = 12 + LEAD_TILE + 10;
    CGFloat titleWidth = MAX(0, right - left - badges - 4);
    CGFloat measured = ceil(ExteriaStringSize(_name.text, _name.font).width);
    _name.frame = CGRectMake(left, _role.text.length ? (_made.text.length ? 9 : 11) : (height - 22) / 2, MIN(titleWidth, measured), 22);
    CGFloat x = CGRectGetMaxX(_name.frame) + 4;
    for (UIImageView *badge in _marks) {
        badge.frame = CGRectMake(x, _name.frame.origin.y + 2, 18, 18);
        x += 20;
    }
    _role.frame = CGRectMake(left, CGRectGetMaxY(_name.frame), MAX(0, right - left), 18);
    _made.frame = CGRectMake(left, CGRectGetMaxY(_role.frame), MAX(0, right - left), 18);
}

- (void)dealloc {
    [_picture release];
    [_name release];
    [_role release];
    [_made release];
    [_appIcon release];
    [_marks release];
    [super dealloc];
}
@end

@interface ExteriaAboutController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaWeakReference *_weak;
    /* photos and people by their stable account id */
    NSMutableDictionary *_fresh;
    NSMutableDictionary *_people;
    NSMutableSet *_requested;
    NSUInteger _teamTab;
}
@end

@implementation ExteriaAboutController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _fresh = [[NSMutableDictionary alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _requested = [[NSMutableSet alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.exteria", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_fresh release];
    [_people release];
    [_requested release];
    [_avatars release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self fetchPhotos];
}

/* the id stays with the account when its username changes */
- (void)fetchPhotos {
    NSMutableArray *ids = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(ExteriaCredits) / sizeof(ExteriaCredits[0]); ++i)
        [ids addObject:[NSNumber numberWithLongLong:ExteriaCredits[i].userId]];
    if (_teamTab == 1) [ids addObjectsFromArray:ExteriaOfficialTesterIds()];
    for (NSNumber *identifier in ids) {
        if ([_requested containsObject:identifier]) continue;
        [_requested addObject:identifier];
        ExteriaWeakReference *weak = _weak;
        ExteriaLoadTeamPerson(_session, identifier.longLongValue, ^(ExteriaPerson *person, NSString *error) {
            ExteriaAboutController *me = weak.target;
            if (!me) return;
            if (!person) {
                NSLog(@"exteria: team user %@ could not be loaded: %@", identifier, error);
                return;
            }
            [me->_people setObject:person forKey:identifier];
            [me rebuildSections];
            if (!person.photo) return;
            [me->_avatars loadImageForPhoto:person.photo completion:^(UIImage *image) {
                ExteriaAboutController *again = weak.target;
                if (!again || !image) return;
                [again->_fresh setObject:image forKey:identifier];
                [again rebuildSections];
            }];
        });
    }
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaAboutController alloc] initWithSession:_session avatars:_avatars] autorelease];
}

#pragma mark header

- (UIView *)makeHeader {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, HEADER_HEIGHT)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaRoundIcon(ICON_SIDE)] autorelease];
    icon.frame = CGRectMake(0, 24, ICON_SIDE, ICON_SIDE);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    icon.center = CGPointMake(width / 2, icon.center.y);
    [header addSubview:icon];
    UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake(0, 24 + ICON_SIDE + 10, width, 30)] autorelease];
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.backgroundColor = [UIColor clearColor];
    name.textAlignment = ExteriaTextAlignmentCenter;
    name.font = ExteriaFontBold(24);
    name.textColor = ExteriaColorTitle();
    name.text = NSLocalizedString(@"about.name", nil);
    [header addSubview:name];

    NSString *version = [@"v" stringByAppendingString:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @""];
    UILabel *versionLabel = [[[UILabel alloc] init] autorelease];
    versionLabel.backgroundColor = [UIColor clearColor];
    versionLabel.font = ExteriaFontRegular(15);
    versionLabel.textColor = ExteriaColorSecondary();
    versionLabel.text = version;
    UILabel *pill = [[[UILabel alloc] init] autorelease];
    pill.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.18];
    pill.textColor = ExteriaColorAccent();
    pill.font = ExteriaFontSemibold(12);
    pill.textAlignment = ExteriaTextAlignmentCenter;
    pill.text = ExteriaSliceName();
    pill.layer.cornerRadius = PILL_HEIGHT / 2;
    pill.layer.masksToBounds = YES;
    CGFloat versionWidth = ceil(ExteriaStringSize(version, versionLabel.font).width);
    CGFloat pillWidth = ceil(ExteriaStringSize(pill.text, pill.font).width) + 18;
    CGFloat gap = 8, x = floor((width - versionWidth - gap - pillWidth) / 2);
    CGFloat y = CGRectGetMaxY(name.frame) + 4;
    versionLabel.frame = CGRectMake(x, y, versionWidth, PILL_HEIGHT);
    pill.frame = CGRectMake(x + versionWidth + gap, y, pillWidth, PILL_HEIGHT);
    versionLabel.autoresizingMask = pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [header addSubview:versionLabel];
    [header addSubview:pill];
    return header;
}

#pragma mark rows

- (void)open:(NSString *)address {
    NSURL *url = [NSURL URLWithString:address];
    /* t.me addresses open as chats and profiles inside the app, through the main screen */
    if (url && ExteriaIsTelegramLink(url)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenLinkNotification object:self userInfo:[NSDictionary dictionaryWithObject:address forKey:@"url"]];
        return;
    }
    if (url && ![[UIApplication sharedApplication] openURL:url]) NSLog(@"exteria: the system did not open %@", address);
}

- (ExteriaSettingsRow *)categoryRow:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone key:(NSString *)key page:(UIViewController *(^)(void))page {
    ExteriaWeakReference *weak = _weak;
    NSString *title = NSLocalizedString(key, nil);
    return [ExteriaSettingsRow rowWithSymbol:symbol tone:tone title:title subtitle:nil value:nil tap:^{
        ExteriaAboutController *me = weak.target;
        if (me) [me.navigationController pushViewController:page() animated:YES];
    }];
}

- (ExteriaSettingsRow *)personRow:(const ExteriaCredit *)person {
    NSNumber *identifier = [NSNumber numberWithLongLong:person->userId];
    ExteriaPerson *known = [_people objectForKey:identifier];
    NSString *name = known.username.length ? known.username : ExteriaTeamUsername(person->userId);
    NSString *role = person->role ? NSLocalizedString(person->role, nil) : nil;
    BOOL lead = person == &ExteriaCredits[0];
    NSString *made = lead && person->app ? [NSString stringWithFormat:NSLocalizedString(@"about.made", nil), person->app] : nil;
    UIImage *picture = [_fresh objectForKey:identifier] ?: ExteriaInitialPicture(name, 2 * LEAD_TILE);
    UIImage *icon = lead && person->appIcon ? ExteriaBundledPicture(person->appIcon) : nil;
    ExteriaCreditView *view = [[[ExteriaCreditView alloc] initWithName:name role:role made:made picture:ExteriaShapedPicture(picture, person->lobes, person->depth, LEAD_TILE)
                                                                  appIcon:icon marks:ExteriaMarksOfId(person->userId)] autorelease];
    [view addTarget:self action:@selector(creditTapped:) forControlEvents:UIControlEventTouchUpInside];
    view.userId = person->userId;
    return [ExteriaSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return made ? 80 : 62; }];
}

- (void)creditTapped:(ExteriaCreditView *)view {
    ExteriaPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:view.userId]];
    if (!person || !person.accessHash) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"about.person.unavailable", nil));
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenTeamPersonNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:person forKey:@"person"]];
}

- (void)rebuild {
    self.headerView = [self makeHeader];
    [self rebuildSections];
}

- (void)rebuildSections {
    ExteriaWeakReference *weak = _weak;
    ExteriaSession *session = _session;

    NSArray *categories = [NSArray arrayWithObjects:
        [self categoryRow:ExteriaSymbolGear tone:ExteriaSettingsToneBlue key:@"about.main" page:^UIViewController *{
            return [[[ExteriaGeneralSettingsController alloc] init] autorelease];
        }],
        /* the theme and the dark mode live on this page, so it is the one category that has something in it */
        [self categoryRow:ExteriaSymbolBackground tone:ExteriaSettingsToneOrange key:@"about.look" page:^UIViewController *{
            return [[[ExteriaAppearanceSettingsController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:ExteriaSymbolSettingsChat tone:ExteriaSettingsToneGreen key:@"about.chats" page:^UIViewController *{
            return [[[ExteriaChatExtrasController alloc] initWithSession:session] autorelease];
        }],
        [self categoryRow:ExteriaSymbolEllipsis tone:ExteriaSettingsToneGray key:@"about.more" page:^UIViewController *{
            return [[[ExteriaMoreSettingsController alloc] initWithSession:session] autorelease];
        }], nil];

    ExteriaSettingsRow *channel = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMegaphone tone:ExteriaSettingsToneCyan title:NSLocalizedString(@"about.channel", nil)
                                                           subtitle:@"@sqmrakdev" value:nil tap:^{ [(ExteriaAboutController *)weak.target open:ExteriaChannelAddress]; }];
    ExteriaSettingsRow *source = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolExternalLink tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"about.source", nil)
                                                          subtitle:[ExteriaSourceAddress substringFromIndex:[@"https://" length]] value:nil tap:^{ [(ExteriaAboutController *)weak.target open:ExteriaSourceAddress]; }];

    ExteriaPillTabsView *tabs = [[[ExteriaPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"about.developers", nil), NSLocalizedString(@"about.testers", nil), nil]] autorelease];
    tabs.selectedIndex = _teamTab;
    tabs.changeHandler = ^(NSUInteger index) {
        ExteriaAboutController *me = weak.target;
        if (!me) return;
        me->_teamTab = index;
        [me rebuildSections];
        [me fetchPhotos];
    };
    NSMutableArray *people = [NSMutableArray array];
    if (_teamTab == 0) {
        for (size_t i = 1; i < sizeof(ExteriaCredits) / sizeof(ExteriaCredits[0]); ++i) [people addObject:[self personRow:&ExteriaCredits[i]]];
    } else {
        for (NSNumber *identifier in ExteriaOfficialTesterIds()) {
            ExteriaCredit tester = {identifier.longLongValue, nil, 8, 0.12, nil, nil};
            [people addObject:[self personRow:&tester]];
        }
    }

    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.categories", nil) footer:nil rows:categories],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.links", nil) footer:nil rows:[NSArray arrayWithObjects:channel, source, nil]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.team", nil) footer:nil rows:[NSArray arrayWithObject:[self personRow:&ExteriaCredits[0]]]],
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:[ExteriaSettingsRow viewRowWithView:tabs height:^CGFloat(CGFloat width) { (void)width; return 40; }]]],
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:people], nil];
}

@end
