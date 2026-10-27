#import "exteria_input_panel.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_animation.h"
#import "exteria_emoji_store.h"
#import "exteria_symbol.h"
#import "exteria_string_drawing.h"
#import "exteria_theme.h"

#define PILL_HEIGHT 38.0
#define PILL_MARGIN 8.0
#define SEGMENT_MIN 72.0
#define BACKSPACE_WIDTH 48.0
/* the room the lists leave at the foot, under the pill, so the last row can be scrolled out from under it */
#define FOOT (PILL_HEIGHT + 2 * PILL_MARGIN)

typedef enum { ExteriaPageEmoji, ExteriaPageGifs, ExteriaPageStickers, ExteriaPageCustom } ExteriaPage;

@interface ExteriaInputPanel () <UIGestureRecognizerDelegate> {
    ExteriaEmojiPicker *_emoji;
    ExteriaGifPicker *_gifs;
    ExteriaStickerPicker *_stickers;
    ExteriaCustomEmojiPicker *_custom;
    UIView *_pill;
    UIButton *_emojiTab;
    UIButton *_gifTab;
    UIButton *_stickerTab;
    UIButton *_customTab;
    UIView *_marker;
    UIButton *_backspace;
    NSTimer *_repeat;
    ExteriaPage _page;
}
@end

@implementation ExteriaInputPanel

@synthesize delegate = _delegate;

- (UIButton *)segmentWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = ExteriaFontSemibold(15);
    /* a segment squeezed by the delete key keeps its whole word */
    ExteriaLabelFitToWidth(button.titleLabel, 11);
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_pill addSubview:button];
    return button;
}

- (id)initWithMedia:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorBar();
    _emoji = [[ExteriaEmojiPicker alloc] init];
    _emoji.delegate = self;
    [self addSubview:_emoji];
    _stickers = [[ExteriaStickerPicker alloc] initWithMedia:media library:library];
    _stickers.delegate = self;
    _stickers.bottomInset = FOOT;
    _stickers.hidden = YES;
    [self addSubview:_stickers];
    _pill = [[UIView alloc] init];
    _pill.backgroundColor = [ExteriaColorField() colorWithAlphaComponent:0.96];
    _pill.layer.cornerRadius = PILL_HEIGHT / 2;
    _pill.layer.borderColor = ExteriaColorHairline().CGColor;
    _pill.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    [self addSubview:_pill];
    _marker = [[UIView alloc] init];
    _marker.backgroundColor = [ExteriaColorAccent() colorWithAlphaComponent:0.2];
    _marker.layer.cornerRadius = (PILL_HEIGHT - 8) / 2;
    [_pill addSubview:_marker];
    _emojiTab = [[self segmentWithTitle:NSLocalizedString(@"panel.emoji", nil) action:@selector(showEmoji)] retain];
    _stickerTab = [[self segmentWithTitle:NSLocalizedString(@"panel.stickers", nil) action:@selector(showStickers)] retain];
    _backspace = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_backspace setImage:ExteriaSymbolImage(ExteriaSymbolBackspace, 24, ExteriaColorSecondary()) forState:UIControlStateNormal];
    [_backspace addTarget:self action:@selector(backspaceDown) forControlEvents:UIControlEventTouchDown];
    [_backspace addTarget:self action:@selector(backspaceUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:_backspace];
    for (NSUInteger i = 0; i < 2; ++i) {
        UISwipeGestureRecognizer *swipe = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(pageSwiped:)] autorelease];
        swipe.delegate = self;
        swipe.direction = i ? UISwipeGestureRecognizerDirectionRight : UISwipeGestureRecognizerDirectionLeft;
        [self addGestureRecognizer:swipe];
    }
    [self refreshTabs];
    return self;
}

- (void)dealloc {
    [_repeat invalidate];
    _emoji.delegate = nil;
    _stickers.delegate = nil;
    _gifs.delegate = nil;
    [_emoji release];
    [_stickers release];
    [_gifs release];
    _custom.delegate = nil;
    [_custom release];
    [_pill release];
    [_marker release];
    [_customTab release];
    [_gifTab release];
    [_emojiTab release];
    [_stickerTab release];
    [_backspace release];
    [super dealloc];
}

/* the tabs that exist, left to right */
- (NSArray *)pages {
    NSMutableArray *pages = [NSMutableArray arrayWithObject:[NSNumber numberWithInt:ExteriaPageEmoji]];
    if (_gifs) [pages addObject:[NSNumber numberWithInt:ExteriaPageGifs]];
    [pages addObject:[NSNumber numberWithInt:ExteriaPageStickers]];
    if (_custom) [pages addObject:[NSNumber numberWithInt:ExteriaPageCustom]];
    return pages;
}

