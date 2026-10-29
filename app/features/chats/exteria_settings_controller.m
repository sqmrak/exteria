#import "exteria_developers.h"
#import "exteria_folders_controller.h"
#import "exteria_settings_controller.h"
#import "exteria_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_avatar_view.h"
#import "exteria_avatar_viewer.h"
#import "exteria_chat_settings.h"
#import "exteria_chat_settings_controller.h"
#import "exteria_about_controller.h"
#import "exteria_update_controller.h"
#import "exteria_account_controller.h"
#import "exteria_data_settings_controller.h"
#import "exteria_stickers_settings_controller.h"
#import "exteria_passcode_settings_controller.h"
#import "exteria_passcode_store.h"
#import "exteria_privacy_controller.h"
#import "exteria_classic_devices_controller.h"
#import "exteria_devices_controller.h"
#import "exteria_dialog.h"
#import "exteria_emoji_label.h"
#import "exteria_language.h"
#import "exteria_language_controller.h"
#import "exteria_lite_mode.h"
#import "exteria_lite_mode_controller.h"
#import "exteria_notifications_settings_controller.h"
#import "exteria_person.h"
#import "exteria_popup_menu.h"
#import "exteria_profile_identity_view.h"
#import "exteria_platform.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_session_profile.h"
#import "exteria_settings_pages.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_translator_controller.h"
#import "exteria_weak_reference.h"

/* the identity block starts 58 points under the top, like the one of the profile screen, and the table starts
   under the status bar so that it scrolls up behind the bar list does */
#define HEADER_HEIGHT (EXTERIA_IDENTITY_BAR + EXTERIA_IDENTITY_TOP + EXTERIA_IDENTITY_HEIGHT + 24)
/* the classic style puts the table under the system navigation bar, so the block needs no room for a bar of ours; the grouped table
   adds a gap of its own above the first section, so the room under the @name is smaller than the 24 points of the modern one */
#define CLASSIC_HEADER_HEIGHT (EXTERIA_IDENTITY_TOP + EXTERIA_IDENTITY_HEIGHT + 8)
/* the title comes in once the header has gone up under the bar, over 420 ms */
#define TITLE_FADE_SECONDS 0.42
static NSString *const ExteriaDevicesCountKey = @"exteria.devices.count";

/* the table header: the shared identity block, below the room the bar takes */
@interface ExteriaSettingsHeaderView : UIView {
    ExteriaProfileIdentityView *_identity;
    CGFloat _identityTop;
}
@property (nonatomic, readonly) ExteriaProfileIdentityView *identity;
- (id)initWithFrame:(CGRect)frame identityTop:(CGFloat)identityTop;
@end

@implementation ExteriaSettingsHeaderView

@synthesize identity = _identity;

- (id)initWithFrame:(CGRect)frame identityTop:(CGFloat)identityTop {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _identityTop = identityTop;
    _identity = [[ExteriaProfileIdentityView alloc] init];
    [self addSubview:_identity];
    return self;
}

- (void)dealloc {
    [_identity release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _identity.frame = CGRectMake(0, _identityTop, self.bounds.size.width, EXTERIA_IDENTITY_HEIGHT);
}

@end

@interface ExteriaSettingsController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWeakReference *_weak;
    ExteriaSettingsHeaderView *_header;
    ExteriaPerson *_person;
    BOOL _uploading;
    BOOL _barFilled;
    BOOL _signingOut;
    UIButton *_more;
    void (^_signOutHandler)(void (^)(NSString *));
}
@end

@implementation ExteriaSettingsController

@synthesize signOutHandler = _signOutHandler;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.showsBack = NO;
    self.contentUnderBar = YES;
    self.pageTitle = NSLocalizedString(@"tab.settings", nil);
    self.barFill = 0;
    self.searchable = YES;
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_header release];
    [_person release];
    [_more release];
    [_signOutHandler release];
    [super dealloc];
}

