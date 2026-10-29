#import "exteria_sticker_pack_sheet.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_platform.h"
#import "exteria_plural.h"
#import "exteria_popup_menu.h"
#import "exteria_session_stickermanage.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define CARD_RADIUS 28.0
#define CARD_WIDTH_MAX 420.0
#define CARD_MARGIN 12.0
#define HEADER_HEIGHT 76.0
#define FOOTER_HEIGHT 56.0
#define COLUMNS 5
#define GRID_PAD 6.0
#define DIM_ALPHA 0.5
#define ROUND_BUTTON 44.0

@interface ExteriaStickerPackSheet () {
    ExteriaSession *_session;
    ExteriaMediaCache *_media;
    void (^_sender)(ExteriaMedia *);
    long long _setId;
    long long _accessHash;
    ExteriaStickerSet *_set;
    NSArray *_stickers;
    BOOL _installed;
    BOOL _working;
    BOOL _closing;
    UIView *_dim;
    UIView *_card;
    UIButton *_close;
    UILabel *_title;
    UILabel *_name;
    UIButton *_more;
    UIScrollView *_grid;
    UIView *_rule;
    UIButton *_action;
    UIActivityIndicatorView *_spinner;
    UILabel *_note;
    UILabel *_copied;
    ExteriaPopupMenu *_menu;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaStickerPackSheet

+ (BOOL)presentInView:(UIView *)host forSticker:(ExteriaMedia *)sticker session:(ExteriaSession *)session media:(ExteriaMediaCache *)media
               sender:(void (^)(ExteriaMedia *))sender {
    if (!sticker.stickerSetId || !session || !host) return NO;
    ExteriaStickerPackSheet *sheet = [[[ExteriaStickerPackSheet alloc] initWithFrame:host.bounds] autorelease];
    sheet->_session = [session retain];
    sheet->_media = [media retain];
    sheet->_sender = [sender copy];
    sheet->_setId = sticker.stickerSetId;
    sheet->_accessHash = sticker.stickerSetHash;
    [host addSubview:sheet];
    [sheet enter];
    [sheet load];
    return YES;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _dim = [[UIView alloc] init];
    _dim.backgroundColor = [UIColor blackColor];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)] autorelease]];
    [self addSubview:_dim];
    _card = [[UIView alloc] init];
    _card.backgroundColor = ExteriaColorCard();
    _card.layer.cornerRadius = CARD_RADIUS;
    _card.clipsToBounds = YES;
    [self addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(close));
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_close setImage:ExteriaSymbolImage(ExteriaSymbolClose, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    _close.accessibilityLabel = NSLocalizedString(@"attach.cancel", nil);
    [_card addSubview:_close];
    _title = [[UILabel alloc] init];
    _title.backgroundColor = [UIColor clearColor];
    _title.font = ExteriaFontBold(20);
    _title.textColor = ExteriaColorTitle();
    [_card addSubview:_title];
    _name = [[UILabel alloc] init];
    _name.backgroundColor = [UIColor clearColor];
    _name.font = ExteriaFontRegular(17);
    _name.textColor = ExteriaColorAccent();
    [_card addSubview:_name];
    _more = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _more.backgroundColor = ExteriaColorField();
    _more.layer.cornerRadius = ROUND_BUTTON / 2;
    [_more setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_more addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    _more.accessibilityLabel = NSLocalizedString(@"attach.more", nil);
    _more.hidden = YES;
    [_card addSubview:_more];
    _grid = [[UIScrollView alloc] init];
    _grid.alwaysBounceVertical = YES;
    _grid.scrollsToTop = NO;
    [_card addSubview:_grid];
    _rule = [[UIView alloc] init];
    _rule.backgroundColor = ExteriaColorHairline();
    [_card addSubview:_rule];
    _action = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _action.titleLabel.font = ExteriaFontSemibold(16);
    [_action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    _action.hidden = YES;
    [_card addSubview:_action];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_card addSubview:_spinner];
    _note = [[UILabel alloc] init];
    _note.backgroundColor = [UIColor clearColor];
    _note.font = ExteriaFontRegular(15);
    _note.textColor = ExteriaColorSecondary();
    _note.textAlignment = ExteriaTextAlignmentCenter;
    _note.numberOfLines = 0;
    [_card addSubview:_note];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [_sender release];
    [_set release];
    [_stickers release];
    [_dim release]; [_card release]; [_close release]; [_title release]; [_name release]; [_more release]; [_grid release];
    [_rule release]; [_action release]; [_spinner release]; [_note release]; [_copied release]; [_menu release];
    [super dealloc];
}

#pragma mark layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _dim.frame = self.bounds;
    CGFloat width = MIN(size.width - 2 * CARD_MARGIN, CARD_WIDTH_MAX);
    CGFloat height = MIN(size.height - 2 * 40, 580);
    _card.frame = CGRectMake(floor((size.width - width) / 2), floor((size.height - height) / 2), width, height);
    _close.frame = CGRectMake(10, 14, 48, 48);
    _more.frame = CGRectMake(width - 14 - ROUND_BUTTON, 16, ROUND_BUTTON, ROUND_BUTTON);
    CGFloat textLeft = 64, textWidth = width - textLeft - 14 - ROUND_BUTTON - 10;
    _title.frame = CGRectMake(textLeft, 12, textWidth, 28);
    _name.frame = CGRectMake(textLeft, 40, textWidth, 24);
    CGFloat footer = _action.hidden ? 0 : FOOTER_HEIGHT;
    _grid.frame = CGRectMake(0, HEADER_HEIGHT, width, height - HEADER_HEIGHT - footer);
    _rule.frame = CGRectMake(0, height - footer, width, 1.0 / ExteriaScreenScale());
    _rule.hidden = !footer;
    _action.frame = CGRectMake(0, height - footer, width, footer);
    _spinner.center = CGPointMake(width / 2, height / 2);
    _note.frame = CGRectMake(24, HEADER_HEIGHT, width - 48, height - HEADER_HEIGHT - 24);
    [self layoutStickers];
}