- (UIButton *)tabOfPage:(ExteriaPage)page {
    switch (page) {
    case ExteriaPageEmoji: return _emojiTab;
    case ExteriaPageGifs: return _gifTab;
    case ExteriaPageStickers: return _stickerTab;
    case ExteriaPageCustom: return _customTab;
    }
    return nil;
}

- (void)refreshTabs {
    for (NSNumber *page in [self pages]) {
        UIButton *tab = [self tabOfPage:(ExteriaPage)page.intValue];
        BOOL current = (ExteriaPage)page.intValue == _page;
        [tab setTitleColor:current ? ExteriaColorTitle() : ExteriaColorSecondary() forState:UIControlStateNormal];
        if (page.intValue == ExteriaPageCustom) [tab setImage:ExteriaSymbolImage(ExteriaSymbolStar, 22, current ? ExteriaColorAccent() : ExteriaColorSecondary()) forState:UIControlStateNormal];
    }
    _backspace.hidden = _page == ExteriaPageStickers || _page == ExteriaPageGifs;
    [self setNeedsLayout];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    for (UIView *view = touch.view; view && view != self; view = view.superview) {
        if ([view isKindOfClass:[UIScrollView class]]) {
            UIScrollView *scroll = (UIScrollView *)view;
            if (scroll.contentSize.width > scroll.bounds.size.width + 1) return NO;
        }
    }
    return YES;
}

- (void)pageSwiped:(UISwipeGestureRecognizer *)swipe {
    NSArray *pages = [self pages];
    NSInteger at = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:_page]];
    NSInteger next = at + (swipe.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1);
    if (next < 0 || next >= (NSInteger)pages.count) return;
    [self showPage:(ExteriaPage)[[pages objectAtIndex:(NSUInteger)next] intValue]];
}

- (UIView *)viewOfPage:(ExteriaPage)page {
    switch (page) {
    case ExteriaPageEmoji: return _emoji;
    case ExteriaPageGifs: return _gifs;
    case ExteriaPageStickers: return _stickers;
    case ExteriaPageCustom: return _custom;
    }
    return nil;
}

/* a page comes in from the side its tab lies on */
- (void)showPage:(ExteriaPage)page {
    if (page == _page && ![self viewOfPage:page].hidden) return;
    NSArray *pages = [self pages];
    NSInteger from = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:_page]], to = (NSInteger)[pages indexOfObject:[NSNumber numberWithInt:page]];
    for (NSNumber *other in pages) [self viewOfPage:(ExteriaPage)other.intValue].hidden = YES;
    _page = page;
    UIView *view = [self viewOfPage:page];
    view.hidden = NO;
    if (page == ExteriaPageStickers) [_stickers prepare];
    else if (page == ExteriaPageGifs) [_gifs prepare];
    else if (page == ExteriaPageCustom) [_custom prepare];
    [self refreshTabs];
    view.transform = CGAffineTransformMakeTranslation(to >= from ? 16 : -16, 0);
    view.alpha = 0;
    ExteriaAnimateView(view, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
}

- (void)showEmoji { [self showPage:ExteriaPageEmoji]; }
- (void)showGifs { [self showPage:ExteriaPageGifs]; }
- (void)showStickers { [self showPage:ExteriaPageStickers]; }
- (void)showCustom { [self showPage:ExteriaPageCustom]; }

- (void)enableCustomEmojiWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media {
    if (_custom) return;
    _custom = [[ExteriaCustomEmojiPicker alloc] initWithSession:session media:media];
    _custom.delegate = self;
    _custom.hidden = YES;
    [self insertSubview:_custom aboveSubview:_stickers];
    _customTab = [[self segmentWithTitle:nil action:@selector(showCustom)] retain];
    [self refreshTabs];
    [self setNeedsLayout];
}

- (void)enableGifsWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library dialog:(ExteriaDialog *)dialog {
    if (_gifs) return;
    _gifs = [[ExteriaGifPicker alloc] initWithSession:session media:media library:library];
    _gifs.delegate = self;
    _gifs.dialog = dialog;
    _gifs.bottomInset = FOOT;
    _gifs.hidden = YES;
    [self insertSubview:_gifs aboveSubview:_emoji];
    _gifTab = [[self segmentWithTitle:@"GIF" action:@selector(showGifs)] retain];
    [self refreshTabs];
    [self setNeedsLayout];
}

