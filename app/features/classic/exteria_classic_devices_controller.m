#import "exteria_classic_devices_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_classic_chrome.h"
#import "exteria_lottie_view.h"
#import "exteria_image_decoder.h"
#import "exteria_media_cache.h"
#import "exteria_plural.h"
#import "exteria_platform.h"
#import "exteria_qr_scan_controller.h"
#import "exteria_session_devices.h"
#import "exteria_settings_kit.h"
#import "exteria_sheet.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define ICON 42.0
#define STICKER_SIDE 110.0
#define RELOAD_PAUSE 2.5
#define RELOAD_ROUNDS 3

static NSString *ExteriaClassicPluralText(NSString *base, NSInteger count) {
    NSString *key = [NSString stringWithFormat:@"%@.%@", base, ExteriaPluralForm(count)];
    return [NSString stringWithFormat:NSLocalizedString(key, nil), (long)count];
}

static NSString *ExteriaClassicTtlText(int32_t days) {
    if (days > 30 && days <= 183) return ExteriaClassicPluralText(@"plural.months", days / 30);
    if (days == 365) return ExteriaClassicPluralText(@"plural.years", days / 365);
    return ExteriaClassicPluralText(@"plural.weeks", MAX(1, days / 7));
}

#pragma mark detail

/* one session: its picture, name and time over a grouped table of what the server knows, with the two switches and a glossy red button */
@interface ExteriaClassicDeviceDetailController : UITableViewController {
    ExteriaSession *_session;
    ExteriaDeviceSession *_device;
    void (^_ended)(ExteriaDeviceSession *);
    NSMutableArray *_rows;
}
- (id)initWithSession:(ExteriaSession *)session device:(ExteriaDeviceSession *)device ended:(void (^)(ExteriaDeviceSession *))ended;
@end

@implementation ExteriaClassicDeviceDetailController

- (id)initWithSession:(ExteriaSession *)session device:(ExteriaDeviceSession *)device ended:(void (^)(ExteriaDeviceSession *))ended {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (!self) return nil;
    _session = [session retain];
    _device = [device retain];
    _ended = [ended copy];
    self.title = NSLocalizedString(@"devices.title", nil);
    /* each row: the glyph-less title, its caption, and 0 plain, 1 the secret chats switch, 2 the calls switch */
    _rows = [[NSMutableArray alloc] init];
    [_rows addObject:[NSArray arrayWithObjects:device.appLine, NSLocalizedString(@"devices.application", nil), [NSNumber numberWithInt:0], nil]];
    if (device.place.length) [_rows addObject:[NSArray arrayWithObjects:device.place, NSLocalizedString(@"devices.location", nil), [NSNumber numberWithInt:0], nil]];
    if (device.ip.length) [_rows addObject:[NSArray arrayWithObjects:device.ip, NSLocalizedString(@"devices.ip", nil), [NSNumber numberWithInt:0], nil]];
    if (device.takesSecretChatsSetting) [_rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"devices.secret", nil), NSLocalizedString(@"devices.secret.info", nil), [NSNumber numberWithInt:1], nil]];
    if (device.takesCallsSetting) [_rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"devices.calls", nil), NSLocalizedString(@"devices.calls.info", nil), [NSNumber numberWithInt:2], nil]];
    return self;
}

