#import "exteria_reactions_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_dust_effect.h"
#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_platform.h"
#import "exteria_emoji_label.h"
#import "exteria_person.h"
#import "exteria_text_layout.h"
#import "exteria_classic_chrome.h"
#import "exteria_theme.h"
#import "exteria_imported_theme.h"
#include "exteria_reaction_layout.h"

/* the plate, label and faces are laid out separately, so UIKit cannot resize the classic plate independently of its contents */
#define LABEL_TAG 7401
#define FACE_TAG 7402
#define PLATE_TAG 7403
#define FACE_SIZE 20.0
/* each face covers a third of the one before it, as the people of a call or a group do */
#define FACE_STEP 14.0
#define FACE_GAP 4.0

/* a chip with faces shows the people in the place of the number */
static NSString *ExteriaReactionText(ExteriaReaction *reaction, BOOL counts) {
    if (counts && !reaction.faces.count) return [NSString stringWithFormat:@"%@ %d", reaction.displayText, reaction.count];
    return reaction.displayText;
}

static CGFloat ExteriaFacesWidth(ExteriaReaction *reaction, BOOL counts) {
    NSUInteger faces = counts ? reaction.faces.count : 0;
    return faces ? FACE_GAP + FACE_SIZE + (CGFloat)(faces - 1) * FACE_STEP : 0;
}

/* the chips follow the size of the message text, as the text of exteraGram's chips does, down to three quarters and up to a third more */
static CGFloat ExteriaReactionScale(void) {
    return MAX(0.75f, MIN(1.35f, (CGFloat)ExteriaChatTextSize() / (CGFloat)ExteriaChatDefaultTextSize()));
}

static CGFloat ExteriaReactionFrames(NSArray *reactions, CGFloat width, BOOL counts, exteria_rect *frames) {
    memset(frames, 0, sizeof(*frames) * EXTERIA_REACTION_CATALOG_MAX);
    if (reactions.count > EXTERIA_REACTION_CATALOG_MAX || width < 44 * ExteriaReactionScale()) return 0;
    double widths[EXTERIA_REACTION_CATALOG_MAX], height = 0;
    for (NSUInteger i = 0; i < reactions.count; ++i) {
        NSString *text = ExteriaReactionText([reactions objectAtIndex:i], counts);
        ExteriaTextLayout *layout = [ExteriaTextLayout layoutForText:text entities:[[reactions objectAtIndex:i] displayEntities] font:ExteriaFontMedium(16 * ExteriaReactionScale())
            color:ExteriaColorTitle() linkColor:ExteriaColorAccent() width:MAX(44, width - 20) maxLines:1 flush:0];
        widths[i] = ceil(layout.size.width) + 20 * ExteriaReactionScale() + ExteriaFacesWidth([reactions objectAtIndex:i], counts);
    }
    exteria_status status = exteria_reaction_layout_compute(width, ExteriaReactionScale(), widths, reactions.count, frames,
        EXTERIA_REACTION_CATALOG_MAX, &height);
    if (status != EXTERIA_OK) {
        NSLog(@"exteria: reaction layout rejected: %s", exteria_status_name(status));
        return 0;
    }
    return (CGFloat)height;
}

CGFloat ExteriaReactionsHeight(NSArray *reactions, CGFloat width, BOOL counts) {
    exteria_rect frames[EXTERIA_REACTION_CATALOG_MAX];
    return ExteriaReactionFrames(reactions, width, counts, frames);
}

CGFloat ExteriaReactionsMetrics(NSArray *reactions, CGFloat width, BOOL counts, CGFloat *used, CGFloat *lastRow) {
    exteria_rect frames[EXTERIA_REACTION_CATALOG_MAX];
    CGFloat height = ExteriaReactionFrames(reactions, width, counts, frames);
    CGFloat widest = 0, lastY = 0, last = 0;
    NSUInteger count = MIN(reactions.count, (NSUInteger)EXTERIA_REACTION_CATALOG_MAX);
    for (NSUInteger i = 0; i < count; ++i) {
        widest = MAX(widest, (CGFloat)(frames[i].x + frames[i].width));
        lastY = MAX(lastY, (CGFloat)frames[i].y);
    }
    for (NSUInteger i = 0; i < count; ++i) {
        if (frames[i].y == lastY) last = MAX(last, (CGFloat)(frames[i].x + frames[i].width));
    }
    if (used) *used = ceil(widest);
    if (lastRow) *lastRow = ceil(last);
    return height;
}

