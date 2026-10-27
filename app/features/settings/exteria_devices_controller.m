#import "exteria_devices_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_device_sheet.h"
#import "exteria_image_decoder.h"
#import "exteria_lottie_view.h"
#import "exteria_plural.h"
#import "exteria_qr_scan_controller.h"
#import "exteria_session_devices.h"
#import "exteria_sheet.h"
#import "exteria_string_drawing.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define HEADER_INSET 12.0
#define STICKER_SIDE 130.0
#define RELOAD_PAUSE 2.5
#define RELOAD_ROUNDS 3
#define BUTTON_HEIGHT 48.0

#pragma mark link text

/* text with links, drawn by the text layout and opened by a tap on a link; the asterisks of a string mark them
   strings */
@interface ExteriaDevicesLinkText : UIView {
    ExteriaTextLayout *_layout;
    NSString *_text;
    NSArray *_entities;
}
- (void)setMarkedText:(NSString *)marked urls:(NSArray *)urls width:(CGFloat)width;
@property (nonatomic, readonly) CGSize textSize;
@end

@implementation ExteriaDevicesLinkText

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease]];
    return self;
}

- (void)dealloc {
    [_layout release];
    [_text release];
    [_entities release];
    [super dealloc];
}

- (void)setMarkedText:(NSString *)marked urls:(NSArray *)urls width:(CGFloat)width {
    NSMutableString *plain = [NSMutableString string];
    NSMutableArray *entities = [NSMutableArray array];
    NSArray *parts = [marked componentsSeparatedByString:@"*"];
    for (NSUInteger i = 0; i < parts.count; ++i) {
        NSString *part = [parts objectAtIndex:i];
        /* every odd part sits between a pair of asterisks, and is the text of the next address */
        if (i % 2 == 1 && (i / 2) < urls.count) {
            NSRange range = NSMakeRange(plain.length, part.length);
            [entities addObject:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleLink range:range url:[urls objectAtIndex:i / 2]] autorelease]];
        }
        [plain appendString:part];
    }
    [_text release];
    _text = [plain copy];
    [_entities release];
    _entities = [entities copy];
    [_layout release];
    _layout = [[ExteriaTextLayout layoutForText:_text entities:_entities font:ExteriaFontRegular(15) color:ExteriaColorTitle() linkColor:ExteriaColorAccent()
                                           width:width maxLines:0 flush:0.5] retain];
    [self setNeedsDisplay];
}

- (CGSize)textSize { return _layout.size; }

- (void)drawRect:(CGRect)rect {
    (void)rect;
    [_layout drawAtPoint:CGPointZero];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    NSString *url = [_layout linkAtPoint:[tap locationInView:self]];
    if (url.length && ![[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]]) NSLog(@"exteria: the system would not open %@", url);
}

@end

#pragma mark controller

@interface ExteriaDevicesController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    NSArray *_devices;
    int32_t _ttlDays;
    BOOL _loaded;
    BOOL _loading;
    NSUInteger _reloadsLeft;
    UIView *_bulletin;
    UIButton *_connect;
    ExteriaMediaCache *_media;
    /* the sticker of the card: loaded once, and moved into each card the header is built again with */
    UIView *_stickerHost;
    UIImageView *_stickerPreview;
    ExteriaLottieView *_stickerLottie;
    BOOL _stickerAsked;
}
@end

@implementation ExteriaDevicesController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _stickerHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, STICKER_SIDE, STICKER_SIDE)];
    _stickerPreview = [[UIImageView alloc] initWithFrame:_stickerHost.bounds];
    _stickerPreview.contentMode = UIViewContentModeScaleAspectFit;
    [_stickerHost addSubview:_stickerPreview];
    [_stickerHost addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(replaySticker)] autorelease]];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _devices = [[NSArray alloc] init];
    self.pageTitle = NSLocalizedString(@"devices.title", nil);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_stickerHost release];
    [_stickerPreview release];
    [_stickerLottie release];
    [_devices release];
    [_bulletin release];
    [_connect release];
    [super dealloc];
}

#pragma mark loading

/* the picture over the card is the seventh sticker of the official pack tg_placeholders_android, which shows in
   the same place (setSticker); the thumbnail stands in until the animation has its first frame, and the animation
   plays once and again at a tap */
