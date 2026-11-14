#import "exteria_customization_views.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_chat_settings.h"
#import "exteria_dialog.h"
#import "exteria_dialog_cell.h"
#import "exteria_classic_chrome.h"
#import "exteria_platform.h"
#import "exteria_shape.h"
#import "exteria_team.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wallpaper.h"

#define GRID_COLUMNS 5
#define GRID_PAD 12.0
#define CELL_GAP 6.0

@implementation ExteriaShapeGridView

@synthesize selectedShape = _selectedShape;
@synthesize chooseHandler = _chooseHandler;

+ (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat cell = floor((width - 2 * GRID_PAD - (GRID_COLUMNS - 1) * CELL_GAP) / GRID_COLUMNS);
    NSUInteger rows = (ExteriaShapeCount + GRID_COLUMNS - 1) / GRID_COLUMNS;
    return 2 * GRID_PAD + rows * cell + (rows - 1) * CELL_GAP;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentMode = UIViewContentModeRedraw;
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    [self addGestureRecognizer:tap];
    return self;
}

- (void)dealloc {
    [_chooseHandler release];
    [super dealloc];
}

- (void)setSelectedShape:(NSInteger)shape {
    if (shape == _selectedShape) return;
    _selectedShape = shape;
    [self setNeedsDisplay];
}

- (CGFloat)cellSide {
    return floor((self.bounds.size.width - 2 * GRID_PAD - (GRID_COLUMNS - 1) * CELL_GAP) / GRID_COLUMNS);
}

- (CGRect)rectOfCell:(NSUInteger)index {
    CGFloat side = [self cellSide];
    NSUInteger column = index % GRID_COLUMNS, row = index / GRID_COLUMNS;
    return CGRectMake(GRID_PAD + column * (side + CELL_GAP), GRID_PAD + row * (side + CELL_GAP), side, side);
}

- (void)drawRect:(CGRect)dirty {
    (void)dirty;
    UIColor *accent = ExteriaColorAccent();
    for (NSUInteger i = 0; i < ExteriaShapeCount; ++i) {
        CGRect cell = [self rectOfCell:i];
        BOOL chosen = (NSInteger)i == _selectedShape;
        if (chosen) {
            [[accent colorWithAlphaComponent:0.16f] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:cell cornerRadius:cell.size.width * 0.3f] fill];
        }
        CGRect box = CGRectInset(cell, cell.size.width * 0.17f, cell.size.width * 0.17f);
        [chosen ? accent : ExteriaColorSecondary() setFill];
        /* the rounded square is drawn with a fixed corner: at the default 84% of the stored corner it is a circle, the same as the next cell */
        [ExteriaShapePath((ExteriaShape)i, box, i == ExteriaShapeRounded ? 36 : 0) fill];
    }
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:self];
    for (NSUInteger i = 0; i < ExteriaShapeCount; ++i) {
        if (!CGRectContainsPoint(CGRectInset([self rectOfCell:i], -CELL_GAP / 2, -CELL_GAP / 2), point)) continue;
        if ((NSInteger)i != _selectedShape && _chooseHandler) _chooseHandler((NSInteger)i);
        return;
    }
}

- (BOOL)isAccessibilityElement {
    return NO;
}

@end

#define PREVIEW_GAP 14.0
#define PREVIEW_BUBBLE 38.0
#define PREVIEW_FIELD 38.0
#define PREVIEW_BAR 46.0

@interface ExteriaCustomPreviewView () {
    ExteriaDialogCell *_cell;
    UIView *_separator;
    UIView *_bubble;
    UILabel *_bubbleText;
    UIView *_field;
    UILabel *_placeholder;
    UIButton *_send;
    UIView *_bar;
    UIView *_indicator;
    NSMutableArray *_tabIcons;
    UIImage *_picture;
}
@end

@implementation ExteriaCustomPreviewView

/* the room it takes: the row of the chat list as the list draws it, then a message with the field and the bar of a chat under it */
+ (CGFloat)height {
    return [ExteriaDialogCell rowHeight] + PREVIEW_GAP + PREVIEW_BUBBLE + 12 + PREVIEW_FIELD + PREVIEW_GAP + PREVIEW_BAR + 8;
}

