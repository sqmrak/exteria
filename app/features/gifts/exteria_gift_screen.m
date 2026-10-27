#import "exteria_emoji_label.h"
#import "exteria_gift_screen.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_bar_button.h"
#import "exteria_classic_chrome.h"
#import "exteria_platform.h"
#import "exteria_split_controller.h"
#import "exteria_theme.h"

#define BAR_HEIGHT 44.0

static NSString *ExteriaGroupedNumber(long long value) {
    NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter stringFromNumber:[NSNumber numberWithLongLong:value]];
}

NSString *ExteriaStarsText(long long stars) {
    NSString *language = [[NSLocale preferredLanguages] count] ? [[NSLocale preferredLanguages] objectAtIndex:0] : @"en";
    long long ones = stars % 10, tens = stars % 100;
    NSString *key;
    if ([language hasPrefix:@"ru"]) {
        if (ones == 1 && tens != 11) key = @"gifts.stars.one";
        else if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) key = @"gifts.stars.few";
        else key = @"gifts.stars.many";
    } else {
        key = stars == 1 ? @"gifts.stars.one" : @"gifts.stars.many";
    }
    return [NSString stringWithFormat:NSLocalizedString(key, nil), ExteriaGroupedNumber(stars)];
}

UIImage *ExteriaStarsImage(NSString *prefix, long long stars, UIFont *font, UIColor *color) {
    NSString *count = ExteriaGroupedNumber(stars);
    NSString *lead = prefix.length ? [prefix stringByAppendingString:@" "] : @"";
    CGSize leadSize = lead.length ? [lead sizeWithFont:font] : CGSizeZero;
    CGSize countSize = [count sizeWithFont:font];
    CGFloat side = ceil(font.pointSize * 1.05);
    UIImage *star = ExteriaStarsGlyph(side);
    CGFloat gap = 3;
    CGFloat width = ceil(leadSize.width + side + gap + countSize.width);
    CGFloat height = ceil(MAX(side, countSize.height));
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0);
    [color set];
    if (lead.length) [lead drawAtPoint:CGPointMake(0, (height - leadSize.height) / 2) withFont:font];
    [star drawInRect:CGRectMake(leadSize.width, (height - side) / 2, side, side)];
    [count drawAtPoint:CGPointMake(leadSize.width + side + gap, (height - countSize.height) / 2) withFont:font];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

