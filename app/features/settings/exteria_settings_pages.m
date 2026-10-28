#import "exteria_settings_pages.h"

#import "exteria_alert.h"
#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_platform.h"
#include <math.h>
#import "exteria_sheet.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define PREVIEW_AVATARS 4
#define PREVIEW_SIDE 56.0

/* a row of four pictures that take the corner the slider gives them as it moves, so the person sees the shape before it reaches the rest of the app */
@interface ExteriaAvatarCornerPreview : UIView {
    NSMutableArray *_avatars;
}
- (void)refresh;
@end

@implementation ExteriaAvatarCornerPreview

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    static NSString *const initials[PREVIEW_AVATARS] = {@"A", @"Б", @"V", @"Ж"};
    _avatars = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < PREVIEW_AVATARS; ++i) {
        ExteriaAvatarView *avatar = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, PREVIEW_SIDE, PREVIEW_SIDE)] autorelease];
        avatar.initials = initials[i];
        avatar.seed = i * 3 + 1;
        [self addSubview:avatar];
        [_avatars addObject:avatar];
    }
    return self;
}

- (void)dealloc {
    [_avatars release];
    [super dealloc];
}

- (void)refresh {
    for (ExteriaAvatarView *avatar in _avatars) [avatar setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat gap = (self.bounds.size.width - PREVIEW_AVATARS * PREVIEW_SIDE) / (PREVIEW_AVATARS + 1);
    CGFloat scale = ExteriaScreenScale();
    for (NSUInteger i = 0; i < PREVIEW_AVATARS; ++i) {
        CGFloat x = round((gap + i * (PREVIEW_SIDE + gap)) * scale) / scale;
        CGFloat y = round((self.bounds.size.height - PREVIEW_SIDE) * scale / 2) / scale;
        ((UIView *)[_avatars objectAtIndex:i]).frame = CGRectMake(x, y, PREVIEW_SIDE, PREVIEW_SIDE);
    }
}

@end

@interface ExteriaAppearanceSettingsController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    ExteriaAvatarCornerPreview *_preview;
}
@end

@implementation ExteriaAppearanceSettingsController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.exteria.look", nil);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_preview release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

/* every screen reads its settings when it is built, so the main controller builds them again on this notification, from the row that was touched; this page
   stays and is made again */
- (void)apply {
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:ExteriaThemeOriginKey]];
}

/* a slider moves in many small steps, and the screens are built once it rests */
- (void)applySoon {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(apply) object:nil];
    [self performSelector:@selector(apply) withObject:nil afterDelay:0.7];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaAppearanceSettingsController alloc] initWithSession:_session] autorelease];
}

#pragma mark sections

- (ExteriaSettingsSection *)layoutSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaTabLayout current = ExteriaTabLayoutStored();
    NSArray *keys = [NSArray arrayWithObjects:@"look.layout.messenger", @"look.layout.calls", nil];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil) subtitle:nil checked:!ExteriaTabOrderIsCustom() && (NSUInteger)current == i tap:^{
            if (!ExteriaTabOrderIsCustom() && (NSUInteger)ExteriaTabLayoutStored() == i) return;
            ExteriaTabLayoutStore((ExteriaTabLayout)i);
            [(ExteriaAppearanceSettingsController *)weak.target apply];
        }]];
    }
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.layout.header", nil) footer:NSLocalizedString(@"look.layout.info", nil) rows:rows];
}

- (ExteriaSettingsSection *)avatarSection {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    if (!_preview) _preview = [[ExteriaAvatarCornerPreview alloc] initWithFrame:CGRectMake(0, 0, 320, 88)];
    ExteriaAvatarCornerPreview *preview = _preview;
    [rows addObject:[ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return 88; }]];
    [rows addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.avatar.corners", nil) format:@"%.0f%%" value:(float)ExteriaAvatarCornerPercent()
                                                   minimum:0 maximum:100 change:^(float value) {
        ExteriaAvatarCornerStore((NSInteger)(value + 0.5f));
        [preview refresh];
        [(ExteriaAppearanceSettingsController *)weak.target applySoon];
    }]];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.avatar.header", nil) footer:NSLocalizedString(@"look.avatar.info", nil) rows:rows];
}

