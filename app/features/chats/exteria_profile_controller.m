#import "exteria_developers.h"
#import "exteria_emoji_label.h"
#import "exteria_gift_folder_bar.h"
#import "exteria_animation.h"
#import "exteria_text_filter.h"
#import "exteria_profile_controller.h"
#import "exteria_profile_identity_view.h"
#import "exteria_chat_settings.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_alert.h"
#import "exteria_channel_card.h"
#import "exteria_chat_controller.h"
#import "exteria_info_card_view.h"
#import "exteria_profile_qr_controller.h"
#import "exteria_row_icon.h"
#import "exteria_contact_picker_controller.h"
#import "exteria_avatar_viewer.h"
#import "exteria_dialog.h"
#import "exteria_gift_catalog_controller.h"
#import "exteria_gift_detail_controller.h"
#import "exteria_gift_grid_view.h"
#import "exteria_person.h"
#import "exteria_popup_menu.h"
#import "exteria_music_list_controller.h"
#import "exteria_music_pill.h"
#import "exteria_pill_tabs_view.h"
#import "exteria_platform.h"
#import "exteria_profile_edit_controller.h"
#import "exteria_profile_feed.h"
#import "exteria_rating_view.h"
#import "exteria_profile_photo_picker.h"
#import "exteria_session_profile.h"
#import "exteria_sheet.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_wave_background_view.h"
#import "exteria_weak_reference.h"

#define BAR_HEIGHT 44.0
#define ACTION_HEIGHT 44.0
#define INFO_ROW 62.0
#define CARD_ROW 52.0
#define GAP 14.0
#define SEND_HEIGHT 48.0

/* the edit action under the profile */
@interface ExteriaProfileAction : UIControl {
    UIImageView *_icon;
    UILabel *_caption;
}
- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title;
@end

@implementation ExteriaProfileAction

- (id)initWithSymbol:(ExteriaSymbol)symbol title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    ExteriaAttachBounce(self, 0.06);
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 14;
    _icon = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(symbol, 24, ExteriaColorAccent())];
    _icon.contentMode = UIViewContentModeCenter;
    [self addSubview:_icon];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textAlignment = ExteriaTextAlignmentCenter;
    _caption.font = ExteriaFontMedium(13);
    _caption.textColor = ExteriaColorTitle();
    _caption.adjustsFontSizeToFitWidth = YES;
    _caption.text = title;
    [self addSubview:_caption];
    self.accessibilityLabel = title;
    return self;
}

