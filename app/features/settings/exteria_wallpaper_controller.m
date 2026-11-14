#import "exteria_wallpaper_controller.h"

#import "exteria_animation.h"
#import "exteria_avatar_cache.h"
#import "exteria_chat_preview_view.h"
#import "exteria_chat_settings.h"
#import "exteria_customization_views.h"
#import "exteria_developers.h"
#import "exteria_person.h"
#import "exteria_pill_tabs_view.h"
#import "exteria_shape.h"
#import "exteria_gift_screen.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_session.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_tint_editor.h"
#import "exteria_tint_picker.h"
#import "exteria_wallpaper.h"
#import "exteria_wallpaper_grid_view.h"
#import "exteria_weak_reference.h"


@interface ExteriaWallpaperController () {
    ExteriaWeakReference *_weak;
    ExteriaChatPreviewView *_preview;
    ExteriaWallpaperGridView *_grid;
    UIControl<ExteriaTintControl> *_picker;
    /* the modern page has two tabs, the wallpapers and the customization of the look of the app; the second is not offered for the wallpaper of one chat */
    NSUInteger _tab;
    ExteriaPillTabsView *_tabs;
    ExteriaShapeGridView *_shapes;
    ExteriaCustomPreviewView *_customPreview;
    ExteriaClassicPreviewView *_classicPreview;
    /* the classic style makes every page again after a change of the color, and the new table starts at the top; the offset of the old one is brought back */
    CGFloat _restoreOffset;
    BOOL _restoresOffset;
    /* the chat the page edits the wallpaper of, zero for every chat */
    int32_t _peerKind;
    long long _peerId;
    ExteriaSession *_session;
}
@end

@implementation ExteriaWallpaperController
@synthesize session = _session;


- (id)init {
    return [self initWithPeerKind:0 peerId:0];
}

- (id)initWithPeerKind:(int32_t)peerKind peerId:(long long)peerId {
    self = [super init];
    if (!self) return nil;
    _peerKind = peerId ? peerKind : 0;
    _peerId = peerId;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(_peerId ? @"chatset.wallpaper.chat" : @"chatset.wallpaper", nil);
    return self;
}

/* what the page reads and writes: the wallpaper of its chat, or the one of every chat */
- (ExteriaWallpaperSetting)stored {
    if (!_peerId) return ExteriaWallpaperStored();
    ExteriaWallpaperSetting setting = ExteriaWallpaperStoredForChat(_peerKind, _peerId);
    /* a chat without a wallpaper of its own starts from the colors of every chat, but not from their photo, which is a file this chat does not have */
    if (setting.kind == ExteriaWallpaperPhoto && !ExteriaWallpaperChatHasOwn(_peerKind, _peerId)) setting.kind = ExteriaWallpaperStandard;
    return setting;
}

/* a setting taken from the stored one or a preset belongs to this page's chat */
- (void)store:(ExteriaWallpaperSetting)setting {
    setting.chatKind = _peerKind;
    setting.chatId = _peerId;
    ExteriaWallpaperStore(setting);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_preview release];
    [_grid release];
    [_picker release];
    [_tabs release];
    [_shapes release];
    [_customPreview release];
    [_classicPreview release];
    [_session release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [super dealloc];
}

