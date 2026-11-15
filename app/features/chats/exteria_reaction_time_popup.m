#import "exteria_reaction_time_popup.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"
#import "exteria_person.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"

#define CARD_HEIGHT 64.0
#define CARD_GAP 8.0
#define CARD_WIDTH_MAX 360.0
#define REACTION_SIZE 96.0

@interface ExteriaReactionTimePopup () {
    ExteriaEmojiLabel *_reaction;
    NSMutableArray *_cards;
}
@end

@implementation ExteriaReactionTimePopup

+ (void)presentReaction:(ExteriaReaction *)reaction entries:(NSArray *)entries avatars:(ExteriaAvatarCache *)avatars inView:(UIView *)host {
    if (!host || !entries.count) return;
    ExteriaReactionTimePopup *popup = [[[ExteriaReactionTimePopup alloc] initWithFrame:host.bounds] autorelease];
    popup.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [popup fillReaction:reaction entries:entries avatars:avatars];
    popup.alpha = 0;
    [host addSubview:popup];
    [UIView animateWithDuration:0.18 animations:^{ popup.alpha = 1; }];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)] autorelease]];
    _cards = [[NSMutableArray alloc] init];
    self.accessibilityViewIsModal = YES;
    return self;
}

- (void)dealloc {
    [_reaction release];
    [_cards release];
    [super dealloc];
}

- (void)fillReaction:(ExteriaReaction *)reaction entries:(NSArray *)entries avatars:(ExteriaAvatarCache *)avatars {
    _reaction = [[ExteriaEmojiLabel alloc] init];
    _reaction.backgroundColor = [UIColor clearColor];
    _reaction.text = reaction.emoji;
    _reaction.entities = reaction.displayEntities;
    _reaction.font = ExteriaFontRegular(REACTION_SIZE * 0.8);
    _reaction.textAlignment = ExteriaTextAlignmentCenter;
    [self addSubview:_reaction];
    for (NSDictionary *entry in entries) {
        ExteriaPerson *person = [entry objectForKey:@"person"];
        int32_t date = [[entry objectForKey:@"date"] intValue];
        UIView *card = [[[UIView alloc] init] autorelease];
        card.backgroundColor = ExteriaColorField();
        card.layer.cornerRadius = 18;
        ExteriaAvatarView *face = [[[ExteriaAvatarView alloc] init] autorelease];
        face.circular = YES;
        face.tag = 1;
        face.seed = (NSUInteger)(llabs(person.userId) % 1000003);
        face.initials = person.initials;
        face.deleted = person.deleted;
        face.layer.cornerRadius = 22;
        [face setPhoto:person.photo cache:avatars];
        [card addSubview:face];
        UILabel *name = [[[UILabel alloc] init] autorelease];
        name.tag = 2;
        name.backgroundColor = [UIColor clearColor];
        name.font = ExteriaFontSemibold(17);
        name.textColor = ExteriaColorTitle();
        name.text = person.name.length ? person.name : NSLocalizedString(@"chat.someone", nil);
        [card addSubview:name];
        UIImageView *mark = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolHeartOutline, 15, ExteriaColorSecondary())] autorelease];
        mark.tag = 3;
        [card addSubview:mark];
        UILabel *time = [[[UILabel alloc] init] autorelease];
        time.tag = 4;
        time.backgroundColor = [UIColor clearColor];
        time.font = ExteriaFontRegular(14);
        time.textColor = ExteriaColorSecondary();
        time.text = ExteriaMediaTimeText(date);
        [card addSubview:time];
        [self addSubview:card];
        [_cards addObject:card];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat stack = _cards.count * CARD_HEIGHT + (_cards.count ? _cards.count - 1 : 0) * CARD_GAP;
    CGFloat block = REACTION_SIZE + 28 + stack;
    CGFloat top = MAX(40, (height - block) / 2);
    _reaction.frame = CGRectMake(0, top, width, REACTION_SIZE + 12);
    CGFloat cardWidth = MIN(width - 32, CARD_WIDTH_MAX);
    CGFloat y = top + REACTION_SIZE + 28;
    for (UIView *card in _cards) {
        card.frame = CGRectMake(floor((width - cardWidth) / 2), y, cardWidth, CARD_HEIGHT);
        [card viewWithTag:1].frame = CGRectMake(12, (CARD_HEIGHT - 44) / 2, 44, 44);
        [card viewWithTag:2].frame = CGRectMake(68, 10, cardWidth - 80, 24);
        UIView *mark = [card viewWithTag:3];
        mark.frame = CGRectMake(68, 38, 15, 15);
        [card viewWithTag:4].frame = CGRectMake(68 + 15 + 5, 35, cardWidth - 68 - 20 - 12, 20);
        y += CARD_HEIGHT + CARD_GAP;
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    }];
}

@end