- (void)dealloc {
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_device release];
    [_ended release];
    [_rows release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    ExteriaClassicStyleTable(self.tableView);
    CGFloat width = self.tableView.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 148)] autorelease];
    UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaDeviceIconImage(_device.kind, 72)] autorelease];
    icon.frame = CGRectMake((width - 72) / 2, 16, 72, 72);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    icon.layer.shadowColor = [UIColor blackColor].CGColor;
    icon.layer.shadowOpacity = 0.4f;
    icon.layer.shadowRadius = 3;
    icon.layer.shadowOffset = CGSizeMake(0, 2);
    [header addSubview:icon];
    UILabel *name = [[[UILabel alloc] initWithFrame:CGRectMake(16, 94, width - 32, 24)] autorelease];
    name.backgroundColor = [UIColor clearColor];
    name.textAlignment = ExteriaTextAlignmentCenter;
    name.font = [UIFont boldSystemFontOfSize:19];
    name.textColor = ExteriaThemeIsDark() ? ExteriaColorTitle() : [UIColor blackColor];
    name.text = _device.title;
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:name];
    UILabel *time = [[[UILabel alloc] initWithFrame:CGRectMake(16, 120, width - 32, 18)] autorelease];
    time.backgroundColor = [UIColor clearColor];
    time.textAlignment = ExteriaTextAlignmentCenter;
    time.font = [UIFont systemFontOfSize:14];
    time.textColor = ExteriaThemeIsDark() ? ExteriaColorSecondary() : [UIColor grayColor];
    time.text = _device.current ? NSLocalizedString(@"devices.online", nil) : [NSString stringWithFormat:NSLocalizedString(@"devices.last", nil), ExteriaMediaTimeText(_device.dateActive)];
    time.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:time];
    self.tableView.tableHeaderView = header;
    if (!_device.current) {
        UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 70)] autorelease];
        UIButton *end = [UIButton buttonWithType:UIButtonTypeCustom];
        end.frame = CGRectMake(10, 14, width - 20, 44);
        end.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [end setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossRed, NO) forState:UIControlStateNormal];
        [end setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossRed, YES) forState:UIControlStateHighlighted];
        end.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [end setTitle:NSLocalizedString(@"devices.end", nil) forState:UIControlStateNormal];
        [end setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [end setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
        end.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [end addTarget:self action:@selector(endTapped) forControlEvents:UIControlEventTouchUpInside];
        [footer addSubview:end];
        self.tableView.tableFooterView = footer;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *row = [_rows objectAtIndex:(NSUInteger)indexPath.row];
    int kind = [[row objectAtIndex:2] intValue];
    UITableViewCell *cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
    ExteriaClassicStyleCell(cell);
    cell.textLabel.text = [row objectAtIndex:0];
    cell.detailTextLabel.text = [row objectAtIndex:1];
    cell.selectionStyle = kind ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    if (kind) {
        UISwitch *toggle = [[[UISwitch alloc] init] autorelease];
        toggle.on = kind == 1 ? _device.secretChatsOn : _device.callsOn;
        toggle.tag = kind;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *row = [_rows objectAtIndex:(NSUInteger)indexPath.row];
    if ([[row objectAtIndex:2] intValue] == 0) [UIPasteboard generalPasteboard].string = [row objectAtIndex:0];
}

- (void)toggled:(UISwitch *)toggle {
    BOOL secret = toggle.tag == 1;
    if (secret) _device.secretChatsOn = toggle.on;
    else _device.callsOn = toggle.on;
    [_session setDevice:_device secretChats:secret ? (toggle.on ? 1 : 0) : -1 calls:secret ? -1 : (toggle.on ? 1 : 0) completion:^(NSString *errorName) {
        if (errorName) NSLog(@"exteria: the session switch was not saved: %@", errorName);
    }];
}

- (void)endTapped {
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    ExteriaConfirm(nil, NSLocalizedString(@"devices.end.confirm", nil), NSLocalizedString(@"devices.terminate", nil), ^{
        ExteriaClassicDeviceDetailController *me = weak.target;
        if (!me) return;
        [me->_session endDevice:me->_device completion:^(NSString *errorName) {
            ExteriaClassicDeviceDetailController *again = weak.target;
            if (!again) return;
            if (errorName) {
                NSLog(@"exteria: the session was not ended: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"devices.error", nil));
                return;
            }
            if (again->_ended) again->_ended(again->_device);
            [again.navigationController popViewControllerAnimated:YES];
        }];
    });
}

@end

#pragma mark list

enum { RowLink, RowThis, RowEndOthers };

@interface ExteriaClassicDevicesController () {
    ExteriaSession *_session;
    ExteriaWeakReference *_weak;
    NSArray *_devices;
    int32_t _ttlDays;
    BOOL _loaded;
    BOOL _loading;
    NSUInteger _reloadsLeft;
    NSMutableArray *_sections;
    ExteriaMediaCache *_media;
    UIView *_stickerHost;
    UIImageView *_stickerPreview;
    ExteriaLottieView *_stickerLottie;
    BOOL _stickerAsked;
}
@end

@implementation ExteriaClassicDevicesController

- (id)initWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    self = [super initWithStyle:UITableViewStyleGrouped];
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
    _sections = [[NSMutableArray alloc] init];
    self.title = NSLocalizedString(@"devices.title", nil);
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_weak clear];
    [_weak release];
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_media release];
    [_stickerHost release];
    [_stickerPreview release];
    [_stickerLottie release];
    [_devices release];
    [_sections release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    ExteriaClassicStyleTable(self.tableView);
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, STICKER_SIDE + 24)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _stickerHost.frame = CGRectMake((header.bounds.size.width - STICKER_SIDE) / 2, 16, STICKER_SIDE, STICKER_SIDE);
    _stickerHost.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [header addSubview:_stickerHost];
    self.tableView.tableHeaderView = header;
    [self loadSticker];
    [self rebuild];
    [self load];
}

