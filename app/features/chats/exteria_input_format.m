#import "exteria_input_format.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_person.h"
#import "exteria_session.h"
#import "exteria_session_bots.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_translate_config.h"
#import "exteria_translator.h"
#import "exteria_weak_reference.h"

/* what a pick in the menu does, in the order of the menu */
typedef enum {
    ExteriaFormatTranslate,
    ExteriaFormatBold,
    ExteriaFormatItalic,
    ExteriaFormatMono,
    ExteriaFormatCode,
    ExteriaFormatStrike,
    ExteriaFormatUnderline,
    ExteriaFormatQuote,
    ExteriaFormatSpoiler,
    ExteriaFormatLink,
    ExteriaFormatMention,
    ExteriaFormatDate,
    ExteriaFormatRegular
} ExteriaFormatAction;

#define STYLE_BIT(style) (1u << (unsigned)(style))
#define INLINE_STYLES (STYLE_BIT(ExteriaTextStyleBold) | STYLE_BIT(ExteriaTextStyleItalic) | STYLE_BIT(ExteriaTextStyleUnderline) | \
                       STYLE_BIT(ExteriaTextStyleStrike) | STYLE_BIT(ExteriaTextStyleSpoiler))
#define MONO_STYLES (STYLE_BIT(ExteriaTextStyleCode) | STYLE_BIT(ExteriaTextStylePre))
#define TARGET_STYLES (STYLE_BIT(ExteriaTextStyleLink) | STYLE_BIT(ExteriaTextStyleMentionName) | STYLE_BIT(ExteriaTextStyleDate))
/* every style a person can pick; the custom emoji are not theirs to remove with "regular" */
#define PICKED_STYLES (INLINE_STYLES | MONO_STYLES | TARGET_STYLES | STYLE_BIT(ExteriaTextStyleQuote))

static ExteriaTextEntity *ExteriaRunLike(ExteriaTextEntity *base, NSRange range) {
    ExteriaTextEntity *run = [[[ExteriaTextEntity alloc] initWithStyle:base.style range:range url:base.url] autorelease];
    run.userId = base.userId;
    run.accessHash = base.accessHash;
    run.date = base.date;
    run.flags = base.flags;
    return run;
}

#pragma mark date picker

/* a card with a wheel for the day and the time, over the host; the date is asked for the same way, one moment and
   no shapes */
@interface ExteriaFormatDatePicker : UIView {
    UIView *_card;
    UIDatePicker *_picker;
    void (^_done)(NSDate *date);
}
- (id)initWithFrame:(CGRect)frame done:(void (^)(NSDate *date))done;
@end

@implementation ExteriaFormatDatePicker

- (id)initWithFrame:(CGRect)frame done:(void (^)(NSDate *date))done {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _done = [done copy];
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 14;
    _card.layer.masksToBounds = YES;
    [self addSubview:_card];
    _picker = [[UIDatePicker alloc] init];
    _picker.datePickerMode = UIDatePickerModeDateAndTime;
    [_card addSubview:_picker];
    NSString *titles[2] = {NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"tr.ok", nil)};
    for (int i = 0; i < 2; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = i;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
        button.titleLabel.font = i ? ExteriaFontSemibold(17) : ExteriaFontRegular(17);
        [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:button];
    }
    return self;
}

