#import "exteria_gift_detail_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_gift_folders.h"
#import "exteria_weak_reference.h"
#import "exteria_animation.h"
#import "exteria_dismiss_pan.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_custom_emoji.h"
#import "exteria_emoji_label.h"
#import "exteria_contact_picker_controller.h"
#import "exteria_custom_gift.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"
#import "exteria_gift_backdrop_view.h"
#import "exteria_gift_facts_view.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_user_profile_controller.h"
#import "exteria_time.h"

#define STICKER_SIDE 120.0
#define UNIQUE_STICKER_SIDE 150.0

enum {
    ExteriaDetailAlertConvert = 1,
    ExteriaDetailAlertUpgrade,
    ExteriaDetailAlertTransfer
};

@interface ExteriaGiftDetailController (PopupClosing)
- (void)popupWillClose;
- (BOOL)popupCanClose;
@end

@interface ExteriaGiftPopupController : UIViewController
- (id)initWithDetail:(ExteriaGiftDetailController *)detail;
- (void)showInHost:(UIViewController *)host;
- (void)close;
@end

@interface ExteriaGiftPopupController () {
    UINavigationController *_navigation;
    ExteriaGiftDetailController *_detail;
    UIControl *_dim;
    UIView *_card;
    BOOL _closing;
}
@end

@implementation ExteriaGiftPopupController

- (id)initWithDetail:(ExteriaGiftDetailController *)detail {
    self = [super init];
    if (!self) return nil;
    _detail = detail;
    _navigation = [[UINavigationController alloc] initWithRootViewController:detail];
    _navigation.navigationBarHidden = !ExteriaThemeIsClassic();
    if (ExteriaThemeIsClassic()) {
        detail.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"story.close", nil)
            style:UIBarButtonItemStyleDone target:self action:@selector(close)] autorelease];
    }
    return self;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    root.backgroundColor = [UIColor clearColor];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    _dim = [[UIControl alloc] initWithFrame:root.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dim.backgroundColor = [UIColor blackColor];
    [_dim addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_dim];
    _card = [[UIView alloc] initWithFrame:CGRectZero];
    _card.backgroundColor = ExteriaColorScreen();
    _card.layer.cornerRadius = 18;
    _card.clipsToBounds = YES;
    [root addSubview:_card];
    ExteriaAddDismissPan(_card, self, @selector(close));
    [self addChildViewController:_navigation];
    [_card addSubview:_navigation.view];
    [_navigation didMoveToParentViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* a layout pass in the middle of the slide would set the frame of a card that carries a transform and make it jump */
    if (_closing) return;
    CGSize size = self.view.bounds.size;
    CGFloat width = MIN(size.width, 520);
    CGFloat height = MIN(MAX(0, size.height - 44), 700);
    CGAffineTransform held = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(floor((size.width - width) / 2), size.height - height, width, height);
    _card.transform = held;
    _navigation.view.frame = _card.bounds;
}

- (void)showInHost:(UIViewController *)host {
    [host addChildViewController:self];
    self.view.frame = host.view.bounds;
    [host.view addSubview:self.view];
    [self didMoveToParentViewController:host];
    [self.view layoutIfNeeded];
    _dim.alpha = 0;
    _card.transform = CGAffineTransformMakeTranslation(0, _card.bounds.size.height);
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0.45, EXTERIA_MOTION_ENTER, nil);
    ExteriaAnimateView(_card, CGAffineTransformIdentity, 1, EXTERIA_MOTION_ENTER, nil);
}

- (BOOL)exteriaCanDismissByPan {
    return !_closing && [_detail popupCanClose];
}

- (void)close {
    if (_closing) return;
    if (![_detail popupCanClose]) {
        _card.transform = CGAffineTransformIdentity;
        return;
    }
    _closing = YES;
    self.view.userInteractionEnabled = NO;
    [_detail popupWillClose];
    /* the plate stays whole while it slides: it is told it has left only once it is off the screen, since telling it first tears down its pictures and leaves an empty card moving down */
    ExteriaAnimateView(_dim, CGAffineTransformIdentity, 0, EXTERIA_MOTION_EXIT, nil);
    ExteriaAnimateView(_card, CGAffineTransformMakeTranslation(0, self.view.bounds.size.height - (_card.center.y - _card.bounds.size.height / 2)), 1, EXTERIA_MOTION_EXIT, ^(BOOL finished) {
        (void)finished;
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
    });
}

