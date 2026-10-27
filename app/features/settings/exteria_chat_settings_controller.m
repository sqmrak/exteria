#import "exteria_chat_settings_controller.h"

#import "exteria_chat_preview_view.h"
#import "exteria_platform.h"
#import "exteria_theme_busy_view.h"
#import "exteria_proximity.h"
#import "exteria_gift_screen.h"
#import "exteria_app_icon.h"
#import "exteria_alert.h"
#import "exteria_app_icon_list_view.h"
#import "exteria_audio_session.h"
#import "exteria_chat_settings.h"
#import "exteria_lite_mode_controller.h"
#import "exteria_night_mode.h"
#import "exteria_night_mode_controller.h"
#import "exteria_popup_menu.h"
#import "exteria_session_content.h"
#import "exteria_settings_pages.h"
#import "exteria_symbol.h"
#import "exteria_theme_list_view.h"
#import "exteria_tab_editor.h"
#import "exteria_wallpaper_controller.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaChatSettingsController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    /* the content settings of the account, which only the server knows: loaded when the screen opens, and the row of sensitive content waits for them */
    BOOL _contentLoaded;
    BOOL _canChangeContent;
    BOOL _sensitiveShown;
    ExteriaChatPreviewView *_preview;
    UIButton *_more;
}
@end

/* the duck of the theme change covers the window while the icon is written, which takes a moment and ends the app
   on the systems that restart SpringBoard; the view is kept, so its parsed animation is ready for the next change */
static ExteriaThemeBusyView *ExteriaIconBusy;
static NSTimeInterval ExteriaIconBusyShownAt;

static ExteriaThemeBusyView *ExteriaIconBusyShow(void) {
    UIView *window = ExteriaOverlayHost();
    if (!window) return nil;
    if (!ExteriaIconBusy) ExteriaIconBusy = [[ExteriaThemeBusyView alloc] initWithFrame:window.bounds];
    ExteriaIconBusy.text = NSLocalizedString(@"icon.applying", nil);
    ExteriaIconBusy.frame = window.bounds;
    ExteriaIconBusy.alpha = ExteriaReduceMotionEnabled() ? 1 : 0;
    [window addSubview:ExteriaIconBusy];
    [ExteriaIconBusy startAnimating];
    ExteriaIconBusyShownAt = [NSDate timeIntervalSinceReferenceDate];
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.22 animations:^{ ExteriaIconBusy.alpha = 1; }];
    return ExteriaIconBusy;
}

/* a change that returns at once still shows the duck for a moment, or it would flash */
static void ExteriaIconBusyHide(ExteriaThemeBusyView *busy) {
    if (!busy) return;
    NSTimeInterval left = 1.2 - ([NSDate timeIntervalSinceReferenceDate] - ExteriaIconBusyShownAt);
    [busy retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(left, 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.3 animations:^{ busy.alpha = 0; } completion:^(BOOL finished) {
            (void)finished;
            if (busy.alpha > 0) return;
            [busy stopAnimating];
            [busy removeFromSuperview];
        }];
        [busy release];
    });
}

@implementation ExteriaChatSettingsController

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.title", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_preview release];
    [_more release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildThemedViews];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(nightModeChanged) name:ExteriaNightModeDidChangeNotification object:nil];
    [self rebuild];
    [self loadContent];
}

/* the preview and the button of the menu read their colors when they are made */
- (void)buildThemedViews {
    [_preview release];
    _preview = [[ExteriaChatPreviewView alloc] init];
    ExteriaWeakReference *weak = _weak;
    _preview.heightHandler = ^{ [(ExteriaChatSettingsController *)weak.target updateRowHeights]; };
    [_more release];
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _more.frame = CGRectMake(0, 0, 44, 44);
    [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    _more.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [self refreshMenu];
}

/* the page stays up when the theme changes; its views are made again in the new colors under the circle that spreads over the screen */
- (void)themeDidChange {
    [self buildThemedViews];
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[ExteriaChatSettingsController alloc] initWithSession:_session] autorelease];
}


