#import "exteria_gift_compose_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

#define NOTE_LIMIT 255
#define STICKER_SIDE 132.0

@interface ExteriaGiftComposeController () <UITextFieldDelegate, UIAlertViewDelegate> {
    ExteriaDialog *_dialog;
    ExteriaStarGift *_gift;
    UIScrollView *_scroll;
    UIImageView *_picture;
    ExteriaLottieView *_animation;
    UILabel *_name;
    UILabel *_detail;
    UIImageView *_price;
    UILabel *_to;
    UIView *_card;
    UITextField *_note;
    UILabel *_hideLabel;
    UISwitch *_hide;
    UILabel *_upgradeLabel;
    UISwitch *_upgrade;
    UIButton *_send;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    ExteriaPaymentQuote *_quote;
    CGFloat _keyboardOverlap;
    void (^_sentHandler)(void);
}
@end

@implementation ExteriaGiftComposeController

@synthesize sentHandler = _sentHandler;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog gift:(ExteriaStarGift *)gift
              avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _gift = [gift retain];
    self.screenTitle = NSLocalizedString(@"gifts.send", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _note.delegate = nil;
    [_dialog release];
    [_gift release];
    [_scroll release];
    [_picture release];
    [_animation release];
    [_name release];
    [_detail release];
    [_price release];
    [_to release];
    [_card release];
    [_note release];
    [_hideLabel release];
    [_hide release];
    [_upgradeLabel release];
    [_upgrade release];
    [_send release];
    [_spinner release];
    [_quote release];
    [_sentHandler release];
    [super dealloc];
}

static UILabel *ExteriaComposeLabel(UIColor *color, CGFloat size, BOOL bold) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = bold ? ExteriaFontSemibold(size) : ExteriaFontRegular(size);
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = YES;
    [root addSubview:_scroll];
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [_scroll addSubview:_picture];
    _name = ExteriaComposeLabel(ExteriaColorTitle(), 20, YES);
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.text = _gift.title.length ? _gift.title : NSLocalizedString(@"gifts.gift", nil);
    [_scroll addSubview:_name];
    _detail = ExteriaComposeLabel(ExteriaColorSecondary(), 14, NO);
    _detail.textAlignment = ExteriaTextAlignmentCenter;
    _detail.text = _gift.limited ? [NSString stringWithFormat:NSLocalizedString(@"gifts.left", nil), (int)_gift.remains, (int)_gift.total] : @"";
    [_scroll addSubview:_detail];
    _price = [[UIImageView alloc] initWithImage:ExteriaStarsImage(nil, _gift.stars, ExteriaFontSemibold(17), ExteriaColorTitle())];
    _price.contentMode = UIViewContentModeCenter;
    [_scroll addSubview:_price];
    _to = ExteriaComposeLabel(ExteriaColorSecondary(), 14, NO);
    _to.textAlignment = ExteriaTextAlignmentCenter;
    _to.text = _dialog.saved ? NSLocalizedString(@"gifts.to.self", nil) : [NSString stringWithFormat:NSLocalizedString(@"gifts.to", nil), _dialog.title];
    [_scroll addSubview:_to];

    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = 12;
    [_scroll addSubview:_card];
    _note = [[UITextField alloc] init];
    _note.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _note.delegate = self;
    _note.placeholder = NSLocalizedString(@"gifts.note", nil);
    _note.font = ExteriaFontRegular(16);
    _note.textColor = ExteriaColorTitle();
    _note.returnKeyType = UIReturnKeyDone;
    _note.clearButtonMode = UITextFieldViewModeWhileEditing;
    _note.keyboardAppearance = ExteriaThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [_card addSubview:_note];
    _hideLabel = ExteriaComposeLabel(ExteriaColorTitle(), 16, NO);
    _hideLabel.text = NSLocalizedString(@"gifts.hide", nil);
    _hideLabel.numberOfLines = 0;
    [_card addSubview:_hideLabel];
    _hide = [[UISwitch alloc] init];
    [_card addSubview:_hide];
    if (_gift.upgradeStars > 0) {
        _upgradeLabel = ExteriaComposeLabel(ExteriaColorTitle(), 16, NO);
        _upgradeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"gifts.upgrade.include", nil), ExteriaStarsText(_gift.upgradeStars)];
        _upgradeLabel.numberOfLines = 0;
        [_card addSubview:_upgradeLabel];
        _upgrade = [[UISwitch alloc] init];
        [_card addSubview:_upgrade];
    }
    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.backgroundColor = ExteriaColorAccent();
    _send.layer.cornerRadius = 12;
    _send.titleLabel.font = ExteriaFontSemibold(17);
    [_send setImage:ExteriaStarsImage(NSLocalizedString(@"gifts.send.for", nil), _gift.stars, ExteriaFontSemibold(17), [UIColor whiteColor]) forState:UIControlStateNormal];
    [_send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_send];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    [self showPicture];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