#pragma mark header

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL classic = ExteriaThemeIsClassic();
    _header = [[ExteriaSettingsHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, classic ? CLASSIC_HEADER_HEIGHT : HEADER_HEIGHT)
                                                   identityTop:classic ? EXTERIA_IDENTITY_TOP : EXTERIA_IDENTITY_BAR + EXTERIA_IDENTITY_TOP];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    /* the grouped table of the light classic style keeps the system's own background, which the modern ring color is not */
    if (classic && !ExteriaThemeIsDark()) [_header.identity setBadgeRingColor:[UIColor clearColor]];
    [_header.identity.avatarHit addTarget:self action:@selector(openPhotos) forControlEvents:UIControlEventTouchUpInside];
    [_header.identity.badge addTarget:self action:@selector(changePhoto) forControlEvents:UIControlEventTouchUpInside];
    self.headerView = _header;
    if (classic) {
        /* the same one-row menu as the dots of the modern bar, on the system bar, and the magnifier of its search
           in the corner at the left; the bars of this style are dark, so the pictures are drawn white */
        UIBarButtonItem *dots = [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 22, [UIColor whiteColor])
                                                                  style:UIBarButtonItemStyleBordered target:self action:@selector(showMenu)] autorelease];
        dots.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
        UIBarButtonItem *search = [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 22, [UIColor whiteColor])
                                                                    style:UIBarButtonItemStyleBordered target:self action:@selector(focusSearch)] autorelease];
        search.accessibilityLabel = NSLocalizedString(@"settings.search", nil);
        /* the magnifier takes the corner on the left, and the dots stay alone on the right */
        self.navigationItem.leftBarButtonItem = search;
        self.navigationItem.rightBarButtonItem = dots;
    } else {
        _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _more.frame = CGRectMake(0, 0, 44, 44);
        [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
        _more.accessibilityLabel = NSLocalizedString(@"settings.more", nil);
        [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        self.barViews = [NSArray arrayWithObject:_more];
    }
    [self rebuildRows];
    [self loadPerson];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildRows];
    [self loadPerson];
}

- (void)loadPerson {
    /* the profile of the last time draws at once, and the answer corrects it */
    ExteriaPerson *known = _person ? nil : [_session ownPerson];
    if (known) {
        _person = [known retain];
        [self showPerson];
    }
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaSettingsController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"exteria: the profile of the settings did not load: %@", errorName);
            return;
        }
        [me->_person release];
        me->_person = [[items objectAtIndex:0] retain];
        [me->_avatars pinPhoto:me->_person.photo];
        ExteriaLiteSetPremium(ExteriaPremiumEffective(me->_person.premium));
        [me showPerson];
    }];
}

- (void)showPerson {
    ExteriaProfileIdentityView *identity = _header.identity;
    [identity setName:_person.name developer:ExteriaPersonIsDeveloper(_person)];
    identity.line.text = _person.username.length ? [@"@" stringByAppendingString:_person.username] : ExteriaOwnPhoneText(_person.phone);
    identity.avatar.initials = _person.initials;
    identity.avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [identity.avatar setPhoto:_person.photo cache:_avatars];
}

- (void)openPhotos {
    if (!_person) return;
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person] avatars:_avatars
                                                                          media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)changePhoto {
    if (_uploading) return;
    ExteriaWeakReference *weak = _weak;
    [ExteriaProfilePhotoPicker pickFrom:self picked:^(NSString *path) {
        ExteriaSettingsController *me = weak.target;
        if (!path) return;
        if (!me) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        me->_uploading = YES;
        [me->_header.identity setUploading:YES];
        [me->_session uploadProfilePhotoAtPath:path completion:^(NSString *errorName) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            ExteriaSettingsController *again = weak.target;
            if (!again) return;
            again->_uploading = NO;
            [again->_header.identity setUploading:NO];
            if (errorName) {
                NSLog(@"exteria: the profile photo was not set: %@", errorName);
                return;
            }
            [again loadPerson];
        }];
    } unavailable:^{
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"attach.gallery.unavailable", nil) delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }];
}

#pragma mark rows

- (void)push:(UIViewController *)page {
    [self.navigationController pushViewController:page animated:YES];
}

/* the sessions list has rows with a picture and three lines, which only the classic screen of its own draws in a grouped table */
- (void)openDevices {
    [self push:ExteriaThemeIsClassic() ? (UIViewController *)[[[ExteriaClassicDevicesController alloc] initWithSession:_session media:_media] autorelease]
                                       : (UIViewController *)[[[ExteriaDevicesController alloc] initWithSession:_session media:_media] autorelease]];
}

