#import "exteria_info_card_view.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_emoji_label.h"
#import "exteria_link_router.h"
#include "exteria_links.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

#define ROW_MIN 62.0
#define STARS_ROW 56.0
#define CODE_SIDE 48.0

@interface ExteriaInfoCardView () {
    NSMutableArray *_rows;
    UIView *_starsRow;
    UIImageView *_starsPicture;
    void (^_copyHandler)(void);
    NSString *_codeCaption;
    void (^_codeHandler)(void);
}
@end

@implementation ExteriaInfoCardView

@synthesize copyHandler = _copyHandler;
@synthesize codeCaption = _codeCaption;
@synthesize codeHandler = _codeHandler;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 14;
    _rows = [[NSMutableArray alloc] init];
    self.hidden = YES;
    return self;
}

- (void)dealloc {
    [_rows release];
    [_starsRow release];
    [_starsPicture release];
    [_copyHandler release];
    [_codeCaption release];
    [_codeHandler release];
    [super dealloc];
}

static ExteriaEmojiLabel *ExteriaInfoLabel(UIColor *color, CGFloat size) {
    ExteriaEmojiLabel *label = [[[ExteriaEmojiLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = ExteriaFontRegular(size);
    return label;
}

static NSArray *ExteriaInfoMentions(NSString *text) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [[NSRegularExpression alloc] initWithPattern:@"(?<![A-Za-z0-9_@])@[A-Za-z0-9_]{1,32}(?![A-Za-z0-9_])" options:0 error:NULL];
    });
    NSMutableArray *entities = [NSMutableArray array];
    for (NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *name = [text substringWithRange:match.range];
        char checked[EXTERIA_LINK_NAME_MAX];
        if (exteria_mention_name(name.UTF8String, checked, sizeof(checked)) != EXTERIA_OK) continue;
        ExteriaTextEntity *entity = [[[ExteriaTextEntity alloc] initWithStyle:ExteriaTextStyleMention range:match.range url:nil] autorelease];
        [entities addObject:entity];
    }
    return entities;
}

- (void)setRows:(NSArray *)rows {
    for (UIView *row in _rows) [row removeFromSuperview];
    [_rows removeAllObjects];
    for (NSArray *pair in rows) {
        NSString *caption = [pair objectAtIndex:0], *text = [pair objectAtIndex:1];
        if (!text.length) continue;
        UIControl *row = [[[UIControl alloc] init] autorelease];
        ExteriaEmojiLabel *value = ExteriaInfoLabel(ExteriaColorTitle(), 17);
        value.numberOfLines = 0;
        value.text = text;
        if ([caption isEqualToString:NSLocalizedString(@"profile.about", nil)] || [caption isEqualToString:NSLocalizedString(@"channel.description", nil)]) {
            value.entities = ExteriaInfoMentions(text);
            value.linkColor = ExteriaColorAccent();
        }
        value.tag = 1;
        ExteriaEmojiLabel *small = ExteriaInfoLabel(ExteriaColorSecondary(), 13);
        small.text = caption;
        small.tag = 2;
        [row addSubview:value];
        [row addSubview:small];
        [row addTarget:self action:@selector(copyRow:event:) forControlEvents:UIControlEventTouchUpInside];
        if (_codeHandler && [caption isEqualToString:_codeCaption]) {
            UIButton *code = [UIButton buttonWithType:UIButtonTypeCustom];
            code.tag = 3;
            [code setImage:ExteriaSymbolImage(ExteriaSymbolQr, 26, ExteriaColorTitle()) forState:UIControlStateNormal];
            code.accessibilityLabel = NSLocalizedString(@"profile.qr", nil);
            [code addTarget:self action:@selector(openCode) forControlEvents:UIControlEventTouchUpInside];
            [row addSubview:code];
        }
        [self addSubview:row];
        [_rows addObject:row];
    }
    self.hidden = _rows.count == 0 && !_starsRow;
    [self setNeedsLayout];
}

