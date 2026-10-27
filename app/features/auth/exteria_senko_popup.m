#import "exteria_senko_popup.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define CARD_MAX_WIDTH 340.0
#define SIDE_MARGIN 24.0
#define CARD_PAD 16.0
#define BUTTON_HEIGHT 44.0

@interface ExteriaSenkoPopup () <UIGestureRecognizerDelegate> {
    UIView *_card;
    UIImageView *_picture;
    UILabel *_title;
    UILabel *_message;
    UIButton *_button;
    NSString *_titleText;
    NSString *_messageText;
    NSString *_buttonTitle;
    void (^_dismissHandler)(void);
    BOOL _shown;
    BOOL _leaving;
}
@end

@implementation ExteriaSenkoPopup

@synthesize titleText = _titleText;
@synthesize messageText = _messageText;
@synthesize buttonTitle = _buttonTitle;
@synthesize dismissHandler = _dismissHandler;
@synthesize isShown = _shown;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 22;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = 0.3f;
    _card.layer.shadowRadius = 18;
    _card.layer.shadowOffset = CGSizeMake(0, 8);
    [self addSubview:_card];
    /* the picture is a jpeg of a photo size; the system picks the file for the screen scale */
    _picture = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"senko_meme.jpg"]];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.layer.cornerRadius = 14;
    [_card addSubview:_picture];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontBold(18);
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.numberOfLines = 0;
    [_card addSubview:_title];
    _message = [[UILabel alloc] init];
    _message.backgroundColor = [UIColor clearColor];
    _message.textColor = ExteriaColorMessage();
    _message.font = ExteriaFontRegular(14);
    _message.textAlignment = ExteriaTextAlignmentCenter;
    _message.numberOfLines = 0;
    [_card addSubview:_message];
    _button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _button.titleLabel.font = ExteriaFontBold(16);
    _button.layer.cornerRadius = BUTTON_HEIGHT / 2;
    _button.backgroundColor = ExteriaColorAccent();
    [_button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_button];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backdropTapped:)] autorelease];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    [_card release];
    [_picture release];
    [_title release];
    [_message release];
    [_button release];
    [_titleText release];
    [_messageText release];
    [_buttonTitle release];
    [_dismissHandler release];
    [super dealloc];
}

/* a tap on the card itself keeps it; only the dimmed part around it closes the window */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return !CGRectContainsPoint(_card.frame, [touch locationInView:self]);
}

- (void)backdropTapped:(UITapGestureRecognizer *)tap {
    (void)tap;
    [self dismiss];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width - 2 * SIDE_MARGIN, CARD_MAX_WIDTH);
    CGFloat inner = width - 2 * CARD_PAD;
    UIImage *image = _picture.image;
    CGFloat pictureHeight = image && image.size.width > 0 ? ceil(inner * image.size.height / image.size.width) : inner;
    _title.text = _titleText;
    _message.text = _messageText;
    [_button setTitle:_buttonTitle forState:UIControlStateNormal];
    CGSize title = [_title sizeThatFits:CGSizeMake(inner, 400)];
    CGSize message = [_message sizeThatFits:CGSizeMake(inner, 400)];
    CGFloat y = CARD_PAD;
    _picture.frame = CGRectMake(CARD_PAD, y, inner, pictureHeight);
    y += pictureHeight + 14;
    _title.frame = CGRectMake(CARD_PAD, y, inner, ceil(title.height));
    y += ceil(title.height) + 6;
    _message.frame = CGRectMake(CARD_PAD, y, inner, ceil(message.height));
    y += ceil(message.height) + 16;
    _button.frame = CGRectMake(CARD_PAD, y, inner, BUTTON_HEIGHT);
    y += BUTTON_HEIGHT + CARD_PAD;
    /* the card is kept at its size while it springs, so only a fresh layout moves it */
    if (!_leaving) {
        CGAffineTransform held = _card.transform;
        _card.transform = CGAffineTransformIdentity;
        _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - y) / 2), width, y);
        _card.transform = held;
    }
}

- (void)showInView:(UIView *)host {
    if (_shown) return;
    _shown = YES;
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    BOOL still = ExteriaReduceMotionEnabled();
    self.alpha = still ? 1 : 0;
    _card.transform = still ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.86f, 0.86f);
    if (still) return;
    /* the spring call of ios 7 does not exist on ios 5 and 6, so the card grows a little past its size and settles back */
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 1;
        _card.transform = CGAffineTransformMakeScale(1.03f, 1.03f);
    } completion:^(BOOL done) {
        (void)done;
        [UIView animateWithDuration:0.12 animations:^{ _card.transform = CGAffineTransformIdentity; }];
    }];
}

- (void)dismiss {
    if (!_shown || _leaving) return;
    _leaving = YES;
    [self retain];
    void (^finish)(void) = ^{
        [self removeFromSuperview];
        _shown = NO;
        void (^handler)(void) = [_dismissHandler retain];
        if (handler) handler();
        [handler release];
        [self autorelease];
    };
    if (ExteriaReduceMotionEnabled()) {
        finish();
        return;
    }
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
    } completion:^(BOOL done) {
        (void)done;
        finish();
    }];
}

@end