/* the seventh sticker of tg_placeholders_android, the one the modern devices card shows; the thumbnail stands in until the animation has a frame */
- (void)loadSticker {
    if (_stickerAsked || !_media) return;
    _stickerAsked = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadStickersOfSetNamed:@"tg_placeholders_android" completion:^(NSArray *stickers, NSString *errorName) {
        ExteriaClassicDevicesController *me = weak.target;
        if (!me) return;
        if (stickers.count <= 6) {
            NSLog(@"exteria: the sticker of the devices table did not load: %@", errorName ? errorName : @"short set");
            me->_stickerAsked = NO;
            return;
        }
        ExteriaMedia *media = [(ExteriaSticker *)[stickers objectAtIndex:6] media];
        if (media.previewFile) {
            [me->_media loadImageForFile:media.previewFile maxSide:(NSUInteger)(STICKER_SIDE * 2) completion:^(UIImage *image) {
                ExteriaClassicDevicesController *again = weak.target;
                if (again && image && !again->_stickerLottie) again->_stickerPreview.image = image;
            }];
        }
        if (media.stickerFormat == EXTERIA_STICKER_ANIMATED && media.file) {
            NSString *key = media.file.key;
            [me->_media loadDataForFile:media.file completion:^(NSData *data) {
                ExteriaClassicDevicesController *again = weak.target;
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
                ExteriaClassicDevicesController *again = weak.target;
                if (again && image) again->_stickerPreview.image = image;
            }];
        }
    }];
}

- (void)replaySticker {
    [_stickerLottie rewind];
    [_stickerLottie playOnce];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_loaded) [self load];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(load) object:nil];
    _reloadsLeft = 0;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (void)load {
    if (_loading) return;
    _loading = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadDevices:^(NSArray *sessions, int32_t ttl, NSString *errorName) {
        ExteriaClassicDevicesController *me = weak.target;
        if (!me) return;
        me->_loading = NO;
        if (errorName) {
            NSLog(@"exteria: the devices were not loaded: %@", errorName);
        } else {
            [me->_devices release];
            me->_devices = [sessions retain];
            me->_ttlDays = ttl;
            me->_loaded = YES;
            [me rebuild];
        }
        if (me->_reloadsLeft > 0) {
            --me->_reloadsLeft;
            if (me->_reloadsLeft > 0) [me performSelector:@selector(load) withObject:nil afterDelay:RELOAD_PAUSE];
        }
    }];
}

/* each section is a dictionary: header, footer, and the rows, which are a device, or a marker for the link button, the end button or the time */
- (void)rebuild {
    [_sections removeAllObjects];
    ExteriaDeviceSession *current = nil;
    NSMutableArray *others = [NSMutableArray array], *pending = [NSMutableArray array];
    for (ExteriaDeviceSession *device in _devices) {
        if (device.current) current = device;
        else if (device.passwordPending) [pending addObject:device];
        else [others addObject:device];
    }
    BOOL scanning = [ExteriaQrScanController scanningAvailable];
    if (scanning) {
        [_sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:@"link"], @"rows",
                              [NSString stringWithFormat:@"%@", [NSLocalizedString(@"devices.link.info", nil) stringByReplacingOccurrencesOfString:@"*" withString:@""]], @"footer", nil]];
    } else {
        [_sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSArray array], @"rows",
                              [NSLocalizedString(@"devices.link.info.noscan", nil) stringByReplacingOccurrencesOfString:@"*" withString:@""], @"footer", nil]];
    }
    NSMutableArray *thisRows = [NSMutableArray array];
    if (current) [thisRows addObject:current];
    if (others.count || pending.count) [thisRows addObject:@"end"];
    if (thisRows.count) {
        NSMutableDictionary *section = [NSMutableDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"devices.this", nil), @"header", thisRows, @"rows", nil];
        if (others.count || pending.count) [section setObject:NSLocalizedString(@"devices.end.all.info", nil) forKey:@"footer"];
        [_sections addObject:section];
    }
    if (pending.count) {
        [_sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"devices.attempts", nil), @"header", pending, @"rows",
                              NSLocalizedString(@"devices.attempts.info", nil), @"footer", nil]];
    }
    if (others.count) {
        [_sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"devices.active", nil), @"header", others, @"rows",
                              NSLocalizedString(@"devices.list.info", nil), @"footer", nil]];
    }
    if (_ttlDays > 0) {
        [_sections addObject:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"devices.ttl.header", nil), @"header", [NSArray arrayWithObject:@"ttl"], @"rows", nil]];
    }
    [self.tableView reloadData];
}