/* the settings table does not move for the keyboard of the hex field, which stands low on this page: the table gets room under it and brings the field up */
- (void)keyboardWillChange:(NSNotification *)note {
    NSValue *end = [note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (![end isKindOfClass:[NSValue class]]) return;
    CGRect keyboard = [self.view convertRect:[end CGRectValue] fromView:nil];
    CGFloat covered = MAX(0, CGRectGetMaxY(self.table.frame) - keyboard.origin.y);
    UIEdgeInsets insets = self.table.contentInset;
    insets.bottom = covered;
    self.table.contentInset = insets;
    self.table.scrollIndicatorInsets = insets;
    if (covered > 0 && _picker.window) {
        [self.table scrollRectToVisible:[self.table convertRect:_picker.editingRect fromView:_picker] animated:YES];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    ExteriaWallpaperController *again = [[[ExteriaWallpaperController alloc] initWithPeerKind:_peerKind peerId:_peerId] autorelease];
    if ([self isViewLoaded]) {
        again->_restoreOffset = self.table.contentOffset.y;
        again->_restoresOffset = YES;
    }
    again->_tab = _tab;
    again.session = _session;
    return again;
}

/* the offset is set once the new table has its size and its rows, clamped to what the page can scroll now */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_restoresOffset) return;
    UITableView *table = self.table;
    if (table.bounds.size.height <= 0 || table.contentSize.height <= 0) return;
    _restoresOffset = NO;
    CGFloat low = -table.contentInset.top;
    CGFloat high = MAX(low, table.contentSize.height - table.bounds.size.height + table.contentInset.bottom);
    table.contentOffset = CGPointMake(0, MIN(high, MAX(low, _restoreOffset)));
}

/* the preview and the tiles read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[ExteriaChatPreviewView alloc] init];
    _preview.wallpaperPeerKind = _peerKind;
    _preview.wallpaperPeerId = _peerId;
    ExteriaWeakReference *previewWeak = _weak;
    _preview.heightHandler = ^{ [(ExteriaWallpaperController *)previewWeak.target updateRowHeights]; };
    [_picker release];
    /* the classic look keeps the square with metal discs; the modern one has the expressive editor */
    _picker = ExteriaThemeIsClassic() ? (UIControl<ExteriaTintControl> *)[[ExteriaTintPicker alloc] init] : (UIControl<ExteriaTintControl> *)[[ExteriaTintEditor alloc] init];
    [_picker addTarget:self action:@selector(tintCommitted:) forControlEvents:UIControlEventTouchUpInside];
    [_grid release];
    _grid = [[ExteriaWallpaperGridView alloc] init];
    ExteriaWeakReference *weak = _weak;
    _grid.galleryHandler = ^{ [(ExteriaWallpaperController *)weak.target pickPhoto]; };
    _grid.standardHandler = ^{
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        /* the standard tile of a chat is the way back to the wallpaper every chat wears */
        if (me->_peerId) {
            ExteriaWallpaperClearChat(me->_peerKind, me->_peerId);
        } else {
            ExteriaWallpaperSetting standard = ExteriaWallpaperStored();
            standard.kind = ExteriaWallpaperStandard;
            ExteriaWallpaperStore(standard);
        }
        [me rebuild];
    };
    _grid.chooseHandler = ^(NSUInteger index) {
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        [me store:ExteriaWallpaperPreset(index)];
        [me rebuild];
    };    [self buildCustomizationViews];
}

/* the rows under the tabs come in from the side the new tab lies on: with a wobble, a spring that overshoots and settles back, in the modern style, and with a plain ease in the
   skeuomorphic one. the tabs themselves stay where they are */
- (void)animateTabChangeFrom:(NSUInteger)previous {
    if (previous == _tab || !self.isViewLoaded) return;
    [self.table layoutIfNeeded];
    CGFloat direction = _tab > previous ? 1 : -1;
    BOOL modern = !ExteriaThemeIsClassic();
    for (UITableViewCell *cell in self.table.visibleCells) {
        if ([_tabs isDescendantOfView:cell]) continue;
        if (modern) ExteriaAnimateEnter(cell, CGAffineTransformConcat(CGAffineTransformMakeScale(0.94f, 0.94f), CGAffineTransformMakeTranslation(direction * 56, 0)), 0, EXTERIA_MOTION_WOBBLE);
        else ExteriaAnimateEnter(cell, CGAffineTransformMakeTranslation(direction * 24, 0), 0, EXTERIA_MOTION_ENTER);
    }
}