- (void)dealloc {
    [_icon release];
    [_caption release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat text = MIN(MAX(0, size.width - 52), ceil([_caption sizeThatFits:CGSizeMake(size.width, 24)].width));
    CGFloat left = floor((size.width - text - 28) / 2);
    _icon.frame = CGRectMake(left, (size.height - 22) / 2, 22, 22);
    _caption.frame = CGRectMake(left + 28, 0, text, size.height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

@interface ExteriaProfileController () <ExteriaGiftGridDelegate, ExteriaGiftFolderBarDelegate> {
    ExteriaGiftFolderBar *_folderBar;
    ExteriaSession *_session;
    CGFloat _bottomInset;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaWaveBackgroundView *_backdrop;
    UIView *_bar;
    BOOL _barFilled;
    UILabel *_titleLabel;
    ExteriaEmojiLabel *_barName;
    UILabel *_barStatus;
    ExteriaGiftGridView *_grid;
    UIView *_head;
    ExteriaProfileIdentityView *_identity;
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_name;
    UILabel *_status;
    ExteriaRatingBadge *_ratingBadge;
    ExteriaProfileAction *_editAction;
    ExteriaInfoCardView *_info;
    UIView *_signOutCard;
    UIButton *_signOut;
    UIActivityIndicatorView *_spinner;
    ExteriaPillTabsView *_tabs;
    UILabel *_empty;
    UIButton *_send;
    UILabel *_toast;
    ExteriaProfileFeed *_feeds[3];
    NSUInteger _tab;
    ExteriaPerson *_person;
    NSString *_about;
    ExteriaFullUser *_full;
    ExteriaMusicPill *_music;
    ExteriaChannelCard *_channelCard;
    UIButton *_qrButton;
    UIButton *_moreButton;
    UIImage *_starsImage;
    ExteriaStickerLibrary *_stickerLibrary;
    ExteriaWeakReference *_weak;
    CGFloat _headHeight;
    CGFloat _headWidth;
    BOOL _working;
    BOOL _uploading;
}
@end

@implementation ExteriaProfileController

@synthesize delegate = _delegate;
@synthesize bottomInset = _bottomInset;
@synthesize avatars = _avatars;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _about = [@"" copy];
    return self;
}

- (void)openAvatars {
    if (!_person) return;
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person]
                                                                        avatars:_avatars media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaChatSettingsDidChangeNotification object:nil];
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_session release];
    [_avatars release];
    [_media release];
    [_stickerLibrary release];
    [_full release];
    [_music release];
    [_channelCard release];
    [_qrButton release];
    [_moreButton release];
    [_starsImage release];
    [_backdrop release];
    [_bar release];
    [_titleLabel release];
    [_barName release];
    [_barStatus release];
    [_grid release];
    [_head release];
    [_identity release];
    [_avatar release];
    [_name release];
    [_status release];
    [_ratingBadge release];
    [_editAction release];
    for (int i = 0; i < 3; ++i) [_feeds[i] release];
    [_info release];
    [_signOutCard release];
    [_signOut release];
    [_spinner release];
    _folderBar.delegate = nil;
    [_folderBar release];
    [_tabs release];
    [_empty release];
    [_send release];
    [_toast release];
    [_person release];
    [_about release];
    [super dealloc];
}