/* the animation plays once its file is here; the thumbnail stands in until then */
- (void)showPicture {
    ExteriaMedia *sticker = _gift.sticker;
    ExteriaRemoteFile *thumb = sticker.previewFile;
    if (thumb) {
        [self.media loadImageForFile:thumb maxSide:STICKER_SIDE * ExteriaScreenScale() completion:^(UIImage *image) {
            if (image && !_animation) _picture.image = image;
        }];
    }
    ExteriaRemoteFile *file = sticker.file;
    if (!file || sticker.stickerFormat != EXTERIA_STICKER_ANIMATED) return;
    [self retain];
    [self.media loadDataForFile:file completion:^(NSData *data) {
        [self autorelease];
        if (!data) return;
        _animation = [[ExteriaLottieView alloc] initWithPackedData:data key:file.key];
        [_scroll addSubview:_animation];
        [self.view setNeedsLayout];
        [_animation setPlaying:YES];
        _picture.hidden = YES;
    }];
}

- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat width = body.size.width;
    CGFloat inner = MIN(width - 32, 460);
    CGFloat x = (width - inner) / 2;
    CGFloat y = 18;
    CGRect sticker = CGRectMake((width - STICKER_SIDE) / 2, y, STICKER_SIDE, STICKER_SIDE);
    _picture.frame = sticker;
    _animation.frame = sticker;
    y += STICKER_SIDE + 8;
    _name.frame = CGRectMake(x, y, inner, 26);
    y += 28;
    _price.frame = CGRectMake(x, y, inner, 24);
    y += 26;
    _detail.frame = CGRectMake(x, y, _gift.limited ? inner : 0, _gift.limited ? 20 : 0);
    y += _gift.limited ? 22 : 0;
    _to.frame = CGRectMake(x, y, inner, 20);
    y += 34;
    CGFloat rows = _upgrade ? 3 : 2;
    _card.frame = CGRectMake(x, y, inner, rows * 52);
    _note.frame = CGRectMake(14, 0, inner - 28, 52);
    _hideLabel.frame = CGRectMake(14, 52, inner - 14 - 70, 52);
    _hide.center = CGPointMake(inner - 14 - _hide.bounds.size.width / 2, 78);
    if (_upgrade) {
        _upgradeLabel.frame = CGRectMake(14, 104, inner - 14 - 70, 52);
        _upgrade.center = CGPointMake(inner - 14 - _upgrade.bounds.size.width / 2, 130);
    }
    y += rows * 52 + 22;
    _send.frame = CGRectMake(x, y, inner, 50);
    _spinner.center = CGPointMake(CGRectGetMaxX(_send.frame) - 28, CGRectGetMidY(_send.frame));
    y += 50 + 24;
    _scroll.contentSize = CGSizeMake(width, y);
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, _keyboardOverlap, 0);
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:[self.view.window convertRect:frame fromWindow:nil] fromView:nil];
    BOOL showing = [note.name isEqualToString:UIKeyboardWillShowNotification];
    _keyboardOverlap = showing ? MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame)) : 0;
    [self.view setNeedsLayout];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *next = [field.text stringByReplacingCharactersInRange:range withString:string];
    return [next lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= NOTE_LIMIT;
}

#pragma mark paying

- (void)setWorking:(BOOL)working {
    _working = working;
    _send.enabled = !working;
    _send.alpha = working ? 0.6 : 1;
    if (working) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)sendTapped {
    if (_working) return;
    [_note resignFirstResponder];
    [self setWorking:YES];
    NSString *note = [_note.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self retain];
    [self.session quoteSendingGift:_gift toDialog:_dialog note:note hideName:_hide.on includeUpgrade:_upgrade.on completion:^(ExteriaPaymentQuote *quote, NSString *errorName) {
        [self autorelease];
        if (!quote) {
            [self setWorking:NO];
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [_quote release];
        _quote = [quote retain];
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil
                                             message:[NSString stringWithFormat:NSLocalizedString(@"gifts.confirm", nil), ExteriaStarsText(quote.stars), _dialog.saved ? NSLocalizedString(@"gifts.you", nil) : _dialog.title]
                                            delegate:self cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil)
                                   otherButtonTitles:NSLocalizedString(@"gifts.pay", nil), nil];
        [alert show];
        [alert release];
    }];
}

- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == [alert cancelButtonIndex]) {
        [self setWorking:NO];
        return;
    }
    [self retain];
    [self.session payQuote:_quote completion:^(NSString *errorName) {
        [self autorelease];
        [self setWorking:NO];
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        if (_sentHandler) _sentHandler();
    }];
}

@end