- (void)loadSticker {
    if (_stickerAsked || !_media) return;
    _stickerAsked = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadStickersOfSetNamed:@"tg_placeholders_android" completion:^(NSArray *stickers, NSString *errorName) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        if (stickers.count <= 6) {
            NSLog(@"exteria: the sticker of the devices card did not load: %@", errorName ? errorName : @"short set");
            me->_stickerAsked = NO;
            return;
        }
        ExteriaMedia *media = [(ExteriaSticker *)[stickers objectAtIndex:6] media];
        if (media.previewFile) {
            [me->_media loadImageForFile:media.previewFile maxSide:(NSUInteger)(STICKER_SIDE * 2) completion:^(UIImage *image) {
                ExteriaDevicesController *again = weak.target;
                if (again && image && !again->_stickerLottie) again->_stickerPreview.image = image;
            }];
        }
        if (media.stickerFormat == EXTERIA_STICKER_ANIMATED && media.file) {
            NSString *key = media.file.key;
            [me->_media loadDataForFile:media.file completion:^(NSData *data) {
                ExteriaDevicesController *again = weak.target;
                if (!again || !data || ExteriaFileFormatOfData(data) != ExteriaFileFormatGzip) return;
                again->_stickerLottie = [[ExteriaLottieView alloc] initWithPackedData:data key:key];
                again->_stickerLottie.frame = again->_stickerHost.bounds;
                again->_stickerLottie.userInteractionEnabled = NO;
                [again->_stickerLottie setLoaded:YES];
                [again->_stickerHost addSubview:again->_stickerLottie];
                [again->_stickerLottie playOnce];
            }];
        } else if (media.stickerFormat == EXTERIA_STICKER_STATIC && media.file) {
            [me->_media loadImageForFile:media.file maxSide:(NSUInteger)(STICKER_SIDE * 2) completion:^(UIImage *image) {
                ExteriaDevicesController *again = weak.target;
                if (again && image) again->_stickerPreview.image = image;
            }];
        }
    }];
}

- (void)replaySticker {
    [_stickerLottie rewind];
    [_stickerLottie playOnce];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadSticker];
    [self rebuildHeader];
    [self rebuildSections];
    [self loadDevices];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_loaded) [self loadDevices];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadDevices) object:nil];
    _reloadsLeft = 0;
}

- (void)loadDevices {
    if (_loading) return;
    _loading = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadDevices:^(NSArray *sessions, int32_t ttl, NSString *errorName) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        me->_loading = NO;
        if (errorName) {
            NSLog(@"exteria: the devices were not loaded: %@", errorName);
        } else {
            [me->_devices release];
            me->_devices = [sessions retain];
            me->_ttlDays = ttl;
            me->_loaded = YES;
            /* the settings list shows the count the last visit saw */
            [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)sessions.count forKey:@"exteria.devices.count"];
            [me rebuildSections];
        }
        if (me->_reloadsLeft > 0) {
            --me->_reloadsLeft;
            if (me->_reloadsLeft > 0) [me performSelector:@selector(loadDevices) withObject:nil afterDelay:RELOAD_PAUSE];
        }
    }];
}

#pragma mark header