static UILabel *ExteriaProfileLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.plain = YES;
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    _grid = [[ExteriaGiftGridView alloc] initWithMedia:_media];
    _grid.avatars = _avatars;
    _grid.delegate = self;
    [root addSubview:_grid];

    _head = [[UIView alloc] init];
    _head.backgroundColor = [UIColor clearColor];
    /* the photo, the camera, the name and the line under it are the block that the settings screen shows too, so both lay out the same */
    _identity = [[ExteriaProfileIdentityView alloc] init];
    [_identity.avatarHit addTarget:self action:@selector(openAvatars) forControlEvents:UIControlEventTouchUpInside];
    [_identity.badge addTarget:self action:@selector(choosePhoto) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_identity];
    _avatar = [_identity.avatar retain];
    _name = [_identity.name retain];
    _status = [_identity.line retain];
    _status.text = NSLocalizedString(@"profile.online", nil);
    _ratingBadge = [[ExteriaRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [_identity addSubview:_ratingBadge];

    _editAction = [[ExteriaProfileAction alloc] initWithSymbol:ExteriaSymbolCompose title:NSLocalizedString(@"profile.edit", nil)];
    [_editAction addTarget:self action:@selector(editProfile) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_editAction];

    _music = [[ExteriaMusicPill alloc] init];
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    ExteriaWeakReference *musicMe = _weak;
    _music.contentHandler = ^{ [(ExteriaProfileController *)musicMe.target layoutHead]; };
    [_head addSubview:_music];

    _channelCard = [[ExteriaChannelCard alloc] init];
    _channelCard.hidden = YES;
    [_channelCard addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_channelCard];

    _info = [[ExteriaInfoCardView alloc] init];
    ExteriaWeakReference *infoMe = _weak;
    _info.copyHandler = ^{ [(ExteriaProfileController *)infoMe.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    [_head addSubview:_info];

    _signOutCard = [[UIView alloc] init];
    _signOutCard.backgroundColor = ExteriaColorCard();
    _signOutCard.layer.cornerRadius = 14;
    _signOutCard.layer.masksToBounds = YES;
    [_head addSubview:_signOutCard];
    _signOut = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_signOut setTitle:NSLocalizedString(@"profile.signout", nil) forState:UIControlStateNormal];
    [_signOut setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_signOut setTitleColor:ExteriaColorMuted() forState:UIControlStateDisabled];
    [_signOut addTarget:self action:@selector(confirmSignOut) forControlEvents:UIControlEventTouchUpInside];
    [_signOutCard addSubview:_signOut];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_signOutCard addSubview:_spinner];

    _tabs = [[ExteriaPillTabsView alloc] initWithTitles:[NSArray arrayWithObjects:NSLocalizedString(@"profile.tab.stories", nil),
                                                         NSLocalizedString(@"profile.tab.archive", nil), NSLocalizedString(@"gifts.title", nil), nil]];
    ExteriaWeakReference *me = _weak;
    _tabs.changeHandler = ^(NSUInteger index) { [(ExteriaProfileController *)me.target selectTab:index]; };
    [_head addSubview:_tabs];
    _empty = ExteriaProfileLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [ExteriaColorScreen() colorWithAlphaComponent:0.94];
    _bar.alpha = 0;
    [root addSubview:_bar];
    _titleLabel = ExteriaProfileLabel(ExteriaColorTitle(), ExteriaFontBold(ExteriaIsPad() ? 24 : 20), ExteriaTextAlignmentCenter);
    _titleLabel.text = NSLocalizedString(@"tab.profile", nil);
    [root addSubview:_titleLabel];
    _barName = [[ExteriaEmojiLabel alloc] init];
    _barName.textColor = ExteriaColorTitle();
    _barName.font = ExteriaFontSemibold(17);
    _barName.textAlignment = ExteriaTextAlignmentCenter;
    _barName.alpha = 0;
    [root addSubview:_barName];
    _barStatus = ExteriaProfileLabel(ExteriaColorSecondary(), ExteriaFontRegular(12), ExteriaTextAlignmentCenter);
    _barStatus.text = NSLocalizedString(@"profile.online", nil);
    _barStatus.alpha = 0;
    [root addSubview:_barStatus];

    _qrButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qrButton setImage:ExteriaSymbolImage(ExteriaSymbolQr, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_qrButton addTarget:self action:@selector(openQr) forControlEvents:UIControlEventTouchUpInside];
    _qrButton.accessibilityLabel = NSLocalizedString(@"profile.qr", nil);
    [root addSubview:_qrButton];

    /* the menu only has the link to copy, so the dots wait for a username */
    _moreButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_moreButton setImage:ExteriaSymbolImage(ExteriaSymbolEllipsis, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_moreButton addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    _moreButton.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
    _moreButton.hidden = YES;
    [root addSubview:_moreButton];

    _send = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _send.backgroundColor = ExteriaColorAccent();
    _send.layer.cornerRadius = SEND_HEIGHT / 2;
    _send.titleLabel.font = ExteriaFontSemibold(17);
    [_send setTitle:[@"  " stringByAppendingString:NSLocalizedString(@"profile.sendgifts", nil)] forState:UIControlStateNormal];
    [_send setImage:ExteriaSymbolImage(ExteriaSymbolGift, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    [_send setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_send addTarget:self action:@selector(sendGifts) forControlEvents:UIControlEventTouchUpInside];
    _send.hidden = YES;
    [root addSubview:_send];
    _toast = ExteriaProfileLabel([UIColor whiteColor], ExteriaFontSemibold(14), ExteriaTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshOwnStatus) name:ExteriaChatSettingsDidChangeNotification object:nil];
    [self refreshOwnStatus];
    [self loadProfile];
    [self selectTab:0];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshOwnStatus];
    /* a story seen or a gift hidden while away shows on coming back */
    if (_person) [self refreshCurrentFeed];
}

- (void)refreshOwnStatus {
    NSString *text = NSLocalizedString(ExteriaChatFlagGet(ExteriaChatFlagGhostOffline) ? @"profile.offline.question" : @"profile.online", nil);
    _status.text = text;
    _barStatus.text = text;
    _moreButton.hidden = !_person.username.length && !ExteriaChatFlagGet(ExteriaChatFlagGhostOffline);
    [self layoutHead];
}

#pragma mark data

- (void)loadProfile {
    /* the profile of the last time draws at once, and the answer corrects it */
    if (!_person && [_session ownPerson]) {
        _person = [[_session ownPerson] retain];
        [self refreshProfile];
    }
    [self retain];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items) {
            NSLog(@"exteria: profile did not load: %@", errorName);
            return;
        }
        [_person release];
        _person = [[items objectAtIndex:0] retain];
        [self refreshProfile];
        [self refreshCurrentFeed];
        [self loadFull];
    }];
    [self retain];
    [_session loadStarsBalance:^(long long stars, NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"exteria: star balance not loaded: %@", errorName);
            return;
        }
        [_starsImage release];
        _starsImage = [ExteriaStarsImage(nil, stars, ExteriaFontSemibold(17), ExteriaColorTitle()) retain];
        [self refreshProfile];
    }];
}

