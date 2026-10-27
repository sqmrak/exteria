#import "exteria_reaction_picker.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_blur.h"
#import "exteria_custom_emoji_picker.h"
#import "exteria_emoji_label.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define CARD_MAX_WIDTH 344.0
#define CARD_MIN_HEIGHT 260.0
#define CARD_EDGE 12.0
#define ANCHOR_GAP 8.0
#define CELL_TARGET 44.0
#define CELL_MIN_COLUMNS 5
#define SIDE_PAD 6.0
#define SECTION_HEIGHT 30.0

@interface ExteriaReactionPicker () <ExteriaCustomEmojiPickerDelegate> {
    UIControl *_dim;
    UIView *_card;
    UILabel *_status;
    UIButton *_retry;
    UIScrollView *_scroll;
    UILabel *_customHeader;
    ExteriaCustomEmojiPicker *_sets;
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    BOOL _premium;
    NSArray *_reactions;
    NSArray *_buttons;
    /* index of the first custom reaction in _reactions, which lists the ordinary ones first */
    NSUInteger _customStart;
    CGRect _anchorRect;
    BOOL _anchorOutgoing;
    BOOL _opened;
    BOOL _below;
    ExteriaWeakReference *_weak;
    BOOL _closing;
}
@end

@implementation ExteriaReactionPicker

@synthesize pickHandler = _pickHandler;
@synthesize customPickHandler = _customPickHandler;
@synthesize cancelHandler = _cancelHandler;
@synthesize retryHandler = _retryHandler;
@synthesize anchorRect = _anchorRect;
@synthesize anchorOutgoing = _anchorOutgoing;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.accessibilityViewIsModal = YES;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _dim = [[UIControl alloc] initWithFrame:self.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    [_dim addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dim];
    BOOL classic = ExteriaThemeIsClassic();
    _card = [[UIView alloc] init];
    _card.backgroundColor = classic ? ExteriaColorBar() : ExteriaColorCard();
    _card.layer.cornerRadius = classic ? 12 : 18;
    _card.layer.shadowColor = [UIColor blackColor].CGColor;
    _card.layer.shadowOpacity = 0.3f;
    _card.layer.shadowRadius = 12;
    _card.layer.shadowOffset = CGSizeMake(0, 4);
    [self addSubview:_card];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.font = ExteriaFontRegular(15);
    _status.numberOfLines = 0;
    _status.textAlignment = ExteriaTextAlignmentCenter;
    [_card addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _retry.titleLabel.font = ExteriaFontMedium(16);
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:_retry];
    _scroll = [[UIScrollView alloc] init];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.layer.cornerRadius = _card.layer.cornerRadius;
    _scroll.clipsToBounds = YES;
    [_card addSubview:_scroll];
    [self setLoading];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _sets.delegate = nil;
    [_dim release];
    [_card release];
    [_status release];
    [_retry release];
    [_scroll release];
    [_customHeader release];
    [_sets release];
    [_session release];
    [_media release];
    [_reactions release];
    [_buttons release];
    [_pickHandler release];
    [_customPickHandler release];
    [_cancelHandler release];
    [_retryHandler release];
    [super dealloc];
}

/* the custom emoji sets share the card with the reactions: they own the strip at the top, whose first tab is the reactions themselves */
- (void)attachSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media premium:(BOOL)premium {
    [_session release];
    _session = [session retain];
    [_media release];
    _media = [media retain];
    _premium = premium;
    _sets.showsLocks = !premium;
    if (_sets || !session || !media) return;
    _sets = [[ExteriaCustomEmojiPicker alloc] initWithSession:session media:media];
    _sets.delegate = self;
    _sets.leadingSymbol = ExteriaSymbolSmiley;
    _sets.leadingLabel = NSLocalizedString(@"chat.reactions", nil);
    _sets.showsLocks = !premium;
    _sets.hasLeading = YES;
    /* the strip goes under the reactions' own content in z order, so the grid of the reactions can lie over the empty body of the picker */
    [_card insertSubview:_sets belowSubview:_scroll];
    [self setNeedsLayout];
}

- (void)customEmojiPickerDidSelectLeading:(ExteriaCustomEmojiPicker *)picker {
    (void)picker;
    _scroll.hidden = !_buttons.count;
    _status.hidden = _buttons.count > 0;
}

- (void)customEmojiPickerDidSelectSet:(ExteriaCustomEmojiPicker *)picker {
    (void)picker;
    _scroll.hidden = YES;
    _status.hidden = YES;
    _retry.hidden = YES;
}