- (void)rebuildRows {
    ExteriaWeakReference *weak = _weak;
    /* the classic cell draws a tile at 29 points, the modern row at 36 */
    UIImage *logo = ExteriaSettingsMarkTile(ExteriaThemeIsClassic() ? 29 : 36);
    ExteriaSettingsRow *look = [ExteriaSettingsRow rowWithTileImage:logo title:NSLocalizedString(@"settings.exteria", nil)
                                                           subtitle:NSLocalizedString(@"settings.exteria.info", nil)
                                                                tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaAboutController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session avatars:((ExteriaSettingsController *)weak.target)->_avatars] autorelease]]; }];
    ExteriaSettingsRow *account = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsAccount tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"account.title", nil)
                                                           subtitle:NSLocalizedString(@"account.title.info", nil) value:nil tap:^{
        ExteriaSettingsController *me = weak.target;
        if (!me) return;
        ExteriaAccountController *page = [[[ExteriaAccountController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease];
        page.changedHandler = ^{ [(ExteriaSettingsController *)weak.target loadPerson]; };
        page.logoutHandler = ^{ [(ExteriaSettingsController *)weak.target confirmSignOut]; };
        [me push:page];
    }];
    ExteriaSettingsRow *chats = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsChat tone:ExteriaSettingsToneOrange title:NSLocalizedString(@"settings.chats", nil)
                                                         subtitle:NSLocalizedString(@"settings.chats.info", nil) value:nil
                                                              tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaChatSettingsController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session] autorelease]]; }];
    ExteriaSettingsRow *stickers = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSticker tone:ExteriaSettingsToneOrangeBright title:NSLocalizedString(@"chatset.stickers", nil)
                                                            subtitle:NSLocalizedString(@"chatset.stickers.info2", nil) value:nil tap:^{
        ExteriaSettingsController *me = weak.target;
        if (me) [me push:[[[ExteriaStickersSettingsController alloc] initWithSession:me->_session media:me->_media] autorelease]];
    }];
    ExteriaSettingsRow *folders = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsFolders tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"folders.title", nil) subtitle:NSLocalizedString(@"folders.title.info", nil) value:nil tap:^{
        ExteriaSettingsController *me = weak.target;
        if (me) [me push:[[[ExteriaFoldersController alloc] initWithSession:me->_session] autorelease]];
    }];
    ExteriaSettingsRow *notifications = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsSounds tone:ExteriaSettingsToneRed
                                                                    title:NSLocalizedString(@"settings.notifications", nil) subtitle:NSLocalizedString(@"settings.notifications.info", nil)
                                                                    value:nil tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaNotificationsSettingsController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session avatars:((ExteriaSettingsController *)weak.target)->_avatars media:((ExteriaSettingsController *)weak.target)->_media] autorelease]]; }];
    ExteriaSettingsRow *privacy = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsPrivacy tone:ExteriaSettingsToneGreen title:NSLocalizedString(@"privacy.title", nil)
                                                           subtitle:NSLocalizedString(@"privacy.title.info", nil) value:nil tap:^{
        ExteriaSettingsController *me = weak.target;
        if (me) [me push:[[[ExteriaPrivacyController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    }];
    ExteriaSettingsRow *passcode = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolLock tone:ExteriaSettingsToneGray title:NSLocalizedString(@"passcode.title", nil)
                                                            subtitle:nil value:NSLocalizedString(ExteriaPasscodeEnabled() ? @"passcode.on" : @"passcode.off", nil) tap:^{
        ExteriaSettingsController *me = weak.target;
        if (!me) return;
        [ExteriaPasscodeSettingsController openFrom:me push:^(UIViewController *page) { [(ExteriaSettingsController *)weak.target push:page]; }];
    }];
    ExteriaSettingsRow *data = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsData tone:ExteriaSettingsToneBlueDeep title:NSLocalizedString(@"settings.data", nil)
                                                        subtitle:NSLocalizedString(@"settings.data.info", nil) value:nil tap:^{
        ExteriaSettingsController *me = weak.target;
        [me push:[[[ExteriaDataSettingsController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    }];
    /* the number of sessions the last visit to the devices screen saw stands at the right of the row the count it
       last knew */
    NSInteger known = [[NSUserDefaults standardUserDefaults] integerForKey:ExteriaDevicesCountKey];
    ExteriaSettingsRow *devices = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsDevices tone:ExteriaSettingsToneCyan title:NSLocalizedString(@"settings.devices", nil)
                                                           subtitle:NSLocalizedString(@"settings.devices.info", nil)
                                                              value:known > 0 ? [NSString stringWithFormat:@"%ld", (long)known] : nil tap:^{
        [(ExteriaSettingsController *)weak.target openDevices];
    }];
    ExteriaSettingsRow *power = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsPower tone:ExteriaSettingsToneOrangeDeep title:NSLocalizedString(@"settings.power", nil)
                                                         subtitle:NSLocalizedString(@"settings.power.info", nil) value:nil
                                                              tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaLiteModeSettingsController alloc] init] autorelease]]; }];
    ExteriaSettingsRow *language = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolSettingsLanguage tone:ExteriaSettingsTonePurple title:NSLocalizedString(@"language.title", nil)
                                                            subtitle:nil value:ExteriaNativeLanguageName(ExteriaInterfaceLanguageVariant())
                                                                 tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaLanguageSettingsController alloc] init] autorelease]]; }];
    ExteriaSettingsRow *update = [ExteriaSettingsRow rowWithSymbol:ExteriaSymbolArrowDown tone:ExteriaSettingsToneBlue title:NSLocalizedString(@"update.page.title", nil)
                                                         subtitle:nil value:nil tap:^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaUpdateController alloc] init] autorelease]]; }];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