- (void)loadContent {
    ExteriaWeakReference *weak = _weak;
    [_session loadContentSettings:^(BOOL enabled, BOOL canChange, NSString *errorName) {
        ExteriaChatSettingsController *me = weak.target;
        if (!me) return;
        if (errorName) {
            NSLog(@"exteria: the content settings did not load: %@", errorName);
            return;
        }
        me->_contentLoaded = YES;
        me->_canChangeContent = canChange;
        me->_sensitiveShown = enabled;
        [me rebuild];
    }];
}

/* the screen shows the night setup in a row, and the page of it is pushed over this one, so the row is made again when the person comes back */
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.sections) [self rebuild];
}

- (void)nightModeChanged {
    if (self.isViewLoaded) [self rebuild];
}

#pragma mark rows

static NSString *ExteriaNightStateText(void) {
    switch (ExteriaNightConfig().mode) {
    case EXTERIA_NIGHT_SCHEDULED: return NSLocalizedString(@"chatset.night.scheduled", nil);
    case EXTERIA_NIGHT_ADAPTIVE: return NSLocalizedString(@"chatset.night.adaptive", nil);
    default: return NSLocalizedString(@"chatset.night.off", nil);
    }
}

/* the sizes move under the finger, so a change repaints the preview and leaves the rows alone */
- (void)textSizeMoved:(float)value {
    NSInteger size = (NSInteger)(value + 0.5f);
    if (size == ExteriaChatTextSize()) return;
    ExteriaChatSetTextSize(size);
    [self updateRowHeights];
    [self refreshMenu];
}

- (void)radiusMoved:(float)value {
    NSInteger radius = (NSInteger)(value + 0.5f);
    if (radius == ExteriaChatBubbleRadius()) return;
    ExteriaChatSetBubbleRadius(radius);
    [self refreshMenu];
}