/* the bio, the birthday and the personal channel, which come with the full profile */
- (void)loadFull {
    if (!_person) return;
    [self retain];
    [_session loadFullUserOfDialog:[ExteriaDialog savedMessagesWithPerson:_person] completion:^(ExteriaFullUser *user, NSString *errorName) {
        [self autorelease];
        if (!user) {
            NSLog(@"exteria: full profile did not load: %@", errorName);
            return;
        }
        [_full release];
        _full = [user retain];
        [_about release];
        _about = [user.about copy];
        [self refreshProfile];
    }];
}

- (void)refreshProfile {
    _ratingBadge.hidden = !_full.hasRating;
    if (_full.hasRating) {
        _ratingBadge.level = _full.rating.level;
        _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)_full.rating.level];
    }
    [_identity setName:_person.name developer:ExteriaPersonIsDeveloper(_person)];
    _barName.text = _person.name;
    _avatar.initials = _person.initials;
    _avatar.deleted = _person.deleted;
    _avatar.seed = (NSUInteger)(_person.userId % 1000003);
    [_avatar setPhoto:_person.photo cache:_avatars];
    NSString *birthday = @"";
    if (_full.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = _full.birthdayDay;
        parts.month = _full.birthdayMonth;
        parts.year = _full.birthdayYear > 0 ? _full.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = _full.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) birthday = [formatter stringFromDate:date];
    }
    NSMutableArray *infoRows = [NSMutableArray arrayWithObjects:
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), ExteriaOwnPhoneText(_person.phone), nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), _about ? _about : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), _person.username.length ? [@"@" stringByAppendingString:_person.username] : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), birthday, nil], nil];
    [infoRows addObjectsFromArray:ExteriaIdentityRows(_person.userId, _person.photo)];
    [_info setRows:infoRows];
    [_info setStarsBalance:_starsImage caption:NSLocalizedString(@"profile.stars", nil)];
    _moreButton.hidden = !_person.username.length && !ExteriaChatFlagGet(ExteriaChatFlagGhostOffline);
    _music.savedTrack = _full.music;
    [self refreshChannelCard];
    [self layoutHead];
}

- (ExteriaProfileFeed *)feedForTab:(NSUInteger)tab {
    if (!_feeds[tab] && _person) {
        ExteriaProfileFeedKind kind = tab == 0 ? ExteriaFeedPinnedStories : (tab == 1 ? ExteriaFeedArchivedStories : ExteriaFeedGifts);
        ExteriaDialog *own = [ExteriaDialog savedMessagesWithPerson:_person];
        _feeds[tab] = [[ExteriaProfileFeed alloc] initWithSession:_session kind:kind owner:own];
        if (tab == 2 && !_folderBar) {
            /* the folders of our own gifts, which this screen can also make, rename and delete */
            _folderBar = [[ExteriaGiftFolderBar alloc] initWithSession:_session dialog:own mine:YES];
            _folderBar.delegate = self;
            [_head addSubview:_folderBar];
            [_folderBar reload];
        }
    }
    return _feeds[tab];
}