#pragma mark table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_sections.count;
}

- (NSDictionary *)sectionAt:(NSInteger)index { return [_sections objectAtIndex:(NSUInteger)index]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[(NSArray *)[[self sectionAt:section] objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[self sectionAt:section] objectForKey:@"header"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return [[self sectionAt:section] objectForKey:@"footer"];
}

/* the system header and footer text on the dark grouped background is a centered grey that sinks into it, so the dark theme draws them as the settings
   screens of the classic style do */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!ExteriaThemeIsDark()) return nil;
    NSString *text = [[self sectionAt:section] objectForKey:@"header"];
    if (!text.length) return nil;
    return ExteriaClassicGroupedHeader(text, tableView.bounds.size.width, 34, [UIColor whiteColor]);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (!ExteriaThemeIsDark()) return nil;
    NSString *text = [[self sectionAt:section] objectForKey:@"footer"];
    if (!text.length) return nil;
    CGFloat edge = ExteriaClassicGroupedTextInset(tableView.bounds.size.width);
    CGFloat width = MAX(0, tableView.bounds.size.width - 2 * edge);
    CGSize fit = ExteriaStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(width, 600));
    return ExteriaClassicGroupedFooter(text, tableView.bounds.size.width, fit.height + 12);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *text = [[self sectionAt:section] objectForKey:@"header"];
    if (!ExteriaThemeIsDark()) return text.length ? UITableViewAutomaticDimension : 10;
    return text.length ? 34 : 10;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [[self sectionAt:section] objectForKey:@"footer"];
    if (!text.length) return 10;
    if (!ExteriaThemeIsDark()) return UITableViewAutomaticDimension;
    CGSize fit = ExteriaStringSizeIn(text, [UIFont systemFontOfSize:14], CGSizeMake(MAX(0, tableView.bounds.size.width - 2 * ExteriaClassicGroupedTextInset(tableView.bounds.size.width)), 600));
    return fit.height + 12;
}

