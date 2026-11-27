#import "exteria_toggle.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_theme.h"

#define TOGGLE_WIDTH 52.0
#define TOGGLE_HEIGHT 32.0
#define TOGGLE_THUMB 24.0
#define TOGGLE_INSET 4.0

@interface ExteriaToggle () {
    UIView *_track;
    UIView *_thumb;
    /* the classic theme shows the switch of the system and the two views above stay hidden */
    UISwitch *_system;
    BOOL _on;
}
@end

@implementation ExteriaToggle

+ (CGSize)controlSize {
    if (!ExteriaThemeIsClassic()) return CGSizeMake(TOGGLE_WIDTH, TOGGLE_HEIGHT);
    /* 94 points wide before ios 7 and 51 from it, so the size is asked of the system */
    UISwitch *probe = [[UISwitch alloc] init];
    CGSize size = probe.frame.size;
    [probe release];
    return size;
}

- (id)initWithFrame:(CGRect)frame {
    (void)frame;
    self = [super initWithFrame:CGRectMake(0, 0, TOGGLE_WIDTH, TOGGLE_HEIGHT)];
    if (!self) return nil;
    _track = [[UIView alloc] initWithFrame:CGRectMake(0, 0, TOGGLE_WIDTH, TOGGLE_HEIGHT)];
    _track.userInteractionEnabled = NO;
    _track.layer.cornerRadius = TOGGLE_HEIGHT / 2;
    [self addSubview:_track];
    _thumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, TOGGLE_THUMB, TOGGLE_THUMB)];
    _thumb.userInteractionEnabled = NO;
    _thumb.layer.cornerRadius = TOGGLE_THUMB / 2;
    _thumb.center = CGPointMake(TOGGLE_INSET + TOGGLE_THUMB / 2, TOGGLE_HEIGHT / 2);
    [self addSubview:_thumb];
    _system = [[UISwitch alloc] init];
    [_system addTarget:self action:@selector(systemChanged) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_system];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:ExteriaThemeDidChangeNotification object:nil];
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_track release];
    [_thumb release];
    [_system release];
    [super dealloc];
}

- (CGSize)sizeThatFits:(CGSize)size {
    (void)size;
    return [ExteriaToggle controlSize];
}

- (BOOL)classic {
    return ExteriaThemeIsClassic();
}

/* the thumb stands at the left and is moved by its transform: small when off, full size and 20 points to the right when on */
- (CGAffineTransform)thumbTransform {
    return _on ? CGAffineTransformMakeTranslation(TOGGLE_WIDTH - TOGGLE_HEIGHT, 0) : CGAffineTransformMakeScale(0.667, 0.667);
}

/* the colors of the track and the thumb for the state; read again whenever the palette changes */
- (void)paintParts {
    BOOL classic = [self classic];
    _track.hidden = classic;
    _thumb.hidden = classic;
    _system.hidden = !classic;
    if (classic) {
        /* ios 5 and 6 tint the lit track, ios 7 does it through onTintColor */
        if ([_system respondsToSelector:@selector(setOnTintColor:)]) _system.onTintColor = ExteriaColorAccent();
        _system.on = _on;
        return;
    }
    _track.backgroundColor = _on ? ExteriaColorAccent() : ExteriaColorField();
    _track.layer.borderWidth = _on ? 0 : 2;
    _track.layer.borderColor = ExteriaColorSecondary().CGColor;
    _thumb.backgroundColor = _on ? [UIColor whiteColor] : ExteriaColorSecondary();
}

- (void)applyTheme {
    CGSize size = [ExteriaToggle controlSize];
    if (!CGSizeEqualToSize(self.bounds.size, size)) self.bounds = CGRectMake(0, 0, size.width, size.height);
    [self paintParts];
    self.accessibilityValue = _on ? @"1" : @"0";
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!_thumb.layer.animationKeys.count) _thumb.transform = [self thumbTransform];
    [CATransaction commit];
}

- (void)themeChanged {
    [self applyTheme];
}

/* the system switch takes its own touches, so this control takes none while it shows */
- (void)layoutSubviews {
    [super layoutSubviews];
    _system.frame = CGRectMake(0, 0, _system.frame.size.width, _system.frame.size.height);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    _system.enabled = enabled;
}

- (BOOL)isOn {
    return _on;
}

- (void)setOn:(BOOL)on {
    [self setOn:on animated:NO];
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    if (on == _on && !animated) {
        [self applyTheme];
        return;
    }
    _on = on;
    self.accessibilityValue = on ? @"1" : @"0";
    if ([self classic]) {
        [_system setOn:on animated:animated && self.window != nil];
        return;
    }
    if (animated && self.window) {
        ExteriaAnimateView(_thumb, [self thumbTransform], 1, EXTERIA_MOTION_WOBBLE, nil);
        [UIView animateWithDuration:0.2 animations:^{ [self paintParts]; }];
    } else {
        [self applyTheme];
    }
}

- (void)tapped {
    /* a tap on the system switch is its own event, this control sees it as well and must not turn it back */
    if ([self classic]) return;
    [self setOn:!_on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)systemChanged {
    _on = _system.on;
    self.accessibilityValue = _on ? @"1" : @"0";
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end