#if defined(__arm64__)
    NSString *architecture = @"arm64";
#else
    NSString *architecture = @"armv7";
#endif
    NSString *version = [NSString stringWithFormat:NSLocalizedString(@"settings.version.line", nil), [info objectForKey:@"CFBundleShortVersionString"], architecture];
    version = [version stringByAppendingString:@"\nuse senko by sqmrak btw"];
    ExteriaSettingsSection *list = [ExteriaSettingsSection sectionWithHeader:nil footer:version rows:[NSArray arrayWithObjects:account, chats, stickers, privacy, passcode, notifications, data, folders, devices, power, update, language, nil]];
    list.centerFooter = YES;
    self.sections = [NSArray arrayWithObjects:
        [ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:look]], list, nil];
}

#pragma mark scrolling

/* the title stands in the bar all the time */
- (void)updateBarFill {
    if (ExteriaThemeIsClassic()) return;
    CGFloat offset = self.table.contentOffset.y;
    BOOL filled = HEADER_HEIGHT - offset < 56 + [self statusInset];
    if (filled == _barFilled) return;
    _barFilled = filled;
    [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : TITLE_FADE_SECONDS delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.barFill = filled ? 1 : 0; } completion:nil];
}

- (CGFloat)statusInset {
    return ExteriaLayoutInsets(self).top;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    (void)scrollView;
    [self updateBarFill];
}

#pragma mark menu

/* the dots in the bar open a card with one row do */
- (void)showMenu {
    ExteriaWeakReference *weak = _weak;
    if (ExteriaThemeIsClassic()) {
        ExteriaSettingsChoose(self, nil, [NSArray arrayWithObject:NSLocalizedString(@"settings.signout", nil)], ^(NSUInteger index) {
            (void)index;
            [(ExteriaSettingsController *)weak.target confirmSignOut];
        });
        return;
    }
    ExteriaSymbol symbols[] = {ExteriaSymbolLogout};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"settings.signout", nil)] symbols:symbols
                                                               handler:^(NSUInteger index) {
        (void)index;
        [(ExteriaSettingsController *)weak.target confirmSignOut];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_more.frame) - 6, CGRectGetMaxY(_more.frame) - 8)];
}

- (void)confirmSignOut {
    if (_signingOut) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"settings.signout.confirm", nil), NSLocalizedString(@"settings.signout", nil),
                         ^{ [(ExteriaSettingsController *)weak.target signOutNow]; });
}

