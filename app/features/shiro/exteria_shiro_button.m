#import "exteria_shiro_button.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_shiro_controller.h"
#import "exteria_shiro_style.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

@interface ExteriaShiroButton () {
    ExteriaShiro *_shiro;
    ExteriaWeakReference *_host;
}
@end

@implementation ExteriaShiroButton

- (id)initWithShiro:(ExteriaShiro *)shiro host:(UIViewController *)host {
    self = [super initWithFrame:CGRectMake(0, 0, 54, 28)];
    if (!self) return nil;
    _shiro = [shiro retain];
    _host = [[ExteriaWeakReference referenceTo:host] retain];
    [self setTitle:NSLocalizedString(@"shiro.button", nil) forState:UIControlStateNormal];
    self.accessibilityLabel = NSLocalizedString(@"shiro.button.accessibility", nil);
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1.5;
    self.titleLabel.font = ExteriaShiroFontBody(14, YES);
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:ExteriaShiroStateDidChangeNotification object:shiro];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:ExteriaThemeDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_host clear];
    [_host release];
    [_shiro release];
    [super dealloc];
}

- (CGSize)preferredSize {
    return CGSizeMake(54, 28);
}

- (void)refresh {
    ExteriaShiroState state = _shiro.state;
    BOOL lit = state == ExteriaShiroStateUp;
    BOOL working = state == ExteriaShiroStateRegistering || state == ExteriaShiroStateConnecting;
    UIColor *accent = ExteriaColorAccent();
    UIColor *quiet = [accent colorWithAlphaComponent:0.5f];
    /* the accent of the theme: solid while the tunnel carries the traffic, an outline while it dials, a paler outline when it is off or has failed */
    self.backgroundColor = lit ? accent : [UIColor clearColor];
    self.layer.borderColor = (lit || working ? accent : quiet).CGColor;
    [self setTitleColor:lit ? [UIColor whiteColor] : (working ? accent : quiet) forState:UIControlStateNormal];
}

- (void)open {
    UIViewController *host = _host.target;
    if (host) [ExteriaShiroController presentWithShiro:_shiro from:host];
}

@end

@interface ExteriaShiroBarItem () {
    ExteriaShiro *_shiro;
    ExteriaWeakReference *_host;
}
@end

@implementation ExteriaShiroBarItem

- (id)initWithShiro:(ExteriaShiro *)shiro host:(UIViewController *)host {
    self = [super initWithTitle:NSLocalizedString(@"shiro.button", nil) style:UIBarButtonItemStyleBordered target:nil action:NULL];
    if (!self) return nil;
    _shiro = [shiro retain];
    _host = [[ExteriaWeakReference referenceTo:host] retain];
    self.target = self;
    self.action = @selector(open);
    self.accessibilityLabel = NSLocalizedString(@"shiro.button.accessibility", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:ExteriaShiroStateDidChangeNotification object:shiro];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_host clear];
    [_host release];
    [_shiro release];
    [super dealloc];
}

- (void)refresh {
    switch (_shiro.state) {
    case ExteriaShiroStateUp: self.tintColor = [UIColor colorWithRed:0.20f green:0.52f blue:0.24f alpha:1]; break;
    case ExteriaShiroStateRegistering:
    case ExteriaShiroStateConnecting: self.tintColor = [UIColor colorWithRed:0.80f green:0.55f blue:0.08f alpha:1]; break;
    default: self.tintColor = nil; break;
    }
}

- (void)open {
    UIViewController *host = _host.target;
    if (host) [ExteriaShiroController presentWithShiro:_shiro from:host];
}

@end