- (void)dealloc {
    [_card release];
    [_picker release];
    [_done release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(self.bounds.size.width - 20, 360), pickerHeight = 216, bar = 50;
    CGFloat height = bar + pickerHeight;
    _card.frame = CGRectMake(floor((self.bounds.size.width - width) / 2), floor((self.bounds.size.height - height) / 2), width, height);
    _picker.frame = CGRectMake(0, bar, width, pickerHeight);
    for (UIView *view in _card.subviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        view.frame = CGRectMake(view.tag ? width - 110 : 0, 0, 110, bar);
    }
}

- (void)tapped:(UIButton *)button {
    NSDate *date = button.tag ? _picker.date : nil;
    void (^done)(NSDate *) = [_done retain];
    [self removeFromSuperview];
    if (date && done) done(date);
    [done release];
}

@end

#pragma mark runs

@implementation ExteriaInputFormat

@synthesize session = _session;
@synthesize host = _host;
@synthesize changed = _changed;
@synthesize replace = _replace;

- (id)initWithTextView:(UITextView *)view {
    self = [super init];
    if (!self) return nil;
    _view = view;
    _runs = [[NSMutableArray alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_job cancel];
    [_job release];
    [_runs release];
    [_changed release];
    [_replace release];
    [super dealloc];
}

- (void)reset {
    [_runs removeAllObjects];
    [self refreshAppearance];
}

- (void)restoreEntities:(NSArray *)entities {
    NSUInteger length = _view.text.length;
    [_runs removeAllObjects];
    for (ExteriaTextEntity *entity in entities) {
        if (NSMaxRange(entity.range) > length || !entity.range.length) continue;
        switch (entity.style) {
        case ExteriaTextStyleBold:
        case ExteriaTextStyleItalic:
        case ExteriaTextStyleUnderline:
        case ExteriaTextStyleStrike:
        case ExteriaTextStyleCode:
        case ExteriaTextStylePre:
        case ExteriaTextStyleSpoiler:
        case ExteriaTextStyleQuote:
        case ExteriaTextStyleDate:
            [_runs addObject:entity];
            break;
        case ExteriaTextStyleLink:
            if (entity.url.length) [_runs addObject:entity];
            break;
        case ExteriaTextStyleMentionName:
            /* the server wants the access hash of the user in a sent message, and a draft does not bring it back */
            if (entity.userId && entity.accessHash) [_runs addObject:entity];
            break;
        default:
            break;
        }
    }
    [self refreshAppearance];
}

- (void)shiftForRange:(NSRange)range replacementLength:(NSUInteger)length {
    if (!_runs.count) return;
    NSInteger delta = (NSInteger)length - (NSInteger)range.length;
    NSUInteger editEnd = NSMaxRange(range);
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_runs.count];
    for (ExteriaTextEntity *run in _runs) {
        NSRange at = run.range;
        NSUInteger end = NSMaxRange(at);
        if (end <= range.location) {
            [kept addObject:run];
        } else if (at.location >= editEnd && !(range.length == 0 && at.location == range.location && length == 0)) {
            [kept addObject:ExteriaRunLike(run, NSMakeRange((NSUInteger)((NSInteger)at.location + delta), at.length))];
        } else if (range.location >= at.location && editEnd <= end && !(range.length == 0 && (range.location == at.location || range.location == end))) {
            NSInteger grown = (NSInteger)at.length + delta;
            if (grown > 0) [kept addObject:ExteriaRunLike(run, NSMakeRange(at.location, (NSUInteger)grown))];
        } else if (range.location <= at.location && editEnd >= end) {
            /* replaced whole */
        } else if (range.location <= at.location) {
            [kept addObject:ExteriaRunLike(run, NSMakeRange(range.location + length, end - editEnd))];
        } else {
            [kept addObject:ExteriaRunLike(run, NSMakeRange(at.location, range.location - at.location))];
        }
    }
    [_runs setArray:kept];
}

/* what is left of the runs of these styles once the range is cut out of them */
- (void)cutRange:(NSRange)range styles:(unsigned)styles {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:_runs.count + 2];
    NSUInteger rangeEnd = NSMaxRange(range);
    for (ExteriaTextEntity *run in _runs) {
        NSRange at = run.range;
        NSUInteger end = NSMaxRange(at);
        if (!(STYLE_BIT(run.style) & styles) || end <= range.location || at.location >= rangeEnd) {
            [kept addObject:run];
            continue;
        }
        if (at.location < range.location) [kept addObject:ExteriaRunLike(run, NSMakeRange(at.location, range.location - at.location))];
        if (end > rangeEnd) [kept addObject:ExteriaRunLike(run, NSMakeRange(rangeEnd, end - rangeEnd))];
    }
    [_runs setArray:kept];
}

/* whether runs of the style together cover every character of the range */
- (BOOL)style:(ExteriaTextStyle)style coversRange:(NSRange)range {
    NSUInteger position = range.location, end = NSMaxRange(range);
    BOOL moved = YES;
    while (position < end && moved) {
        moved = NO;
        for (ExteriaTextEntity *run in _runs) {
            if (run.style != style || run.range.location > position || NSMaxRange(run.range) <= position) continue;
            position = NSMaxRange(run.range);
            moved = YES;
        }
    }
    return position >= end;
}