- (void)rebuild {
    ExteriaWeakReference *weak = _weak;
    BOOL classic = ExteriaThemeIsClassic();
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *size = [NSMutableArray array];
    [size addObject:[ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.textsize.row", nil) format:@"%.0f" value:(float)ExteriaChatTextSize()
                                                   minimum:EXTERIA_CHAT_TEXT_SIZE_MIN maximum:EXTERIA_CHAT_TEXT_SIZE_MAX change:^(float value) {
        [(ExteriaChatSettingsController *)weak.target textSizeMoved:value];
    }]];
    if (_preview) {
        ExteriaChatPreviewView *preview = _preview;
        [size addObject:[ExteriaSettingsRow viewRowWithView:preview height:^CGFloat(CGFloat width) { return [preview heightForWidth:width]; }]];
    }
    /* the modern page has the reset in its menu; the classic one has no bar of its own to hold a menu, so the row stands under the preview */
    if (classic && ExteriaChatAppearanceChanged()) {
        ExteriaSettingsRow *reset = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolRepeat tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"chatset.reset", nil) subtitle:nil
                                                                value:nil tap:^{
            ExteriaChatResetAppearance();
            [(ExteriaChatSettingsController *)weak.target rebuild];
        }];
        [size addObject:reset];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.textsize.header", nil) footer:nil rows:size]];

    NSMutableArray *looks = [NSMutableArray array];
    [looks addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolGallery tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"chatset.wallpaper", nil) subtitle:nil
                                                 value:nil tap:^{
        ExteriaChatSettingsController *me = weak.target;
        ExteriaWallpaperController *wallpapers = [[[ExteriaWallpaperController alloc] init] autorelease];
        [me.navigationController pushViewController:wallpapers animated:YES];
    }]];
    [looks addObject:[ExteriaSettingsRow rowWithSymbol:ExteriaSymbolApps tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"tabedit.title", nil) subtitle:nil value:nil tap:^{
        ExteriaChatSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[ExteriaTabEditor alloc] init] autorelease] animated:YES];
    }]];
    if (looks.count) [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:looks]];

    NSMutableArray *themeRows = [NSMutableArray array];
    {
        ExteriaThemeListView *themes = [[[ExteriaThemeListView alloc] init] autorelease];
        ExteriaWeakReference *shownThemes = [ExteriaWeakReference referenceTo:themes];
        themes.chooseHandler = ^(BOOL toClassic, BOOL toDark) {
            [(ExteriaChatSettingsController *)weak.target applyThemeClassic:toClassic dark:toDark from:((ExteriaThemeListView *)shownThemes.target).tapPoint];
        };
        [themeRows addObject:[ExteriaSettingsRow viewRowWithView:themes height:^CGFloat(CGFloat width) { (void)width; return [ExteriaThemeListView height]; }]];
    }
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.colortheme.header", nil) footer:nil rows:themeRows]];

    {
        ExteriaSettingsRow *radius = [ExteriaSettingsRow sliderRowWithTitle:NSLocalizedString(@"chatset.corners.row", nil) format:@"%.0f" value:(float)ExteriaChatBubbleRadius()
                                                                    minimum:EXTERIA_CHAT_BUBBLE_RADIUS_MIN maximum:EXTERIA_CHAT_BUBBLE_RADIUS_MAX change:^(float value) {
            [(ExteriaChatSettingsController *)weak.target radiusMoved:value];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.corners.header", nil) footer:nil rows:[NSArray arrayWithObject:radius]]];

        ExteriaChatListStyle style = ExteriaChatListStyleStored();
        ExteriaSettingsRow *two = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"chatset.list.two", nil) subtitle:nil checked:style == ExteriaChatListTwoLines tap:^{
            [(ExteriaChatSettingsController *)weak.target chooseListStyle:ExteriaChatListTwoLines];
        }];
        ExteriaSettingsRow *three = [ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(@"chatset.list.three", nil) subtitle:nil checked:style == ExteriaChatListThreeLines tap:^{
            [(ExteriaChatSettingsController *)weak.target chooseListStyle:ExteriaChatListThreeLines];
        }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.list.header", nil) footer:nil rows:[NSArray arrayWithObjects:two, three, nil]]];
    }

    [sections addObject:[self swipeSection]];
    /* ios 10.3 has the call; older systems change the icon only through a bundle the app can write, which a jailbreak install gives, and the row says so
       where it does not */
    if (ExteriaAlternateIconNames().count > 0) {
        ExteriaAppIconListView *icons = [[[ExteriaAppIconListView alloc] init] autorelease];
        ExteriaAppIconMode mode = ExteriaAppIconCurrentMode();
        icons.enabled = mode != ExteriaAppIconUnavailable;
        /* the list holds the handler, so the handler holds the list only through a reference that does not keep it alive */
        ExteriaWeakReference *shown = [ExteriaWeakReference referenceTo:icons];
        icons.chooseHandler = ^(NSString *name) {
            /* before ios 10.3 the change ends with SpringBoard starting again, which takes the app with it */
            void (^change)(void) = ^{
                /* a rebuild of the page lets the list go while the change is running, so the change keeps the list until it ends */
                ExteriaAppIconListView *list = [(ExteriaAppIconListView *)shown.target retain];
                list.enabled = NO;
                ExteriaThemeBusyView *busy = ExteriaIconBusyShow();
                ExteriaSetAlternateIcon(name, ^(NSError *error) {
                    ExteriaIconBusyHide(busy);
                    list.enabled = YES;
                    [list refreshSelection];
                    if (!error) { [list release]; return; }
                    NSLog(@"exteria: the app icon was not changed: %@", error);
                    NSString *detail = [NSString stringWithFormat:@"%@\n\n%@ (%@ %ld)", NSLocalizedString(@"chatset.appicon.failed", nil), error.localizedDescription, error.domain, (long)error.code];
                    if (mode == ExteriaAppIconNative && ExteriaAppIconCanRewrite()) {
                        NSString *question = [detail stringByAppendingFormat:@"\n\n%@", NSLocalizedString(@"chatset.appicon.restart.message", nil)];
                        ExteriaConfirm(nil, question, NSLocalizedString(@"chatset.appicon.restart.action", nil), ^{
                            ExteriaAppIconListView *fallbackList = [list retain];
                            fallbackList.enabled = NO;
                            ExteriaThemeBusyView *fallbackBusy = ExteriaIconBusyShow();
                            ExteriaRewriteAppIcon(name, ^(NSError *rewriteError) {
                                ExteriaIconBusyHide(fallbackBusy);
                                fallbackList.enabled = YES;
                                [fallbackList refreshSelection];
                                [fallbackList release];
                                if (rewriteError) ExteriaGiftAlert(nil, rewriteError.localizedDescription);
                            });
                        });
                    } else {
                        ExteriaGiftAlert(nil, detail);
                    }
                    [list release];
                });
            };
            if (ExteriaAppIconCurrentMode() == ExteriaAppIconRewrite) {
                ExteriaConfirm(nil, NSLocalizedString(@"chatset.appicon.restart.message", nil), NSLocalizedString(@"chatset.appicon.restart.action", nil), change);
            } else {
                change();
            }
        };
        NSString *footer = mode == ExteriaAppIconUnavailable ? NSLocalizedString(@"chatset.appicon.jailbreak", nil) : nil;
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.appicon", nil) footer:footer rows:[NSArray arrayWithObject:
            [ExteriaSettingsRow viewRowWithView:icons height:^CGFloat(CGFloat width) { (void)width; return [ExteriaAppIconListView height]; }]]]];
    }

    ExteriaSettingsRow *night = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolMoon tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"chatset.night", nil)
                                                         subtitle:ExteriaNightStateText() value:nil tap:^{
        [[(ExteriaChatSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaNightModeController alloc] init] autorelease] animated:YES];
    }];
    ExteriaSettingsRow *animations = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsPower tone:ExteriaSettingsToneOrangeDeep title:NSLocalizedString(@"chatset.animations", nil)
                                                              subtitle:NSLocalizedString(@"chatset.animations.info", nil) value:nil tap:^{
        [[(ExteriaChatSettingsController *)weak.target navigationController] pushViewController:[[[ExteriaLiteModeSettingsController alloc] init] autorelease] animated:YES];
    }];
    [sections addObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObjects:night, animations, nil]]];
    [sections addObject:[self mediaSection]];
    [sections addObject:[self otherSection]];

    self.sections = sections;
    [self reloadSettings];
    [self refreshMenu];
}

