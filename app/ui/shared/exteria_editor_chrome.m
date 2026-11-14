#import "exteria_editor_chrome.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#import "exteria_animation.h"
#import "exteria_classic_chrome.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define PANEL_RADIUS 22

@interface ExteriaEditorPanel () {
    UIView *_effect;
    UIView *_content;
    BOOL _floating;
}
@end

@implementation ExteriaEditorPanel
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    if (ExteriaThemeIsClassic()) {
        /* the old system draws the bar flat and edge to edge: a toolbar is the background and the subviews stand on it */
        UIToolbar *bar = [[[UIToolbar alloc] init] autorelease];
        ExteriaClassicStyleToolbar(bar);
        bar.userInteractionEnabled = NO;
        _effect = [bar retain];
        _content = self;
        [self addSubview:_effect];
        return self;
    }
    _floating = YES;
    self.layer.cornerRadius = PANEL_RADIUS;
    self.clipsToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.1].CGColor;
    Class effect = NSClassFromString(@"UIBlurEffect"), view = NSClassFromString(@"UIVisualEffectView");
    if (effect && view) {
        /* UIBlurEffectStyleDark */
        id blur = ((id (*)(id, SEL, NSInteger))objc_msgSend)(effect, NSSelectorFromString(@"effectWithStyle:"), 2);
        id made = ((id (*)(id, SEL, id))objc_msgSend)([view alloc], NSSelectorFromString(@"initWithEffect:"), blur);
        if (made) {
            _effect = (UIView *)made;
            _content = [_effect valueForKey:@"contentView"];
        }
    }
    if (!_effect) {
        /* before ios 8 there is no live blur, and a plate that is nearly opaque keeps the icons readable over any picture */
        _effect = [[UIView alloc] init];
        _effect.backgroundColor = [UIColor colorWithRed:0.09 green:0.09 blue:0.1 alpha:0.94];
        _content = _effect;
    }
    [self addSubview:_effect];
    return self;
}
- (void)dealloc {
    [_effect release];
    [super dealloc];
}
- (UIView *)content { return _content; }
- (BOOL)floating { return _floating; }
- (void)layoutSubviews {
    [super layoutSubviews];
    _effect.frame = self.bounds;
    if (_floating) self.layer.cornerRadius = MIN(self.bounds.size.height / 2, ExteriaIsPad() ? 26 : PANEL_RADIUS);
}
@end

/* the editors fill an ipad, so the marks and the captions grow with the screen */
#define TOOL_ICON (ExteriaIsPad() ? 30 : 24)
#define PILL_ICON (ExteriaIsPad() ? 22 : 18)
#define ROUND_ICON (ExteriaIsPad() ? 26 : 22)

@interface ExteriaEditorButton () {
    ExteriaEditorButtonStyle _style;
    ExteriaSymbol _symbol;
    BOOL _hasSymbol;
    BOOL _lit;
    BOOL _classic;
    UIView *_plate;
    UIImageView *_icon;
    UILabel *_caption;
}
@end