- (void)dealloc {
    [_detail popupWillClose];
    [_navigation release];
    [_dim release];
    [_card release];
    [super dealloc];
}

@end

@interface ExteriaGiftDetailController () <UIAlertViewDelegate> {
    ExteriaSavedGift *_saved;
    BOOL _mine;
    UIScrollView *_scroll;
    ExteriaGiftBackdropView *_backdrop;
    UIImageView *_picture;
    ExteriaLottieView *_animation;
    ExteriaEmojiLabel *_name;
    ExteriaEmojiLabel *_subtitle;
    ExteriaGiftFactsView *_facts;
    UILabel *_footer;
    UILabel *_customCredit;
    UIButton *_footerLink;
    NSString *_ownerName;
    ExteriaStickerLibrary *_stickers;
    NSMutableArray *_buttons;
    UIButton *_convertButton;
    int32_t _convertPeriod;
    ExteriaWeakReference *_detailWeak;
    ExteriaGiftPopupController *_popup;
    UIActivityIndicatorView *_spinner;
    BOOL _working;
    BOOL _changed;
    ExteriaPaymentQuote *_quote;
    ExteriaDialog *_recipient;
    void (^_changedHandler)(void);
    ExteriaDialog *_folderDialog;
}
@end

@implementation ExteriaGiftDetailController

@synthesize changedHandler = _changedHandler;
@synthesize folderDialog = _folderDialog;
@synthesize ownerName = _ownerName;
@synthesize stickers = _stickers;

- (void)showInViewController:(UIViewController *)host {
    if (_popup || !host.view) return;
    _popup = [[[ExteriaGiftPopupController alloc] initWithDetail:self] autorelease];
    [_popup showInHost:host];
}

- (void)goBack {
    if (_popup) [_popup close];
    else [super goBack];
}

- (void)popupWillClose {
    _popup = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshConvertButton) object:nil];
    if (_changed && _changedHandler) _changedHandler();
    _changed = NO;
}

- (BOOL)popupCanClose { return !_working; }

- (id)initWithSession:(ExteriaSession *)session gift:(ExteriaSavedGift *)gift mine:(BOOL)mine avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _saved = [gift retain];
    /* nothing can be done with the gift of the app, whose profile it is on */
    _mine = mine && !gift.customImageName;
    _buttons = [[NSMutableArray alloc] init];
    _convertPeriod = EXTERIA_GIFT_CONVERT_PERIOD_DEFAULT;
    _detailWeak = [[ExteriaWeakReference referenceTo:self] retain];
    ExteriaStarGift *star = gift.gift;
    self.screenTitle = star.unique ? [NSString stringWithFormat:@"%@ %@", star.title, [self numberText]] : NSLocalizedString(@"gifts.gift", nil);
    return self;
}

- (void)dealloc {
    [_detailWeak clear];
    [_detailWeak release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshConvertButton) object:nil];
    [_saved release];
    [_scroll release];
    [_backdrop release];
    [_picture release];
    [_animation release];
    [_name release];
    [_subtitle release];
    [_facts release];
    [_footer release];
    [_customCredit release];
    [_footerLink release];
    [_ownerName release];
    [_stickers release];
    [_buttons release];
    [_spinner release];
    [_quote release];
    [_recipient release];
    [_changedHandler release];
    [_folderDialog release];
    [super dealloc];
}

static NSString *ExteriaDetailCount(int32_t count);

/* "#227,690" the way the original client writes it, "#001" for the gifts of the app, which count from one */
- (NSString *)numberText {
    int32_t number = _saved.gift.number;
    return _saved.customImageName ? ExteriaCustomGiftNumberText(number) : [@"#" stringByAppendingString:ExteriaDetailCount(number)];
}

- (CGFloat)stickerSide {
    return _saved.gift.unique ? UNIQUE_STICKER_SIDE : STICKER_SIDE;
}

/* "227,690" the way the original client groups a count */
static NSString *ExteriaDetailCount(int32_t count) {
    NSString *digits = [NSString stringWithFormat:@"%d", (int)count];
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < digits.length; ++i) {
        if (i > 0 && (digits.length - i) % 3 == 0) [text appendString:@","];
        [text appendString:[digits substringWithRange:NSMakeRange(i, 1)]];
    }
    return text;
}