- (void)setStarsBalance:(UIImage *)balance caption:(NSString *)caption {
    [_starsRow removeFromSuperview];
    [_starsRow release];
    _starsRow = nil;
    [_starsPicture release];
    _starsPicture = nil;
    if (balance) {
        _starsRow = [[UIView alloc] init];
        ExteriaEmojiLabel *title = ExteriaInfoLabel(ExteriaColorTitle(), 17);
        title.tag = 2;
        title.text = caption;
        _starsPicture = [[UIImageView alloc] initWithImage:balance];
        [_starsRow addSubview:title];
        [_starsRow addSubview:_starsPicture];
        [self addSubview:_starsRow];
    }
    self.hidden = _rows.count == 0 && !_starsRow;
    [self setNeedsLayout];
}

/* the text of a row with a QR button stops short of it */
- (CGFloat)textWidthOfRow:(UIView *)row card:(CGFloat)width {
    return width - 32 - ([row viewWithTag:3] ? CODE_SIDE : 0);
}

- (CGFloat)rowHeight:(UIView *)row width:(CGFloat)width {
    ExteriaEmojiLabel *value = (ExteriaEmojiLabel *)[row viewWithTag:1];
    CGSize fit = [value sizeThatFits:CGSizeMake([self textWidthOfRow:row card:width], 400)];
    return MAX(ROW_MIN, fit.height + 38);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat total = 0;
    for (UIView *row in _rows) total += [self rowHeight:row width:width];
    return total + (_starsRow ? STARS_ROW : 0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, y = 0;
    for (UIView *row in _rows) {
        ExteriaEmojiLabel *value = (ExteriaEmojiLabel *)[row viewWithTag:1], *caption = (ExteriaEmojiLabel *)[row viewWithTag:2];
        CGFloat textWidth = [self textWidthOfRow:row card:width];
        CGSize fit = [value sizeThatFits:CGSizeMake(textWidth, 400)];
        CGFloat height = [self rowHeight:row width:width];
        row.frame = CGRectMake(0, y, width, height);
        value.frame = CGRectMake(16, 10, textWidth, fit.height);
        caption.frame = CGRectMake(16, 10 + fit.height + 2, textWidth, 16);
        [row viewWithTag:3].frame = CGRectMake(width - CODE_SIDE - 4, (height - CODE_SIDE) / 2, CODE_SIDE, CODE_SIDE);
        y += height;
    }
    if (_starsRow) {
        _starsRow.frame = CGRectMake(0, y, width, STARS_ROW);
        [_starsRow viewWithTag:2].frame = CGRectMake(16, 0, width - 16 - 100, STARS_ROW);
        CGSize balance = _starsPicture.bounds.size;
        _starsPicture.frame = CGRectMake(width - 16 - balance.width, (STARS_ROW - balance.height) / 2, balance.width, balance.height);
    }
}

- (void)openCode {
    if (_codeHandler) _codeHandler();
}

- (void)copyRow:(UIControl *)row event:(UIEvent *)event {
    ExteriaEmojiLabel *value = (ExteriaEmojiLabel *)[row viewWithTag:1];
    UITouch *touch = [[event allTouches] anyObject];
    NSString *link = touch ? [value linkAtPoint:[touch locationInView:value]] : nil;
    if (link.length) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaOpenLinkNotification object:self userInfo:[NSDictionary dictionaryWithObject:link forKey:@"url"]];
        return;
    }
    ExteriaEmojiLabel *caption = (ExteriaEmojiLabel *)[row viewWithTag:2];
    if ([caption.text isEqualToString:NSLocalizedString(@"profile.about", nil)] ||
        [caption.text isEqualToString:NSLocalizedString(@"channel.description", nil)]) return;
    [UIPasteboard generalPasteboard].string = value.text;
    if (_copyHandler) _copyHandler();
}

@end
