#import "exteria_plugin_sheet.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_platform.h"
#import "exteria_plugin_ui.h"
#import "exteria_plugins.h"
#import "exteria_string_drawing.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#include "exteria_surface.h"

/* a key on the sheet: down while touched. the dismiss pull leaves it alone, a finger that slides on the pad must not close the card */
@interface ExteriaSheetKey : UIButton {
@public
    int code;
    BOOL held;
    NSString *slot;
    /* up, down, left or right: the key is an arrow drawn as a shape, not a character of a font, which older systems show as an emoji */
    NSString *icon;
    CAShapeLayer *arrow;
}
- (BOOL)exteriaBlocksDismissPan;
@end

@implementation ExteriaSheetKey
- (void)dealloc {
    [slot release];
    [icon release];
    [super dealloc];
}
- (BOOL)exteriaBlocksDismissPan {
    return YES;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!icon) return;
    if (!arrow) {
        arrow = [CAShapeLayer layer];
        arrow.lineJoin = kCALineJoinRound;
        [self.layer addSublayer:arrow];
    }
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat reach = side * 0.2;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(0, -reach * 1.1)];
    [path addLineToPoint:CGPointMake(reach * 1.2, reach * 0.8)];
    [path addLineToPoint:CGPointMake(-reach * 1.2, reach * 0.8)];
    [path closePath];
    CGFloat turn = [icon isEqualToString:@"right"] ? 90 : ([icon isEqualToString:@"down"] ? 180 : ([icon isEqualToString:@"left"] ? 270 : 0));
    [path applyTransform:CGAffineTransformMakeRotation(turn * (CGFloat)M_PI / 180)];
    [path applyTransform:CGAffineTransformMakeTranslation(self.bounds.size.width / 2, self.bounds.size.height / 2)];
    arrow.path = path.CGPath;
    arrow.fillColor = ExteriaColorTitle().CGColor;
    arrow.strokeColor = ExteriaColorTitle().CGColor;
    arrow.lineWidth = MAX(2, side * 0.06);
}
@end

@interface ExteriaPluginSheetController : UIViewController <ExteriaDismissPanGuard> {
    NSInteger _number;
    NSString *_surface;
    NSString *_sheetTitle;
    NSString *_ended;
    CGSize _aspect;
    NSMutableArray *_keys;
    UIView *_dim;
    UIView *_card;
    UIView *_handle;
    UILabel *_titleLabel;
    UIButton *_close;
    UIView *_screen;
    UILabel *_status;
    CADisplayLink *_link;
    BOOL _ready;
    BOOL _closing;
}
- (id)initWithNumber:(NSInteger)number spec:(NSDictionary *)spec;
- (void)enter;
- (void)ready;
- (void)failWithText:(NSString *)text;
- (void)close;
@end

static NSMutableDictionary *g_sheets;
static NSInteger g_next_number;

static ExteriaPluginSheetController *sheet_for(NSInteger number) {
    return [g_sheets objectForKey:[NSNumber numberWithInteger:number]];
}

NSInteger ExteriaPluginSheetOpen(NSDictionary *spec, UIViewController *host) {
    if (!host || ![spec isKindOfClass:[NSDictionary class]] || ![[spec objectForKey:@"surface"] isKindOfClass:[NSString class]]) return 0;
    if (!g_sheets) g_sheets = [[NSMutableDictionary alloc] init];
    UIViewController *parent = host;
    while (parent.parentViewController) parent = parent.parentViewController;
    NSInteger number = ++g_next_number;
    ExteriaPluginSheetController *sheet = [[[ExteriaPluginSheetController alloc] initWithNumber:number spec:spec] autorelease];
    [g_sheets setObject:sheet forKey:[NSNumber numberWithInteger:number]];
    [parent addChildViewController:sheet];
    sheet.view.frame = parent.view.bounds;
    [parent.view addSubview:sheet.view];
    [sheet didMoveToParentViewController:parent];
    [sheet enter];
    return number;
}

void ExteriaPluginSheetReady(NSInteger number) { [sheet_for(number) ready]; }
void ExteriaPluginSheetFail(NSInteger number, NSString *text) { [sheet_for(number) failWithText:text]; }
void ExteriaPluginSheetClose(NSInteger number) { [sheet_for(number) close]; }

void ExteriaPluginSheetCloseAll(void) {
    for (ExteriaPluginSheetController *sheet in [[g_sheets allValues] copy]) [sheet close];
}

@implementation ExteriaPluginSheetController