/* the tabs and the views of the customization, made again with the colors of a new theme */
- (void)buildCustomizationViews {
    [_tabs release];
    _tabs = [[ExteriaPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"custom.tab.wallpapers", nil), NSLocalizedString(@"custom.tab.look", nil), nil]];
    _tabs.selectedIndex = _tab;
    ExteriaWeakReference *weak = _weak;
    _tabs.changeHandler = ^(NSUInteger index) {
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        NSUInteger previous = me->_tab;
        me->_tab = index;
        [me rebuild];
        [me animateTabChangeFrom:previous];
    };
    [_shapes release];
    _shapes = [[ExteriaShapeGridView alloc] init];
    _shapes.chooseHandler = ^(NSInteger shape) {
        ExteriaWallpaperController *me = weak.target;
        if (!me) return;
        ExteriaAvatarShapeStore(shape);
        [me applyLook];
        [me applyLookNow];
    };
    [_customPreview release];
    _customPreview = [[ExteriaCustomPreviewView alloc] init];
    [_classicPreview release];
    _classicPreview = [[ExteriaClassicPreviewView alloc] init];
    [self showLeadPicture];
}

/* the previews show the lead developer, sqmrak, with the picture that ships in the bundle, so the row looks the same before the network is up */
- (void)showLeadPicture {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"app_sqmrak" ofType:@"png"];
    UIImage *picture = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!picture) {
        NSLog(@"exteria: the picture of the lead is missing from the bundle");
        return;
    }
    [_customPreview setPicture:picture];
    [_classicPreview setPicture:picture];
}

/* every screen reads its settings when it is built, so the main controller builds them again on this notification; this page stays and is made again */
- (void)applyLook {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyLookNow) object:nil];
    [self performSelector:@selector(applyLookNow) withObject:nil afterDelay:0.5];
    [_customPreview refresh];
    [_classicPreview refresh];
    _shapes.selectedShape = ExteriaAvatarShapeStored();
}

/* a tap on a choice starts the duck at once, from the point that was touched; a slider waits until it rests */
- (void)applyLookNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyLookNow) object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:ExteriaThemeOriginKey]];
}

- (ExteriaSettingsSection *)tabsSection {
    ExteriaPillTabsView *tabs = _tabs;
    return [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:[ExteriaSettingsRow viewRowWithView:tabs height:^CGFloat(CGFloat width) { (void)width; return 40; }]]];
}

/* a group of rows of which one is chosen: a tap stores it, starts the duck and makes the page again */
- (NSArray *)choiceRowsWithKeys:(NSArray *)keys current:(NSInteger)current store:(void (^)(NSInteger))store {
    ExteriaWeakReference *weak = _weak;
    void (^keep)(NSInteger) = [[store copy] autorelease];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString([keys objectAtIndex:i], nil) subtitle:nil checked:(NSUInteger)current == i tap:^{
            ExteriaWallpaperController *me = weak.target;
            if (!me || (NSInteger)i == current) return;
            keep((NSInteger)i);
            [me applyLook];
            [me applyLookNow];
        }]];
    }
    return rows;
}