static NSString *ExteriaDetailRarity(int32_t permille) {
    if (permille <= 0) return nil;
    return permille % 10 == 0 ? [NSString stringWithFormat:@"%d%%", (int)(permille / 10)] : [NSString stringWithFormat:@"%d.%d%%", (int)(permille / 10), (int)(permille % 10)];
}

- (void)buildBodyInView:(UIView *)root {
    ExteriaStarGift *gift = _saved.gift;
    BOOL unique = gift.unique && gift.hasBackdropColors;
    _scroll = [[UIScrollView alloc] init];
    _scroll.bounces = NO;
    [root addSubview:_scroll];
    if (unique) {
        _backdrop = [[ExteriaGiftBackdropView alloc] init];
        _backdrop.centerColor = gift.backdropCenter;
        _backdrop.edgeColor = gift.backdropEdge;
        _backdrop.patternColor = gift.backdropPattern;
        _backdrop.expressive = _saved.customImageName != nil;
        _backdrop.focus = CGPointMake(0.5, 0.42);
        [_scroll addSubview:_backdrop];
        if (gift.patternSticker) {
            ExteriaGiftLoadPatternSymbol(self.media, gift.patternSticker, gift.backdropPattern, ^(UIImage *symbol) { _backdrop.symbol = symbol; });
        }
    }
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFit;
    [_scroll addSubview:_picture];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.backgroundColor = [UIColor clearColor];
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.font = ExteriaFontBold(22);
    _name.textColor = unique ? [UIColor whiteColor] : ExteriaColorTitle();
    _name.text = [self headline];
    [_scroll addSubview:_name];
    _subtitle = [[ExteriaEmojiLabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.numberOfLines = 0;
    _subtitle.textAlignment = ExteriaTextAlignmentCenter;
    _subtitle.font = ExteriaFontRegular(15);
    _subtitle.textColor = unique ? ExteriaGiftRgb(gift.backdropText) : ExteriaColorSecondary();
    _subtitle.text = [self subtitleText];
    [_scroll addSubview:_subtitle];
    _facts = [[ExteriaGiftFactsView alloc] init];
    _facts.avatars = self.avatars;
    [self fillFacts];
    [_scroll addSubview:_facts];
    if (_saved.customImageName) {
        _customCredit = [[UILabel alloc] init];
        _customCredit.backgroundColor = [UIColor clearColor];
        _customCredit.textColor = ExteriaColorSecondary();
        _customCredit.font = ExteriaFontRegular(13);
        _customCredit.textAlignment = ExteriaTextAlignmentCenter;
        _customCredit.numberOfLines = 0;
        _customCredit.text = @"by sqmrak, not a real telegram gift :3";
        [_scroll addSubview:_customCredit];
    }
    if (_mine) [self buildFooter];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    if (_mine) [self buildButtons];
    if (_mine && !gift.unique && _saved.convertStars > 0) {
        ExteriaWeakReference *weak = _detailWeak;
        [self.session loadGiftConvertPeriod:^(int32_t seconds, NSString *error) {
            ExteriaGiftDetailController *me = weak.target;
            if (!me) return;
            if (error) { NSLog(@"exteria: gift conversion period unavailable: %@", error); return; }
            me->_convertPeriod = seconds;
            [me refreshConvertButton];
        }];
    }
    [self showPicture];
}

- (NSString *)headline {
    ExteriaStarGift *gift = _saved.gift;
    if (gift.unique) return [NSString stringWithFormat:@"%@ %@", gift.title, [self numberText]];
    if (_mine) return NSLocalizedString(@"gifts.detail.mine", nil);
    return gift.title.length ? gift.title : NSLocalizedString(@"gifts.gift", nil);
}

- (NSString *)subtitleText {
    ExteriaStarGift *gift = _saved.gift;
    if (gift.unique) return gift.model;
    return _mine ? NSLocalizedString(@"gifts.detail.mine.note", nil) : nil;
}

- (void)fillFacts {
    ExteriaStarGift *gift = _saved.gift;
    /* a gift of the app is a unique one in look only: it says who sent it, when, and the words that came with it, and none of the facts of a collectible */
    if (gift.unique && !_saved.customImageName) {
        NSString *owner = gift.ownerName.length ? gift.ownerName : _ownerName;
        if (owner.length) [_facts addRow:NSLocalizedString(@"gifts.row.owner", nil) name:owner photo:nil seed:(NSUInteger)gift.ownerId anonymous:NO];
        if (gift.model.length) [_facts addRow:NSLocalizedString(@"gifts.row.model", nil) text:gift.model pill:ExteriaDetailRarity(gift.modelPermille)];
        if (gift.pattern.length) [_facts addRow:NSLocalizedString(@"gifts.row.pattern", nil) text:gift.pattern pill:ExteriaDetailRarity(gift.patternPermille)];
        if (gift.backdrop.length) [_facts addRow:NSLocalizedString(@"gifts.row.backdrop", nil) text:gift.backdrop pill:ExteriaDetailRarity(gift.backdropPermille)];
        if (gift.total) {
            NSString *issued = [NSString stringWithFormat:@"%@/%@", ExteriaDetailCount(gift.remains), ExteriaDetailCount(gift.total)];
            [_facts addRow:NSLocalizedString(@"gifts.row.quantity", nil) text:[NSString stringWithFormat:NSLocalizedString(@"gifts.row.issued", nil), issued] pill:nil];
        }
        return;
    }
    BOOL anonymous = _saved.nameHidden || _saved.fromId == 0;
    ExteriaWeakReference *weak = _detailWeak;
    NSString *fromText = anonymous ? NSLocalizedString(@"gifts.from.anonymous", nil) : _saved.fromName;
    NSArray *fromEntities = nil;
    if (!anonymous) {
        /* the name is drawn as everywhere in the app: emoji as pictures, the status and the marks after it */
        NSUInteger marks = ExteriaPersonIsDeveloper(_saved.fromPerson) | ExteriaMarksOfId(_saved.fromId);
        fromText = ExteriaNameWithBadges(_saved.fromName, ExteriaPersonBadgeDocument(_saved.fromPerson), marks, &fromEntities);
        if (_saved.fromPerson.emojiStatus) {
            ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_saved.fromPerson.emojiStatus]], self.session, self.media, ^{
                ExteriaGiftDetailController *me = weak.target;
                [me->_facts redrawNames];
            });
        }
    }
    [_facts addRow:NSLocalizedString(@"gifts.row.from", nil) name:fromText entities:fromEntities photo:_saved.fromPhoto
              seed:(NSUInteger)_saved.fromId anonymous:anonymous
             onTap:anonymous ? nil : ^{ [(ExteriaGiftDetailController *)weak.target openSender]; }];
    if (_saved.date) {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:_saved.date];
        [_facts addRow:NSLocalizedString(@"gifts.row.date", nil)
                  text:[NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] pill:nil];
    }
    if (gift.stars) [_facts addRow:NSLocalizedString(@"gifts.row.cost", nil) stars:gift.stars];
    if (_saved.note.length) {
        [_facts addNote:_saved.note entities:_saved.noteEntities];
        NSMutableArray *documents = [NSMutableArray array];
        for (ExteriaTextEntity *entity in _saved.noteEntities) {
            if (entity.style == ExteriaTextStyleCustomEmoji && entity.documentId) [documents addObject:[NSNumber numberWithLongLong:entity.documentId]];
        }
        if (documents.count) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(customEmojiLoaded:) name:ExteriaCustomEmojiDidLoadNotification object:nil];
            [ExteriaCustomEmojiLoader loadDocuments:documents session:self.session media:self.media documents:nil picture:nil];
        }
    }
}