- (void)giftFolderBar:(ExteriaGiftFolderBar *)bar didSelectFolder:(ExteriaGiftFolder *)folder {
    (void)bar;
    [self reloadGiftsOfFolder:folder.folderId];
}

- (void)giftFolderBarDidChange:(ExteriaGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) [self reloadGiftsOfFolder:bar.selectedFolder.folderId];
    [self.view setNeedsLayout];
}

- (void)reloadGiftsOfFolder:(int32_t)folderId {
    ExteriaProfileFeed *feed = [self feedForTab:2];
    if (!feed) return;
    feed.folderId = folderId;
    ExteriaWeakReference *me = _weak;
    [feed reload:^{ [(ExteriaProfileController *)me.target feedChanged:2]; }];
}

- (void)selectTab:(NSUInteger)tab {
    _tab = tab;
    _tabs.selectedIndex = tab;
    _send.hidden = tab != 2;
    [_grid setTiles:[[self feedForTab:tab] tiles]];
    [self refreshCurrentFeed];
    [self showFeedState];
    [self.view setNeedsLayout];
}

- (void)refreshCurrentFeed {
    ExteriaProfileFeed *feed = [self feedForTab:_tab];
    if (!feed || feed.loading) return;
    ExteriaWeakReference *me = _weak;
    NSUInteger tab = _tab;
    [feed reload:^{ [(ExteriaProfileController *)me.target feedChanged:tab]; }];
    [self showFeedState];
}

- (void)feedChanged:(NSUInteger)tab {
    if (tab != _tab) return;
    [_grid setTiles:[[self feedForTab:tab] tiles]];
    [self showFeedState];
}

/* under the tabs: a line for the empty list, the loading or the failure; nothing once there are tiles */
- (void)showFeedState {
    ExteriaProfileFeed *feed = [self feedForTab:_tab];
    NSString *text = @"";
    if (!feed || !feed.loaded) text = feed.errorName ? [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), feed.errorName]
                                                     : NSLocalizedString(@"profile.loading", nil);
    else if (!feed.items.count) text = NSLocalizedString(_tab == 0 ? @"profile.stories.empty" : (_tab == 1 ? @"profile.archive.empty" : @"gifts.mine.empty"), nil);
    if ([_empty.text isEqualToString:text]) return;
    _empty.text = text;
    [self layoutHead];
}

- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid {
    (void)grid;
    ExteriaWeakReference *me = _weak;
    NSUInteger tab = _tab;
    [[self feedForTab:tab] loadMore:^{ [(ExteriaProfileController *)me.target feedChanged:tab]; }];
}

- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    ExteriaProfileFeed *feed = [self feedForTab:_tab];
    if (index >= feed.items.count || !_person) return;
    if (_tab == 2) {
        ExteriaGiftDetailController *detail = [[[ExteriaGiftDetailController alloc] initWithSession:_session gift:[feed.items objectAtIndex:index] mine:YES
                                                                                            avatars:_avatars media:_media] autorelease];
        detail.ownerName = _person.name;
        detail.stickers = _stickerLibrary;
        detail.folderDialog = [ExteriaDialog savedMessagesWithPerson:_person];
        ExteriaWeakReference *me = _weak;
        detail.changedHandler = ^{ ExteriaProfileController *profile = me.target; [profile refreshCurrentFeed]; [profile->_folderBar reload]; };
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    ExteriaDialog *own = [ExteriaDialog savedMessagesWithPerson:_person];
    ExteriaStoryViewerController *viewer = [[[ExteriaStoryViewerController alloc] initWithSession:_session owner:own stories:feed.items index:index
                                                                                          avatars:_avatars media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark layout

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self.view setNeedsLayout];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return ExteriaOrientationMask();
}
#pragma clang diagnostic pop

/* the head scrolls with the tiles, so it has a fixed frame that this works out from the width */
- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat y = EXTERIA_IDENTITY_TOP;
    _identity.frame = CGRectMake(0, y, width, EXTERIA_IDENTITY_HEIGHT);
    [_identity layoutIfNeeded];
    CGFloat statusWidth = MIN(width - 70, ceil([_status sizeThatFits:CGSizeMake(width - 70, 22)].width));
    _ratingBadge.frame = CGRectMake(floor((width - statusWidth) / 2) - 26, _status.frame.origin.y + 1, 22, 20);
    y += EXTERIA_IDENTITY_HEIGHT + GAP + 4;
    _editAction.frame = CGRectMake(x, y, contentWidth, ACTION_HEIGHT);
    y += ACTION_HEIGHT + GAP;
    if (_music.hasContent) {
        _music.frame = CGRectMake(x, y - GAP + 8, contentWidth, [ExteriaMusicPill height]);
        y += [ExteriaMusicPill height] + 8;
    }
    if (!_channelCard.hidden) {
        _channelCard.frame = CGRectMake(x, y, contentWidth, [ExteriaChannelCard height]);
        y += [ExteriaChannelCard height] + GAP;
    }
    if (!_info.hidden) {
        CGFloat height = [_info heightForWidth:contentWidth];
        _info.frame = CGRectMake(x, y, contentWidth, height);
        y += height + GAP;
    }
    _signOutCard.frame = CGRectMake(x, y, contentWidth, CARD_ROW);
    _signOut.titleLabel.font = ExteriaFontRegular(17);
    _signOut.frame = _signOutCard.bounds;
    _spinner.center = CGPointMake(contentWidth - 28, CARD_ROW / 2);
    y += CARD_ROW + GAP + 4;
    _tabs.frame = CGRectMake(x, y, contentWidth, 40);
    y += 40 + 12;
    CGFloat folders = _tab == 2 ? [_folderBar height] : 0;
    _folderBar.hidden = folders == 0;
    _folderBar.frame = CGRectMake(x, y - 12, contentWidth, folders);
    y += folders;
    CGSize empty = _empty.text.length ? [_empty sizeThatFits:CGSizeMake(contentWidth - 16, 200)] : CGSizeZero;
    _empty.frame = CGRectMake(x + 8, y + 16, contentWidth - 16, empty.height);
    y += empty.height ? empty.height + 40 : 0;
    if (fabs(y - _headHeight) > 0.5 || fabs(width - _headWidth) > 0.5) {
        _headHeight = y;
        _headWidth = width;
        _head.frame = CGRectMake(0, 0, width, y);
        _grid.headerView = _head;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat barHeight = insets.top + BAR_HEIGHT;
    /* the wave and the bar plate run full width; the bar's words, the tiles and the button stand in one column */
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_PAGE);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    _backdrop.frame = self.view.bounds;
    _bar.frame = CGRectMake(0, 0, size.width, barHeight);
    _titleLabel.frame = CGRectMake(left + 60, insets.top, width - 120, BAR_HEIGHT);
    _barName.frame = CGRectMake(left + 60, insets.top + 3, width - 120, 22);
    _barStatus.frame = CGRectMake(left + 60, insets.top + 24, width - 120, 16);
    _grid.frame = CGRectMake(left, insets.top, width, size.height - insets.top);
    _grid.topInset = BAR_HEIGHT;
    _grid.bottomInset = _bottomInset + (_tab == 2 ? SEND_HEIGHT + 24 : 0);
    CGFloat sendWidth = MIN(width - 64, 280);
    _send.frame = CGRectMake(CGRectGetMidX(column) - sendWidth / 2, size.height - _bottomInset - SEND_HEIGHT - 16, sendWidth, SEND_HEIGHT);
    _toast.frame = CGRectMake(CGRectGetMidX(column) - 80, barHeight + 12, 160, 28);
    _qrButton.frame = CGRectMake(left + 6, insets.top, 48, BAR_HEIGHT);
    _moreButton.frame = CGRectMake(edge - 54, insets.top, 48, BAR_HEIGHT);
    [self layoutHead];
}

