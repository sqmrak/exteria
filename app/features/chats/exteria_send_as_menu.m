#import "exteria_send_as_menu.h"

#import <QuartzCore/QuartzCore.h>
#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_session_sendas.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

@interface ExteriaSendAsMenu () {
    NSArray *_options;
    NSUInteger _selected;
    ExteriaAvatarCache *_avatars;
    void (^_handler)(NSUInteger);
    UIView *_card;
    BOOL _closing;
}
@end

@implementation ExteriaSendAsMenu
- (id)initWithOptions:(NSArray *)options selected:(NSUInteger)selected avatars:(ExteriaAvatarCache *)avatars handler:(void (^)(NSUInteger))handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _options = [options copy]; _selected = selected; _avatars = [avatars retain]; _handler = [handler copy];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIControl *outside = [[[UIControl alloc] init] autorelease];
    outside.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [outside addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:outside];
    return self;
}
- (void)dealloc {
    [_options release]; [_avatars release]; [_handler release]; [_card release];
    [super dealloc];
}
- (void)showInView:(UIView *)host anchor:(CGRect)anchor {
    self.frame = host.bounds;
    [[self.subviews objectAtIndex:0] setFrame:self.bounds];
    UIEdgeInsets insets = ExteriaSafeInsets(host);
    CGFloat width = MIN(260, MAX(1, host.bounds.size.width - insets.left - insets.right - 20));
    CGFloat bottom = MAX(insets.top + 60, CGRectGetMinY(anchor) - 8);
    CGFloat height = MIN(450, MIN(48 + _options.count * 54, bottom - insets.top - 10));
    _card = [[UIView alloc] initWithFrame:CGRectMake(MAX(insets.left + 10, MIN(CGRectGetMinX(anchor), host.bounds.size.width - insets.right - width - 10)), bottom - height, width, height)];
    _card.backgroundColor = ExteriaColorCard(); _card.layer.cornerRadius = 14;
    _card.layer.shadowColor = [UIColor blackColor].CGColor; _card.layer.shadowOpacity = ExteriaThemeIsDark() ? 0.5 : 0.22;
    _card.layer.shadowRadius = 12; _card.layer.shadowOffset = CGSizeMake(0, 4);
    UILabel *header = [[[UILabel alloc] initWithFrame:CGRectMake(16, 0, width - 32, 48)] autorelease];
    header.backgroundColor = [UIColor clearColor]; header.font = ExteriaFontSemibold(16); header.textColor = ExteriaColorAccent();
    header.text = NSLocalizedString(@"chat.sendas", nil); [_card addSubview:header];
    UIScrollView *scroll = [[[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, width, height - 48)] autorelease];
    scroll.contentSize = CGSizeMake(width, _options.count * 54); scroll.showsVerticalScrollIndicator = NO;
    scroll.clipsToBounds = YES; [_card addSubview:scroll];
    for (NSUInteger i = 0; i < _options.count; ++i) {
        ExteriaSendAsOption *option = [_options objectAtIndex:i]; ExteriaDialog *identity = option.identity;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom]; row.frame = CGRectMake(0, i * 54, width, 54); row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        ExteriaAvatarView *avatar = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(12, 7, 40, 40)] autorelease];
        avatar.circular = YES; avatar.initials = identity.initials; avatar.seed = (NSUInteger)(identity.peerId % 1000003);
        [avatar setPhoto:identity.photo cache:_avatars]; [row addSubview:avatar];
        ExteriaEmojiLabel *title = [[[ExteriaEmojiLabel alloc] initWithFrame:CGRectMake(62, 0, MAX(1, width - 100), 54)] autorelease];
        title.font = ExteriaFontMedium(16); title.textColor = ExteriaColorTitle(); title.text = identity.title; [row addSubview:title];
        if (i == _selected || option.premiumRequired) {
            ExteriaSymbol symbol = i == _selected ? ExteriaSymbolCheck : ExteriaSymbolLock;
            UIImageView *icon = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, 17, i == _selected ? ExteriaColorAccent() : ExteriaColorSecondary())] autorelease];
            icon.frame = CGRectMake(width - 30, 18, 18, 18); [row addSubview:icon];
        }
        row.accessibilityLabel = identity.title;
        row.accessibilityTraits = UIAccessibilityTraitButton | (i == _selected ? UIAccessibilityTraitSelected : 0);
        [scroll addSubview:row];
    }
    [self addSubview:_card]; [host addSubview:self];
    _card.transform = CGAffineTransformMakeScale(0.85, 0.85); _card.alpha = 0;
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}
- (void)leave:(NSInteger)index {
    if (_closing) return;
    _closing = YES; self.userInteractionEnabled = NO;
    [self retain];
    ExteriaAnimateView(_card, CGAffineTransformMakeScale(0.85, 0.85), 0, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
        if (index >= 0 && _handler) _handler((NSUInteger)index);
        [self release];
    });
}
- (void)dismiss { [self leave:-1]; }
- (void)picked:(UIButton *)button { [self leave:button.tag]; }
@end
