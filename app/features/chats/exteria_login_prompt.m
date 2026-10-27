#import "exteria_login_prompt.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_classic_chrome.h"
#import "exteria_gift_screen.h"
#import "exteria_platform.h"
#import "exteria_session_logins.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define CARD_MARGIN 14.0
#define CARD_PAD 14.0
#define BUTTON_HEIGHT 38.0
#define REFRESH_GAP 30.0

@interface ExteriaLoginPrompt () {
    ExteriaSession *_session;
    void (^_changed)(void);
    ExteriaWeakReference *_weak;
    NSMutableArray *_logins;
    UIView *_view;
    UIImageView *_plate;
    BOOL _classic;
    UILabel *_title;
    UILabel *_message;
    UIButton *_yes;
    UIButton *_no;
    NSDate *_askedAt;
    BOOL _asking;
    BOOL _answering;
}
@end

@implementation ExteriaLoginPrompt

@synthesize view = _view;

- (id)initWithSession:(ExteriaSession *)session changed:(void (^)(void))changed {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _changed = [changed copy];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _logins = [[NSMutableArray alloc] init];
    _classic = ExteriaThemeIsClassic();
    _view = [[UIView alloc] init];
    _view.hidden = YES;
    if (_classic) {
        /* the image supplies the rim and the card color of the classic theme */
        _view.backgroundColor = [UIColor clearColor];
        _plate = [[UIImageView alloc] initWithImage:ExteriaClassicPlateImage()];
        [_view addSubview:_plate];
    } else {
        _view.backgroundColor = ExteriaColorCard();
        _view.layer.cornerRadius = 14;
    }
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontSemibold(15);
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.numberOfLines = 0;
    _title.text = NSLocalizedString(@"login.prompt.title", nil);
    [_view addSubview:_title];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = ExteriaColorSecondary();
    _message.font = ExteriaFontRegular(13);
    _message.textAlignment = ExteriaTextAlignmentCenter;
    _message.numberOfLines = 0;
    [_view addSubview:_message];
    _yes = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_yes setTitle:NSLocalizedString(@"login.prompt.yes", nil) forState:UIControlStateNormal];
    [_yes setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_yes setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    _yes.titleLabel.font = ExteriaFontSemibold(15);
    [_yes addTarget:self action:@selector(confirm) forControlEvents:UIControlEventTouchUpInside];
    [_view addSubview:_yes];
    _no = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_no setTitle:NSLocalizedString(@"login.prompt.no", nil) forState:UIControlStateNormal];
    [_no setTitleColor:ExteriaColorBadgeRed() forState:UIControlStateNormal];
    [_no setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    _no.titleLabel.font = ExteriaFontSemibold(15);
    [_no addTarget:self action:@selector(terminate) forControlEvents:UIControlEventTouchUpInside];
    [_view addSubview:_no];
    if (_classic) [self styleClassic];
    return self;
}

/* the card follows the theme while its buttons keep the engraved classic labels */
- (void)styleClassic {
    UIColor *ink = ExteriaColorTitle();
    UIColor *pale = [UIColor colorWithWhite:ExteriaThemeIsDark() ? 0 : 1 alpha:0.4];
    _title.textColor = ink;
    _title.font = [UIFont boldSystemFontOfSize:16];
    _message.textColor = ExteriaColorSecondary();
    _message.font = [UIFont systemFontOfSize:13];
    for (UILabel *label in [NSArray arrayWithObjects:_title, _message, nil]) {
        label.shadowColor = pale;
        label.shadowOffset = CGSizeMake(0, 1);
    }
    UIButton *buttons[2] = {_yes, _no};
    ExteriaClassicGloss colors[2] = {ExteriaClassicGlossSlate, ExteriaClassicGlossRed};
    for (int i = 0; i < 2; ++i) {
        UIButton *button = buttons[i];
        [button setBackgroundImage:ExteriaClassicGlossButtonImage(colors[i], NO) forState:UIControlStateNormal];
        [button setBackgroundImage:ExteriaClassicGlossButtonImage(colors[i], YES) forState:UIControlStateHighlighted];
        [button setBackgroundImage:ExteriaClassicGlossButtonImage(colors[i], YES) forState:UIControlStateDisabled];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateDisabled];
        [button setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
        button.titleLabel.shadowOffset = CGSizeMake(0, -1);
        button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumFontSize = 10;
    }
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_changed release];
    [_logins release];
    [_view release];
    [_plate release];
    [_title release];
    [_message release];
    [_yes release];
    [_no release];
    [_askedAt release];
    [super dealloc];
}

#pragma mark content

/* "iPhone4,1, Frankfurt am Main, Germany" */
- (NSString *)describe:(ExteriaUnconfirmedLogin *)login {
    return login.place.length ? [NSString stringWithFormat:@"%@, %@", login.device, login.place] : login.device;
}