- (void)customEmojiPicker:(ExteriaCustomEmojiPicker *)picker didPickEmoji:(ExteriaCustomEmojiDocument *)emoji {
    (void)picker;
    [_delegate inputPanel:self didPickCustomEmoji:emoji];
}

- (void)gifPicker:(ExteriaGifPicker *)picker didPickGif:(ExteriaMedia *)gif {
    (void)picker;
    [_delegate inputPanel:self didPickGif:gif];
}

- (void)gifPicker:(ExteriaGifPicker *)picker didPickInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId {
    (void)picker;
    [_delegate inputPanel:self didPickInlineResult:result queryId:queryId];
}

- (void)stickerPickerDidTapCreate:(ExteriaStickerPicker *)picker {
    (void)picker;
    [_delegate inputPanelDidTapCreateSticker:self];
}

/* a held delete key repeats, as the system keyboard's does */
- (void)backspaceDown {
    [_delegate inputPanelDidTapBackspace:self];
    [_repeat invalidate];
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.09 target:self selector:@selector(repeatBackspace) userInfo:nil repeats:YES];
    _repeat.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.4];
}

- (void)repeatBackspace {
    [_delegate inputPanelDidTapBackspace:self];
}

- (void)backspaceUp {
    [_repeat invalidate];
    _repeat = nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    /* the emoji grids stop above the pill; the lists of stickers and animations run to the foot and scroll under it */
    CGFloat contentHeight = size.height - FOOT;
    _emoji.frame = CGRectMake(0, 0, size.width, contentHeight);
    _custom.frame = CGRectMake(0, 0, size.width, contentHeight);
    _stickers.frame = CGRectMake(0, 0, size.width, size.height);
    _gifs.frame = CGRectMake(0, 0, size.width, size.height);
    NSArray *pages = [self pages];
    CGFloat width = 0;
    NSMutableArray *widths = [NSMutableArray array];
    for (NSNumber *page in pages) {
        CGFloat segment = page.intValue == ExteriaPageCustom ? 48 : MAX(SEGMENT_MIN, ceil([[[self tabOfPage:(ExteriaPage)page.intValue] titleForState:UIControlStateNormal] sizeWithFont:ExteriaFontSemibold(15)].width) + 28);
        [widths addObject:[NSNumber numberWithDouble:segment]];
        width += segment;
    }
    width += 8;
    /* the delete key stands at the right edge, so a pill that centering would push under it moves left of it, and one that is still too wide gives up width evenly */
    CGFloat limit = size.width - BACKSPACE_WIDTH - 6 - 8;
    if (width > limit - 8) {
        CGFloat factor = MAX(0.5, (limit - 8 - 8) / (width - 8));
        width = 8;
        for (NSUInteger i = 0; i < widths.count; ++i) {
            CGFloat shrunk = floor([[widths objectAtIndex:i] doubleValue] * factor);
            [widths replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:shrunk]];
            width += shrunk;
        }
    }
    CGFloat x = MAX(8, MIN((size.width - width) / 2, limit - width));
    _pill.frame = CGRectMake(x, size.height - PILL_MARGIN - PILL_HEIGHT, width, PILL_HEIGHT);
    CGFloat at = 4;
    for (NSUInteger i = 0; i < pages.count; ++i) {
        ExteriaPage page = (ExteriaPage)[[pages objectAtIndex:i] intValue];
        CGFloat segment = [[widths objectAtIndex:i] doubleValue];
        UIButton *tab = [self tabOfPage:page];
        tab.frame = CGRectMake(at, 0, segment, PILL_HEIGHT);
        if (page == _page) _marker.frame = CGRectMake(at, 4, segment, PILL_HEIGHT - 8);
        at += segment;
    }
    _backspace.frame = CGRectMake(size.width - BACKSPACE_WIDTH - 6, size.height - PILL_MARGIN - PILL_HEIGHT, BACKSPACE_WIDTH, PILL_HEIGHT);
}

- (void)emojiPicker:(ExteriaEmojiPicker *)picker didPickEntry:(size_t)entry {
    (void)picker;
    [_delegate inputPanel:self didPickEmoji:ExteriaEmojiString(entry)];
}

- (void)stickerPicker:(ExteriaStickerPicker *)picker didPickSticker:(ExteriaSticker *)sticker {
    (void)picker;
    [_delegate inputPanel:self didPickSticker:sticker];
}

@end