- (void)add:(ExteriaTextEntity *)entity {
    [_runs addObject:entity];
    [self refreshAppearance];
    if (_changed) _changed();
}

- (void)applyStyle:(ExteriaTextStyle)style toRange:(NSRange)range {
    if ([self style:style coversRange:range]) {
        [self cutRange:range styles:STYLE_BIT(style)];
        [self refreshAppearance];
        if (_changed) _changed();
        return;
    }
    /* mono text keeps no other inline style and no other inline style keeps mono it */
    unsigned clear = STYLE_BIT(style);
    if (style == ExteriaTextStyleCode || style == ExteriaTextStylePre) clear |= INLINE_STYLES | MONO_STYLES;
    else if (STYLE_BIT(style) & INLINE_STYLES) clear |= MONO_STYLES;
    [self cutRange:range styles:clear];
    [self add:[[[ExteriaTextEntity alloc] initWithStyle:style range:range url:nil] autorelease]];
}

- (void)applyTarget:(ExteriaTextEntity *)entity {
    /* a link, a name and a date all say what a tap on the words does, so one replaces another */
    [self cutRange:entity.range styles:TARGET_STYLES];
    [self add:entity];
}

#pragma mark entities

- (NSArray *)entitiesAfterLead:(NSUInteger)lead length:(NSUInteger)length {
    NSMutableArray *entities = [NSMutableArray arrayWithCapacity:_runs.count];
    for (ExteriaTextEntity *run in _runs) {
        NSRange at = run.range;
        if (at.location >= lead + length || NSMaxRange(at) <= lead) continue;
        NSUInteger from = MAX(at.location, lead), to = MIN(NSMaxRange(at), lead + length);
        [entities addObject:ExteriaRunLike(run, NSMakeRange(from - lead, to - from))];
    }
    return entities;
}

#pragma mark appearance

/* the attribute names of NSAttributedString from ios 6 and 7 by their values: a constant the old runtime lacks would not load, and the text
   storage that takes them only exists from ios 7 */
- (void)refreshAppearance {
    if (![_view respondsToSelector:@selector(textStorage)] || _view.markedTextRange) return;
    /* the ios 6.1 headers of the armv7 slice do not declare the storage, so it is sent to as an id */
    id storage = [_view performSelector:@selector(textStorage)];
    NSUInteger length = [[storage string] length];
    if (!length) return;
    UIFont *base = _view.font ? _view.font : ExteriaFontRegular(16);
    UIColor *ink = _view.textColor ? _view.textColor : ExteriaColorTitle();
    CGFloat size = base.pointSize;
    [storage beginEditing];
    [storage setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:base, @"NSFont", ink, @"NSColor", nil] range:NSMakeRange(0, length)];
    for (ExteriaTextEntity *run in _runs) {
        NSRange range = run.range;
        if (NSMaxRange(range) > length) continue;
        switch (run.style) {
        case ExteriaTextStyleBold: [storage addAttribute:@"NSFont" value:ExteriaFontBold(size) range:range]; break;
        case ExteriaTextStyleItalic: [storage addAttribute:@"NSObliqueness" value:[NSNumber numberWithFloat:0.2f] range:range]; break;
        case ExteriaTextStyleUnderline: [storage addAttribute:@"NSUnderline" value:[NSNumber numberWithInt:1] range:range]; break;
        case ExteriaTextStyleStrike: [storage addAttribute:@"NSStrikethrough" value:[NSNumber numberWithInt:1] range:range]; break;
        case ExteriaTextStyleCode:
        case ExteriaTextStylePre: {
            UIFont *mono = [UIFont fontWithName:@"Courier" size:size - 1];
            if (mono) [storage addAttribute:@"NSFont" value:mono range:range];
            [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.12] range:range];
            break;
        }
        case ExteriaTextStyleSpoiler: [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.3] range:range]; break;
        case ExteriaTextStyleQuote: [storage addAttribute:@"NSBackgroundColor" value:[ink colorWithAlphaComponent:0.08] range:range]; break;
        case ExteriaTextStyleLink:
        case ExteriaTextStyleMentionName:
        case ExteriaTextStyleDate:
            [storage addAttribute:@"NSColor" value:ExteriaColorAccent() range:range];
            if (run.style != ExteriaTextStyleMentionName) [storage addAttribute:@"NSUnderline" value:[NSNumber numberWithInt:1] range:range];
            break;
        default: break;
        }
    }
    [storage endEditing];
}