- (void)customEmojiLoaded:(NSNotification *)notification {
    NSNumber *document = notification.object;
    for (ExteriaTextEntity *entity in _saved.noteEntities) {
        if (entity.style == ExteriaTextStyleCustomEmoji && entity.documentId == document.longLongValue) {
            [_facts redrawNote];
            break;
        }
    }
}

/* the profile of the person who sent the gift; a sender the answer carried without a usable hash cannot be opened */
- (void)openSender {
    ExteriaDialog *dialog = [ExteriaDialog dialogWithPerson:_saved.fromPerson];
    if (!dialog) return;
    ExteriaUserProfileController *profile = [[[ExteriaUserProfileController alloc] initWithSession:self.session dialog:dialog avatars:self.avatars
                                                                                              media:self.media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}

/* "gift is visible on your profile. Hide >": the line says where the gift is, the link moves it */
- (void)buildFooter {
    _footer = [[UILabel alloc] init];
    _footer.backgroundColor = [UIColor clearColor];
    _footer.font = ExteriaFontRegular(14);
    _footer.textColor = ExteriaColorSecondary();
    _footer.text = NSLocalizedString(_saved.hidden ? @"gifts.footer.hidden" : @"gifts.footer.shown", nil);
    [_scroll addSubview:_footer];
    _footerLink = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _footerLink.titleLabel.font = ExteriaFontSemibold(14);
    [_footerLink setTitle:[NSLocalizedString(_saved.hidden ? @"gifts.footer.show" : @"gifts.footer.hide", nil) stringByAppendingString:@" \u203A"] forState:UIControlStateNormal];
    [_footerLink setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_footerLink setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    [_footerLink addTarget:self action:@selector(toggleHidden) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_footerLink];
}

- (void)showPicture {
    if (_saved.customImageName) {
        _picture.image = [UIImage imageNamed:_saved.customImageName];
        return;
    }
    ExteriaMedia *sticker = _saved.gift.sticker;
    ExteriaRemoteFile *thumb = sticker.previewFile;
    if (thumb) {
        [self.media loadImageForFile:thumb maxSide:[self stickerSide] * ExteriaScreenScale() completion:^(UIImage *image) {
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
        UIImageView *picture = _picture;
        _animation.firstFrameHandler = ^{ picture.image = nil; };
        [_scroll addSubview:_animation];
        [self.view setNeedsLayout];
        [_animation setPlaying:YES];
    }];
}

- (UIButton *)buttonTitled:(NSString *)title action:(SEL)action destructive:(BOOL)destructive {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = ExteriaColorCard();
    button.layer.cornerRadius = 12;
    button.titleLabel.font = ExteriaFontRegular(17);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:destructive ? ExteriaColorBadgeRed() : ExteriaColorAccent() forState:UIControlStateNormal];
    [button setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:button];
    [_buttons addObject:button];
    return button;
}

- (void)buildButtons {
    ExteriaStarGift *gift = _saved.gift;
    if (_saved.canUpgrade && !gift.unique) {
        NSString *title = _saved.upgradeStars > 0 ? [NSString stringWithFormat:NSLocalizedString(@"gifts.upgrade.for", nil), ExteriaStarsText(_saved.upgradeStars)]
                                                  : NSLocalizedString(@"gifts.upgrade", nil);
        [self buttonTitled:title action:@selector(askUpgrade) destructive:NO];
    }
    if (_folderDialog && _saved.messageId > 0) [self buttonTitled:NSLocalizedString(@"gifts.folder.add", nil) action:@selector(chooseFolder) destructive:NO];
    if (gift.unique) [self buttonTitled:NSLocalizedString(@"gifts.transfer", nil) action:@selector(chooseRecipient) destructive:NO];
    [self refreshConvertButton];
}

- (void)refreshConvertButton {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshConvertButton) object:nil];
    int64_t now = (int64_t)[[NSDate date] timeIntervalSince1970];
    BOOL canConvert = _mine && [_saved canConvertAt:now period:_convertPeriod];
    if (canConvert && !_convertButton) {
        _convertButton = [self buttonTitled:[NSString stringWithFormat:NSLocalizedString(@"gifts.convert", nil), ExteriaStarsText(_saved.convertStars)]
                                    action:@selector(askConvert) destructive:YES];
        _convertButton.enabled = !_working;
    } else if (!canConvert && _convertButton) {
        [_convertButton removeFromSuperview];
        [_buttons removeObject:_convertButton];
        _convertButton = nil;
    }
    if (canConvert) {
        int64_t remaining = (int64_t)_saved.date + _convertPeriod - now;
        if (remaining > 0) [self performSelector:@selector(refreshConvertButton) withObject:nil afterDelay:(NSTimeInterval)remaining];
    }
    [self.view setNeedsLayout];
}

- (void)layoutBody:(CGRect)body {
    _scroll.frame = body;
    CGFloat width = body.size.width;
    CGFloat inner = MIN(width - 32, 460);
    CGFloat x = (width - inner) / 2;
    CGFloat side = [self stickerSide];
    CGFloat y = 22;
    CGRect sticker = CGRectMake((width - side) / 2, y, side, side);
    _picture.frame = sticker;
    _animation.frame = sticker;
    y += side + 12;
    _name.frame = CGRectMake(x, y, inner, 28);
    y += 30;
    CGSize subtitle = _subtitle.text.length ? [_subtitle sizeThatFits:CGSizeMake(inner, 200)] : CGSizeZero;
    _subtitle.frame = CGRectMake(x, y, inner, subtitle.height);
    y += subtitle.height + 20;
    if (_backdrop) {
        /* the backdrop runs past the top edge so a bounce at the top shows it and not the plain screen */
        _backdrop.frame = CGRectMake(0, -400, width, y + 400);
        _backdrop.focus = CGPointMake(0.5, (22 + side / 2 + 400) / (y + 400));
        y += 4;
    }
    _facts.frame = CGRectMake(x, y, inner, [_facts heightForWidth:inner]);
    y += _facts.frame.size.height + 14;
    if (_footer) {
        CGSize text = [_footer sizeThatFits:CGSizeMake(inner, 20)];
        CGSize link = [_footerLink sizeThatFits:CGSizeMake(inner, 30)];
        BOOL sideBySide = text.width + 6 + link.width <= inner;
        CGFloat start = sideBySide ? (width - text.width - 6 - link.width) / 2 : x;
        _footer.frame = CGRectMake(sideBySide ? start : x, y, sideBySide ? text.width : inner, 22);
        _footer.textAlignment = sideBySide ? ExteriaTextAlignmentLeft : ExteriaTextAlignmentCenter;
        if (sideBySide) {
            _footerLink.frame = CGRectMake(start + text.width + 6, y - 4, link.width, 30);
            y += 26;
        } else {
            _footerLink.frame = CGRectMake((width - link.width) / 2, y + 22, link.width, 30);
            y += 54;
        }
        y += 10;
    }
    for (UIButton *button in _buttons) {
        button.frame = CGRectMake(x, y, inner, 50);
        y += 58;
    }
    if (_customCredit) {
        CGSize credit = [_customCredit sizeThatFits:CGSizeMake(inner, 100)];
        y = MAX(y, body.size.height - credit.height - 20);
        _customCredit.frame = CGRectMake(x, y, inner, credit.height);
        y += credit.height;
    }
    _spinner.center = CGPointMake(width / 2, y + 12);
    _scroll.contentSize = CGSizeMake(width, y + 40);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshConvertButton) object:nil];
    if (_changed && _changedHandler && ![self.navigationController.viewControllers containsObject:self]) _changedHandler();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_mine && self.isViewLoaded) [self refreshConvertButton];
}