#pragma mark sections



/* what a swipe to the left on a chat does: the archive until another is chosen */
- (ExteriaSettingsSection *)swipeSection {
    ExteriaWeakReference *weak = _weak;
    ExteriaChatSwipe current = ExteriaChatSwipeStored();
    static NSString *const keys[] = {@"chatset.swipe.archive", @"chatset.swipe.pin", @"chatset.swipe.read", @"chatset.swipe.mute", @"chatset.swipe.delete"};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        [rows addObject:[ExteriaSettingsRow checkRowWithTitle:NSLocalizedString(keys[i], nil) subtitle:nil checked:(NSUInteger)current == i tap:^{
            ExteriaChatSetSwipe((ExteriaChatSwipe)i);
            [(ExteriaChatSettingsController *)weak.target rebuild];
        }]];
    }
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.swipe.header", nil) footer:NSLocalizedString(@"chatset.swipe.info", nil) rows:rows];
}

/* media and sound; the ear features only exist where there is a sensor to hear the ear with, "raise to speak"
   waits for "raise to listen" as in the original */
- (ExteriaSettingsSection *)mediaSection {
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.nexttap", nil) subtitle:NSLocalizedString(@"chatset.nexttap.info", nil)
                                                        on:ExteriaChatNextMediaTap() toggle:^(BOOL on) { ExteriaChatSetNextMediaTap(on); }]];
    if (ExteriaProximityAvailable()) {
        ExteriaWeakReference *weak = _weak;
        [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.raiselisten", nil) subtitle:NSLocalizedString(@"chatset.raiselisten.info", nil)
                                                            on:ExteriaChatRaiseToListen() toggle:^(BOOL on) {
            ExteriaChatSetRaiseToListen(on);
            [(ExteriaChatSettingsController *)weak.target rebuild];
        }]];
        if (ExteriaChatRaiseToListen()) {
            [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.raisespeak", nil) subtitle:NSLocalizedString(@"chatset.raisespeak.info", nil)
                                                                on:ExteriaChatRaiseToSpeak() toggle:^(BOOL on) { ExteriaChatSetRaiseToSpeak(on); }]];
        }
    }
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.pauserecord", nil) subtitle:NSLocalizedString(@"chatset.pauserecord.info", nil)
                                                        on:ExteriaChatPauseMusicOnRecord() toggle:^(BOOL on) { ExteriaChatSetPauseMusicOnRecord(on); }]];
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.pausemedia", nil) subtitle:nil
                                                        on:ExteriaChatPauseMusicOnMedia() toggle:^(BOOL on) { ExteriaChatSetPauseMusicOnMedia(on); }]];
    if (ExteriaAudioSessionCanUseBluetoothMicrophone()) {
        ExteriaWeakReference *weak = _weak;
        BOOL bluetooth = ExteriaChatRecordViaBluetooth();
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chatset.mic", nil) value:NSLocalizedString(bluetooth ? @"chatset.mic.bluetooth" : @"chatset.mic.builtin", nil) tap:^{
            ExteriaChatSettingsController *me = weak.target;
            if (!me) return;
            NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"chatset.mic.builtin", nil), NSLocalizedString(@"chatset.mic.bluetooth", nil), nil];
            ExteriaSettingsChoose(me, NSLocalizedString(@"chatset.mic", nil), options, ^(NSUInteger index) {
                ExteriaChatSetRecordViaBluetooth(index == 1);
                [(ExteriaChatSettingsController *)weak.target rebuild];
            });
        }]];
    }
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.media.header", nil) footer:nil rows:rows];
}