- (id)itemAt:(NSIndexPath *)indexPath {
    return [[[self sectionAt:indexPath.section] objectForKey:@"rows"] objectAtIndex:(NSUInteger)indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return [[self itemAt:indexPath] isKindOfClass:[ExteriaDeviceSession class]] ? 70 : 46;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id item = [self itemAt:indexPath];
    UITableViewCell *cell;
    if ([item isKindOfClass:[ExteriaDeviceSession class]]) {
        ExteriaDeviceSession *device = item;
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil] autorelease];
        ExteriaClassicStyleCell(cell);
        cell.imageView.image = ExteriaDeviceIconImage(device.kind, ICON);
        cell.textLabel.text = device.title;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        NSString *time = device.current ? NSLocalizedString(@"devices.online", nil) : ExteriaListTimeText(device.dateActive);
        NSString *where = device.place.length ? [NSString stringWithFormat:@"%@ • %@", device.place, time] : time;
        cell.detailTextLabel.numberOfLines = 2;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", device.appLine, where];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil] autorelease];
    ExteriaClassicStyleCell(cell);
    NSString *marker = item;
    if ([marker isEqualToString:@"link"]) {
        cell.textLabel.text = NSLocalizedString(@"devices.connect", nil);
        cell.textLabel.textAlignment = ExteriaTextAlignmentCenter;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    } else if ([marker isEqualToString:@"end"]) {
        cell.textLabel.text = NSLocalizedString(@"devices.end.all", nil);
        cell.textLabel.textColor = ExteriaColorBadgeRed();
        cell.textLabel.textAlignment = ExteriaTextAlignmentCenter;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    } else {
        cell.textLabel.text = NSLocalizedString(@"devices.ttl.row", nil);
        cell.detailTextLabel.text = ExteriaClassicTtlText(_ttlDays);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = [self itemAt:indexPath];
    ExteriaWeakReference *weak = _weak;
    if ([item isKindOfClass:[ExteriaDeviceSession class]]) {
        ExteriaClassicDeviceDetailController *detail = [[[ExteriaClassicDeviceDetailController alloc] initWithSession:_session device:item ended:^(ExteriaDeviceSession *device) {
            ExteriaClassicDevicesController *me = weak.target;
            if (!me) return;
            NSMutableArray *rest = [NSMutableArray arrayWithArray:me->_devices];
            [rest removeObject:device];
            [me->_devices release];
            me->_devices = [rest copy];
            [me rebuild];
        }] autorelease];
        [self.navigationController pushViewController:detail animated:YES];
    } else if ([item isEqualToString:@"link"]) {
        [self connect];
    } else if ([item isEqualToString:@"end"]) {
        ExteriaConfirm(NSLocalizedString(@"devices.end.all.title", nil), NSLocalizedString(@"devices.end.all.confirm", nil), NSLocalizedString(@"devices.terminate", nil), ^{
            [(ExteriaClassicDevicesController *)weak.target endOthers];
        });
    } else {
        [self chooseTtl];
    }
}

#pragma mark actions

- (void)endOthers {
    ExteriaWeakReference *weak = _weak;
    [_session endOtherDevicesWithCompletion:^(NSString *errorName) {
        ExteriaClassicDevicesController *me = weak.target;
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
        [me rebuild];
        ExteriaShowNotice(nil, NSLocalizedString(@"devices.ended", nil));
    }];
}

static const int32_t ExteriaClassicTtlDays[4] = {7, 90, 183, 365};

- (void)chooseTtl {
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"devices.ttl.title", nil) delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil
                                               otherButtonTitles:nil] autorelease];
    [sheet addButtonWithTitle:ExteriaClassicPluralText(@"plural.weeks", 1)];
    [sheet addButtonWithTitle:ExteriaClassicPluralText(@"plural.months", 3)];
    [sheet addButtonWithTitle:ExteriaClassicPluralText(@"plural.months", 6)];
    [sheet addButtonWithTitle:ExteriaClassicPluralText(@"plural.years", 1)];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"picker.cancel", nil)];
    [sheet showInView:self.tabBarController ? self.tabBarController.view : self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index < 0 || index >= 4) return;
    int32_t before = _ttlDays;
    _ttlDays = ExteriaClassicTtlDays[index];
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session setDevicesTTL:ExteriaClassicTtlDays[index] completion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"exteria: the self destruct time was not saved: %@", errorName);
        ExteriaClassicDevicesController *me = weak.target;
        if (!me) return;
        me->_ttlDays = before;
        [me rebuild];
    }];
}

- (void)connect {
    ExteriaQrScanController *scan = [[[ExteriaQrScanController alloc] init] autorelease];
    ExteriaWeakReference *weak = _weak;
    scan.closeHandler = ^{ [(UIViewController *)[(ExteriaClassicDevicesController *)weak.target presentedViewController] dismissViewControllerAnimated:YES completion:nil]; };
    scan.scanHandler = ^(NSString *link) {
        ExteriaClassicDevicesController *me = weak.target;
        if (!me) return;
        [me dismissViewControllerAnimated:YES completion:^{ [(ExteriaClassicDevicesController *)weak.target acceptLink:link]; }];
    };
    [self presentViewController:scan animated:YES completion:nil];
}

- (void)acceptLink:(NSString *)link {
    ExteriaWeakReference *weak = _weak;
    [_session acceptLoginLink:link completion:^(NSString *errorName) {
        ExteriaClassicDevicesController *me = weak.target;
        if (!me) return;
        if (!errorName) {
            ExteriaShowNotice(nil, NSLocalizedString(@"devices.linked", nil));
            me->_reloadsLeft = RELOAD_ROUNDS;
            [me load];
            return;
        }
        NSLog(@"exteria: the device was not linked: %@", errorName);
        BOOL already = [errorName isEqualToString:@"AUTH_TOKEN_ALREADY_ACCEPTED"];
        ExteriaShowNotice(NSLocalizedString(@"devices.scan.title", nil),
                          already ? NSLocalizedString(@"devices.already", nil) : [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"devices.error", nil), errorName]);
    }];
}

@end