- (id)initWithNumber:(NSInteger)number spec:(NSDictionary *)spec {
    self = [super init];
    if (!self) return nil;
    _number = number;
    _surface = [[spec objectForKey:@"surface"] copy];
    id title = [spec objectForKey:@"title"];
    _sheetTitle = [([title isKindOfClass:[NSString class]] ? title : @"") copy];
    id ended = [spec objectForKey:@"ended"];
    _ended = [([ended isKindOfClass:[NSString class]] ? ended : @"") copy];
    CGFloat width = (CGFloat)[[spec objectForKey:@"width"] doubleValue];
    CGFloat height = (CGFloat)[[spec objectForKey:@"height"] doubleValue];
    _aspect = (width > 0 && height > 0) ? CGSizeMake(width, height) : CGSizeMake(4, 3);
    _keys = [[NSMutableArray alloc] init];
    NSArray *buttons = [spec objectForKey:@"buttons"];
    if ([buttons isKindOfClass:[NSArray class]]) {
        for (NSDictionary *item in buttons) {
            if (![item isKindOfClass:[NSDictionary class]] || ![[item objectForKey:@"slot"] isKindOfClass:[NSString class]]) continue;
            ExteriaSheetKey *key = [ExteriaSheetKey buttonWithType:UIButtonTypeCustom];
            key->code = [[item objectForKey:@"key"] intValue];
            key->slot = [[item objectForKey:@"slot"] copy];
            id icon = [item objectForKey:@"icon"];
            if ([icon isKindOfClass:[NSString class]]) key->icon = [icon copy];
            id label = [item objectForKey:@"label"];
            [key setTitle:[label isKindOfClass:[NSString class]] ? label : @"" forState:UIControlStateNormal];
            [key addTarget:self action:@selector(keyDown:) forControlEvents:UIControlEventTouchDown];
            [key addTarget:self action:@selector(keyUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [_keys addObject:key];
        }
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_surface release];
    [_sheetTitle release];
    [_ended release];
    [_keys release];
    [_dim release];
    [_card release];
    [_handle release];
    [_titleLabel release];
    [_close release];
    [_screen release];
    [_status release];
    [super dealloc];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] init] autorelease];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease]];
    [root addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 28;
    _card.clipsToBounds = NO;
    [root addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(close));
    _handle = [[UIView alloc] init];
    _handle.backgroundColor = [ExteriaColorSecondary() colorWithAlphaComponent:0.4];
    _handle.layer.cornerRadius = 2;
    [_card addSubview:_handle];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 20, ExteriaColorAccent()) forState:UIControlStateNormal];
    _close.accessibilityLabel = NSLocalizedString(@"shiro.close", nil);
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_close];
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.font = ExteriaFontSemibold(15);
    _titleLabel.textAlignment = ExteriaTextAlignmentCenter;
    _titleLabel.text = _sheetTitle;
    [_card addSubview:_titleLabel];
    /* the picture is black behind the frames; the corners follow the card */
    _screen = [[UIView alloc] init];
    _screen.backgroundColor = [UIColor blackColor];
    _screen.layer.magnificationFilter = kCAFilterNearest;
    _screen.layer.contentsGravity = kCAGravityResize;
    [_card addSubview:_screen];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = [UIColor whiteColor];
    _status.font = ExteriaFontRegular(14);
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.text = NSLocalizedString(@"plugins.sheet.loading", nil);
    [_screen addSubview:_status];
    for (ExteriaSheetKey *key in _keys) {
        BOOL circle = [key->slot isEqualToString:@"a"] || [key->slot isEqualToString:@"b"];
        /* the longer words of the small keys shrink to the key instead of ending in three dots */
        key.titleLabel.font = ExteriaFontSemibold(circle ? 16 : 12);
        key.titleLabel.lineBreakMode = NSLineBreakByClipping;
        key.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
        BOOL primary = [key->slot isEqualToString:@"a"];
        key.backgroundColor = primary ? ExteriaColorAccent() : ExteriaColorField();
        [key setTitleColor:primary ? [UIColor whiteColor] : ExteriaColorTitle() forState:UIControlStateNormal];
        key.layer.masksToBounds = NO;
        [_card addSubview:key];
    }
}

- (BOOL)exteriaCanDismissByPan {
    return !_closing;
}