/* other settings; "show 18+ materials" is the account's own setting on the server and is offered only when the
   server says this account may change it; Direct Share and the distance units are Android's share sheet and a map
   the app does not have */
- (ExteriaSettingsSection *)otherSection {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *rows = [NSMutableArray array];
    if (_contentLoaded && _canChangeContent) {
        [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.sensitive", nil) subtitle:NSLocalizedString(@"chatset.sensitive.info", nil)
                                                            on:_sensitiveShown toggle:^(BOOL on) {
            [(ExteriaChatSettingsController *)weak.target setSensitive:on];
        }]];
    }
    [rows addObject:[ExteriaSettingsRow switchRowWithTitle:NSLocalizedString(@"chatset.sendenter", nil) subtitle:nil on:ExteriaChatSendByEnter() toggle:^(BOOL on) {
        ExteriaChatSetSendByEnter(on);
    }]];
    return [ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"chatset.other.header", nil) footer:nil rows:rows];
}

- (void)setSensitive:(BOOL)on {
    ExteriaWeakReference *weak = _weak;
    _sensitiveShown = on;
    [_session setSensitiveContent:on completion:^(NSString *errorName) {
        ExteriaChatSettingsController *me = weak.target;
        if (!me || !errorName) return;
        /* the server refused, so the switch goes back to what it has */
        NSLog(@"exteria: the sensitive content setting was refused: %@", errorName);
        me->_sensitiveShown = !on;
        ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        [me rebuild];
    }];
}

#pragma mark actions


/* the colors spread from the point that was touched */
- (void)applyThemeClassic:(BOOL)classic dark:(BOOL)dark from:(CGPoint)origin {
    ExteriaThemeStoreClassic(classic);
    ExteriaThemeStoreDark(dark);
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:origin] forKey:ExteriaThemeOriginKey]];
}

- (void)chooseListStyle:(ExteriaChatListStyle)style {
    if (style == ExteriaChatListStyleStored()) return;
    ExteriaChatSetListStyle(style);
    [self rebuild];
}

/* the menu of the screen has one entry, which puts the size and the corners back, and it only exists while they differ from the defaults */
- (void)refreshMenu {
    /* the classic page has no bar of its own to hold the button, and the button would sit in the corner of the screen */
    if (ExteriaThemeIsClassic()) return;
    self.barViews = ExteriaChatAppearanceChanged() ? [NSArray arrayWithObject:_more] : [NSArray array];
}

- (void)showMenu {
    ExteriaWeakReference *weak = _weak;
    ExteriaSymbol symbols[] = {ExteriaSymbolRepeat};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"chatset.reset", nil)] symbols:symbols
                                                               handler:^(NSUInteger index) {
        (void)index;
        ExteriaChatSettingsController *me = weak.target;
        if (!me) return;
        ExteriaChatResetAppearance();
        [me rebuild];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_more.frame) - 6, CGRectGetMaxY(_more.frame) - 8)];
}

@end