@implementation ExteriaEditorButton
@synthesize lit = _lit;
- (id)initWithStyle:(ExteriaEditorButtonStyle)style symbol:(ExteriaSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _style = style;
    _classic = ExteriaThemeIsClassic();
    _symbol = symbol;
    _hasSymbol = YES;
    self.backgroundColor = [UIColor clearColor];
    _plate = [[UIView alloc] init];
    _plate.userInteractionEnabled = NO;
    [self addSubview:_plate];
    _icon = [[UIImageView alloc] init];
    _icon.userInteractionEnabled = NO;
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.userInteractionEnabled = NO;
    _caption.textAlignment = (NSTextAlignment)ExteriaTextAlignmentCenter;
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.minimumFontSize = 8;
    _caption.font = style == ExteriaEditorButtonTool ? ExteriaFontMedium(ExteriaIsPad() ? 12 : 10) : ExteriaFontSemibold(ExteriaIsPad() ? 17 : 15);
    [self addSubview:_caption];
    _caption.text = title;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = title;
    ExteriaAttachBounce(self, style == ExteriaEditorButtonTool ? 0.1 : 0.06);
    [self refreshAnimated:NO];
    return self;
}
- (id)initWithStyle:(ExteriaEditorButtonStyle)style title:(NSString *)title {
    self = [self initWithStyle:style symbol:ExteriaSymbolCheck title:title];
    if (self) {
        _hasSymbol = NO;
        [self refreshAnimated:NO];
    }
    return self;
}
- (void)dealloc {
    [_plate release];
    [_icon release];
    [_caption release];
    [super dealloc];
}
- (NSString *)title { return _caption.text; }
- (void)setTitle:(NSString *)title { [self setTitle:title animated:NO]; }
- (void)setTitle:(NSString *)title animated:(BOOL)animated {
    if (title == _caption.text || [title isEqualToString:_caption.text]) return;
    if (animated && self.window && !ExteriaReduceMotionEnabled()) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.18;
        [_caption.layer addAnimation:fade forKey:@"exteria.caption"];
    }
    _caption.text = title;
    self.accessibilityLabel = title;
    [self setNeedsLayout];
}
- (UIColor *)contentColor {
    if (_style == ExteriaEditorButtonAccent && !_classic) return [UIColor whiteColor];
    if (_lit) return _classic ? [UIColor colorWithRed:0.35 green:0.65 blue:1 alpha:1] : ExteriaMixedColor(ExteriaColorAccent(), [UIColor whiteColor], 0.4);
    return [UIColor colorWithWhite:1 alpha:0.94];
}
- (UIColor *)plateColor {
    if (_classic) return [UIColor clearColor];
    if (_style == ExteriaEditorButtonAccent) return ExteriaColorAccent();
    if (_lit) return [ExteriaColorAccent() colorWithAlphaComponent:0.34];
    if (_style == ExteriaEditorButtonRound || _style == ExteriaEditorButtonPill) return [UIColor colorWithWhite:1 alpha:0.12];
    return [UIColor clearColor];
}
- (void)refreshAnimated:(BOOL)animated {
    UIColor *color = [self contentColor];
    CGFloat side = _style == ExteriaEditorButtonTool ? TOOL_ICON : (_style == ExteriaEditorButtonRound ? ROUND_ICON : PILL_ICON);
    _icon.image = _hasSymbol ? ExteriaSymbolImage(_symbol, side, color) : nil;
    _caption.textColor = color;
    UIColor *plate = [self plateColor];
    void (^apply)(void) = ^{ _plate.backgroundColor = plate; };
    if (animated && self.window && !ExteriaReduceMotionEnabled()) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];
    else apply();
    [self setNeedsLayout];
}
- (void)setLit:(BOOL)lit { [self setLit:lit animated:NO]; }
- (void)setLit:(BOOL)lit animated:(BOOL)animated {
    if (_lit == lit) return;
    _lit = lit;
    self.accessibilityTraits = UIAccessibilityTraitButton | (lit ? UIAccessibilityTraitSelected : 0);
    [self refreshAnimated:animated];
    if (animated && lit) ExteriaEditorPop(_icon);
}
- (void)setSymbol:(ExteriaSymbol)symbol animated:(BOOL)animated {
    if (_hasSymbol && _symbol == symbol) return;
    UIImageView *old = nil;
    if (animated && self.window && !ExteriaReduceMotionEnabled() && _icon.image) {
        old = [[UIImageView alloc] initWithImage:_icon.image];
        old.frame = _icon.frame;
        old.contentMode = UIViewContentModeCenter;
        [self insertSubview:old aboveSubview:_icon];
    }
    _symbol = symbol;
    _hasSymbol = YES;
    [self refreshAnimated:NO];
    if (old) {
        ExteriaAnimateEnter(_icon, CGAffineTransformMakeScale(0.4, 0.4), 0, EXTERIA_MOTION_WOBBLE);
        ExteriaAnimateView(old, CGAffineTransformMakeScale(0.4, 0.4), 0, EXTERIA_MOTION_DISMISS, ^(BOOL finished) { [old removeFromSuperview]; });
        [old release];
    }
}
- (void)playQuarterTurn {
    if (self.window) ExteriaAnimateEnter(_icon, CGAffineTransformMakeRotation((CGFloat)(-M_PI_2)), 1, EXTERIA_MOTION_WOBBLE);
}
- (void)playFlip {
    if (self.window) ExteriaAnimateEnter(_icon, CGAffineTransformMakeScale(-1, 1), 1, EXTERIA_MOTION_WOBBLE);
}
/* the parts dim, not the button, so a card that fades its buttons in and out and a button that is disabled do not fight over one alpha */
- (void)refreshDim {
    CGFloat alpha = (self.enabled ? 1 : 0.38) * (self.highlighted ? 0.7 : 1);
    _icon.alpha = _caption.alpha = _plate.alpha = alpha;
}
- (void)setEnabled:(BOOL)enabled {
    BOOL changed = enabled != self.enabled;
    [super setEnabled:enabled];
    if (!changed) return;
    if (self.window && !ExteriaReduceMotionEnabled()) [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ [self refreshDim]; } completion:nil];
    else [self refreshDim];
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self refreshDim];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    BOOL hasTitle = _caption.text.length > 0;
    _icon.transform = CGAffineTransformIdentity;
    if (_style == ExteriaEditorButtonTool) {
        _plate.frame = CGRectInset(bounds, 3, 3);
        _plate.layer.cornerRadius = 14;
        CGFloat caption = ExteriaIsPad() ? 16 : 13, stack = TOOL_ICON + (hasTitle ? caption + 1 : 0);
        CGFloat top = floor((h - stack) / 2);
        _icon.frame = CGRectMake(floor((w - TOOL_ICON) / 2), top, TOOL_ICON, TOOL_ICON);
        _caption.frame = CGRectMake(2, top + TOOL_ICON + 1, w - 4, caption);
        return;
    }
    _plate.frame = bounds;
    _plate.layer.cornerRadius = h / 2;
    if (_style == ExteriaEditorButtonRound) {
        _icon.frame = CGRectMake(floor((w - ROUND_ICON) / 2), floor((h - ROUND_ICON) / 2), ROUND_ICON, ROUND_ICON);
        _caption.frame = CGRectZero;
        return;
    }
    CGFloat textWidth = hasTitle ? MIN(w - 16, ceil([_caption.text sizeWithFont:_caption.font].width)) : 0;
    CGFloat iconWidth = _hasSymbol ? PILL_ICON : 0, gap = _hasSymbol && hasTitle ? 6 : 0;
    CGFloat x = floor((w - iconWidth - gap - textWidth) / 2);
    _icon.frame = CGRectMake(x, floor((h - PILL_ICON) / 2), iconWidth, PILL_ICON);
    _caption.frame = CGRectMake(x + iconWidth + gap, 0, textWidth, h);
}
@end