@interface ExteriaReactionsView () {
    /* where the chips that stay stood before this change, by key; the next layout moves them from there */
    NSMutableDictionary *_moveFrom;
    NSUInteger _ghosts;
    NSMutableDictionary *_labelFrom;
}
@end

@implementation ExteriaReactionsView

@synthesize pickHandler = _pickHandler;
@synthesize alignRight = _alignRight;
@synthesize inBubble = _inBubble;
@synthesize outgoing = _outgoing;
@synthesize avatars = _avatars;

- (BOOL)animatingOut {
    return _ghosts > 0;
}

- (void)dealloc {
    [_moveFrom release];
    [_labelFrom release];
    [_reactions release];
    [_buttons release];
    [_pickHandler release];
    [super dealloc];
}

- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts {
    [self setReactions:reactions counts:counts animated:NO];
}

/* the look of a chip over a bubble: our bubble is the accent color */
- (UIColor *)chipColorChosen:(BOOL)chosen {
    if (!_inBubble) return chosen ? ExteriaColorAccent() : ExteriaColorCard();
    UIColor *imported = ExteriaImportedThemeColor(_outgoing ? (chosen ? "chat.message.outgoing.bubble.withWp.reactionActiveBg" : "chat.message.outgoing.bubble.withWp.reactionInactiveBg")
                                                        : (chosen ? "chat.message.incoming.bubble.withWp.reactionActiveBg" : "chat.message.incoming.bubble.withWp.reactionInactiveBg"));
    if (imported) return imported;
    if (_outgoing) return chosen ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.22];
    return chosen ? ExteriaColorAccent() : [ExteriaColorAccent() colorWithAlphaComponent:0.16];
}

- (UIColor *)chipTextColorChosen:(BOOL)chosen {
    if (!_inBubble) return chosen ? [UIColor whiteColor] : ExteriaColorTitle();
    UIColor *imported = ExteriaImportedThemeColor(_outgoing ? (chosen ? "chat.message.outgoing.bubble.withWp.reactionActiveFg" : "chat.message.outgoing.bubble.withWp.reactionInactiveFg")
                                                        : (chosen ? "chat.message.incoming.bubble.withWp.reactionActiveFg" : "chat.message.incoming.bubble.withWp.reactionInactiveFg"));
    if (imported && CGColorGetAlpha(imported.CGColor) > 0) return imported;
    if (_outgoing) return chosen ? ExteriaColorAccent() : [UIColor whiteColor];
    return chosen ? [UIColor whiteColor] : ExteriaColorAccent();
}

/* the reactions of ReactionsLayoutInBubble */
/* the person asked for reduced motion, or switched the transitions off in the power settings, which UIKit animations obey and layer animations do not */
static BOOL ExteriaReactionStill(void) {
    return ExteriaReduceMotionEnabled() || ![UIView areAnimationsEnabled];
}

/* ChatListItemAnimator runs the whole change of a cell on one progress, 250 ms on DEFAULT_INTERPOLATOR */
#define CHANGE_SECONDS 0.25

static CAMediaTimingFunction *ExteriaReactionCurve(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.19919473f :0.010644531f :0.27920937f :0.91025391f];
}

/* ReactionsLayoutInBubble.draw, ANIMATION_TYPE_IN: a chip that comes scales from half its size to its size while its alpha goes from 0 to 1 */
- (void)growButton:(UIView *)button {
    if (ExteriaReactionStill()) return;
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = [NSNumber numberWithFloat:0.5f];
    scale.toValue = [NSNumber numberWithFloat:1];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:0];
    fade.toValue = [NSNumber numberWithFloat:1];
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:scale, fade, nil];
    group.duration = CHANGE_SECONDS;
    group.timingFunction = ExteriaReactionCurve();
    [button.layer addAnimation:group forKey:@"exteria.reaction.grow"];
}

/* the count of a chip is an AnimatedTextDrawable with moveAmplitude 0.4, 320 ms, EASE_OUT_QUINT: the old words leave and the new ones come in from the
   side the count moved to, each by 0.4 of the line height, while they fade */