/* the plain "profile" title gives way to the name once the head has scrolled up */
- (void)giftGrid:(ExteriaGiftGridView *)grid didScrollToOffset:(CGFloat)offset {
    (void)grid;
    CGFloat limit = 140;
    offset += BAR_HEIGHT;
    CGFloat mix = MAX(0, MIN(1, (offset - limit + 40) / 40));
    BOOL filled = offset > 0.5;
    if (filled != _barFilled) {
        _barFilled = filled;
        [UIView animateWithDuration:ExteriaReduceMotionEnabled() ? 0 : 0.42 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ _bar.alpha = filled ? 1 : 0; } completion:nil];
    }
    _titleLabel.alpha = 1 - mix;
    _barName.alpha = mix;
    _barStatus.alpha = mix;
}

#pragma mark channel and code

/* the personal channel under the buttons: its name, its followers and the newest line it shows */
- (void)refreshChannelCard {
    ExteriaPersonalChannel *channel = _full.channel;
    _channelCard.hidden = channel == nil;
    if (channel) [_channelCard configureWithChannel:channel avatars:_avatars];
}

- (void)openRating { ExteriaShowRating(self.view.window, _full); }

- (void)openMusic {
    if (!_person || !_media) return;
    ExteriaMusicListController *list = [[[ExteriaMusicListController alloc] initWithSession:_session dialog:[ExteriaDialog savedMessagesWithPerson:_person]
                                                                                    first:_full.music avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openChannel {
    ExteriaPersonalChannel *channel = _full.channel;
    if (!channel || !_media) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:channel.dialog avatars:_avatars media:_media
                                                                         stickers:_stickerLibrary] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)showMenu {
    BOOL hasLink = _person.username.length > 0;
    BOOL ghost = ExteriaChatFlagGet(ExteriaChatFlagGhostOffline);
    if (!hasLink && !ghost) return;
    NSMutableArray *titles = [NSMutableArray array];
    ExteriaSymbol symbols[2];
    NSUInteger count = 0;
    if (hasLink) {
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        symbols[count++] = ExteriaSymbolLink;
    }
    if (ghost) {
        [titles addObject:NSLocalizedString(@"profile.peek.online", nil)];
        symbols[count++] = ExteriaSymbolEye;
    }
    ExteriaWeakReference *me = _weak;
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols
                                                              handler:^(NSUInteger index) {
        ExteriaProfileController *profile = me.target;
        if (hasLink && index == 0) [profile copyLink];
        else if (ghost && index == (hasLink ? 1u : 0u)) [profile peekOnline];
    }] autorelease];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(_moreButton.frame) - 6, CGRectGetMaxY(_moreButton.frame) - 8)];
}

- (void)peekOnline {
    [self toast:NSLocalizedString(@"profile.peek.loading", nil)];
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaProfileController *profile = weak.target;
        if (!profile || !profile.view.window) return;
        ExteriaPerson *person = items.count ? [items objectAtIndex:0] : nil;
        NSString *message;
        if (errorName) {
            message = [errorName isEqualToString:@"TIMEOUT"] || [errorName isEqualToString:@"OFFLINE"] ? NSLocalizedString(@"error.offline", nil) : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName];
        } else if (!person || person.presence == EXTERIA_PRESENCE_UNKNOWN || (person.presence == EXTERIA_PRESENCE_OFFLINE && person.seen <= 0)) {
            message = NSLocalizedString(@"profile.peek.unavailable", nil);
        } else if (person.presence == EXTERIA_PRESENCE_OFFLINE) {
            message = [NSString stringWithFormat:NSLocalizedString(@"profile.peek.lastseen", nil), ExteriaMediaTimeText(person.seen)];
        } else {
            message = ExteriaLastSeenText(person.presence, person.seen);
        }
        ExteriaShowNotice(NSLocalizedString(@"profile.peek.online", nil), message);
    }];
}

