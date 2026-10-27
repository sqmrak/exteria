#import "exteria_gift_facts_view.h"

#import "exteria_avatar_view.h"
#import "exteria_emoji_label.h"
#import "exteria_gift_screen.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import <QuartzCore/QuartzCore.h>
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define ROW_HEIGHT 46.0
/* the title column is at least this share of the width and grows to the longest title, up to the larger share, so a title such as "Администраторы"
   is not cut to "Админис…" on a 320 point screen */
#define TITLE_SHARE 0.36
#define TITLE_SHARE_MAX 0.6
#define PAD 14.0
#define AVATAR 26.0
#define PILL_HEIGHT 20.0

@interface ExteriaGiftFactsRow : NSObject {
@public
    UILabel *title;
    ExteriaEmojiLabel *value;
    UILabel *pill;
    UIImageView *stars;
    ExteriaAvatarView *person;
    UIImageView *spy;
    BOOL full;
    CGFloat height;
    void (^tap)(void);
}
@end

@implementation ExteriaGiftFactsRow
- (void)dealloc {
    [title release];
    [value release];
    [pill release];
    [stars release];
    [person release];
    [spy release];
    [tap release];
    [super dealloc];
}
@end

@interface ExteriaGiftFactsView () {
    NSMutableArray *_rows;
    ExteriaAvatarCache *_avatars;
}
@end

@implementation ExteriaGiftFactsView

@synthesize avatars = _avatars;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _rows = [[NSMutableArray alloc] init];
    self.backgroundColor = ExteriaColorCard();
    self.contentMode = UIViewContentModeRedraw;
    self.layer.cornerRadius = 12;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.0 / ExteriaScreenScale();
    self.layer.borderColor = ExteriaColorHairline().CGColor;
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease]];
    return self;
}

- (void)dealloc {
    [_rows release];
    [_avatars release];
    [super dealloc];
}

static UILabel *ExteriaFactsLabel(UIFont *font, UIColor *color, NSString *text) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textColor = color;
    label.text = text;
    return label;
}

static ExteriaEmojiLabel *ExteriaFactsValue(UIColor *color, NSString *text) {
    ExteriaEmojiLabel *label = [[ExteriaEmojiLabel alloc] init];
    label.font = ExteriaFontRegular(15);
    label.textColor = color;
    label.text = text;
    return label;
}

- (ExteriaGiftFactsRow *)rowTitled:(NSString *)title {
    ExteriaGiftFactsRow *row = [[[ExteriaGiftFactsRow alloc] init] autorelease];
    row->height = ROW_HEIGHT;
    if (title) {
        row->title = ExteriaFactsLabel(ExteriaFontSemibold(15), ExteriaColorTitle(), title);
        [self addSubview:row->title];
    }
    [_rows addObject:row];
    return row;
}

- (void)addRow:(NSString *)title text:(NSString *)text pill:(NSString *)pill {
    ExteriaGiftFactsRow *row = [self rowTitled:title];
    row->value = ExteriaFactsValue(ExteriaColorTitle(), text);
    [self addSubview:row->value];
    if (pill.length) {
        row->pill = ExteriaFactsLabel(ExteriaFontRegular(12), ExteriaColorAccent(), pill);
        row->pill.textAlignment = ExteriaTextAlignmentCenter;
        row->pill.layer.cornerRadius = PILL_HEIGHT / 2;
        row->pill.layer.masksToBounds = YES;
        row->pill.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.16];
        [self addSubview:row->pill];
    }
}

- (void)addRow:(NSString *)title name:(NSString *)name photo:(ExteriaPhoto *)photo seed:(NSUInteger)seed anonymous:(BOOL)anonymous {
    [self addRow:title name:name photo:photo seed:seed anonymous:anonymous onTap:nil];
}

- (void)addRow:(NSString *)title name:(NSString *)name photo:(ExteriaPhoto *)photo seed:(NSUInteger)seed anonymous:(BOOL)anonymous
         onTap:(void (^)(void))handler {
    ExteriaGiftFactsRow *row = [self rowTitled:title];
    row->tap = [handler copy];
    row->value = ExteriaFactsValue(anonymous ? ExteriaColorSecondary() : ExteriaColorAccent(), name);
    row->value.dropsUndrawable = YES;
    [self addSubview:row->value];
    if (anonymous) {
        row->spy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"gift_anonymous"]];
        row->spy.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:row->spy];
        return;
    }
    row->person = [[ExteriaAvatarView alloc] init];
    row->person.circular = YES;
    row->person.seed = seed;
    row->person.initials = ExteriaInitialsOfName(name);
    [row->person setPhoto:photo cache:_avatars];
    [self addSubview:row->person];
}