- (void)signOutNow {
    if (!_signOutHandler || _signingOut) return;
    _signingOut = YES;
    ExteriaWeakReference *weak = _weak;
    _signOutHandler(^(NSString *errorName) {
        ExteriaSettingsController *me = weak.target;
        if (me) me->_signingOut = NO;
        if (!errorName) return;
        NSLog(@"exteria: the sign out failed: %@", errorName);
        ExteriaShowNotice(nil, [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
    });
}

#pragma mark search

/* a result row: the name of the setting, the way to it under that, and what a tap does */
- (ExteriaSettingsRow *)resultWithTitle:(NSString *)title path:(NSArray *)path symbol:(ExteriaSymbol)symbol tone:(ExteriaSettingsTone)tone tap:(void (^)(void))tap {
    return [ExteriaSettingsRow rowWithSymbol:symbol tone:tone title:title subtitle:path.count ? [path componentsJoinedByString:@" › "] : nil value:nil tap:tap];
}

- (NSArray *)searchEntries {
    ExteriaWeakReference *weak = _weak;
    void (^openLook)(void) = ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaAppearanceSettingsController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session] autorelease]]; };
    void (^openNotifications)(void) = ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaNotificationsSettingsController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session avatars:((ExteriaSettingsController *)weak.target)->_avatars media:((ExteriaSettingsController *)weak.target)->_media] autorelease]]; };
    void (^openChats)(void) = ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaChatSettingsController alloc] initWithSession:((ExteriaSettingsController *)weak.target)->_session] autorelease]]; };
    void (^openStickers)(void) = ^{
        ExteriaSettingsController *me = weak.target;
        if (me) [me push:[[[ExteriaStickersSettingsController alloc] initWithSession:me->_session media:me->_media] autorelease]];
    };
    void (^openData)(void) = ^{
        ExteriaSettingsController *me = weak.target;
        [me push:[[[ExteriaDataSettingsController alloc] initWithSession:me->_session avatars:me->_avatars media:me->_media] autorelease]];
    };
    void (^openDevices)(void) = ^{ [(ExteriaSettingsController *)weak.target openDevices]; };
    void (^openPower)(void) = ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaLiteModeSettingsController alloc] init] autorelease]]; };
    void (^openLanguage)(void) = ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaLanguageSettingsController alloc] init] autorelease]]; };
    void (^openTranslator)(void) = ^{
        ExteriaSettingsController *me = weak.target;
        [me.navigationController pushViewController:[[[ExteriaLanguageSettingsController alloc] init] autorelease] animated:NO];
        [me push:[[[ExteriaTranslatorSettingsController alloc] init] autorelease]];
    };
    NSString *look = NSLocalizedString(@"settings.exteria", nil), *notify = NSLocalizedString(@"settings.notifications", nil);
    NSString *data = NSLocalizedString(@"settings.data", nil), *language = NSLocalizedString(@"language.title", nil), *translator = NSLocalizedString(@"tr.title", nil);
    NSMutableArray *entries = [NSMutableArray array];
    ExteriaSettingsTone blue = ExteriaSettingsToneBlue;