#pragma mark menu

- (void)presentMenu {
    if (!_host || !_view.text.length) return;
    BOOL selected = _view.selectedRange.length > 0;
    static const ExteriaFormatAction all[] = {ExteriaFormatTranslate, ExteriaFormatBold, ExteriaFormatItalic, ExteriaFormatMono, ExteriaFormatCode,
        ExteriaFormatStrike, ExteriaFormatUnderline, ExteriaFormatQuote, ExteriaFormatSpoiler, ExteriaFormatLink, ExteriaFormatMention, ExteriaFormatDate,
        ExteriaFormatRegular};
    static NSString *const keys[] = {@"fmt.translate", @"fmt.bold", @"fmt.italic", @"fmt.mono", @"fmt.code", @"fmt.strike", @"fmt.underline", @"fmt.quote",
        @"fmt.spoiler", @"fmt.link", @"fmt.mention", @"fmt.date", @"fmt.regular"};
    NSMutableArray *options = [NSMutableArray array], *actions = [NSMutableArray array];
    /* with nothing selected only the translation of the whole text makes sense */
    for (size_t i = 0; i < sizeof(all) / sizeof(all[0]); ++i) {
        if (!selected && all[i] != ExteriaFormatTranslate) continue;
        [options addObject:NSLocalizedString(keys[i], nil)];
        [actions addObject:[NSNumber numberWithInt:all[i]]];
    }
    NSRange range = selected ? _view.selectedRange : NSMakeRange(0, _view.text.length);
    ExteriaWeakReference *weak = _weak;
    /* the sheet stands on the bottom edge of the screen, where the keyboard is; the keyboard goes while the choice is made and comes back with the answer */
    BOOL hadKeyboard = [_view isFirstResponder];
    if (hadKeyboard) [_view resignFirstResponder];
    [ExteriaSheet presentInView:_host title:nil message:nil options:options destructive:nil cancelTitle:NSLocalizedString(@"picker.cancel", nil)
                        handler:^(NSUInteger index) {
        ExteriaInputFormat *format = weak.target;
        if (!format || index >= actions.count) return;
        ExteriaFormatAction action = (ExteriaFormatAction)[[actions objectAtIndex:index] intValue];
        /* the questions that follow (a link, a language, a date) ask for the keyboard themselves or have none, so only the plain styles take it back at once */
        if (hadKeyboard && action != ExteriaFormatTranslate && action != ExteriaFormatCode && action != ExteriaFormatLink && action != ExteriaFormatMention && action != ExteriaFormatDate) {
            [format->_view becomeFirstResponder];
            if (NSMaxRange(range) <= format->_view.text.length) format->_view.selectedRange = range;
        }
        [format perform:action range:range];
    }];
}

- (void)perform:(ExteriaFormatAction)action range:(NSRange)range {
    if (NSMaxRange(range) > _view.text.length) return;
    switch (action) {
    case ExteriaFormatTranslate: [self translateRange:range]; break;
    case ExteriaFormatBold: [self applyStyle:ExteriaTextStyleBold toRange:range]; break;
    case ExteriaFormatItalic: [self applyStyle:ExteriaTextStyleItalic toRange:range]; break;
    case ExteriaFormatMono: [self applyStyle:ExteriaTextStyleCode toRange:range]; break;
    case ExteriaFormatStrike: [self applyStyle:ExteriaTextStyleStrike toRange:range]; break;
    case ExteriaFormatUnderline: [self applyStyle:ExteriaTextStyleUnderline toRange:range]; break;
    case ExteriaFormatQuote: [self applyStyle:ExteriaTextStyleQuote toRange:range]; break;
    case ExteriaFormatSpoiler: [self applyStyle:ExteriaTextStyleSpoiler toRange:range]; break;
    case ExteriaFormatCode: [self askCodeInRange:range]; break;
    case ExteriaFormatLink: [self askLinkInRange:range]; break;
    case ExteriaFormatMention: [self askMentionInRange:range]; break;
    case ExteriaFormatDate: [self askDateInRange:range]; break;
    case ExteriaFormatRegular:
        [self cutRange:range styles:PICKED_STYLES];
        [self refreshAppearance];
        if (_changed) _changed();
        break;
    }
}