#pragma mark actions

- (void)setWorking:(BOOL)working {
    _working = working;
    for (UIButton *button in _buttons) button.enabled = !working;
    _footerLink.enabled = !working;
    if (working) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

/* runs the call, then tells the list to reload and leaves this screen when the gift is gone from the profile */
- (void)finishWithError:(NSString *)errorName leave:(BOOL)leave {
    [self setWorking:NO];
    if (errorName) {
        ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
        return;
    }
    _changed = YES;
    if (leave) [self goBack];
}

/* the folders of the profile, asked for when the button is pressed, and the gift goes into the one that is chosen */
- (void)chooseFolder {
    if (_working) return;
    [self setWorking:YES];
    [self retain];
    [self.session loadGiftFoldersOfDialog:_folderDialog completion:^(NSArray *folders, NSString *errorName) {
        [self autorelease];
        [self setWorking:NO];
        if (!folders) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        if (!folders.count) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"gifts.folder.none", nil));
            return;
        }
        NSMutableArray *titles = [NSMutableArray array];
        for (ExteriaGiftFolder *folder in folders) [titles addObject:folder.title];
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        ExteriaChoose(NSLocalizedString(@"gifts.folder.add", nil), titles, -1, ^(NSInteger index) {
            ExteriaGiftDetailController *me = weak.target;
            if (!me || index < 0 || index >= (NSInteger)folders.count) return;
            ExteriaGiftFolder *folder = [folders objectAtIndex:(NSUInteger)index];
            [me setWorking:YES];
            [me retain];
            [me.session addGifts:[NSArray arrayWithObject:me->_saved] toFolder:folder dialog:me->_folderDialog completion:^(NSString *error) {
                [me autorelease];
                [me setWorking:NO];
                if (error) {
                    ExteriaGiftAlert(nil, ExteriaGiftErrorText(error));
                    return;
                }
                me->_changed = YES;
                ExteriaGiftAlert(nil, [NSString stringWithFormat:NSLocalizedString(@"gifts.folder.added", nil), folder.title]);
            }];
        });
    }];
}