- (void)rollLabelOfButton:(UIView *)button from:(UIImage *)old up:(BOOL)up {
    if (ExteriaReactionStill()) return;
    UIView *label = [button viewWithTag:LABEL_TAG];
    if (!label) return;
    CGFloat amplitude = 0.4f * ((ExteriaEmojiLabel *)label).font.lineHeight;
    CAMediaTimingFunction *quint = [CAMediaTimingFunction functionWithControlPoints:0.22f :1 :0.36f :1];
    CGFloat sign = up ? 1 : -1;
    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeIn.fromValue = [NSNumber numberWithFloat:0];
    fadeIn.toValue = [NSNumber numberWithFloat:1];
    CABasicAnimation *moveIn = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    moveIn.fromValue = [NSNumber numberWithFloat:(float)(sign * amplitude)];
    moveIn.toValue = [NSNumber numberWithFloat:0];
    CAAnimationGroup *enter = [CAAnimationGroup animation];
    enter.animations = [NSArray arrayWithObjects:fadeIn, moveIn, nil];
    enter.duration = 0.32;
    enter.timingFunction = quint;
    [label.layer addAnimation:enter forKey:@"exteria.reaction.roll"];
    if (!old) return;
    UIImageView *gone = [[[UIImageView alloc] initWithImage:old] autorelease];
    gone.frame = label.frame;
    gone.userInteractionEnabled = NO;
    [button insertSubview:gone aboveSubview:label];
    CABasicAnimation *fadeOut = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeOut.fromValue = [NSNumber numberWithFloat:1];
    fadeOut.toValue = [NSNumber numberWithFloat:0];
    CABasicAnimation *moveOut = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    moveOut.fromValue = [NSNumber numberWithFloat:0];
    moveOut.toValue = [NSNumber numberWithFloat:(float)(-sign * amplitude)];
    CAAnimationGroup *leave = [CAAnimationGroup animation];
    leave.animations = [NSArray arrayWithObjects:fadeOut, moveOut, nil];
    leave.duration = 0.32;
    leave.timingFunction = quint;
    leave.fillMode = kCAFillModeForwards;
    leave.removedOnCompletion = NO;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ [gone removeFromSuperview]; }];
    [gone.layer addAnimation:leave forKey:@"exteria.reaction.roll.out"];
    [CATransaction commit];
}

/* updateColors(progress): the colors blend on the same progress as the move */
- (void)blendButton:(UIView *)button from:(UIColor *)old {
    /* a classic chip is a picture, its backing color is clear and has nothing to blend */
    if (ExteriaReactionStill() || !button.backgroundColor) return;
    CABasicAnimation *blend = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    blend.fromValue = (id)old.CGColor;
    blend.toValue = (id)button.backgroundColor.CGColor;
    blend.duration = CHANGE_SECONDS;
    blend.timingFunction = ExteriaReactionCurve();
    [button.layer addAnimation:blend forKey:@"exteria.reaction.blend"];
}

/* outButtons: the chip of a reaction that went stays where it was and scales from its size to half of it while its alpha goes from 1 to 0 */
- (void)shrinkAwayButton:(UIView *)button {
    if (ExteriaReactionStill()) {
        [button removeFromSuperview];
        return;
    }
    button.userInteractionEnabled = NO;
    ++_ghosts;
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = [NSNumber numberWithFloat:1];
    scale.toValue = [NSNumber numberWithFloat:0.5f];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:1];
    fade.toValue = [NSNumber numberWithFloat:0];
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:scale, fade, nil];
    group.duration = CHANGE_SECONDS;
    group.timingFunction = ExteriaReactionCurve();
    group.fillMode = kCAFillModeForwards;
    group.removedOnCompletion = NO;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [button removeFromSuperview];
        if (_ghosts) --_ghosts;
        /* an empty view that kept its old frame while the last chip shrank must not catch touches meant for the bubble */
        if (!_ghosts && !_buttons.count) self.hidden = YES;
    }];
    [button.layer addAnimation:group forKey:@"exteria.reaction.out"];
    [CATransaction commit];
}