- (NSArray *)classicCustomizationSections {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self tabsSection]];
    ExteriaClassicPreviewView *preview = _classicPreview;
    [preview refresh];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return [ExteriaClassicPreviewView height]; }]]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.gloss.header", nil) footer:NSLocalizedString(@"custom.gloss.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.gloss.off", @"custom.gloss.normal", @"custom.gloss.strong", nil] current:ExteriaClassicGlossLevel()
                                store:^(NSInteger value) { ExteriaClassicGlossStore(value); }]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.material.header", nil) footer:NSLocalizedString(@"custom.material.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.material.accent", @"custom.material.steel", @"custom.material.graphite", @"custom.material.black", nil]
                              current:ExteriaClassicMaterial() store:^(NSInteger value) { ExteriaClassicMaterialStore(value); }]]];
    NSMutableArray *texture = [NSMutableArray arrayWithArray:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.texture.linen", @"custom.texture.plain", nil]
                                                                              current:ExteriaClassicTextureStyle() store:^(NSInteger value) { ExteriaClassicTextureStyleStore(value); }]];
    if (ExteriaClassicTextureStyle() == 0) {
        [texture addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"custom.texture.strength", nil) format:@"%.0f%%" value:(float)ExteriaClassicTextureStrength()
                                                          minimum:0 maximum:100 change:^(float value) {
            ExteriaClassicTextureStrengthStore((NSInteger)(value + 0.5f));
            [(ExteriaWallpaperController *)weak.target applyLook];
        }]];
        /* the linen follows the accent unless a hue of its own is set, which the slider below then moves */
        BOOL ownHue = ExteriaClassicTextureHue() >= 0;
        [texture addObjectsFromArray:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.texture.follow", @"custom.texture.own", nil] current:ownHue ? 1 : 0
                                                        store:^(NSInteger value) { ExteriaClassicTextureHueStore(value ? 262 : -1); }]];
        if (ownHue) {
            [texture addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"custom.texture.hue", nil) format:@"%.0f°" value:(float)ExteriaClassicTextureHue()
                                                              minimum:0 maximum:359 change:^(float value) {
                ExteriaClassicTextureHueStore((NSInteger)(value + 0.5f));
                [(ExteriaWallpaperController *)weak.target applyLook];
            }]];
        }
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.texture.header", nil) footer:NSLocalizedString(@"custom.texture.info", nil) rows:texture]];
    ExteriaSettingsRow *avatarGloss = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"custom.avatar.gloss", nil) subtitle:nil on:ExteriaClassicAvatarGloss() toggle:^(BOOL on) {
        ExteriaClassicAvatarGlossStore(on);
        [(ExteriaWallpaperController *)weak.target applyLookNow];
    }];
    ExteriaSettingsRow *avatarShadow = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"custom.avatar.shadow", nil) subtitle:nil on:ExteriaClassicAvatarShadow() toggle:^(BOOL on) {
        ExteriaClassicAvatarShadowStore(on);
        [(ExteriaWallpaperController *)weak.target applyLookNow];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.avatars.header", nil) footer:nil rows:[NSArray arrayWithObjects:avatarGloss, avatarShadow, nil]]];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.separators.header", nil) footer:NSLocalizedString(@"custom.separators.info", nil)
        rows:[self choiceRowsWithKeys:[NSArray arrayWithObjects:@"custom.separators.thin", @"custom.separators.etched", @"custom.separators.none", nil] current:ExteriaClassicSeparators()
                                store:^(NSInteger value) { ExteriaClassicSeparatorsStore(value); }]]];
    return sections;
}

