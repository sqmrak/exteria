#import "exteria_channel_card.h"
#import "exteria_string_drawing.h"
#import "exteria_animation.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"
#import "exteria_theme.h"
#import "exteria_time.h"

#define CARD_HEIGHT 92.0

@interface ExteriaChannelCard () {
    UILabel *_kind;
    UILabel *_chip;
    ExteriaAvatarView *_picture;
    ExteriaEmojiLabel *_title;
    ExteriaEmojiLabel *_last;
    UILabel *_date;
}
@end

@implementation ExteriaChannelCard

+ (CGFloat)height { return CARD_HEIGHT; }

static UILabel *ExteriaChannelLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    return label;
}

/* the name and the last post are written by other people, so they take the app's own emoji pictures */
static ExteriaEmojiLabel *ExteriaChannelEmojiLabel(UIColor *color, UIFont *font) {
    ExteriaEmojiLabel *label = [[ExteriaEmojiLabel alloc] init];
    label.textColor = color;
    label.font = font;
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.03);
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 14;
    _kind = ExteriaChannelLabel(ExteriaColorAccent(), ExteriaFontSemibold(13), ExteriaTextAlignmentLeft);
    _kind.text = NSLocalizedString(@"profile.channel.kind", nil);
    _chip = ExteriaChannelLabel(ExteriaColorAccent(), ExteriaFontMedium(12), ExteriaTextAlignmentCenter);
    _chip.backgroundColor = ExteriaColorField();
    _chip.layer.cornerRadius = 10;
    _chip.layer.masksToBounds = YES;
    _picture = [[ExteriaAvatarView alloc] init];
    _picture.circular = YES;
    _title = ExteriaChannelEmojiLabel(ExteriaColorTitle(), ExteriaFontSemibold(17));
    _last = ExteriaChannelEmojiLabel(ExteriaColorSecondary(), ExteriaFontRegular(15));
    _date = ExteriaChannelLabel(ExteriaColorSecondary(), ExteriaFontRegular(13), ExteriaTextAlignmentRight);
    ExteriaLabelFitToWidth(_date, 9);
    for (UIView *view in [NSArray arrayWithObjects:_kind, _chip, _picture, _title, _last, _date, nil]) [self addSubview:view];
    return self;
}

- (void)dealloc {
    [_kind release];
    [_chip release];
    [_picture release];
    [_title release];
    [_last release];
    [_date release];
    [super dealloc];
}

- (void)configureWithChannel:(ExteriaPersonalChannel *)channel avatars:(ExteriaAvatarCache *)avatars {
    _chip.text = [NSString stringWithFormat:NSLocalizedString(@"profile.channel.followers", nil), (int)channel.subscribers];
    _picture.initials = channel.dialog.initials;
    _picture.seed = channel.dialog.avatarSeed;
    [_picture setPhoto:channel.dialog.photo cache:avatars];
    _title.text = channel.dialog.title;
    _last.text = channel.lastText;
    _date.text = channel.lastDate ? ExteriaListTimeText(channel.lastDate) : @"";
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGSize kind = [_kind sizeThatFits:CGSizeMake(200, 18)];
    _kind.frame = CGRectMake(16, 10, kind.width, 20);
    CGSize chip = [_chip sizeThatFits:CGSizeMake(width, 20)];
    _chip.frame = CGRectMake(16 + kind.width + 8, 10, chip.width + 16, 20);
    _picture.frame = CGRectMake(14, 38, 44, 44);
    _title.frame = CGRectMake(70, 36, width - 70 - 70, 22);
    _last.frame = CGRectMake(70, 60, width - 70 - 16, 20);
    _date.frame = CGRectMake(width - 66, 38, 52, 18);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1;
}

@end
