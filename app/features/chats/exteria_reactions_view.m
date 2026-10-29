#import "exteria_reactions_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_platform.h"
#import "exteria_emoji_label.h"
#import "exteria_person.h"
#import "exteria_text_layout.h"
#import "exteria_theme.h"
#include "exteria_reaction_layout.h"

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
    if (_outgoing) return chosen ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.22];
    return chosen ? ExteriaColorAccent() : [ExteriaColorAccent() colorWithAlphaComponent:0.16];
}

- (UIColor *)chipTextColorChosen:(BOOL)chosen {
    if (!_inBubble) return chosen ? [UIColor whiteColor] : ExteriaColorTitle();
    if (_outgoing) return chosen ? ExteriaColorAccent() : [UIColor whiteColor];
    return chosen ? [UIColor whiteColor] : ExteriaColorAccent();
}

/* the reactions of ReactionsLayoutInBubble */
/* the person asked for reduced motion, or switched the transitions off in the power settings, which UIKit animations obey and layer animations do not */
static BOOL ExteriaReactionStill(void) {
    return ExteriaReduceMotionEnabled() || ![UIView areAnimationsEnabled];
}

/* a chip that comes swells past its size and settles, while it fades in over the first part of the swell; a plain growth from half read as a jump */
- (void)growButton:(UIView *)button {
    if (ExteriaReactionStill()) return;
    CAKeyframeAnimation *swell = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    swell.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0.25f], [NSNumber numberWithFloat:1.14f], [NSNumber numberWithFloat:0.97f], [NSNumber numberWithFloat:1], nil];
    swell.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.55f], [NSNumber numberWithFloat:0.8f], [NSNumber numberWithFloat:1], nil];
    swell.timingFunctions = [NSArray arrayWithObjects:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
                             [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut], nil];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = [NSNumber numberWithFloat:0];
    fade.toValue = [NSNumber numberWithFloat:1];
    fade.duration = 0.14;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:swell, fade, nil];
    group.duration = 0.34;
    [button.layer addAnimation:group forKey:@"exteria.reaction.grow"];
}

/* a chip that stays and whose count changed gives a small bump, and its number rolls in from the side the count moved to */
- (void)bumpButton:(UIView *)button up:(BOOL)up {
    if (ExteriaReactionStill()) return;
    CAKeyframeAnimation *bump = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    bump.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:1], [NSNumber numberWithFloat:1.12f], [NSNumber numberWithFloat:1], nil];
    bump.keyTimes = [NSArray arrayWithObjects:[NSNumber numberWithFloat:0], [NSNumber numberWithFloat:0.4f], [NSNumber numberWithFloat:1], nil];
    bump.duration = 0.26;
    [button.layer addAnimation:bump forKey:@"exteria.reaction.bump"];
    UIView *label = button.subviews.count ? [button.subviews objectAtIndex:0] : nil;
    if (!label) return;
    label.alpha = 0;
    label.transform = CGAffineTransformMakeTranslation(0, up ? 9 : -9);
    [UIView animateWithDuration:0.22 delay:0.03 options:UIViewAnimationOptionCurveEaseOut animations:^{
        label.alpha = 1;
        label.transform = CGAffineTransformIdentity;
    } completion:nil];
}

/* a chip whose own mark changed takes the new color in a moment, not at once */
- (void)blendButton:(UIView *)button from:(UIColor *)old {
    if (ExteriaReactionStill()) return;
    UIColor *target = button.backgroundColor;
    button.backgroundColor = old;
    [UIView animateWithDuration:0.2 animations:^{ button.backgroundColor = target; }];
}

- (void)shrinkAwayButton:(UIView *)button {
    if (ExteriaReactionStill()) {
        [button removeFromSuperview];
        return;
    }
    button.userInteractionEnabled = NO;
    ++_ghosts;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        button.alpha = 0;
        button.transform = CGAffineTransformMakeScale(0.3f, 0.3f);
    } completion:^(BOOL finished) {
        (void)finished;
        [button removeFromSuperview];
        if (_ghosts) --_ghosts;
        /* an empty view that kept its old frame while the last chip shrank must not catch touches meant for the bubble */
        if (!_ghosts && !_buttons.count) self.hidden = YES;
    }];
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
    for (NSUInteger i = 0; i < _buttons.count; ++i) {
        UIView *button = [_buttons objectAtIndex:i];
        NSString *key = i < _reactions.count ? [(ExteriaReaction *)[_reactions objectAtIndex:i] key] : nil;
        if (animated && key && ![kept containsObject:key]) {
            /* the chip of a reaction that went stays on screen until it has shrunk away */
            [self shrinkAwayButton:button];
        } else {
            if (animated && key) [_moveFrom setObject:[NSValue valueWithCGRect:button.frame] forKey:key];
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
        button.backgroundColor = [self chipColorChosen:r.chosen];
        button.layer.cornerRadius = 16 * ExteriaReactionScale();
        button.layer.borderColor = ExteriaColorHairline().CGColor;
        button.layer.borderWidth = r.chosen || _inBubble ? 0 : 0.5;
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
            if (was.intValue != r.count) [self bumpButton:button up:r.count > was.intValue];
            NSNumber *wasChosen = [beforeChosen objectForKey:r.key];
            if (wasChosen && wasChosen.boolValue != r.chosen) [self blendButton:button from:[self chipColorChosen:wasChosen.boolValue]];
        }
    }
    _buttons = [buttons copy];
    [self setNeedsLayout];
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
            glide.duration = exteria_motion_duration(EXTERIA_MOTION_LIST_MOVE);
            glide.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2f:0.01f:0.28f:0.91f];
            [button.layer addAnimation:glide forKey:@"exteria.reaction.glide"];
        }
        UIView *label = [button.subviews objectAtIndex:0];
        ExteriaReaction *reaction = i < _reactions.count ? [_reactions objectAtIndex:i] : nil;
        CGFloat facesWidth = ExteriaFacesWidth(reaction, _counts);
        label.frame = CGRectMake(5, 0, button.bounds.size.width - 10 - facesWidth, button.bounds.size.height);
        CGFloat faceX = button.bounds.size.width - 10 - facesWidth + FACE_GAP;
        for (NSUInteger f = 1; f < button.subviews.count; ++f) {
            UIView *face = [button.subviews objectAtIndex:f];
            face.frame = CGRectMake(faceX + (CGFloat)(f - 1) * FACE_STEP, (button.bounds.size.height - FACE_SIZE) / 2, FACE_SIZE, FACE_SIZE);
        }
    }
    /* the glide is asked for once, by the layout that follows the change */
    [_moveFrom release];
    _moveFrom = nil;
}

@end