/* the row is the real one of the chat list, made of a chat that is only in this preview: the lead developer, with his badges, a message and an unread count */
static ExteriaDialog *ExteriaPreviewDialog(void) {
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = 1;
    row.peer_id = EXTERIA_TEAM_LEAD_ID;
    row.kind = EXTERIA_DIALOG_USER;
    row.date = (int32_t)[[NSDate date] timeIntervalSince1970] - 120;
    row.unread_count = 2;
    row.preview = EXTERIA_PREVIEW_TEXT;
    snprintf(row.title, sizeof(row.title), "%s", "sqmrak");
    snprintf(row.text, sizeof(row.text), "%s", NSLocalizedString(@"custom.preview.line", nil).UTF8String ?: "");
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    _cell = [[ExteriaDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _cell.userInteractionEnabled = NO;
    [self addSubview:_cell];
    _separator = [[UIView alloc] init];
    [self addSubview:_separator];
    _bubble = [[UIView alloc] init];
    [self addSubview:_bubble];
    _bubbleText = [[UILabel alloc] init];
    _bubbleText.backgroundColor = [UIColor clearColor];
    _bubbleText.text = NSLocalizedString(@"custom.preview.bubble", nil);
    _bubbleText.font = ExteriaFontRegular(15);
    _bubbleText.textColor = [UIColor whiteColor];
    [_bubble addSubview:_bubbleText];
    _field = [[UIView alloc] init];
    [self addSubview:_field];
    _placeholder = [[UILabel alloc] init];
    _placeholder.backgroundColor = [UIColor clearColor];
    _placeholder.text = NSLocalizedString(@"chat.placeholder", nil);
    _placeholder.font = ExteriaFontRegular(15);
    [_field addSubview:_placeholder];
    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.userInteractionEnabled = NO;
    [_send setImage:ExteriaSymbolImage(ExteriaSymbolSendArrow, 18, [UIColor whiteColor]) forState:UIControlStateNormal];
    [self addSubview:_send];
    _bar = [[UIView alloc] init];
    [self addSubview:_bar];
    _indicator = [[UIView alloc] init];
    _indicator.userInteractionEnabled = NO;
    [_bar addSubview:_indicator];
    _tabIcons = [[NSMutableArray alloc] init];
    ExteriaSymbol symbols[] = {ExteriaSymbolChats, ExteriaSymbolPerson, ExteriaSymbolGear};
    for (size_t i = 0; i < sizeof(symbols) / sizeof(symbols[0]); ++i) {
        UIImageView *icon = [[[UIImageView alloc] init] autorelease];
        icon.contentMode = UIViewContentModeCenter;
        icon.tag = (NSInteger)symbols[i];
        [_bar addSubview:icon];
        [_tabIcons addObject:icon];
    }
    [self refresh];
    return self;
}

- (void)dealloc {
    [_cell release];
    [_separator release];
    [_bubble release];
    [_bubbleText release];
    [_field release];
    [_placeholder release];
    [_send release];
    [_bar release];
    [_indicator release];
    [_tabIcons release];
    [_picture release];
    [super dealloc];
}

/* the avatar of the row is inside the cell, in a view of its own that slides with the swipe, so it is looked for down the whole tree: the first avatar that shows is the one of the chat */
static ExteriaAvatarView *ExteriaFirstShownAvatar(UIView *root) {
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:[ExteriaAvatarView class]] && !view.hidden) return (ExteriaAvatarView *)view;
        ExteriaAvatarView *inner = ExteriaFirstShownAvatar(view);
        if (inner) return inner;
    }
    return nil;
}

- (ExteriaAvatarView *)rowAvatar {
    return ExteriaFirstShownAvatar(_cell.contentView);
}

- (void)setPicture:(UIImage *)picture {
    [_picture release];
    _picture = [picture retain];
    [[self rowAvatar] showImage:_picture];
}