- (void)copyLink {
    if (!_person.username.length) return;
    [UIPasteboard generalPasteboard].string = [@"https://t.me/" stringByAppendingString:_person.username];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)openQr {
    if (!_person) return;
    ExteriaProfileQrController *code = [[[ExteriaProfileQrController alloc] initWithSession:_session person:_person avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:code animated:YES];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}


- (void)editProfile {
    if (!_person) return;
    ExteriaProfileEditController *edit = [[[ExteriaProfileEditController alloc] initWithSession:_session person:_person fullUser:_full avatars:_avatars
                                                                                          media:_media] autorelease];
    ExteriaWeakReference *me = _weak;
    edit.changedHandler = ^{ [(ExteriaProfileController *)me.target loadProfile]; };
    edit.logoutHandler = ^{ [(ExteriaProfileController *)me.target confirmSignOut]; };
    [self.navigationController pushViewController:edit animated:YES];
}

- (void)choosePhoto {
    if (_uploading) return;
    ExteriaWeakReference *me = _weak;
    [ExteriaProfilePhotoPicker pickFrom:self picked:^(NSString *path) {
        ExteriaProfileController *profile = me.target;
        if (!path) {
            if (profile) [profile toast:NSLocalizedString(@"attach.failed", nil)];
            return;
        }
        if (!profile) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            return;
        }
        [profile uploadPhotoAtPath:path];
    } unavailable:^{
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"attach.gallery.unavailable", nil) delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
    }];
}

- (void)uploadPhotoAtPath:(NSString *)path {
    _uploading = YES;
    [_identity setUploading:YES];
    [self toast:NSLocalizedString(@"profile.photo.uploading", nil)];
    [self retain];
    [_session uploadProfilePhotoAtPath:path completion:^(NSString *errorName) {
        [self autorelease];
        _uploading = NO;
        [_identity setUploading:NO];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (errorName) {
            NSLog(@"exteria: profile photo not set: %@", errorName);
            [self toast:NSLocalizedString(@"profile.photo.failed", nil)];
            return;
        }
        [self loadProfile];
    }];
}

- (void)sendGifts {
    if (!_person || !_media) return;
    ExteriaContactPickerController *picker = [[[ExteriaContactPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"gifts.send", nil);
    picker.selfPerson = _person;
    ExteriaWeakReference *me = _weak;
    ExteriaWeakReference *pickerRef = [ExteriaWeakReference referenceTo:picker];
    picker.pickHandler = ^(ExteriaDialog *dialog) {
        ExteriaProfileController *profile = me.target;
        UIViewController *host = pickerRef.target;
        if (!profile || !host) return;
        ExteriaGiftCatalogController *catalog = [[[ExteriaGiftCatalogController alloc] initWithSession:profile->_session dialog:dialog avatars:profile->_avatars
                                                                                                  media:profile->_media] autorelease];
        catalog.sentHandler = ^{ [(ExteriaProfileController *)me.target refreshCurrentFeed]; };
        /* the list gives way to the catalog, so the way back from a sent gift leads to the profile */
        UINavigationController *navigation = host.navigationController;
        [navigation popViewControllerAnimated:NO];
        [navigation pushViewController:catalog animated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark sign out

- (void)confirmSignOut {
    if (_working) return;
    ExteriaWeakReference *me = _weak;
    ExteriaConfirmAction(self, NSLocalizedString(@"profile.signout.confirm", nil), NSLocalizedString(@"profile.signout", nil),
                         ^{ [(ExteriaProfileController *)me.target signOutNow]; });
}

- (void)signOutNow {
    _working = YES;
    _signOut.enabled = NO;
    [_spinner startAnimating];
    [_delegate profileController:self requestsSignOut:^(NSString *errorName) {
        _working = NO;
        _signOut.enabled = YES;
        [_spinner stopAnimating];
        if (!errorName) return;
        Class alertClass = NSClassFromString(@"UIAlertView");
        id failure = [[alertClass alloc] initWithTitle:nil
                                               message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                       : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                              delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [failure show];
        [failure release];
    }];
}

@end
