#import "exteria_shiro_home_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_platform.h"
#import "exteria_shiro_fox_field.h"
#import "exteria_shiro_shimmer_label.h"
#import "exteria_shiro_style.h"
#import "exteria_theme.h"

/* the extra large corner of the Material shape scale */
#define CARD_CORNER 28.0

@interface ExteriaShiroHomeView () {
    ExteriaShiroFoxField *_foxes;
    ExteriaShiroShimmerLabel *_wordmark;
    UILabel *_tagline;
    ExteriaShiroPowerButton *_power;
    UILabel *_stateLabel;
    UIControl *_card;
    UILabel *_cardTitle;
    UILabel *_cardSubtitle;
}
@end

@implementation ExteriaShiroHomeView

@synthesize power = _power;
@synthesize stateLabel = _stateLabel;
@synthesize cardTitle = _cardTitle;
@synthesize cardSubtitle = _cardSubtitle;
@synthesize card = _card;

static UILabel *ExteriaShiroLabel(UIView *host, int alignment) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    [host addSubview:label];
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _foxes = [[ExteriaShiroFoxField alloc] initWithFrame:self.bounds spriteName:@"shiro_fox"];
    _foxes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_foxes];
    _wordmark = [[ExteriaShiroShimmerLabel alloc] init];
    _wordmark.text = @"shiro";
    [self addSubview:_wordmark];
    _tagline = [ExteriaShiroLabel(self, ExteriaTextAlignmentCenter) retain];
    _tagline.text = @"by sqmrak :3";
    _power = [[ExteriaShiroPowerButton alloc] init];
    [self addSubview:_power];
    _stateLabel = [ExteriaShiroLabel(self, ExteriaTextAlignmentCenter) retain];
    _card = [[UIControl alloc] init];
    _card.userInteractionEnabled = NO;
    [self addSubview:_card];
    _cardTitle = [ExteriaShiroLabel(_card, ExteriaTextAlignmentLeft) retain];
    _cardSubtitle = [ExteriaShiroLabel(_card, ExteriaTextAlignmentLeft) retain];
    [self applyTheme];
    return self;
}

- (void)dealloc {
    [_wordmark release];
    [_tagline release];
    [_power release];
    [_stateLabel release];
    [_foxes release];
    [_card release];
    [_cardTitle release];
    [_cardSubtitle release];
    [super dealloc];
}

- (void)applyTheme {
    [_wordmark applyTheme];
    _tagline.textColor = ExteriaShiroColorOnSurfaceVariant();
    _stateLabel.textColor = ExteriaShiroColorOnSurface();
    _cardTitle.textColor = ExteriaShiroColorOnSurface();
    _cardSubtitle.textColor = ExteriaShiroColorOnSurfaceVariant();
    _card.backgroundColor = ExteriaShiroColorSurfaceContainer();
    _card.layer.cornerRadius = CARD_CORNER;
    [_power applyTheme];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    BOOL pad = ExteriaIsPad();
    BOOL wide = size.width > size.height && size.height < 420;
    BOOL compact = !pad && !wide && size.height <= 440;
    CGFloat margin = pad ? 28 : (size.width <= 320 ? 14 : 18);
    CGFloat columnWidth = MIN(size.width - 2 * margin, pad ? 480 : 440);
    CGFloat columnX = floor((size.width - columnWidth) / 2);
    CGFloat bottom = pad ? 24 : 14;

    CGFloat wordSize = pad ? 58 : ((compact || wide) ? 32 : 44);
    _wordmark.font = ExteriaShiroFontDisplay(wordSize);
    CGFloat wordHeight = ceil(wordSize * 1.2);
    _wordmark.frame = CGRectMake(margin, 4, size.width - 2 * margin, wordHeight);
    CGFloat tagSize = pad ? 17 : (compact || wide ? 12 : 14);
    _tagline.font = ExteriaShiroFontBody(tagSize, NO);
    CGFloat tagHeight = ceil(tagSize * 1.4);
    _tagline.frame = CGRectMake(margin, 4 + wordHeight - 4, size.width - 2 * margin, tagHeight);
    CGFloat top = CGRectGetMaxY(_tagline.frame) + (compact ? 4 : 10);

    CGFloat cardHeight = pad ? 78 : (compact || wide ? 58 : 68);
    CGFloat stateSize = pad ? 26 : (compact || wide ? 19 : 22);
    _stateLabel.font = ExteriaShiroFontBody(stateSize, YES);
    CGFloat stateHeight = ceil(stateSize * 1.3);

    if (wide) {
        /* a phone on its side has no height for a stacked screen: the control takes the left half, the texts the right */
        CGFloat leftWidth = floor((size.width - 2 * margin) * 0.44);
        CGFloat available = size.height - top - bottom;
        CGFloat side = MAX(80, MIN(available, leftWidth));
        _power.frame = CGRectMake(margin + floor((leftWidth - side) / 2), top + floor((available - side) / 2), side, side);
        CGFloat x = margin + leftWidth + 14;
        CGFloat width = size.width - margin - x;
        CGFloat block = stateHeight + 12 + cardHeight;
        CGFloat y = MAX(top, top + floor((available - block) / 2));
        _stateLabel.frame = CGRectMake(x, y, width, stateHeight);
        _card.frame = CGRectMake(x, y + stateHeight + 12, width, cardHeight);
    } else {
        CGFloat y = size.height - bottom - cardHeight;
        _card.frame = CGRectMake(columnX, y, columnWidth, cardHeight);
        y -= (compact ? 8 : 14) + stateHeight;
        _stateLabel.frame = CGRectMake(columnX, y, columnWidth, stateHeight);
        CGFloat available = y - (compact ? 4 : 10) - top;
        CGFloat side = MIN(available, columnWidth * (pad ? 0.7 : 0.82));
        side = MAX(90, MIN(side, pad ? 380 : 320));
        _power.frame = CGRectMake(floor((size.width - side) / 2), top + floor((available - side) / 2), side, side);
    }

    CGFloat titleSize = cardHeight >= 66 ? 17 : 15;
    _cardTitle.font = ExteriaShiroFontBody(titleSize, YES);
    _cardSubtitle.font = ExteriaShiroFontBody(titleSize - 3, NO);
    CGFloat titleHeight = ceil(titleSize * 1.3), subHeight = ceil((titleSize - 3) * 1.35);
    /* a plate with no second line centers its title */
    CGFloat textTop = floor((cardHeight - titleHeight - ([_cardSubtitle.text length] ? subHeight : 0)) / 2);
    CGFloat textWidth = _card.bounds.size.width - 40;
    _cardTitle.frame = CGRectMake(20, textTop, textWidth, titleHeight);
    _cardSubtitle.frame = CGRectMake(20, textTop + titleHeight, textWidth, subHeight);
}

@end
