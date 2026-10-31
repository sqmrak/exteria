#import "exteria_greeting_view.h"

#import <QuartzCore/QuartzCore.h>


#import "exteria_image_decoder.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define CARD_RADIUS 20.0
#define CARD_PAD 20.0
#define STICKER_SIZE 128.0

@interface ExteriaGreetingView () {
    ExteriaMediaCache *_media;
    ExteriaSticker *_sticker;
    UILabel *_title;
    UILabel *_text;
    UILabel *_note;
    BOOL _intro;
    BOOL _saved;
    UIImageView *_picture;
    ExteriaLottieView *_lottie;
    NSUInteger _token;
}
@end

@implementation ExteriaGreetingView

@synthesize sticker = _sticker;
@synthesize onSend = _onSend;

- (id)initWithMedia:(ExteriaMediaCache *)media {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _media = [media retain];
    self.backgroundColor = ExteriaColorBubbleCapsule();
    self.layer.cornerRadius = CARD_RADIUS;
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.textColor = [UIColor whiteColor];
    _title.textAlignment = ExteriaTextAlignmentCenter;
    _title.font = ExteriaFontSemibold(16);
    _title.text = NSLocalizedString(@"chat.greeting.title", nil);
    [self addSubview:_title];
    _text = [[UILabel alloc] init];
    _text.backgroundColor = [UIColor clearColor];
    _text.textColor = [UIColor whiteColor];
    _text.textAlignment = ExteriaTextAlignmentCenter;
    _text.numberOfLines = 0;
    _text.font = ExteriaFontRegular(15);
    _text.text = NSLocalizedString(@"chat.greeting.text", nil);
    [self addSubview:_text];
    _note = [[UILabel alloc] init];
    _note.backgroundColor = [UIColor clearColor];
    _note.textColor = [UIColor whiteColor];
    _note.textAlignment = ExteriaTextAlignmentCenter;
    _note.numberOfLines = 0;
    _note.font = ExteriaFontRegular(12);
    _note.hidden = YES;
    [self addSubview:_note];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:_picture];
    [self addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)] autorelease]];
    return self;
}

- (void)dealloc {
    [_lottie setPlaying:NO];
    [_media release];
    [_sticker release];
    [_title release];
    [_text release];
    [_note release];
    [_picture release];
    [_lottie release];
    [_onSend release];
    [super dealloc];
}

- (CGSize)cardSizeForWidth:(CGFloat)width {
    CGFloat inner = MIN(width - 64, 300) - 2 * CARD_PAD;
    CGSize text = [_text sizeThatFits:CGSizeMake(inner, 400)];
    CGFloat note = _note.hidden ? 0 : [_note sizeThatFits:CGSizeMake(inner, 200)].height + 12;
    return CGSizeMake(inner + 2 * CARD_PAD, CARD_PAD + 22 + 10 + text.height + 18 + STICKER_SIZE + CARD_PAD + note);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inner = self.bounds.size.width - 2 * CARD_PAD;
    CGSize text = [_text sizeThatFits:CGSizeMake(inner, 400)];
    _title.frame = CGRectMake(CARD_PAD, CARD_PAD, inner, 22);
    _text.frame = CGRectMake(CARD_PAD, CARD_PAD + 32, inner, text.height);
    CGRect stickerFrame = CGRectMake((self.bounds.size.width - STICKER_SIZE) / 2, CGRectGetMaxY(_text.frame) + 18, STICKER_SIZE, STICKER_SIZE);
    _picture.frame = stickerFrame;
    _lottie.frame = stickerFrame;
    _note.frame = CGRectMake(CARD_PAD, CGRectGetMaxY(stickerFrame) + 12, inner, _note.hidden ? 0 : [_note sizeThatFits:CGSizeMake(inner, 200)].height);
}

- (void)showIntroTitle:(NSString *)title text:(NSString *)text sticker:(ExteriaSticker *)sticker author:(NSString *)author {
    _intro = YES;
    if (title.length) _title.text = title;
    if (text.length) _text.text = text;
    _note.text = author.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.intro.note", nil), author] : nil;
    _note.hidden = !_note.text.length;
    if (sticker) [self applySticker:sticker];
    [self setNeedsLayout];
}

- (void)showSavedCard {
    _saved = YES;
    _title.text = NSLocalizedString(@"chat.saved.card.title", nil);
    _text.text = NSLocalizedString(@"chat.saved.card.text", nil);
    _text.textAlignment = ExteriaTextAlignmentLeft;
    [self setNeedsLayout];
}

- (void)showStickers:(NSArray *)stickers {
    if (!stickers.count || _sticker || _intro) return;
    [self applySticker:[stickers objectAtIndex:arc4random() % stickers.count]];
}

- (void)applySticker:(ExteriaSticker *)picked {
    [_sticker release];
    _sticker = [picked retain];
    [_lottie setPlaying:NO];
    [_lottie removeFromSuperview];
    [_lottie release];
    _lottie = nil;
    _picture.image = nil;
    ExteriaMedia *media = picked.media;
    NSUInteger token = ++_token;
    CGFloat side = STICKER_SIZE * ExteriaScreenScale();
    /* the thumbnail fills in until the animation has its first frame */
    if (media.previewFile) {
        [_media loadImageForFile:media.previewFile maxSide:side completion:^(UIImage *image) {
            if (token == _token && image && !_lottie) _picture.image = image;
        }];
    }
    if (media.stickerFormat == EXTERIA_STICKER_ANIMATED && media.file) {
        NSString *key = media.file.key;
        [_media loadDataForFile:media.file completion:^(NSData *data) {
            if (token != _token || !data || ExteriaFileFormatOfData(data) != ExteriaFileFormatGzip) return;
            _lottie = [[ExteriaLottieView alloc] initWithPackedData:data key:key];
            UIImageView *picture = _picture;
            _lottie.firstFrameHandler = ^{ picture.image = nil; };
            _lottie.frame = _picture.frame;
            [_lottie setLoaded:YES];
            [self addSubview:_lottie];
            [_lottie setPlaying:YES];
        }];
    } else if (media.stickerFormat == EXTERIA_STICKER_STATIC && media.file) {
        [_media loadImageForFile:media.file maxSide:side completion:^(UIImage *image) {
            if (token == _token && image) _picture.image = image;
        }];
    }
}

- (void)tapped {
    if (!_saved && _sticker && _onSend) _onSend(_sticker);
}

@end
