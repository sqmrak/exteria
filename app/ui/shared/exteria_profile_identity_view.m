#import "exteria_profile_identity_view.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_symbol.h"
#import "exteria_theme.h"

#define BADGE 38.0
#define PRESS_SCALE 0.94
#define PRESS_SECONDS 0.12
#define PROGRESS_SECONDS 0.18

@interface ExteriaProfileIdentityView () <UIGestureRecognizerDelegate> {
    ExteriaAvatarView *_avatar;
    UIControl *_avatarHit;
    UIControl *_badge;
    UIView *_progress;
    UIActivityIndicatorView *_spinner;
    ExteriaEmojiLabel *_name;
    NSString *_developerName;
    NSUInteger _marks;
    UILabel *_line;
}
@end

@implementation ExteriaProfileIdentityView

@synthesize avatar = _avatar;
@synthesize avatarHit = _avatarHit;
@synthesize badge = _badge;
@synthesize name = _name;
@synthesize line = _line;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.accent = YES;
    _avatar.userInteractionEnabled = NO;
    [self addSubview:_avatar];
    /* the dark disc and the turning ring that cover the photo while a new one goes up */
    _progress = [[UIView alloc] init];
    _progress.backgroundColor = [UIColor colorWithWhite:0 alpha:0.33];
    _progress.layer.cornerRadius = EXTERIA_IDENTITY_AVATAR / 2;
    _progress.alpha = 0;
    _progress.userInteractionEnabled = NO;
    [self addSubview:_progress];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = NO;
    [_progress addSubview:_spinner];
    _avatarHit = [[UIControl alloc] init];
    [_avatarHit addTarget:self action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_avatarHit addTarget:self action:@selector(pressUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self addSubview:_avatarHit];
    _badge = [[UIControl alloc] init];
    _badge.backgroundColor = [UIColor colorWithRed:0.17 green:0.62 blue:0.99 alpha:1];
    _badge.layer.cornerRadius = BADGE / 2;
    _badge.layer.masksToBounds = YES;
    _badge.layer.borderWidth = 3;
    _badge.layer.borderColor = ExteriaColorScreen().CGColor;
    _badge.accessibilityLabel = NSLocalizedString(@"settings.photo", nil);
    UIImageView *camera = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolGallery, 20, [UIColor whiteColor])] autorelease];
    camera.frame = CGRectMake((BADGE - 20) / 2, (BADGE - 20) / 2, 20, 20);
    camera.userInteractionEnabled = NO;
    [_badge addSubview:camera];
    [self addSubview:_badge];
    [_badge addTarget:self action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_badge addTarget:self action:@selector(pressUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.font = ExteriaFontBold(26);
    _name.textColor = ExteriaColorTitle();
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.dropsUndrawable = YES;
    [self addSubview:_name];
    UITapGestureRecognizer *hammerTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nameTapped:)] autorelease];
    hammerTap.delegate = self;
    [self addGestureRecognizer:hammerTap];
    _line = [[UILabel alloc] init];
    _line.backgroundColor = [UIColor clearColor];
    _line.font = ExteriaFontRegular(17);
    _line.textColor = ExteriaColorSecondary();
    _line.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_line];
    return self;
}

- (void)setName:(NSString *)name developer:(NSUInteger)marks {
    NSArray *entities = nil;
    _name.text = ExteriaNameWithBadges(name, 0, marks, &entities);
    _marks = marks;
    _name.entities = entities;
    [_developerName release];
    _developerName = marks ? [name copy] : nil;
}

/* only the touches over the name: the photo and the camera of this block are controls, and a recognizer over all of it would cancel their touches */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return _developerName != nil && CGRectContainsPoint(CGRectInset(_name.frame, 0, -8), [touch locationInView:self]);
}

- (void)nameTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded || !_developerName) return;
    CGPoint point = [tap locationInView:_name];
    CGFloat box = _name.bounds.size.width, text = [_name sizeThatFits:CGSizeMake(box, CGFLOAT_MAX)].width;
    CGFloat end = (box + text) / 2;
    NSUInteger mark = ExteriaMarkAtDistance(_marks, end - point.x);
    if (point.y < -8 || point.y > _name.bounds.size.height + 8 || !mark) return;
    ExteriaShowMarkNotice(_developerName, mark);
}

- (void)dealloc {
    [_developerName release];
    [_avatar release];
    [_avatarHit release];
    [_badge release];
    [_progress release];
    [_spinner release];
    [_name release];
    [_line release];
    [super dealloc];
}

/* a press shrinks the photo and the camera a little and lets go on release scale animator does */
- (void)pressDown:(UIControl *)control {
    UIView *target = control == _avatarHit ? (UIView *)_avatar : (UIView *)control;
    [UIView animateWithDuration:PRESS_SECONDS animations:^{ target.transform = CGAffineTransformMakeScale(PRESS_SCALE, PRESS_SCALE); }];
}

- (void)pressUp:(UIControl *)control {
    UIView *target = control == _avatarHit ? (UIView *)_avatar : (UIView *)control;
    [UIView animateWithDuration:PRESS_SECONDS animations:^{ target.transform = CGAffineTransformIdentity; }];
}

- (void)setBadgeRingColor:(UIColor *)color {
    _badge.layer.borderColor = color.CGColor;
}

- (void)setUploading:(BOOL)uploading {
    if (uploading) [_spinner startAnimating];
    [UIView animateWithDuration:PROGRESS_SECONDS animations:^{ _progress.alpha = uploading ? 1 : 0; } completion:^(BOOL finished) {
        (void)finished;
        if (!uploading) [_spinner stopAnimating];
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _avatar.frame = CGRectMake((width - EXTERIA_IDENTITY_AVATAR) / 2, 0, EXTERIA_IDENTITY_AVATAR, EXTERIA_IDENTITY_AVATAR);
    _avatarHit.frame = _avatar.frame;
    _progress.frame = _avatar.frame;
    _spinner.center = CGPointMake(EXTERIA_IDENTITY_AVATAR / 2, EXTERIA_IDENTITY_AVATAR / 2);
    _badge.frame = CGRectMake(CGRectGetMaxX(_avatar.frame) - BADGE + 4, CGRectGetMaxY(_avatar.frame) - BADGE + 2, BADGE, BADGE);
    _name.frame = CGRectMake(24, CGRectGetMaxY(_avatar.frame) + 22, width - 48, 34);
    _line.frame = CGRectMake(24, CGRectGetMaxY(_name.frame) + 4, width - 48, 22);
}

@end