- (void)refresh {
    UIColor *accent = ExteriaColorAccent();
    [_cell configureWithDialog:ExteriaPreviewDialog() avatars:nil action:ExteriaDialogActionNone];
    [_cell setNeedsLayout];
    [_cell layoutIfNeeded];
    if (_picture) [[self rowAvatar] showImage:_picture];
    _separator.backgroundColor = ExteriaThemeIsDark() ? [UIColor colorWithWhite:1 alpha:0.1f] : [UIColor colorWithWhite:0 alpha:0.1f];
    _bubble.backgroundColor = accent;
    _bubble.layer.cornerRadius = (CGFloat)ExteriaChatBubbleRadius();
    _field.backgroundColor = ExteriaColorField();
    _field.layer.cornerRadius = PREVIEW_FIELD / 2;
    _placeholder.textColor = ExteriaColorSecondary();
    _send.backgroundColor = accent;
    NSInteger choice = ExteriaSendShapeStored();
    ExteriaShape shape = choice == 2 ? (ExteriaShape)ExteriaAvatarShapeStored() : (choice == 1 ? ExteriaShapeRounded : ExteriaShapeCircle);
    ExteriaApplyShapeToLayer(_send.layer, shape, PREVIEW_FIELD, choice == 2 ? ExteriaAvatarCornerPercent() : 33);
    _bar.backgroundColor = ExteriaColorCard();
    _bar.layer.cornerRadius = 14;
    _indicator.backgroundColor = [accent colorWithAlphaComponent:0.2f];
    _indicator.hidden = !ExteriaTabIndicatorOn();
    _indicator.layer.cornerRadius = 14;
    for (NSUInteger i = 0; i < _tabIcons.count; ++i) {
        UIImageView *icon = [_tabIcons objectAtIndex:i];
        icon.image = ExteriaSymbolImage((ExteriaSymbol)icon.tag, 22, i == 0 ? accent : ExteriaColorSecondary());
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat rowHeight = [ExteriaDialogCell rowHeight];
    _cell.frame = CGRectMake(0, 0, width, rowHeight);
    [_cell layoutIfNeeded];
    CGFloat inset = 14 + 48 + 12;
    _separator.frame = CGRectMake(inset, rowHeight - 0.5f, MAX(0, width - inset), 0.5f);
    CGFloat y = rowHeight + PREVIEW_GAP;
    CGSize text = [_bubbleText sizeThatFits:CGSizeMake(width - 120, 40)];
    CGFloat bubbleWidth = text.width + 28;
    /* a message of ours stands at the right edge */
    _bubble.frame = CGRectMake(width - 16 - bubbleWidth, y, bubbleWidth, PREVIEW_BUBBLE);
    _bubbleText.frame = CGRectMake(14, (PREVIEW_BUBBLE - text.height) / 2, text.width, text.height);
    y += PREVIEW_BUBBLE + 12;
    _field.frame = CGRectMake(16, y, MAX(0, width - 32 - PREVIEW_FIELD - 8), PREVIEW_FIELD);
    _placeholder.frame = CGRectMake(16, 0, MAX(0, _field.bounds.size.width - 32), PREVIEW_FIELD);
    _send.frame = CGRectMake(width - 16 - PREVIEW_FIELD, y, PREVIEW_FIELD, PREVIEW_FIELD);
    y += PREVIEW_FIELD + PREVIEW_GAP;
    /* the bar of the app, with the pill that stands behind the icon of the tab that is open */
    _bar.frame = CGRectMake(16, y, MAX(0, width - 32), PREVIEW_BAR);
    CGFloat slot = _bar.bounds.size.width / (CGFloat)MAX((NSUInteger)1, _tabIcons.count);
    for (NSUInteger i = 0; i < _tabIcons.count; ++i) ((UIView *)[_tabIcons objectAtIndex:i]).frame = CGRectMake(slot * i, 0, slot, PREVIEW_BAR);
    _indicator.frame = CGRectMake((slot - 56) / 2, (PREVIEW_BAR - 28) / 2, 56, 28);
}

@end

#define CLASSIC_BAR 44.0
#define CLASSIC_STRIP 76.0
#define CLASSIC_ROW 40.0

/* the two rows of the preview, drawn with the separator the person chose */
@interface ExteriaClassicRowsView : UIView
@end

@implementation ExteriaClassicRowsView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) self.contentMode = UIViewContentModeRedraw;
    return self;
}
- (void)drawRect:(CGRect)dirty {
    (void)dirty;
    CGFloat width = self.bounds.size.width, pixel = 1.0 / ExteriaScreenScale();
    [ExteriaColorCard() setFill];
    UIRectFill(self.bounds);
    UIFont *font = [UIFont boldSystemFontOfSize:15];
    [ExteriaColorTitle() set];
    [NSLocalizedString(@"custom.classic.row1", nil) drawAtPoint:CGPointMake(16, 11) withFont:font];
    [NSLocalizedString(@"custom.classic.row2", nil) drawAtPoint:CGPointMake(16, CLASSIC_ROW + 11) withFont:font];
    NSInteger style = ExteriaClassicSeparators();
    if (style == 2) return;
    BOOL dark = ExteriaThemeIsDark();
    CGFloat y = CLASSIC_ROW - pixel;
    [(dark ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor colorWithWhite:0 alpha:0.2]) setFill];
    UIRectFill(CGRectMake(style == 1 ? 0 : 10, y, width - (style == 1 ? 0 : 10), pixel));
    /* the etched line has a lit line under the dark one */
    if (style == 1) {
        [(dark ? [UIColor colorWithWhite:1 alpha:0.06] : [UIColor colorWithWhite:1 alpha:0.9]) setFill];
        UIRectFill(CGRectMake(0, y + pixel, width, pixel));
    }
}
@end