- (void)rebuildHeader {
    CGFloat width = self.table.bounds.size.width;
    CGFloat cardWidth = width - 2 * HEADER_INSET;
    BOOL scanning = [ExteriaQrScanController scanningAvailable];
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 100)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *card = [[[UIView alloc] init] autorelease];
    card.backgroundColor = ExteriaColorCard();
    card.layer.cornerRadius = 22;
    [header addSubview:card];
    _stickerHost.frame = CGRectMake((cardWidth - STICKER_SIDE) / 2, 20, STICKER_SIDE, STICKER_SIDE);
    [card addSubview:_stickerHost];
    ExteriaDevicesLinkText *text = [[[ExteriaDevicesLinkText alloc] initWithFrame:CGRectZero] autorelease];
    [text setMarkedText:NSLocalizedString(scanning ? @"devices.link.info" : @"devices.link.info.noscan", nil)
                   urls:[NSArray arrayWithObjects:@"https://desktop.telegram.org", @"https://web.telegram.org", nil] width:cardWidth - 72];
    CGFloat y = CGRectGetMaxY(_stickerHost.frame) + 16;
    text.frame = CGRectMake(36, y, cardWidth - 72, ceil(text.textSize.height));
    [card addSubview:text];
    y = CGRectGetMaxY(text.frame) + 16;
    if (scanning) {
        [_connect release];
        _connect = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _connect.frame = CGRectMake(16, y, cardWidth - 32, BUTTON_HEIGHT);
        _connect.backgroundColor = ExteriaColorAccent();
        _connect.layer.cornerRadius = BUTTON_HEIGHT / 2;
        _connect.titleLabel.font = ExteriaFontSemibold(16);
        [_connect setTitle:NSLocalizedString(@"devices.connect", nil) forState:UIControlStateNormal];
        [_connect setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_connect setImage:ExteriaSymbolImage(ExteriaSymbolQrMini, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
        _connect.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
        [_connect addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_connect];
        y += BUTTON_HEIGHT + 16;
    } else {
        y += 4;
    }
    card.frame = CGRectMake(HEADER_INSET, 12, cardWidth, y);
    header.frame = CGRectMake(0, 0, width, 12 + y + 8);
    self.headerView = header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* the card is laid out for the width of the table, so a turn of the phone builds it again */
    UIView *header = self.headerView;
    if (header && fabs(header.bounds.size.width - self.table.bounds.size.width) > 0.5) [self rebuildHeader];
}

#pragma mark sections

static NSString *ExteriaPluralText(NSString *base, NSInteger count) {
    NSString *key = [NSString stringWithFormat:@"%@.%@", base, ExteriaPluralForm(count)];
    return [NSString stringWithFormat:NSLocalizedString(key, nil), (long)count];
}

/* 7 days read as weeks, up to six months as months, a year as years: the way words the self destruct time */
static NSString *ExteriaTtlText(int32_t days) {
    if (days > 30 && days <= 183) return ExteriaPluralText(@"plural.months", days / 30);
    if (days == 365) return ExteriaPluralText(@"plural.years", days / 365);
    return ExteriaPluralText(@"plural.weeks", MAX(1, days / 7));
}

- (ExteriaSettingsRow *)rowForDevice:(ExteriaDeviceSession *)device {
    NSString *time = device.current ? NSLocalizedString(@"devices.online", nil) : ExteriaListTimeText(device.dateActive);
    NSString *line3 = device.place.length ? [NSString stringWithFormat:@"%@ • %@", device.place, time] : time;
    ExteriaWeakReference *weak = _weak;
    return [ExteriaSettingsRow sessionRowWithPicture:ExteriaDeviceIconImage(device.kind, 42) title:device.title line2:device.appLine line3:line3
                                         accentLine3:device.current tap:^{ [(ExteriaDevicesController *)weak.target showSheetOfDevice:device]; }];
}

- (void)rebuildSections {
    ExteriaWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    ExteriaDeviceSession *current = nil;
    NSMutableArray *others = [NSMutableArray array], *pending = [NSMutableArray array];
    for (ExteriaDeviceSession *device in _devices) {
        if (device.current) current = device;
        else if (device.passwordPending) [pending addObject:device];
        else [others addObject:device];
    }
    NSMutableArray *thisRows = [NSMutableArray array];
    if (current) [thisRows addObject:[self rowForDevice:current]];
    else if (!_loaded) [thisRows addObject:[self placeholderRow]];
    BOOL canEndOthers = others.count || pending.count;
    if (canEndOthers) {
        [thisRows addObject:[ExteriaSettingsRow actionRowWithSymbol:ExteriaSymbolBlock title:NSLocalizedString(@"devices.end.all", nil) destructive:YES
                                                               tap:^{ [(ExteriaDevicesController *)weak.target confirmEndOthers]; }]];
    }
    if (thisRows.count) {
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"devices.this", nil)
                                                               footer:canEndOthers ? NSLocalizedString(@"devices.end.all.info", nil) : nil rows:thisRows]];
    }
    if (pending.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (ExteriaDeviceSession *device in pending) [rows addObject:[self rowForDevice:device]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"devices.attempts", nil)
                                                               footer:NSLocalizedString(@"devices.attempts.info", nil) rows:rows]];
    }
    if (others.count) {
        NSMutableArray *rows = [NSMutableArray array];
        for (ExteriaDeviceSession *device in others) [rows addObject:[self rowForDevice:device]];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"devices.active", nil)
                                                               footer:NSLocalizedString(@"devices.list.info", nil) rows:rows]];
    }
    if (_ttlDays > 0) {
        ExteriaSettingsRow *row = [ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"devices.ttl.row", nil) value:ExteriaTtlText(_ttlDays)
                                                               tap:^{ [(ExteriaDevicesController *)weak.target chooseTtl]; }];
        [sections addObject:[ExteriaSettingsSection sectionWithHeader:NSLocalizedString(@"devices.ttl.header", nil) footer:nil rows:[NSArray arrayWithObject:row]]];
    }
    self.sections = sections;
}