NSString *ExteriaGiftErrorText(NSString *errorName) {
    if ([errorName isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([errorName isEqualToString:@"BALANCE_LOW"] || [errorName isEqualToString:@"BALANCE_TOO_LOW"]) return NSLocalizedString(@"gifts.error.balance", nil);
    if ([errorName isEqualToString:@"STARS_UNSUPPORTED"]) return NSLocalizedString(@"gifts.error.unsupported", nil);
    if ([errorName isEqualToString:@"STARGIFT_USAGE_LIMITED"]) return NSLocalizedString(@"gifts.error.limited", nil);
    if ([errorName isEqualToString:@"USER_PRIVACY_RESTRICTED"] || [errorName isEqualToString:@"PRIVACY_PREMIUM_REQUIRED"]) return NSLocalizedString(@"gifts.error.privacy", nil);
    if ([errorName isEqualToString:@"PEER_ID_INVALID"] || [errorName isEqualToString:@"USER_BOT"]) return NSLocalizedString(@"gifts.error.peer", nil);
    if ([errorName isEqualToString:@"JOIN_WEBVIEW"]) return NSLocalizedString(@"channel.join.webview", nil);
    if ([errorName isEqualToString:@"CHANNELS_TOO_MUCH"]) return NSLocalizedString(@"channel.join.toomuch", nil);
    if ([errorName isEqualToString:@"USER_BANNED_IN_CHANNEL"] || [errorName isEqualToString:@"CHANNEL_PRIVATE"]) return NSLocalizedString(@"channel.join.denied", nil);
    if ([errorName isEqualToString:@"NOT_REPORTED"]) return NSLocalizedString(@"report.refused", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"];
}

void ExteriaGiftAlert(NSString *title, NSString *message) {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

@interface ExteriaGiftScreen () {
    UIView *_header;
    UIView *_headerLine;
    ExteriaBarButton *_back;
    ExteriaEmojiLabel *_titleLabel;
    ExteriaBarButton *_action;
    UIButton *_actionIcon;
    ExteriaSymbol _actionSymbol;
    NSString *_actionLabel;
    NSString *_screenTitle;
    NSString *_actionTitle;
    void (^_actionHandler)(void);
    BOOL _clearBar;
    UIView *_backChip;
}
@end

@implementation ExteriaGiftScreen

@synthesize session = _session;
@synthesize avatars = _avatars;
@synthesize media = _media;
@synthesize screenTitle = _screenTitle;
@synthesize clearBar = _clearBar;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_screenTitle release];
    [_actionTitle release];
    [_actionHandler release];
    [_header release];
    [_headerLine release];
    [_back release];
    [_backChip release];
    [_titleLabel release];
    [_action release];
    [_actionIcon release];
    [_actionLabel release];
    [super dealloc];
}

- (void)setScreenTitle:(NSString *)title {
    if (title == _screenTitle) return;
    [_screenTitle release];
    _screenTitle = [title copy];
    self.title = _screenTitle;
    _titleLabel.text = _screenTitle;
}

- (void)setActionTitle:(NSString *)title handler:(void (^)(void))handler {
    /* the classic load path passes these ivars back into the setter */
    NSString *copiedTitle = [title copy];
    void (^copiedHandler)(void) = [handler copy];
    [_actionTitle release];
    _actionTitle = copiedTitle;
    [_actionHandler release];
    _actionHandler = copiedHandler;
    if (ExteriaThemeIsClassic()) {
        self.navigationItem.rightBarButtonItem = title ? [[[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered
                                                                                          target:self action:@selector(actionTapped)] autorelease] : nil;
        return;
    }
    _action.title = title ? title : @"";
    _action.hidden = title == nil;
}

- (void)setActionSymbol:(ExteriaSymbol)symbol label:(NSString *)label handler:(void (^)(void))handler {
    void (^copiedHandler)(void) = [handler copy];
    NSString *copiedLabel = [label copy];
    [_actionHandler release];
    _actionHandler = copiedHandler;
    [_actionLabel release];
    _actionLabel = copiedLabel;
    _actionSymbol = symbol;
    if (ExteriaThemeIsClassic()) {
        self.navigationItem.rightBarButtonItem = handler ? [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(symbol, 22, [UIColor whiteColor])
                                                                                              style:UIBarButtonItemStyleBordered target:self
                                                                                             action:@selector(actionTapped)] autorelease] : nil;
        self.navigationItem.rightBarButtonItem.accessibilityLabel = label;
        return;
    }
    [self refreshActionIcon];
}

/* the bar is built in loadView, so a symbol set before it waits there */
- (void)refreshActionIcon {
    if (!_header) return;
    if (!_actionHandler) {
        [_actionIcon removeFromSuperview];
        [_actionIcon release];
        _actionIcon = nil;
        return;
    }
    if (!_actionIcon) {
        _actionIcon = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _actionIcon.contentMode = UIViewContentModeCenter;
        [_actionIcon addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_actionIcon];
    }
    [_actionIcon setImage:ExteriaSymbolImage(_actionSymbol, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    _actionIcon.accessibilityLabel = _actionLabel;
    [self.view setNeedsLayout];
}

- (CGPoint)actionSymbolAnchor {
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    /* the classic style has its bar above the screen, so its insets already end under it; the modern bar is drawn inside */
    return CGPointMake(self.view.bounds.size.width - insets.right - 8, ExteriaThemeIsClassic() ? insets.top + 4 : insets.top + BAR_HEIGHT);
}

- (void)actionTapped {
    if (_actionHandler) _actionHandler();
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    [self buildBodyInView:root];
    if (ExteriaThemeIsClassic()) {
        self.title = _screenTitle;
        if (_actionTitle) [self setActionTitle:_actionTitle handler:_actionHandler];
        return;
    }
    _header = [[UIView alloc] init];
    _header.backgroundColor = _clearBar ? [UIColor clearColor] : ExteriaColorBar();
    [root addSubview:_header];
    _headerLine = [[UIView alloc] init];
    _headerLine.backgroundColor = ExteriaColorHairline();
    _headerLine.hidden = _clearBar;
    [_header addSubview:_headerLine];
    if (_clearBar) {
        _backChip = [[UIView alloc] init];
        _backChip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _backChip.layer.cornerRadius = 18;
        _backChip.userInteractionEnabled = NO;
        [_header addSubview:_backChip];
    }
    _back = [[ExteriaBarButton alloc] init];
    _back.chevron = YES;
    _back.title = @"";
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_back];
    /* the title may be the name of a person, with emoji, which a plain label draws as boxes */
    _titleLabel = [[ExteriaEmojiLabel alloc] init];
    _titleLabel.dropsUndrawable = YES;
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.textAlignment = ExteriaTextAlignmentCenter;
    _titleLabel.font = ExteriaFontSemibold(17);
    _titleLabel.text = _screenTitle;
    _titleLabel.hidden = _clearBar;
    [_header addSubview:_titleLabel];
    _action = [[ExteriaBarButton alloc] init];
    _action.bold = YES;
    _action.title = _actionTitle ? _actionTitle : @"";
    _action.hidden = _actionTitle == nil;
    [_action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_action];
    [self refreshActionIcon];
}

- (void)buildBodyInView:(UIView *)root {
    (void)root;
}

- (void)layoutBody:(CGRect)body {
    (void)body;
}

- (CGRect)bodyFrame {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = ExteriaThemeIsClassic() ? insets.top : insets.top + BAR_HEIGHT;
    /* the body stands in one column; a layoutBody: places what is not inside its own scroll view or grid from the body's origin, not from zero */
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_PAGE);
    return CGRectMake(column.origin.x, top, column.size.width, size.height - top);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    if (!ExteriaThemeIsClassic()) {
        CGFloat height = insets.top + BAR_HEIGHT;
        _header.frame = CGRectMake(0, 0, size.width, height);
        _headerLine.frame = CGRectMake(0, height - 1.0 / ExteriaScreenScale(), size.width, 1.0 / ExteriaScreenScale());
        CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_PAGE);
        CGFloat left = column.origin.x, edge = CGRectGetMaxX(column);
        BOOL alone = ExteriaIsDetailRoot(self);
        _back.hidden = alone;
        _backChip.hidden = alone;
        _back.frame = CGRectMake(left, insets.top, 52, BAR_HEIGHT);
        /* the chevron is drawn 14 points in from the button's edge and about 5 wide, so the disc centers on it */
        _backChip.frame = CGRectMake(left + 1, insets.top + (BAR_HEIGHT - 36) / 2, 36, 36);
        _titleLabel.frame = CGRectMake(left + 64, insets.top, column.size.width - 128, BAR_HEIGHT);
        _action.frame = CGRectMake(edge - 110, insets.top, 104, BAR_HEIGHT);
        _actionIcon.frame = CGRectMake(edge - 56, insets.top, 52, BAR_HEIGHT);
    }
    [self layoutBody:[self bodyFrame]];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }
- (BOOL)shouldAutorotate { return YES; }

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations { return ExteriaOrientationMask(); }
#pragma clang diagnostic pop

@end