- (void)show {
    ExteriaUnconfirmedLogin *login = _logins.count ? [_logins objectAtIndex:0] : nil;
    BOOL was = !_view.hidden;
    _view.hidden = login == nil;
    if (login) _message.text = [NSString stringWithFormat:NSLocalizedString(@"login.prompt.message", nil), [self describe:login]];
    _yes.enabled = _no.enabled = !_answering;
    if (was != !_view.hidden && _changed) _changed();
    [_view setNeedsLayout];
    if (_changed && login) _changed();
}

- (CGFloat)contentHeightForWidth:(CGFloat)width {
    CGFloat inner = width - 2 * CARD_PAD;
    CGSize title = [_title sizeThatFits:CGSizeMake(inner, 200)];
    CGSize message = [_message sizeThatFits:CGSizeMake(inner, 300)];
    return 10 + title.height + 4 + message.height + 4 + BUTTON_HEIGHT + 4;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    if (!_logins.count) return 0;
    return [self contentHeightForWidth:width - 2 * CARD_MARGIN];
}

/* the owner of the list lays the card out through this, since the card sits inside a header it also sizes */
- (void)layoutInWidth:(CGFloat)width atY:(CGFloat)y {
    CGFloat cardWidth = width - 2 * CARD_MARGIN;
    CGFloat height = [self contentHeightForWidth:cardWidth];
    _view.frame = CGRectMake(CARD_MARGIN, y, cardWidth, height);
    _plate.frame = _view.bounds;
    CGFloat inner = cardWidth - 2 * CARD_PAD;
    CGSize title = [_title sizeThatFits:CGSizeMake(inner, 200)];
    CGSize message = [_message sizeThatFits:CGSizeMake(inner, 300)];
    _title.frame = CGRectMake(CARD_PAD, 10, inner, title.height);
    _message.frame = CGRectMake(CARD_PAD, 10 + title.height + 4, inner, message.height);
    CGFloat buttonsY = height - BUTTON_HEIGHT - 4;
    /* glossy buttons are separate pills with a gap, the flat ones are two halves of one row */
    CGFloat gap = _classic ? 8 : 0;
    CGFloat buttonHeight = _classic ? BUTTON_HEIGHT - 6 : BUTTON_HEIGHT;
    CGFloat buttonY = _classic ? buttonsY + 3 : buttonsY;
    _yes.frame = CGRectMake(CARD_PAD, buttonY, (inner - gap) / 2, buttonHeight);
    _no.frame = CGRectMake(CARD_PAD + (inner + gap) / 2, buttonY, (inner - gap) / 2, buttonHeight);
}

#pragma mark server

- (void)refresh {
    if (_asking || _answering) return;
    if (_askedAt && -[_askedAt timeIntervalSinceNow] < REFRESH_GAP) return;
    _asking = YES;
    [_askedAt release];
    _askedAt = [[NSDate date] retain];
    ExteriaWeakReference *weak = _weak;
    [self retain];
    [_session loadUnconfirmedLogins:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        ExteriaLoginPrompt *prompt = weak.target;
        if (!prompt) return;
        prompt->_asking = NO;
        if (!items) {
            /* no card is better than a wrong one; the next look tries again */
            NSLog(@"exteria: the logins to confirm did not load: %@", errorName);
            return;
        }
        if (prompt->_answering) return;
        [prompt->_logins setArray:items];
        [prompt show];
    }];
}

/* the card goes on to the next login once the server took the answer; a failed answer leaves it and says so */
- (void)answer:(BOOL)confirm {
    if (!_logins.count || _answering) return;
    ExteriaUnconfirmedLogin *login = [[_logins objectAtIndex:0] retain];
    _answering = YES;
    [self show];
    ExteriaWeakReference *weak = _weak;
    [self retain];
    void (^done)(NSString *) = ^(NSString *errorName) {
        [self autorelease];
        ExteriaLoginPrompt *prompt = weak.target;
        [login autorelease];
        if (!prompt) return;
        prompt->_answering = NO;
        if (errorName) {
            NSLog(@"exteria: the answer about the login was not taken: %@", errorName);
            [prompt show];
            /* the server refuses to touch other sessions until this one is a day old */
            NSString *shown = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                : [errorName hasPrefix:@"FRESH_"] ? NSLocalizedString(@"login.prompt.fresh", nil)
                : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName];
            ExteriaGiftAlert(nil, shown);
            return;
        }
        [prompt->_logins removeObjectIdenticalTo:login];
        [prompt show];
        if (!confirm) ExteriaGiftAlert(nil, NSLocalizedString(@"login.prompt.ended", nil));
    };
    if (confirm) [_session confirmLogin:login completion:done];
    else [_session terminateLogin:login completion:done];
}

- (void)confirm { [self answer:YES]; }
- (void)terminate { [self answer:NO]; }

@end