- (void)toggleHidden {
    if (_working) return;
    [self setWorking:YES];
    BOOL hide = !_saved.hidden;
    [self retain];
    [self.session setGift:_saved hidden:hide completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName leave:YES];
    }];
}

- (void)confirm:(NSString *)message tag:(NSInteger)tag action:(NSString *)action {
    if (_working) return;
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:message delegate:self cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil)
                               otherButtonTitles:action, nil];
    [alert setTag:tag];
    [alert show];
    [alert release];
}

- (void)askConvert {
    if (![_saved canConvertAt:(int64_t)[[NSDate date] timeIntervalSince1970] period:_convertPeriod]) {
        [self refreshConvertButton];
        return;
    }
    [self confirm:[NSString stringWithFormat:NSLocalizedString(@"gifts.convert.confirm", nil), ExteriaStarsText(_saved.convertStars)] tag:ExteriaDetailAlertConvert
           action:NSLocalizedString(@"gifts.convert.action", nil)];
}

- (void)askUpgrade {
    NSString *message = _saved.upgradeStars > 0 ? [NSString stringWithFormat:NSLocalizedString(@"gifts.upgrade.confirm", nil), ExteriaStarsText(_saved.upgradeStars)]
                                                : NSLocalizedString(@"gifts.upgrade.free", nil);
    [self confirm:message tag:ExteriaDetailAlertUpgrade action:NSLocalizedString(@"gifts.upgrade", nil)];
}