- (void)layoutStickers {
    CGFloat width = _grid.bounds.size.width;
    CGFloat side = floor((width - 2 * GRID_PAD) / COLUMNS);
    NSUInteger count = _stickers.count;
    NSUInteger rows = (count + COLUMNS - 1) / COLUMNS;
    _grid.contentSize = CGSizeMake(width, GRID_PAD * 2 + side * (CGFloat)rows);
    for (UIView *view in _grid.subviews) {
        NSInteger index = view.tag - 1;
        if (index < 0 || index >= (NSInteger)count) continue;
        NSInteger row = index / COLUMNS, column = index % COLUMNS;
        view.frame = CGRectMake(GRID_PAD + side * (CGFloat)column, GRID_PAD + side * (CGFloat)row, side, side);
    }
}

#pragma mark showing

- (void)enter {
    [self layoutIfNeeded];
    _card.transform = CGAffineTransformMakeScale(0.9, 0.9);
    _card.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ _dim.alpha = DIM_ALPHA; }];
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_SPRING, nil);
    _spinner.hidden = NO;
    [_spinner startAnimating];
}

- (void)close {
    if (_closing) return;
    _closing = YES;
    [_menu dismiss];
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18 animations:^{ _dim.alpha = 0; _card.alpha = 0; _card.transform = CGAffineTransformMakeScale(0.94, 0.94); }
                     completion:^(BOOL finished) { (void)finished; [self removeFromSuperview]; }];
}

#pragma mark pack

- (void)load {
    ExteriaWeakReference *weak = _weak;
    [_session loadStickerPackWithId:_setId accessHash:_accessHash completion:^(ExteriaStickerSet *set, NSArray *stickers, NSString *errorName) {
        ExteriaStickerPackSheet *sheet = weak.target;
        if (!sheet) return;
        [sheet->_spinner stopAnimating];
        if (!set || !stickers.count) {
            NSLog(@"exteria: the sticker pack did not load: %@", errorName);
            sheet->_note.text = NSLocalizedString(@"pack.failed", nil);
            return;
        }
        [sheet showSet:set stickers:stickers];
    }];
}

- (void)showSet:(ExteriaStickerSet *)set stickers:(NSArray *)stickers {
    /* a cached pack can return the sheet's current objects */
    [set retain];
    [stickers retain];
    [_set release];
    _set = set;
    [_stickers release];
    _stickers = stickers;
    _installed = set.row.installed != 0;
    _title.text = set.title;
    _name.text = set.row.short_name[0] ? [@"@" stringByAppendingString:[NSString stringWithUTF8String:set.row.short_name]] : @"";
    _more.hidden = !set.row.short_name[0];
    _action.hidden = NO;
    [self refreshAction];
    CGFloat width = _grid.bounds.size.width;
    CGFloat side = floor((width - 2 * GRID_PAD) / COLUMNS);
    CGFloat shown = ceil(side * ExteriaScreenScale());
    for (NSUInteger i = 0; i < stickers.count; ++i) {
        ExteriaMedia *media = [[stickers objectAtIndex:i] media];
        UIImageView *view = [[[UIImageView alloc] init] autorelease];
        view.contentMode = UIViewContentModeScaleAspectFit;
        view.tag = (NSInteger)i + 1;
        view.userInteractionEnabled = YES;
        [view addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(stickerTapped:)] autorelease]];
        [_grid addSubview:view];
        /* the small preview of the server first, the file itself when the pack has none, as the sticker panel does */
        ExteriaRemoteFile *file = media.stickerFormat == EXTERIA_STICKER_STATIC ? media.file : (media.previewFile ? media.previewFile : media.file);
        UIImage *ready = [_media cachedImageForFile:file maxSide:shown - 12];
        if (ready) { view.image = ready; continue; }
        ExteriaWeakReference *weak = _weak;
        [_media loadImageForFile:file maxSide:shown - 12 completion:^(UIImage *image) {
            if (!weak.target) return;
            if (image) view.image = image;
            else if (file != media.file) [_media loadImageForFile:media.file maxSide:shown - 12 completion:^(UIImage *poster) {
                if (weak.target && poster) view.image = poster;
            }];
        }];
    }
    [self setNeedsLayout];
}