CGFloat ExteriaEditorScale(void) { return ExteriaIsPad() ? 1.25 : 1; }

void ExteriaEditorPresent(UIView *view, BOOL shown, CGFloat distance) {
    view.userInteractionEnabled = shown;
    view.accessibilityElementsHidden = !shown;
    CGAffineTransform away = CGAffineTransformConcat(CGAffineTransformMakeScale(0.97, 0.97), CGAffineTransformMakeTranslation(0, distance));
    ExteriaAnimateView(view, shown ? CGAffineTransformIdentity : away, shown ? 1 : 0, shown ? EXTERIA_MOTION_WOBBLE : EXTERIA_MOTION_DISMISS, nil);
}

void ExteriaEditorRise(NSArray *views, CGFloat distance, NSTimeInterval step) {
    NSTimeInterval delay = 0;
    for (UIView *view in views) {
        CGAffineTransform from = CGAffineTransformMakeTranslation(0, distance);
        view.transform = from;
        view.alpha = 0;
        ExteriaAnimateViewAfter(view, CGAffineTransformIdentity, 1, EXTERIA_MOTION_WOBBLE, delay, nil);
        delay += step;
    }
}

void ExteriaEditorPop(UIView *view) {
    ExteriaAnimateEnter(view, CGAffineTransformMakeScale(0.82, 0.82), 1, EXTERIA_MOTION_WOBBLE);
}