#define ENTRY(t_, p_, s_, k_, a_) [entries addObject:[self resultWithTitle:t_ path:p_ symbol:s_ tone:k_ tap:a_]]
    ENTRY(look, nil, ExteriaSymbolGear, blue, openLook);
    NSString *lookKeys[] = {@"look.layout.header", @"look.avatar.corners", @"look.stories", @"look.hidesearch", @"look.title", @"look.senderavatars", @"look.snow", @"look.foxes", @"look.folders.header", @"look.cards.radius"};
    for (size_t i = 0; i < sizeof(lookKeys) / sizeof(lookKeys[0]); ++i) ENTRY(NSLocalizedString(lookKeys[i], nil), [NSArray arrayWithObject:look], ExteriaSymbolGear, blue, openLook);
    NSString *chats = NSLocalizedString(@"settings.chats", nil);
    ENTRY(chats, nil, ExteriaSymbolSettingsChat, ExteriaSettingsToneOrange, openChats);
    NSString *chatKeys[] = {@"chatset.textsize.header", @"chatset.colortheme.header", @"chatset.corners.header", @"chatset.list.header", @"chatset.night", @"chatset.animations",
                            @"chatset.sendenter"};
    for (size_t i = 0; i < sizeof(chatKeys) / sizeof(chatKeys[0]); ++i) ENTRY(NSLocalizedString(chatKeys[i], nil), [NSArray arrayWithObject:chats], ExteriaSymbolSettingsChat, ExteriaSettingsToneOrange, openChats);
    NSString *stickers = NSLocalizedString(@"chatset.stickers", nil);
    ENTRY(stickers, nil, ExteriaSymbolSticker, ExteriaSettingsToneOrangeBright, openStickers);
    NSString *stickerKeys[] = {@"stickers.featured", @"stickers.archived", @"stickers.emoji", @"chatset.largeemoji", @"chatset.dynamicorder"};
    for (size_t i = 0; i < sizeof(stickerKeys) / sizeof(stickerKeys[0]); ++i) ENTRY(NSLocalizedString(stickerKeys[i], nil), [NSArray arrayWithObject:stickers], ExteriaSymbolSticker, ExteriaSettingsToneOrangeBright, openStickers);
    ENTRY(notify, nil, ExteriaSymbolSettingsSounds, ExteriaSettingsToneRed, openNotifications);
    NSString *notifyKeys[] = {@"notif.private", @"notif.groups", @"notif.channels", @"notif.stories", @"notif.reactions", @"notif.vibrate", @"notif.badge.header", @"notif.inapp.sounds",
                              @"notif.inapp.vibrate", @"notif.inapp.preview", @"notif.inchat", @"notif.contactjoined", @"notif.pinned", @"notif.repeat", @"notif.reset",
                              @"notif.exceptions.title"};
    for (size_t i = 0; i < sizeof(notifyKeys) / sizeof(notifyKeys[0]); ++i) {
        ENTRY(NSLocalizedString(notifyKeys[i], nil), [NSArray arrayWithObject:notify], ExteriaSymbolSettingsSounds, ExteriaSettingsToneRed, openNotifications);
    }
    ENTRY(data, nil, ExteriaSymbolSettingsData, ExteriaSettingsToneBlueDeep, openData);
    NSString *dataKeys[] = {@"memory.title", @"netusage.title", @"data.drafts", @"memory.keep"};
    for (size_t i = 0; i < sizeof(dataKeys) / sizeof(dataKeys[0]); ++i) ENTRY(NSLocalizedString(dataKeys[i], nil), [NSArray arrayWithObject:data], ExteriaSymbolSettingsData, ExteriaSettingsToneBlueDeep, openData);
    ENTRY(NSLocalizedString(@"settings.devices", nil), nil, ExteriaSymbolSettingsDevices, ExteriaSettingsToneCyan, openDevices);
    NSString *power = NSLocalizedString(@"lite.title", nil);
    ENTRY(NSLocalizedString(@"settings.power", nil), nil, ExteriaSymbolSettingsPower, ExteriaSettingsToneOrangeDeep, openPower);
    NSString *lite[] = {@"lite.battery.title", @"lite.options", @"lite.stickers", @"lite.emoji", @"lite.background", @"lite.calls", @"lite.smooth", @"lite.class"};
    for (size_t i = 0; i < sizeof(lite) / sizeof(lite[0]); ++i) ENTRY(NSLocalizedString(lite[i], nil), [NSArray arrayWithObject:power], ExteriaSymbolSettingsPower, ExteriaSettingsToneOrangeDeep, openPower);
    ENTRY(NSLocalizedString(@"update.page.title", nil), nil, ExteriaSymbolArrowDown, blue, ^{ [(ExteriaSettingsController *)weak.target push:[[[ExteriaUpdateController alloc] init] autorelease]]; });
    ENTRY(language, nil, ExteriaSymbolSettingsLanguage, ExteriaSettingsTonePurple, openLanguage);
    ENTRY(translator, [NSArray arrayWithObject:language], ExteriaSymbolTranslate, ExteriaSettingsTonePurple, openTranslator);
    NSArray *translatorPath = [NSArray arrayWithObjects:language, translator, nil];
    NSString *keys[] = {@"tr.show", @"tr.provider", @"tr.original", @"tr.target", @"tr.skip", @"tr.preferred", @"tr.google.key", @"tr.deepl.key", @"tr.ai", @"tr.llm.preset",
                        @"tr.llm.model", @"tr.llm.key", @"tr.llm.url", @"tr.llm.system", @"tr.llm.user", @"tr.llm.context", @"tr.llm.temperature", @"tr.google.new", @"tr.keep"};
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) ENTRY(NSLocalizedString(keys[i], nil), translatorPath, ExteriaSymbolTranslate, ExteriaSettingsTonePurple, openTranslator);
    ENTRY(NSLocalizedString(@"settings.signout", nil), nil, ExteriaSymbolLogout, ExteriaSettingsToneRed, ^{ [(ExteriaSettingsController *)weak.target confirmSignOut]; });
#undef ENTRY
    return entries;
}

/* every word of the name is tried tries them: the query has to open one of them */
- (NSArray *)sectionsForSearchQuery:(NSString *)query {
    if (!query.length) return nil;
    NSString *wanted = [query lowercaseString];
    NSMutableArray *hits = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (ExteriaSettingsRow *row in [self searchEntries]) {
        NSString *key = [NSString stringWithFormat:@"%@/%@", row.title, row.subtitle];
        if ([seen containsObject:key]) continue;
        BOOL match = NO;
        for (NSString *word in [[row.title lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if ([word hasPrefix:wanted]) { match = YES; break; }
        }
        if (!match && [[row.title lowercaseString] hasPrefix:wanted]) match = YES;
        if (!match) continue;
        [seen addObject:key];
        [hits addObject:row];
    }
    return hits.count ? [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:hits]] : [NSArray array];
}

@end