/* what the row of this device shows before the server has answered: the phone as the system names it */
- (ExteriaSettingsRow *)placeholderRow {
    UIDevice *device = [UIDevice currentDevice];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    exteria_session_kind kind = [device.model hasPrefix:@"iPad"] ? EXTERIA_SESSION_IPAD : EXTERIA_SESSION_IPHONE;
    NSString *app = [NSString stringWithFormat:@"exteria %@", [info objectForKey:@"CFBundleShortVersionString"]];
    return [ExteriaSettingsRow sessionRowWithPicture:ExteriaDeviceIconImage(kind, 42) title:device.model line2:app line3:NSLocalizedString(@"devices.online", nil)
                                         accentLine3:YES tap:nil];
}

#pragma mark actions

- (void)showSheetOfDevice:(ExteriaDeviceSession *)device {
    ExteriaWeakReference *weak = _weak;
    ExteriaSession *session = _session;
    [ExteriaDeviceSheet presentInView:self.view device:device
        secretChats:^(BOOL on) {
            device.secretChatsOn = on;
            [session setDevice:device secretChats:on ? 1 : 0 calls:-1 completion:^(NSString *errorName) {
                if (errorName) NSLog(@"exteria: the secret chats switch was not saved: %@", errorName);
            }];
        }
        calls:^(BOOL on) {
            device.callsOn = on;
            [session setDevice:device secretChats:-1 calls:on ? 1 : 0 completion:^(NSString *errorName) {
                if (errorName) NSLog(@"exteria: the calls switch was not saved: %@", errorName);
            }];
        }
        end:^{ [(ExteriaDevicesController *)weak.target endDevice:device]; }];
}

- (void)endDevice:(ExteriaDeviceSession *)device {
    ExteriaWeakReference *weak = _weak;
    [_session endDevice:device completion:^(NSString *errorName) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        if (errorName) {
            NSLog(@"exteria: the session was not ended: %@", errorName);
            ExteriaShowNotice(nil, NSLocalizedString(@"devices.error", nil));
            return;
        }
        NSMutableArray *rest = [NSMutableArray arrayWithArray:me->_devices];
        [rest removeObject:device];
        [me->_devices release];
        me->_devices = [rest copy];
        [me rebuildSections];
    }];
}

- (void)confirmEndOthers {
    ExteriaWeakReference *weak = _weak;
    [ExteriaSheet presentInView:self.view title:NSLocalizedString(@"devices.end.all.title", nil) message:NSLocalizedString(@"devices.end.all.confirm", nil)
                        options:[NSArray arrayWithObject:NSLocalizedString(@"devices.terminate", nil)] destructive:[NSIndexSet indexSetWithIndex:0]
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        (void)index;
        [(ExteriaDevicesController *)weak.target endOthers];
    }];
}

- (void)endOthers {
    ExteriaWeakReference *weak = _weak;
    [_session endOtherDevicesWithCompletion:^(NSString *errorName) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        if (errorName) {
            NSLog(@"exteria: the other sessions were not ended: %@", errorName);
            ExteriaShowNotice(nil, NSLocalizedString(@"devices.error", nil));
            return;
        }
        NSMutableArray *rest = [NSMutableArray array];
        for (ExteriaDeviceSession *device in me->_devices) if (device.current) [rest addObject:device];
        [me->_devices release];
        me->_devices = [rest copy];
        [me rebuildSections];
        [me showBulletin:NSLocalizedString(@"devices.ended", nil)];
    }];
}