- (BOOL)stillHolds:(NSRange)range {
    return NSMaxRange(range) <= _view.text.length;
}

- (void)askCodeInRange:(NSRange)range {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"fmt.code.title", nil), nil, nil, NSLocalizedString(@"fmt.code.language", nil), ^(NSString *language) {
        ExteriaInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        [format cutRange:range styles:INLINE_STYLES | MONO_STYLES];
        NSString *name = [language stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [format add:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStylePre range:range url:name.length ? name : nil] autorelease]];
    });
}

- (void)askLinkInRange:(NSRange)range {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"fmt.link.title", nil), nil, @"http://", NSLocalizedString(@"fmt.link.address", nil), ^(NSString *address) {
        ExteriaInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        NSString *url = [address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        /* nothing typed after the scheme is no link; the run that was there stays as it was */
        if (!url.length || [url isEqualToString:@"http://"]) return;
        if ([url rangeOfString:@"://"].location == NSNotFound && ![url hasPrefix:@"tg:"] && ![url hasPrefix:@"mailto:"]) url = [@"http://" stringByAppendingString:url];
        [format applyTarget:[[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleLink range:range url:url] autorelease]];
    });
}

- (void)askMentionInRange:(NSRange)range {
    ExteriaWeakReference *weak = _weak;
    ExteriaPromptText(NSLocalizedString(@"fmt.mention.title", nil), nil, nil, NSLocalizedString(@"fmt.mention.name", nil), ^(NSString *text) {
        ExteriaInputFormat *format = weak.target;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name hasPrefix:@"@"]) name = [name substringFromIndex:1];
        if (!format || !name.length || !format->_session || ![format stillHolds:range]) return;
        [format->_session resolveUsername:name completion:^(ExteriaDialog *resolved, ExteriaPerson *person, NSString *errorName) {
            (void)resolved;
            ExteriaInputFormat *again = weak.target;
            if (!again) return;
            /* a name needs a person with a hash the server will accept; a channel or a group has none to point at */
            if (!person || person.userId <= 0 || person.accessHash == 0) {
                if (errorName) NSLog(@"exteria: the mention was not resolved: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"fmt.mention.failed", nil));
                return;
            }
            if (![again stillHolds:range]) return;
            ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleMentionName range:range url:nil] autorelease];
            entity.userId = person.userId;
            entity.accessHash = person.accessHash;
            [again applyTarget:entity];
        }];
    });
}

- (void)askDateInRange:(NSRange)range {
    ExteriaWeakReference *weak = _weak;
    ExteriaFormatDatePicker *picker = [[[ExteriaFormatDatePicker alloc] initWithFrame:_host.bounds done:^(NSDate *date) {
        ExteriaInputFormat *format = weak.target;
        if (!format || ![format stillHolds:range]) return;
        ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleDate range:range url:nil] autorelease];
        entity.date = (int32_t)[date timeIntervalSince1970];
        [format applyTarget:entity];
    }] autorelease];
    [_host addSubview:picker];
}

- (void)translateRange:(NSRange)range {
    NSString *text = [_view.text substringWithRange:range];
    if (!text.length || !_replace) return;
    ExteriaWeakReference *weak = _weak;
    [_job cancel];
    [_job release];
    _job = [[ExteriaTranslateJob translateText:text entities:nil to:ExteriaTranslateTargetLanguage() context:nil session:_session
                                      completion:^(ExteriaTranslation *translation, NSString *failure) {
        ExteriaInputFormat *format = weak.target;
        if (!format) return;
        if (!translation) {
            ExteriaShowNotice(nil, failure.length ? failure : NSLocalizedString(@"fmt.translate.failed", nil));
            return;
        }
        /* the text moved under the request; replacing a different range would eat words the person typed since */
        if (![format stillHolds:range] || ![[format->_view.text substringWithRange:range] isEqualToString:text]) return;
        format->_replace(range, translation.text);
    }] retain];
}

@end