- (void)customEmojiPicker:(ExteriaCustomEmojiPicker *)picker didPickEmoji:(ExteriaCustomEmojiDocument *)emoji {
    (void)picker;
    if (_closing || !emoji) return;
    void (^handler)(ExteriaCustomEmojiDocument *) = [_customPickHandler copy];
    if (handler) handler(emoji);
    [handler release];
}

- (void)cancel {
    if (_closing) return;
    void (^handler)(void) = [_cancelHandler copy];
    if (handler) handler();
    [handler release];
}

- (void)retry {
    if (_closing) return;
    void (^handler)(void) = [_retryHandler copy];
    if (handler) handler();
    [handler release];
}

- (void)showMessage:(NSString *)text retry:(BOOL)retry {
    _status.text = text;
    _status.hidden = NO;
    _retry.hidden = !retry;
    _scroll.hidden = YES;
    [self setNeedsLayout];
}

- (void)setLoading {
    [self showMessage:NSLocalizedString(@"chat.reaction.loading", nil) retry:NO];
}

- (void)setFailure:(NSString *)error {
    [self showMessage:error retry:YES];
}

/* the card opens from the corner of it that is nearest the message, the way the menu does */
- (CGPoint)cornerAnchor {
    return CGPointMake(_anchorOutgoing ? 1 : 0, _below ? 0 : 1);
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || _closing || _opened) return;
    _opened = YES;
    /* the picture of the screen is taken with the picker itself out of it, so the blur holds the chat alone */
    self.hidden = YES;
    UIView *blur = ExteriaBlurBackdrop(self.superview, self.bounds);
    self.hidden = NO;
    if (blur) {
        blur.userInteractionEnabled = NO;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_dim insertSubview:blur atIndex:0];
    }
    [_sets prepare];
    [self layoutIfNeeded];
    _dim.alpha = 0;
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
    CGPoint corner = [self cornerAnchor];
    CGRect frame = _card.frame;
    _card.layer.anchorPoint = corner;
    _card.layer.position = CGPointMake(frame.origin.x + frame.size.width * corner.x, frame.origin.y + frame.size.height * corner.y);
    _card.alpha = 0;
    _card.transform = CGAffineTransformMakeScale(0.8, 0.8);
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
}

- (void)dismissAnimated:(BOOL)animated {
    if (_closing) return;
    _closing = YES;
    self.userInteractionEnabled = NO;
    if (!animated) {
        [self removeFromSuperview];
        return;
    }
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeScale(0.8, 0.8), 0, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}

#pragma mark grid

- (UIButton *)buttonForReaction:(ExteriaReaction *)reaction index:(NSUInteger)index {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)index;
    button.layer.cornerRadius = 12;
    if (reaction.chosen) button.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.28];
    button.accessibilityLabel = reaction.displayText;
    button.accessibilityTraits = UIAccessibilityTraitButton | (reaction.chosen ? UIAccessibilityTraitSelected : 0);
    [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(cellDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(cellUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.text = reaction.displayText;
    label.entities = reaction.displayEntities;
    label.font = ExteriaFontRegular(31);
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.userInteractionEnabled = NO;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.frame = button.bounds;
    [button addSubview:label];
    return button;
}

- (void)cellDown:(UIButton *)button {
    button.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.2];
}

- (void)cellUp:(UIButton *)button {
    ExteriaReaction *reaction = (NSUInteger)button.tag < _reactions.count ? [_reactions objectAtIndex:(NSUInteger)button.tag] : nil;
    button.backgroundColor = reaction.chosen ? [ExteriaColorAccent() colorWithAlphaComponent:0.28] : [UIColor clearColor];
}

- (void)picked:(UIButton *)button {
    if ((NSUInteger)button.tag >= _reactions.count) return;
    /* picking closes the overlay and releases its views before this touch handler returns */
    ExteriaReaction *reaction = [[_reactions objectAtIndex:(NSUInteger)button.tag] retain];
    void (^handler)(ExteriaReaction *) = [_pickHandler copy];
    if (!_closing && handler) handler(reaction);
    [handler release];
    [reaction release];
}

- (void)setReactions:(NSArray *)reactions {
    for (UIView *button in _buttons) [button removeFromSuperview];
    [_buttons release];
    _buttons = nil;
    [_reactions release];
    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:reactions.count];
    for (ExteriaReaction *reaction in reactions) if (reaction.row.kind == EXTERIA_REACTION_EMOJI) [ordered addObject:reaction];
    _customStart = ordered.count;
    for (ExteriaReaction *reaction in reactions) if (reaction.row.kind != EXTERIA_REACTION_EMOJI) [ordered addObject:reaction];
    _reactions = [ordered copy];
    NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:ordered.count];
    for (NSUInteger i = 0; i < ordered.count; ++i) {
        UIButton *button = [self buttonForReaction:[ordered objectAtIndex:i] index:i];
        [_scroll addSubview:button];
        [buttons addObject:button];
    }
    _buttons = [buttons copy];
    if (_customStart < ordered.count && !_customHeader) {
        _customHeader = [[UILabel alloc] init];
        _customHeader.backgroundColor = [UIColor clearColor];
        _customHeader.font = ExteriaFontSemibold(14);
        _customHeader.textColor = ExteriaColorSecondary();
        _customHeader.text = NSLocalizedString(@"chat.reaction.section.custom", nil);
        [_scroll addSubview:_customHeader];
    }
    _customHeader.hidden = _customStart >= ordered.count;
    _status.text = NSLocalizedString(@"chat.reaction.disabled", nil);
    _status.hidden = ordered.count > 0;
    _retry.hidden = YES;
    _scroll.hidden = !ordered.count;
    [self setNeedsLayout];
}