- (void)chooseTtl {
    ExteriaWeakReference *weak = _weak;
    static const int32_t days[4] = {7, 90, 183, 365};
    NSArray *options = [NSArray arrayWithObjects:ExteriaPluralText(@"plural.weeks", 1), ExteriaPluralText(@"plural.months", 3), ExteriaPluralText(@"plural.months", 6),
                                                 ExteriaPluralText(@"plural.years", 1), nil];
    [ExteriaSheet presentInView:self.view title:NSLocalizedString(@"devices.ttl.title", nil) message:nil options:options destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        ExteriaDevicesController *me = weak.target;
        if (!me || index >= 4) return;
        int32_t before = me->_ttlDays;
        me->_ttlDays = days[index];
        [me rebuildSections];
        [me->_session setDevicesTTL:days[index] completion:^(NSString *errorName) {
            if (!errorName) return;
            /* the row showed the new time at once, and shows the old one again when the server refuses */
            NSLog(@"exteria: the self destruct time was not saved: %@", errorName);
            ExteriaDevicesController *again = weak.target;
            if (!again) return;
            again->_ttlDays = before;
            [again rebuildSections];
        }];
    }];
}

#pragma mark linking a device

- (void)connectTapped {
    ExteriaQrScanController *scan = [[[ExteriaQrScanController alloc] init] autorelease];
    ExteriaWeakReference *weak = _weak;
    scan.closeHandler = ^{ [[(ExteriaDevicesController *)weak.target presentedViewController] dismissViewControllerAnimated:YES completion:nil]; };
    scan.scanHandler = ^(NSString *link) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        [me dismissViewControllerAnimated:YES completion:^{ [(ExteriaDevicesController *)weak.target acceptLink:link]; }];
    };
    [self presentViewController:scan animated:YES completion:nil];
}

- (void)acceptLink:(NSString *)link {
    ExteriaWeakReference *weak = _weak;
    [_session acceptLoginLink:link completion:^(NSString *errorName) {
        ExteriaDevicesController *me = weak.target;
        if (!me) return;
        if (!errorName) {
            /* the new session needs a moment to show on the server, so the list is asked again a few times */
            [me showBulletin:NSLocalizedString(@"devices.linked", nil)];
            me->_reloadsLeft = RELOAD_ROUNDS;
            [me loadDevices];
            return;
        }
        NSLog(@"exteria: the device was not linked: %@", errorName);
        BOOL already = [errorName isEqualToString:@"AUTH_TOKEN_ALREADY_ACCEPTED"];
        ExteriaShowNotice(NSLocalizedString(@"devices.scan.title", nil),
                          already ? NSLocalizedString(@"devices.already", nil) : [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"devices.error", nil), errorName]);
    }];
}

#pragma mark bulletin

/* the line at the foot of the screen that says something was done: a check that draws itself, and the words */
- (void)showBulletin:(NSString *)text {
    [_bulletin removeFromSuperview];
    [_bulletin release];
    CGFloat width = MIN(self.view.bounds.size.width - 24, 420);
    _bulletin = [[UIView alloc] init];
    _bulletin.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
    _bulletin.layer.cornerRadius = 14;
    ExteriaLottieView *check = [[[ExteriaLottieView alloc] initWithAnimationNamed:@"check_done"] autorelease];
    check.frame = CGRectMake(10, 8, 36, 36);
    check.userInteractionEnabled = NO;
    [_bulletin addSubview:check];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(56, 0, width - 56 - 14, 52)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = ExteriaFontRegular(15);
    label.numberOfLines = 2;
    label.text = text;
    [_bulletin addSubview:label];
    CGFloat bottom = self.bottomInset + 20;
    _bulletin.frame = CGRectMake((self.view.bounds.size.width - width) / 2, self.view.bounds.size.height - bottom - 52 + 80, width, 52);
    _bulletin.alpha = 0;
    [self.view addSubview:_bulletin];
    UIView *bulletin = _bulletin;
    CGRect shown = bulletin.frame;
    shown.origin.y -= 80;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        bulletin.alpha = 1;
        bulletin.frame = shown;
    } completion:^(BOOL finished) {
        (void)finished;
        [check playOnce];
    }];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBulletin) object:nil];
    [self performSelector:@selector(hideBulletin) withObject:nil afterDelay:3];
}

- (void)hideBulletin {
    UIView *bulletin = _bulletin;
    if (!bulletin) return;
    _bulletin = nil;
    [UIView animateWithDuration:0.25 animations:^{ bulletin.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [bulletin removeFromSuperview];
        [bulletin release];
    }];
}

@end
