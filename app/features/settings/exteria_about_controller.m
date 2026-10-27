#import "exteria_about_controller.h"
#import "exteria_general_settings_controller.h"
#import "exteria_more_settings_controller.h"
#import "exteria_link_router.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_extras_controller.h"
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
    NSString *name;
    NSString *picture;
    NSString *role;
    /* the outline of the picture: a circle pressed in by lobes dents of the given depth, as the shapes of the material 3 expressive set are */
    int lobes;
    CGFloat depth;
    /* the app this person made, with the picture of its icon, or nil */
    NSString *app;
    NSString *appIcon;
} ExteriaCredit;

static const ExteriaCredit ExteriaCredits[] = {
    {@"sqmrak", @"credit_sqmrak", @"about.lead", 9, 0.10, @"Senko", @"app_senko"},
    {@"QWERTYU1OPZ", @"credit_qwertyu1opz", @"about.backend", 4, 0.14, @"LegacyGram", @"app_legacygram"},
    {@"LimeDev", @"credit_limedev", @"about.frontend", 8, 0.16, @"MintAI", @"app_mintai"},
    {@"menstry", @"credit_menstry", @"about.backend", 12, 0.08, @"TeleGloss", @"app_telegloss"},
    {@"anazerka", @"credit_anazerka", @"about.backend", 5, 0.12, @"Twelve", @"app_twelve"},
    {@"loveiOS6", @"credit_loveios6", @"about.frontend", 6, 0.14, @"iChatter", @"app_ichatter"},
    {@"nestorvashenko", @"credit_nestorvashenko", @"about.frontend", 7, 0.12, @"iKlassika", @"app_iklassika"},
    {@"svcayon4ik", @"credit_svcayon4ik", @"about.backend", 10, 0.10, @"FlowGram", @"app_flowgram"},
    {@"illyagif", @"credit_illyagif", @"about.backend", 3, 0.12, @"OneGram", @"app_onegram"},
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

@interface ExteriaAboutController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaWeakReference *_weak;
    /* the current profile photo of each name that the server answered for, by name; the bundled picture stands in until then */
    NSMutableDictionary *_fresh;
    BOOL _fetched;
}
@end

@implementation ExteriaAboutController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _fresh = [[NSMutableDictionary alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.exteria", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_fresh release];
    [_avatars release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self fetchPhotos];
}

/* the photo a person has now, by the @name; a name the server does not answer for, or one without a photo, keeps
   the bundled picture */
- (void)fetchPhotos {
    if (_fetched) return;
    _fetched = YES;
    for (size_t i = 0; i < sizeof(ExteriaCredits) / sizeof(ExteriaCredits[0]); ++i) {
        NSString *name = ExteriaCredits[i].name;
        ExteriaWeakReference *weak = _weak;
        [_session resolveUsername:name completion:^(ExteriaDialog *dialog, ExteriaPerson *person, NSString *errorName) {
            (void)dialog;
            ExteriaAboutController *me = weak.target;
            if (!me || !person.photo) {
                if (me && errorName) NSLog(@"exteria: no photo for @%@: %@", name, errorName);
                return;
            }
            [me->_avatars loadImageForPhoto:person.photo completion:^(UIImage *image) {
                ExteriaAboutController *again = weak.target;
                if (!again || !image) return;
                [again->_fresh setObject:image forKey:name];
                [again rebuildSections];
            }];
        }];
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
    ExteriaWeakReference *weak = _weak;
    NSString *address = [@"https://t.me/" stringByAppendingString:person->name];
    NSString *title = [@"@" stringByAppendingString:person->name];
    NSString *role = NSLocalizedString(person->role, nil);
    /* the app they made is named under the role and shown by its icon at the right end of the row */
    NSString *made = person->app ? [NSString stringWithFormat:NSLocalizedString(@"about.made", nil), person->app] : nil;
    UIImage *picture = [_fresh objectForKey:person->name] ?: ExteriaBundledPicture(person->picture);
    UIImage *icon = person->appIcon ? ExteriaBundledPicture(person->appIcon) : nil;
    void (^tap)(void) = ^{ [(ExteriaAboutController *)weak.target open:address]; };
    BOOL lead = person == &ExteriaCredits[0];
    ExteriaSettingsRow *row;
    /* the classic table draws only a tile picture, so there the lead keeps the plain row */
    if (lead && !ExteriaThemeIsClassic()) {
        row = [ExteriaSettingsRow sessionRowWithPicture:ExteriaShapedPicture(picture, person->lobes, person->depth, LEAD_TILE) title:title line2:role
                                                  line3:made accentLine3:YES tap:tap];
    } else {
        CGFloat side = ExteriaThemeIsClassic() ? 29 : PERSON_TILE;
        NSString *subtitle = made ? [NSString stringWithFormat:@"%@\n%@", role, made] : role;
        row = [ExteriaSettingsRow rowWithTileImage:ExteriaShapedPicture(picture, person->lobes, person->depth, side) title:title subtitle:subtitle tap:tap];
    }
    row.trailingImage = icon;
    return row;
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

    NSMutableArray *people = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(ExteriaCredits) / sizeof(ExteriaCredits[0]); ++i) [people addObject:[self personRow:&ExteriaCredits[i]]];

    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.categories", nil) footer:nil rows:categories],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.links", nil) footer:nil rows:[NSArray arrayWithObjects:channel, source, nil]],
        [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"about.developers", nil) footer:nil rows:people], nil];
}

@end