- (NSArray *)customizationSections {
    if (ExteriaThemeIsClassic()) return [self classicCustomizationSections];
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self tabsSection]];
    ExteriaCustomPreviewView *preview = _customPreview;
    [preview refresh];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
        [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { (void)width; return [ExteriaCustomPreviewView height]; }]]]];

    ExteriaShapeGridView *shapes = _shapes;
    shapes.selectedShape = ExteriaAvatarShapeStored();
    NSMutableArray *avatarRows = [NSMutableArray array];
    [avatarRows addObject:[ExteriaSettingsRow viewRowWithView:shapes height:^CGFloat(CGFloat width) { return [ExteriaShapeGridView heightForWidth:width]; }]];
    if (ExteriaAvatarShapeStored() == ExteriaShapeRounded) {
        [avatarRows addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.avatar.corners", nil) format:@"%.0f%%" value:(float)ExteriaAvatarCornerPercent()
                                                             minimum:0 maximum:100 change:^(float value) {
            ExteriaAvatarCornerStore((NSInteger)(value + 0.5f));
            [(ExteriaWallpaperController *)weak.target applyLook];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.avatars.header", nil) footer:NSLocalizedString(@"custom.avatars.info", nil) rows:avatarRows]];

    NSMutableArray *sendRows = [NSMutableArray array];
    NSArray *sendKeys = [NSArray arrayWithObjects:@"custom.send.circle", @"custom.send.rounded", @"custom.send.avatar", nil];
    for (NSUInteger i = 0; i < sendKeys.count; ++i) {
        [sendRows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString([sendKeys objectAtIndex:i], nil) subtitle:nil checked:(NSUInteger)ExteriaSendShapeStored() == i tap:^{
            ExteriaWallpaperController *me = weak.target;
            if (!me || (NSUInteger)ExteriaSendShapeStored() == i) return;
            ExteriaSendShapeStore((NSInteger)i);
            [me applyLook];
            [me applyLookNow];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.send.header", nil) footer:nil rows:sendRows]];

    ExteriaSettingsRow *bubbles = [ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.corners.row", nil) format:@"%.0f" value:(float)ExteriaChatBubbleRadius()
                                                                 minimum:EXTERIA_CHAT_BUBBLE_RADIUS_MIN maximum:EXTERIA_CHAT_BUBBLE_RADIUS_MAX change:^(float value) {
        ExteriaChatSetBubbleRadius((NSInteger)(value + 0.5f));
        [[(ExteriaWallpaperController *)weak.target customPreviewView] refresh];
    }];
    ExteriaSettingsRow *cards = [ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"look.cards.radius", nil) format:@"%.0f" value:(float)ExteriaSectionRadius()
                                                               minimum:0 maximum:EXTERIA_SECTION_RADIUS_MAX change:^(float value) {
        ExteriaSectionRadiusStore((NSInteger)(value + 0.5f));
        [(ExteriaWallpaperController *)weak.target applyLook];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.corners.header", nil) footer:nil rows:[NSArray arrayWithObjects:bubbles, cards, nil]]];

    NSMutableArray *density = [NSMutableArray array];
    NSArray *densityKeys = [NSArray arrayWithObjects:@"custom.density.regular", @"custom.density.compact", nil];
    for (NSUInteger i = 0; i < densityKeys.count; ++i) {
        [density addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString([densityKeys objectAtIndex:i], nil) subtitle:nil checked:(NSUInteger)ExteriaListDensityStored() == i tap:^{
            ExteriaWallpaperController *me = weak.target;
            if (!me || (NSUInteger)ExteriaListDensityStored() == i) return;
            ExteriaListDensityStore((NSInteger)i);
            [me applyLook];
            [me applyLookNow];
        }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"custom.density.header", nil) footer:NSLocalizedString(@"custom.density.info", nil) rows:density]];

    ExteriaSettingsRow *indicator = [ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"custom.indicator", nil) subtitle:nil on:ExteriaTabIndicatorOn() toggle:^(BOOL on) {
        ExteriaTabIndicatorStore(on);
        [(ExteriaWallpaperController *)weak.target applyLookNow];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"look.layout.header", nil) footer:nil rows:[NSArray arrayWithObject:indicator]]];
    return sections;
}

- (ExteriaCustomPreviewView *)customPreviewView {
    return _customPreview;
}

- (void)tintCommitted:(UIControl<ExteriaTintControl> *)picker {
    ExteriaThemeStoreCustomTint(picker.hue, picker.saturation, picker.brightness);
    CGPoint origin = [picker convertPoint:CGPointMake(CGRectGetMidX(picker.bounds), CGRectGetMidY(picker.bounds)) toView:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:ExteriaThemeOriginKey]];
}

- (void)themeDidChange {
    [self buildThemedViews];
    [self rebuild];
}

/* the index of the gradient the stored wallpaper is, NSNotFound when it is none of them (a photo, or the standard wallpaper) */
static NSUInteger ExteriaChosenPreset(ExteriaWallpaperSetting stored) {
    if (stored.kind != ExteriaWallpaperColors) return NSNotFound;
    for (NSUInteger i = 0; i < ExteriaWallpaperPresetCount(); ++i) {
        ExteriaWallpaperSetting preset = ExteriaWallpaperPreset(i);
        if (preset.top == stored.top && preset.bottom == stored.bottom && preset.angle == stored.angle) return i;
    }
    return NSNotFound;
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    ExteriaWallpaperSetting setting = [self stored];
    BOOL tabbed = !_peerId;
    if (tabbed && _tab == 1) {
        self.sections = [self customizationSections];
        [self reloadSettings];
        return;
    }
    NSMutableArray *sections = [NSMutableArray array];
    if (tabbed) [sections addObject:[self tabsSection]];

    ExteriaChatPreviewView *preview = _preview;
    ExteriaSettingsRow *picture = [ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:picture]]];

    /* the purple of the app until a color is picked; the wallpaper does not give the app its color */
    float hue = 286, saturation = 0.6f, brightness = 1;
    ExteriaThemeStoredCustomTint(&hue, &saturation, &brightness);
    _picker.hue = hue;
    _picker.saturation = saturation;
    _picker.brightness = brightness;
    UIControl<ExteriaTintControl> *picker = _picker;
    ExteriaSettingsRow *tint = [ExteriaSettingsRow viewRowWithView:picker height:^CGFloat(CGFloat width) { (void)width; return picker.preferredHeight; }];
    /* the color of the app is the app's, not the chat's */
    if (!_peerId) [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.tint.header", nil) footer:nil rows:[NSArray arrayWithObject:tint]]];

    ExteriaWallpaperGridView *grid = _grid;
    grid.chosenIndex = ExteriaChosenPreset(setting);
    grid.photoChosen = setting.kind == ExteriaWallpaperPhoto;
    grid.standardChosen = _peerId ? !ExteriaWallpaperChatHasOwn(_peerKind, _peerId) : setting.kind == ExteriaWallpaperStandard;
    ExteriaSettingsRow *tiles = [ExteriaSettingsRow viewRowWithView:grid height:^CGFloat(CGFloat width) { (void)width; return [ExteriaWallpaperGridView height]; }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.wallpaper.colors", nil) footer:nil rows:[NSArray arrayWithObject:tiles]]];

    if (setting.kind == ExteriaWallpaperColors) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.pattern", nil) subtitle:nil on:setting.pattern != 0 toggle:^(BOOL on) {
            ExteriaWallpaperController *me = weak.target;
            if (!me) return;
            ExteriaWallpaperSetting next = [me stored];
            next.pattern = on ? 1 : 0;
            [me store:next];
            [me rebuild];
        }]];
        if (setting.pattern) {
            [options addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.intensity", nil) format:@"%.0f%%" value:(float)setting.intensity
                                                              minimum:0 maximum:100 change:^(float value) {
                ExteriaWallpaperController *me = weak.target;
                if (!me) return;
                ExteriaWallpaperSetting next = [me stored];
                int intensity = (int)(value + 0.5f);
                if (intensity == next.intensity) return;
                next.intensity = intensity;
                [me store:next];
            }]];
        }
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    } else if (setting.kind == ExteriaWallpaperPhoto) {
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.wallpaper.blur", nil) subtitle:nil on:setting.blur != 0 toggle:^(BOOL on) {
            ExteriaWallpaperController *me = weak.target;
            if (!me) return;
            ExteriaWallpaperSetting next = [me stored];
            next.blur = on ? 1 : 0;
            [me store:next];
        }]];
        [options addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.wallpaper.dim", nil) format:@"%.0f%%" value:(float)setting.dim
                                                          minimum:0 maximum:100 change:^(float value) {
            ExteriaWallpaperController *me = weak.target;
            if (!me) return;
            ExteriaWallpaperSetting next = [me stored];
            int dim = (int)(value + 0.5f);
            if (dim == next.dim) return;
            next.dim = dim;
            [me store:next];
        }]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:options]];
    }
    self.sections = sections;
    [self reloadSettings];
}

- (void)pickPhoto {
    ExteriaWeakReference *weak = _weak;
    int32_t peerKind = _peerKind;
    long long peerId = _peerId;
    [ExteriaProfilePhotoPicker pickWholeFrom:self picked:^(NSString *path) {
        ExteriaWallpaperController *me = weak.target;
        BOOL used = path && ExteriaWallpaperUsePhotoAtPathForChat(path, peerKind, peerId);
        if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (!used) {
            NSLog(@"exteria: the wallpaper photo could not be prepared");
            ExteriaGiftAlert(nil, NSLocalizedString(@"chatset.wallpaper.failed", nil));
            return;
        }
        [me rebuild];
    } unavailable:^{
        ExteriaGiftAlert(nil, NSLocalizedString(@"attach.gallery.unavailable", nil));
    }];
}

@end