/* the pad follows the room below the picture: it shrinks on a small phone instead of running into the picture */
- (void)layoutKeys:(CGFloat)width top:(CGFloat)top bottom:(CGFloat)bottom {
    CGFloat room = MAX(80, bottom - top);
    CGFloat scale = MIN(1.0, room / 226.0);
    CGFloat unit = floor(52 * scale), gap = floor(4 * scale), margin = 12;
    CGFloat pad_h = 3 * unit + 2 * gap;
    CGFloat pad_top = MAX(top + floor(40 * scale), bottom - pad_h - 8);
    CGFloat pad_x = margin + unit + gap;
    CGFloat fire = floor(84 * scale), use = floor(60 * scale), strafe_w = floor(70 * scale), strafe_h = floor(38 * scale);
    NSUInteger row = 0;
    for (ExteriaSheetKey *key in _keys) {
        NSString *slot = key->slot;
        CGRect frame = CGRectZero;
        if ([slot isEqualToString:@"up"]) frame = CGRectMake(pad_x, pad_top, unit, unit);
        else if ([slot isEqualToString:@"left"]) frame = CGRectMake(margin, pad_top + unit + gap, unit, unit);
        else if ([slot isEqualToString:@"right"]) frame = CGRectMake(margin + 2 * (unit + gap), pad_top + unit + gap, unit, unit);
        else if ([slot isEqualToString:@"down"]) frame = CGRectMake(pad_x, pad_top + 2 * (unit + gap), unit, unit);
        else if ([slot isEqualToString:@"a"]) frame = CGRectMake(width - margin - fire, bottom - 8 - fire, fire, fire);
        else if ([slot isEqualToString:@"b"]) frame = CGRectMake(width - margin - fire - 10 - use, bottom - 8 - use, use, use);
        else if ([slot isEqualToString:@"c"]) frame = CGRectMake(width - margin - strafe_w, bottom - 8 - fire - 8 - strafe_h, strafe_w, strafe_h);
        else {
            frame = CGRectMake(margin + (CGFloat)row * (floor(64 * scale) + 8), top, floor(64 * scale), floor(34 * scale));
            ++row;
        }
        key.frame = frame;
        if (!key->icon) {
            [key layoutIfNeeded];
            ExteriaLabelFitToWidth(key.titleLabel, 8);
        }
        BOOL round = [slot isEqualToString:@"a"] || [slot isEqualToString:@"b"];
        key.layer.cornerRadius = round ? frame.size.width / 2 : MIN(14.0, frame.size.height / 2);
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat width = ExteriaIsPad() ? MIN(size.width, 560) : size.width;
    CGFloat top = ExteriaIsPad() ? MAX(insets.top, 24) + 16 : MAX(insets.top, 0) + 28;
    _dim.frame = self.view.bounds;
    ExteriaPlaceView(_card, CGRectMake(floor((size.width - width) / 2), top, width, size.height - top + 32));
    _handle.frame = CGRectMake(floor((width - 36) / 2), 6, 36, 4);
    _close.frame = CGRectMake(4, 12, 44, 40);
    _titleLabel.frame = CGRectMake(56, 12, width - 112, 40);
    CGFloat picture_h = floor(width * _aspect.height / _aspect.width);
    _screen.frame = CGRectMake(0, 56, width, picture_h);
    _status.frame = CGRectInset(_screen.bounds, 16, 8);
    CGFloat bottom = size.height - top - MAX(insets.bottom, 0);
    [self layoutKeys:width top:CGRectGetMaxY(_screen.frame) + 8 bottom:bottom];
}

- (CGFloat)cardTravel {
    return self.view.bounds.size.height - (_card.center.y - _card.bounds.size.height / 2);
}

- (void)enter {
    [self.view layoutIfNeeded];
    _card.transform = CGAffineTransformMakeTranslation(0, [self cardTravel]);
    _dim.alpha = 0;
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, ExteriaPopupCurve(YES), nil);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.45, ExteriaPopupCurve(YES), nil);
}

#pragma mark frames

- (void)ready {
    if (_ready || _closing) return;
    _ready = YES;
    _status.hidden = YES;
    /* 35 tics a second are the engine's own pace; every second refresh of a 60 Hz screen is about that */
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
    _link.frameInterval = 2;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)failWithText:(NSString *)text {
    [_link invalidate];
    _link = nil;
    _ready = NO;
    [self releaseKeys];
    _status.text = text;
    _status.hidden = NO;
}

- (void)step:(CADisplayLink *)link {
    (void)link;
    if (_closing) return;
    if (!exteria_surface_tick([_surface UTF8String])) {
        [_link invalidate];
        _link = nil;
        _ready = NO;
        [self releaseKeys];
        /* the plugin knows why the surface stopped, and may put the reason on the sheet */
        _status.text = _ended;
        _status.hidden = NO;
        ExteriaPluginsCallHost(@"sheet_ended", [NSArray arrayWithObject:[NSNumber numberWithInteger:_number]]);
        return;
    }
    CGImageRef image = ExteriaPluginSurfaceImage(_surface);
    if (image) {
        _screen.layer.contents = (id)image;
        CGImageRelease(image);
    }
}

#pragma mark keys

- (void)keyDown:(ExteriaSheetKey *)key {
    if (key->held) return;
    key->held = YES;
    key.alpha = 0.6;
    exteria_surface_key([_surface UTF8String], key->code, 1);
}

- (void)keyUp:(ExteriaSheetKey *)key {
    if (!key->held) return;
    key->held = NO;
    key.alpha = 1;
    exteria_surface_key([_surface UTF8String], key->code, 0);
}

/* a key that is down when the sheet goes would stay down in the engine */
- (void)releaseKeys {
    for (ExteriaSheetKey *key in _keys) [self keyUp:key];
}

#pragma mark closing

- (void)close {
    if (_closing) return;
    _closing = YES;
    [_link invalidate];
    _link = nil;
    [self releaseKeys];
    NSNumber *number = [NSNumber numberWithInteger:_number];
    ExteriaPluginsCallHost(@"sheet_closed", [NSArray arrayWithObject:number]);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, ExteriaPopupCurve(NO), nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeTranslation(0, [self cardTravel]), 1, ExteriaPopupCurve(NO), ^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        [g_sheets removeObjectForKey:number];
    });
}

@end