@interface ExteriaClassicPreviewView () {
    UIImageView *_bar;
    UILabel *_title;
    UIView *_strip;
    UIImageView *_button;
    UILabel *_buttonText;
    ExteriaAvatarView *_avatar;
    ExteriaClassicRowsView *_rows;
}
@end

@implementation ExteriaClassicPreviewView

+ (CGFloat)height {
    return CLASSIC_BAR + CLASSIC_STRIP + 2 * CLASSIC_ROW;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    _strip = [[UIView alloc] init];
    [self addSubview:_strip];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.initials = @"s";
    _avatar.seed = 3;
    [_strip addSubview:_avatar];
    _button = [[UIImageView alloc] init];
    [_strip addSubview:_button];
    _buttonText = [[UILabel alloc] init];
    _buttonText.backgroundColor = [UIColor clearColor];
    _buttonText.textColor = [UIColor whiteColor];
    _buttonText.font = [UIFont boldSystemFontOfSize:14];
    _buttonText.textAlignment = ExteriaTextAlignmentCenter;
    _buttonText.text = NSLocalizedString(@"chat.send", nil);
    [_button addSubview:_buttonText];
    _rows = [[ExteriaClassicRowsView alloc] init];
    [self addSubview:_rows];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = [UIColor whiteColor];
    _title.font = [UIFont boldSystemFontOfSize:18];
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.text = @"sqmrak";
    _title.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    _title.shadowOffset = CGSizeMake(0, -1);
    [self addSubview:_title];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_bar release];
    [_title release];
    [_strip release];
    [_button release];
    [_buttonText release];
    [_avatar release];
    [_rows release];
    [super dealloc];
}

- (void)setPicture:(UIImage *)picture {
    [_avatar showImage:picture];
}

- (void)refresh {
    [_bar removeFromSuperview];
    [_bar release];
    _bar = [ExteriaClassicStripBackdrop() retain];
    [self insertSubview:_bar atIndex:0];
    _strip.backgroundColor = ExteriaClassicLinenColor(ExteriaThemeIsDark());
    _button.image = ExteriaClassicGlossButtonImage(ExteriaClassicGlossSlate, NO);
    [_avatar setNeedsDisplay];
    [_avatar setNeedsLayout];
    [_rows setNeedsDisplay];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _bar.frame = CGRectMake(0, 0, width, CLASSIC_BAR);
    _title.frame = CGRectMake(40, 0, width - 80, CLASSIC_BAR);
    _strip.frame = CGRectMake(0, CLASSIC_BAR, width, CLASSIC_STRIP);
    _avatar.frame = CGRectMake(16, (CLASSIC_STRIP - 48) / 2, 48, 48);
    _button.frame = CGRectMake(width - 16 - 90, (CLASSIC_STRIP - 34) / 2, 90, 34);
    _buttonText.frame = _button.bounds;
    _rows.frame = CGRectMake(0, CLASSIC_BAR + CLASSIC_STRIP, width, 2 * CLASSIC_ROW);
}

@end