- (void)addRow:(NSString *)title stars:(long long)stars {
    ExteriaGiftFactsRow *row = [self rowTitled:title];
    UIFont *font = ExteriaFontRegular(15);
    row->stars = [[UIImageView alloc] initWithImage:ExteriaStarsImage(nil, stars, font, ExteriaColorTitle())];
    [self addSubview:row->stars];
}

- (void)addNote:(NSString *)text entities:(NSArray *)entities {
    ExteriaGiftFactsRow *row = [self rowTitled:nil];
    row->full = YES;
    row->value = ExteriaFactsValue(ExteriaColorTitle(), text);
    row->value.entities = entities;
    row->value.numberOfLines = 0;
    [self addSubview:row->value];
}

- (void)redrawNote {
    for (ExteriaGiftFactsRow *row in _rows) if (row->full) [row->value setNeedsDisplay];
}

- (CGFloat)splitForWidth:(CGFloat)width {
    CGFloat split = floor(width * TITLE_SHARE);
    CGFloat longest = 0;
    for (ExteriaGiftFactsRow *row in _rows) {
        if (row->title) longest = MAX(longest, ceil([row->title sizeThatFits:CGSizeMake(width, ROW_HEIGHT)].width));
    }
    return MIN(floor(width * TITLE_SHARE_MAX), MAX(split, PAD + longest + PAD / 2));
}

- (void)tapped:(UITapGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self];
    CGFloat width = self.bounds.size.width, y = 0;
    if (point.x < [self splitForWidth:width]) return;
    for (ExteriaGiftFactsRow *row in _rows) {
        CGFloat height = row->full ? [self noteHeight:row width:width] : row->height;
        if (point.y >= y && point.y < y + height) {
            if (row->tap) row->tap();
            return;
        }
        y += height;
    }
}

- (CGFloat)noteHeight:(ExteriaGiftFactsRow *)row width:(CGFloat)width {
    CGSize fit = [row->value sizeThatFits:CGSizeMake(width - 2 * PAD, 1000)];
    return MAX(ROW_HEIGHT, ceil(fit.height) + 24);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat total = 0;
    for (ExteriaGiftFactsRow *row in _rows) total += row->full ? [self noteHeight:row width:width] : row->height;
    return total;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat split = [self splitForWidth:width];
    CGFloat y = 0;
    for (ExteriaGiftFactsRow *row in _rows) {
        CGFloat height = row->full ? [self noteHeight:row width:width] : row->height;
        if (row->full) {
            row->value.frame = CGRectMake(PAD, y + 12, width - 2 * PAD, height - 24);
        } else {
            row->title.frame = CGRectMake(PAD, y, split - PAD, height);
            CGFloat x = split + PAD;
            if (row->person || row->spy) {
                CGRect picture = CGRectMake(x, y + (height - AVATAR) / 2, AVATAR, AVATAR);
                row->person.frame = picture;
                row->spy.frame = picture;
                x += AVATAR + 8;
            }
            if (row->stars) {
                row->stars.frame = CGRectMake(x, y + (height - row->stars.image.size.height) / 2, row->stars.image.size.width, row->stars.image.size.height);
            }
            if (row->value) {
                CGSize text = [row->value sizeThatFits:CGSizeMake(width - x - PAD, height)];
                CGFloat room = width - x - PAD - (row->pill ? 60 : 0);
                row->value.frame = CGRectMake(x, y, MIN(ceil(text.width), room), height);
                if (row->pill) {
                    CGSize badge = [row->pill sizeThatFits:CGSizeMake(80, PILL_HEIGHT)];
                    row->pill.frame = CGRectMake(CGRectGetMaxX(row->value.frame) + 8, y + (height - PILL_HEIGHT) / 2, ceil(badge.width) + 14, PILL_HEIGHT);
                }
            }
        }
        y += height;
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat width = self.bounds.size.width, split = [self splitForWidth:self.bounds.size.width];
    CGFloat line = 1.0 / ExteriaScreenScale();
    [ExteriaColorHairline() setFill];
    CGFloat y = 0;
    for (NSUInteger i = 0; i < _rows.count; ++i) {
        ExteriaGiftFactsRow *row = [_rows objectAtIndex:i];
        CGFloat height = row->full ? [self noteHeight:row width:width] : row->height;
        if (!row->full) CGContextFillRect(context, CGRectMake(split, y, line, height));
        y += height;
        if (i + 1 < _rows.count) CGContextFillRect(context, CGRectMake(0, y - line, width, line));
    }
}

@end