/* places the cells in rows of equal squares and returns the height of the grid; the custom ones start under their own header */
- (CGFloat)layoutGridInWidth:(CGFloat)width {
    NSUInteger columns = MAX((NSUInteger)CELL_MIN_COLUMNS, (NSUInteger)floor(width / CELL_TARGET));
    CGFloat cell = floor(width / (CGFloat)columns);
    CGFloat left = floor((width - cell * (CGFloat)columns) / 2);
    CGFloat y = 0;
    for (NSUInteger section = 0; section < 2; ++section) {
        NSUInteger first = section == 0 ? 0 : _customStart;
        NSUInteger end = section == 0 ? _customStart : _buttons.count;
        if (first >= end) continue;
        if (section == 1) {
            _customHeader.frame = CGRectMake(left + 6, y + 4, width - 12, SECTION_HEIGHT - 4);
            y += SECTION_HEIGHT;
        }
        for (NSUInteger i = first; i < end; ++i) {
            NSUInteger n = i - first;
            UIView *button = [_buttons objectAtIndex:i];
            button.frame = CGRectMake(left + cell * (CGFloat)(n % columns), y + cell * (CGFloat)(n / columns), cell, cell);
        }
        y += cell * (CGFloat)((end - first + columns - 1) / columns);
    }
    return y;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    UIEdgeInsets insets = ExteriaSafeInsets(self);
    CGFloat width = MIN(CARD_MAX_WIDTH, size.width - 2 * CARD_EDGE);
    /* nearly square, as the card of the original client is, and short enough to leave the bars of the screen free */
    CGFloat room = size.height - insets.top - insets.bottom - 2 * CARD_EDGE;
    CGFloat height = MAX(CARD_MIN_HEIGHT, MIN(floor(width * 1.12), room));
    CGFloat x, y;
    BOOL centered = CGRectIsEmpty(_anchorRect);
    if (centered) {
        x = floor((size.width - width) / 2);
        y = floor((size.height - height) / 2);
        _below = YES;
    } else {
        x = _anchorOutgoing ? CGRectGetMaxX(_anchorRect) - width : CGRectGetMinX(_anchorRect);
        y = CGRectGetMaxY(_anchorRect) + ANCHOR_GAP;
        _below = YES;
        if (y + height > size.height - insets.bottom - CARD_EDGE) {
            CGFloat above = CGRectGetMinY(_anchorRect) - ANCHOR_GAP - height;
            if (above >= insets.top + CARD_EDGE) {
                y = above;
                _below = NO;
            } else {
                y = MAX(insets.top + CARD_EDGE, size.height - insets.bottom - CARD_EDGE - height);
            }
        }
    }
    x = MIN(MAX(CARD_EDGE + insets.left, x), size.width - CARD_EDGE - insets.right - width);
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(x, y, width, height);
    _card.transform = held;
    CGFloat strip = _sets ? [ExteriaCustomEmojiPicker stripHeight] : 0;
    _sets.frame = _card.bounds;
    CGFloat bodyHeight = height - strip;
    CGFloat gridWidth = width - 2 * SIDE_PAD;
    CGFloat gridHeight = _buttons.count ? [self layoutGridInWidth:gridWidth] : 0;
    _scroll.frame = CGRectMake(SIDE_PAD, strip, gridWidth, bodyHeight);
    _scroll.contentSize = CGSizeMake(gridWidth, gridHeight);
    _scroll.bounces = gridHeight > bodyHeight;
    _status.frame = CGRectMake(16, strip, width - 32, bodyHeight - (_retry.hidden ? 0 : 40));
    _retry.frame = CGRectMake(16, height - 40, width - 32, 40);
}

@end