- (void)setReactions:(NSArray *)reactions counts:(BOOL)counts animated:(BOOL)animated {
    if (!reactions.count && !_buttons.count) {
        _counts = counts;
        return;
    }
    NSMutableDictionary *before = [NSMutableDictionary dictionary], *beforeChosen = [NSMutableDictionary dictionary];
    for (ExteriaReaction *old in _reactions) {
        if (!old.key) continue;
        [before setObject:[NSNumber numberWithInt:old.count] forKey:old.key];
        [beforeChosen setObject:[NSNumber numberWithBool:old.chosen] forKey:old.key];
    }
    NSMutableSet *kept = [NSMutableSet set];
    for (ExteriaReaction *next in reactions) if (next.key) [kept addObject:next.key];
    [_moveFrom release];
    _moveFrom = animated ? [[NSMutableDictionary alloc] init] : nil;
    [_labelFrom release];
    _labelFrom = animated ? [[NSMutableDictionary alloc] init] : nil;
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIView *button = [_buttons objectAtIndex:i];
        NSString *key = i < _reactions.count ? [(ExteriaReaction *)[_reactions objectAtIndex:i] key] : nil;
        if (animated && key && ![kept containsObject:key]) {
            /* the chip of a reaction that went stays on screen until it has shrunk away */
            [self shrinkAwayButton:button];
        } else {
            if (animated && key) {
                [_moveFrom setObject:[NSValue valueWithCGRect:button.frame] forKey:key];
                UIView *oldLabel = [button viewWithTag:LABEL_TAG];
                UIImage *oldWords = oldLabel ? ExteriaDustSnapshot(oldLabel) : nil;
                if (oldWords) [_labelFrom setObject:oldWords forKey:key];
            }
            [button removeFromSuperview];
        }
    }
    if (!animated) _ghosts = 0;
    [_buttons release];
    _buttons = nil;
    [_reactions release];
    _reactions = [reactions copy];
    _counts = counts;
    NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:reactions.count];
    for (NSUInteger i = 0; i < reactions.count && i < EXTERIA_REACTION_CATALOG_MAX; ++i) {
        ExteriaReaction *r = [reactions objectAtIndex:i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = (NSInteger)i;
        if (ExteriaThemeIsClassic() && (r.chosen || !_inBubble)) {
            /* a lit button for the chip you picked and a plate for the others, as the old chrome draws them */
            UIImage *face = r.chosen ? ExteriaClassicGlossButtonImage(ExteriaClassicGlossSlate, NO) : ExteriaClassicPlateImage();
            UIImageView *plate = [[[UIImageView alloc] initWithImage:face] autorelease];
            plate.tag = PLATE_TAG;
            plate.userInteractionEnabled = NO;
            [button addSubview:plate];
        } else {
            button.backgroundColor = [self chipColorChosen:r.chosen];
            button.layer.cornerRadius = 16 * ExteriaReactionScale();
            button.layer.borderColor = ExteriaColorHairline().CGColor;
            button.layer.borderWidth = r.chosen || _inBubble ? 0 : 0.5;
        }
        [button addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
        button.accessibilityLabel = ExteriaReactionText(r, counts);
        button.accessibilityTraits = UIAccessibilityTraitButton | (r.chosen ? UIAccessibilityTraitSelected : 0);
        ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
        label.text = ExteriaReactionText(r, counts);
        label.entities = r.displayEntities;
        label.font = ExteriaFontMedium(16 * ExteriaReactionScale());
        label.textColor = [self chipTextColorChosen:r.chosen];
        label.textAlignment = ExteriaTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        label.tag = LABEL_TAG;
        [button addSubview:label];
        /* the people sit over the chip right of the label, the last one on top */
        NSUInteger faceCount = counts ? r.faces.count : 0;
        for (NSUInteger f = 0; f < faceCount; ++f) {
            ExteriaPerson *person = [r.faces objectAtIndex:f];
            ExteriaAvatarView *face = [[[ExteriaAvatarView alloc] init] autorelease];
            face.circular = YES;
            face.seed = (NSUInteger)(llabs(person.userId) % 1000003);
            face.initials = person.initials;
            face.deleted = person.deleted;
            face.userInteractionEnabled = NO;
            face.tag = FACE_TAG;
            face.layer.cornerRadius = FACE_SIZE / 2;
            [face setPhoto:person.photo cache:_avatars];
            [button addSubview:face];
        }
        [self addSubview:button];
        [buttons addObject:button];
        NSNumber *was = r.key ? [before objectForKey:r.key] : nil;
        if (animated && !was) {
            [self growButton:button];
        } else if (animated && was) {
            if (was.intValue != r.count) [self rollLabelOfButton:button from:[_labelFrom objectForKey:r.key] up:r.count > was.intValue];
            NSNumber *wasChosen = [beforeChosen objectForKey:r.key];
            if (wasChosen && wasChosen.boolValue != r.chosen) [self blendButton:button from:[self chipColorChosen:wasChosen.boolValue]];
        }
    }
    _buttons = [buttons copy];
    [self setNeedsLayout];
}

- (CGRect)frameOfReaction:(ExteriaReaction *)reaction inView:(UIView *)view {
    for (NSUInteger i = 0; i < _buttons.count && i < _reactions.count; ++i) {
        if (![[(ExteriaReaction *)[_reactions objectAtIndex:i] key] isEqualToString:reaction.key]) continue;
        return [self convertRect:[(UIView *)[_buttons objectAtIndex:i] frame] toView:view];
    }
    return CGRectZero;
}

- (void)picked:(UIButton *)button {
    if ((NSUInteger)button.tag >= _reactions.count) return;
    /* picking closes the overlay and releases its views before this touch handler returns */
    ExteriaReaction *reaction = [[_reactions objectAtIndex:(NSUInteger)button.tag] retain];
    void (^handler)(ExteriaReaction *) = [_pickHandler copy];
    if (handler) handler(reaction);
    [handler release];
    [reaction release];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    exteria_rect frames[EXTERIA_REACTION_CATALOG_MAX];
    ExteriaReactionFrames(_reactions, self.bounds.size.width, _counts, frames);
    if (_alignRight) {
        NSUInteger start = 0;
        while (start < _buttons.count) {
            NSUInteger end = start;
            while (end + 1 < _buttons.count && frames[end + 1].y == frames[start].y) ++end;
            double offset = self.bounds.size.width - frames[end].x - frames[end].width;
            for (NSUInteger i = start; i <= end; ++i) frames[i].x += offset;
            start = end + 1;
        }
    }
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIView *button = [_buttons objectAtIndex:i];
        exteria_rect r = frames[i];
        CGRect target = CGRectMake((CGFloat)r.x, (CGFloat)r.y, (CGFloat)r.width, (CGFloat)r.height);
        ExteriaReaction *moving = i < _reactions.count ? [_reactions objectAtIndex:i] : nil;
        NSValue *from = moving.key ? [_moveFrom objectForKey:moving.key] : nil;
        button.frame = target;
        if (from && !CGRectEqualToRect([from CGRectValue], target)) {
            /* a chip that stays glides from where it stood: the layer is put back at the old place and runs to the new one */
            CGRect old = [from CGRectValue];
            CABasicAnimation *glide = [CABasicAnimation animationWithKeyPath:@"position"];
            glide.fromValue = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(old), CGRectGetMidY(old))];
            glide.toValue = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target))];
            glide.duration = CHANGE_SECONDS;
            glide.timingFunction = ExteriaReactionCurve();
            [button.layer addAnimation:glide forKey:@"exteria.reaction.glide"];
            if (old.size.width != target.size.width) {
                /* the width runs on the same progress, as w in ReactionButton.draw */
                CABasicAnimation *widen = [CABasicAnimation animationWithKeyPath:@"bounds"];
                widen.fromValue = [NSValue valueWithCGRect:CGRectMake(0, 0, old.size.width, old.size.height)];
                widen.toValue = [NSValue valueWithCGRect:CGRectMake(0, 0, target.size.width, target.size.height)];
                widen.duration = CHANGE_SECONDS;
                widen.timingFunction = ExteriaReactionCurve();
                [button.layer addAnimation:widen forKey:@"exteria.reaction.widen"];
            }
        }
        UIView *label = [button viewWithTag:LABEL_TAG];
        [button viewWithTag:PLATE_TAG].frame = button.bounds;
        ExteriaReaction *reaction = i < _reactions.count ? [_reactions objectAtIndex:i] : nil;
        CGFloat facesWidth = ExteriaFacesWidth(reaction, _counts);
        label.frame = CGRectMake(5, 0, button.bounds.size.width - 10 - facesWidth, button.bounds.size.height);
        CGFloat faceX = button.bounds.size.width - 10 - facesWidth + FACE_GAP;
        NSUInteger placed = 0;
        for (UIView *face in button.subviews) {
            if (face.tag != FACE_TAG) continue;
            face.frame = CGRectMake(faceX + (CGFloat)placed * FACE_STEP, (button.bounds.size.height - FACE_SIZE) / 2, FACE_SIZE, FACE_SIZE);
            ++placed;
        }
    }
    /* the glide is asked for once, by the layout that follows the change */
    [_moveFrom release];
    _moveFrom = nil;
    [_labelFrom release];
    _labelFrom = nil;
}

@end