- (void)chooseRecipient {
    if (_working) return;
    ExteriaContactPickerController *picker = [[[ExteriaContactPickerController alloc] initWithSession:self.session avatars:self.avatars media:self.media] autorelease];
    picker.screenTitle = NSLocalizedString(@"gifts.transfer.to", nil);
    picker.pickHandler = ^(ExteriaDialog *dialog) {
        [_recipient release];
        _recipient = [dialog retain];
        [self.navigationController popToViewController:self animated:YES];
        [self confirm:[NSString stringWithFormat:NSLocalizedString(@"gifts.transfer.confirm", nil), dialog.title] tag:ExteriaDetailAlertTransfer
               action:NSLocalizedString(@"gifts.transfer", nil)];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == [alert cancelButtonIndex]) return;
    switch ([alert tag]) {
    case ExteriaDetailAlertConvert: [self convert]; break;
    case ExteriaDetailAlertUpgrade: [self upgrade]; break;
    case ExteriaDetailAlertTransfer: [self transfer]; break;
    }
}

- (void)convert {
    [self setWorking:YES];
    [self retain];
    [self.session convertGift:_saved completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName leave:YES];
    }];
}

/* a quote that costs stars goes through the payment form; a prepaid or free one is a plain call */
- (void)upgrade {
    [self setWorking:YES];
    [self retain];
    if (_saved.upgradeStars <= 0) {
        [self.session upgradeGift:_saved keepDetails:YES completion:^(NSString *errorName) {
            [self autorelease];
            [self finishWithError:errorName leave:YES];
        }];
        return;
    }
    [self.session quoteUpgradingGift:_saved keepDetails:YES completion:^(ExteriaPaymentQuote *quote, NSString *errorName) {
        if (!quote) {
            [self autorelease];
            [self finishWithError:errorName leave:NO];
            return;
        }
        [self.session payQuote:quote completion:^(NSString *payError) {
            [self autorelease];
            [self finishWithError:payError leave:YES];
        }];
    }];
}

- (void)transfer {
    if (!_recipient) return;
    [self setWorking:YES];
    [self retain];
    if (_saved.transferStars <= 0) {
        [self.session transferGift:_saved toDialog:_recipient completion:^(NSString *errorName) {
            [self autorelease];
            [self finishWithError:errorName leave:YES];
        }];
        return;
    }
    [self.session quoteTransferringGift:_saved toDialog:_recipient completion:^(ExteriaPaymentQuote *quote, NSString *errorName) {
        if (!quote) {
            [self autorelease];
            [self finishWithError:errorName leave:NO];
            return;
        }
        [self.session payQuote:quote completion:^(NSString *payError) {
            [self autorelease];
            [self finishWithError:payError leave:YES];
        }];
    }];
}

@end