- (void)chooseTitle {
    ExteriaWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"look.title.default", nil), NSLocalizedString(@"look.title.username", nil),
                        NSLocalizedString(@"look.title.name", nil), NSLocalizedString(@"look.title.custom", nil), nil];
    ExteriaSettingsChoose(self, NSLocalizedString(@"look.title", nil), options, ^(NSUInteger index) {
        ExteriaAppearanceSettingsController *me = weak.target;
        if (!me) return;
        if (index == ExteriaChatListTitleCustom) {
            ExteriaPromptText(NSLocalizedString(@"look.title.custom", nil), nil, ExteriaChatListCustomTitle(), NSLocalizedString(@"look.title.hint", nil), ^(NSString *text) {
                ExteriaAppearanceSettingsController *page = weak.target;
                if (!page) return;
                ExteriaChatListSetCustomTitle(text);
                ExteriaChatListTitleStore(ExteriaChatListTitleCustom);
                [page apply];
            });
            return;
        }
        ExteriaChatListTitleStore((ExteriaChatListTitle)index);
        [me apply];
    });
}

- (ExteriaSettingsSection *)chatListSection {
    ExteriaWeakReference *weak = _weak;
    static NSString *const titleKeys[] = {@"look.title.default", @"look.title.username", @"look.title.name", @"look.title.custom"};
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.stories", nil) subtitle:nil on:!ExteriaChatFlagGet(ExteriaChatFlagHideStories) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagHideStories, !on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidesearch", nil) subtitle:nil on:ExteriaChatFlagGet(ExteriaChatFlagHideSearchBar) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagHideSearchBar, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidevpn", nil) subtitle:nil on:ExteriaChatFlagGet(ExteriaChatFlagHideVpnButton) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagHideVpnButton, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"look.title", nil) value:NSLocalizedString(titleKeys[ExteriaChatListTitleStored()], nil) tap:^{
        [(ExteriaAppearanceSettingsController *)weak.target chooseTitle];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.senderavatars", nil) subtitle:nil on:ExteriaChatFlagGet(ExteriaChatFlagSenderAvatars) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagSenderAvatars, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.snow", nil) subtitle:NSLocalizedString(@"look.snow.info", nil) on:ExteriaChatFlagGet(ExteriaChatFlagSnow) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagSnow, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.foxes", nil) subtitle:NSLocalizedString(@"look.foxes.info", nil) on:ExteriaChatFlagGet(ExteriaChatFlagFoxes) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagFoxes, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"look.hidewaves", nil) subtitle:NSLocalizedString(@"look.hidewaves.info", nil) on:ExteriaChatFlagGet(ExteriaChatFlagHideWaves) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagHideWaves, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }]];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.chatlist.header", nil) footer:nil rows:rows];
}

- (ExteriaSettingsSection *)foldersSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *hide = [ExteriaSettingsRow switchRowWithTitle:[NSString stringWithFormat:NSLocalizedString(@"look.hidealltab", nil), NSLocalizedString(@"folders.all", nil)]
                                                             subtitle:nil on:ExteriaChatFlagGet(ExteriaChatFlagHideAllChatsTab) toggle:^(BOOL on) {
        ExteriaChatFlagSet(ExteriaChatFlagHideAllChatsTab, on);
        [(ExteriaAppearanceSettingsController *)weak.target apply];
    }];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.folders.header", nil) footer:NSLocalizedString(@"look.folders.info", nil) rows:[NSArray arrayWithObject:hide]];
}

- (ExteriaSettingsSection *)cardsSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaSettingsRow *radius = [ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.cards.radius", nil) format:@"%.0f" value:(float)ExteriaSectionRadius()
                                                                minimum:0 maximum:EXTERIA_SECTION_RADIUS_MAX change:^(float value) {
        ExteriaSectionRadiusStore((NSInteger)(value + 0.5f));
        [(ExteriaAppearanceSettingsController *)weak.target applySoon];
    }];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.cards.header", nil) footer:nil rows:[NSArray arrayWithObject:radius]];
}

- (void)rebuild {
    self.sections = [NSArray arrayWithObjects:[self layoutSection], [self avatarSection], [self chatListSection], [self foldersSection], [self cardsSection], nil];
    [self reloadSettings];
}

@end