- (void)refreshAction {
    NSString *form = [(_installed ? @"pack.remove." : @"pack.add.") stringByAppendingString:ExteriaPluralForm((NSInteger)_stickers.count)];
    [_action setTitle:[NSString stringWithFormat:NSLocalizedString(form, nil), (long)_stickers.count] forState:UIControlStateNormal];
    /* adding takes the accent of the chat, taking away the red that says it undoes something */
    [_action setTitleColor:_installed ? ExteriaColorBadgeRed() : ExteriaColorAccent() forState:UIControlStateNormal];
    [_action setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    _action.enabled = !_working;
}

- (void)actionTapped {
    if (_working || !_set) return;
    _working = YES;
    [self refreshAction];
    ExteriaWeakReference *weak = _weak;
    void (^finished)(NSString *) = ^(NSString *errorName) {
        ExteriaStickerPackSheet *sheet = weak.target;
        if (!sheet) return;
        sheet->_working = NO;
        if (errorName) {
            NSLog(@"exteria: the sticker pack was not changed: %@", errorName);
            ExteriaShowNotice(nil, NSLocalizedString(@"pack.error", nil));
        } else {
            sheet->_installed = !sheet->_installed;
        }
        [sheet refreshAction];
    };
    if (_installed) [_session uninstallStickerSet:_set completion:finished];
    else [_session installStickerSet:_set completion:finished];
}

- (void)stickerTapped:(UITapGestureRecognizer *)tap {
    NSInteger index = tap.view.tag - 1;
    if (index < 0 || index >= (NSInteger)_stickers.count || !_sender) return;
    ExteriaMedia *media = [[_stickers objectAtIndex:(NSUInteger)index] media];
    void (^send)(ExteriaMedia *) = [_sender retain];
    [self close];
    send(media);
    [send release];
}

#pragma mark menu

- (void)showMenu {
    if (!_set.row.short_name[0]) return;
    ExteriaSymbol symbols[] = {ExteriaSymbolCopy};
    ExteriaWeakReference *weak = _weak;
    [_menu release];
    _menu = [[ExteriaPopupMenu alloc] initWithTitles:[NSArray arrayWithObject:NSLocalizedString(@"pack.copy", nil)] symbols:symbols handler:^(NSUInteger index) {
        (void)index;
        [(ExteriaStickerPackSheet *)weak.target copyLink];
    }];
    CGPoint anchor = [self convertPoint:CGPointMake(CGRectGetMaxX(_more.frame) - 4, CGRectGetMaxY(_more.frame) - 6) fromView:_card];
    [_menu showInView:self anchor:anchor];
}

- (void)copyLink {
    NSString *link = [@"https://t.me/addstickers/" stringByAppendingString:[NSString stringWithUTF8String:_set.row.short_name]];
    [UIPasteboard generalPasteboard].string = link;
    if (!_copied) {
        _copied = [[UILabel alloc] init];
        _copied.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        _copied.textColor = [UIColor whiteColor];
        _copied.font = ExteriaFontMedium(14);
        _copied.textAlignment = ExteriaTextAlignmentCenter;
        _copied.layer.cornerRadius = 14;
        _copied.layer.masksToBounds = YES;
    }
    _copied.text = NSLocalizedString(@"pack.copied", nil);
    CGFloat width = ceil([_copied.text sizeWithFont:_copied.font].width) + 28;
    _copied.frame = CGRectMake(floor((_card.bounds.size.width - width) / 2), _card.bounds.size.height - FOOTER_HEIGHT - 48, width, 28);
    _copied.alpha = 0;
    [_card addSubview:_copied];
    [UIView animateWithDuration:0.2 animations:^{ _copied.alpha = 1; } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _copied.alpha = 0; } completion:nil];
    }];
}

@end
