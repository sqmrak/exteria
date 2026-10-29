#import "exteria_user_profile_controller.h"
#import "exteria_media_viewer.h"
#import "exteria_notifications_chat_controller.h"
#import "exteria_group_tabs_view.h"
#import "exteria_chat_settings.h"
#import "exteria_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_avatar_viewer.h"
#import "exteria_channel_card.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"
#import "exteria_chat_controller.h"
#import "exteria_emoji_label.h"
#import "exteria_gift_catalog_controller.h"
#import "exteria_gift_detail_controller.h"
#import "exteria_gift_grid_view.h"
#import "exteria_info_card_view.h"
#import "exteria_music_list_controller.h"
#import "exteria_music_pill.h"
#import "exteria_popup_menu.h"
#import "exteria_profile_action.h"
#import "exteria_profile_backdrop_view.h"
#import "exteria_profile_colors.h"
#import "exteria_custom_emoji.h"
#import "exteria_profile_chat.h"
#import "exteria_profile_qr_controller.h"
#import "exteria_alert.h"
#import "exteria_gift_folder_bar.h"
#import "exteria_image_decoder.h"
#import "exteria_lite_mode.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_session_bots.h"
#import "exteria_profile_feed.h"
#import "exteria_report_flow.h"
#import "exteria_session_channels.h"
#import "exteria_session_profile.h"
#import "exteria_session_actions.h"
#import "exteria_star_gift.h"
#import "exteria_status_label.h"
#import "exteria_rating_view.h"
#import "exteria_typing_board.h"
#import "exteria_story.h"
#import "exteria_story_ring.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define AVATAR 96.0
#define ACTION_HEIGHT 66.0
#define GAP 14.0

#define BAR_SHADE_AFTER 24.0

@interface ExteriaUserProfileController () <ExteriaGiftGridDelegate, ExteriaGroupTabsDelegate, ExteriaGiftFolderBarDelegate, UIGestureRecognizerDelegate> {
    ExteriaGiftFolderBar *_folderBar;
    ExteriaDialog *_dialog;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    ExteriaGiftGridView *_grid;
    UIView *_head;
    ExteriaAvatarView *_avatar;
    ExteriaStoryRing *_storyRing;
    BOOL _storiesShown;
    ExteriaEmojiLabel *_name;
    /* the colored ground behind the head when the person wears a collectible color or status */
    ExteriaProfileBackdropView *_backdrop;
    CGFloat _backdropBottom;
    /* the name of the collectible the person wears and the emoji status it belongs to: a tap on the emoji says the name */
    NSString *_backdropTitle;
    long long _backdropStatusDocument;
    /* the emoji status of the user when it moves: drawn over the still picture the name already holds, at the place the name leaves for it */
    ExteriaLottieView *_statusAnimation;
    long long _statusAnimationDocument;
    NSUInteger _statusAnimationToken;
    ExteriaStatusLabel *_status;
    ExteriaRatingBadge *_ratingBadge;
    ExteriaUserAction *_messageAction;
    ExteriaUserAction *_soundAction;
    ExteriaUserAction *_callAction;
    ExteriaUserAction *_videoAction;
    ExteriaUserAction *_storiesAction;
    ExteriaMusicPill *_music;
    ExteriaChannelCard *_channelCard;
    ExteriaInfoCardView *_info;
    /* gifts, Media, Files and Links of the chat with this person */
    ExteriaGroupTabsView *_tabs;
    UILabel *_empty;
    UILabel *_toast;
    ExteriaProfileFeed *_feed;
    ExteriaFullUser *_fullUser;
    ExteriaStoryPeer *_storyPeer;
    BOOL _muted;
    BOOL _muteBusy;
    CGFloat _headHeight;
    CGFloat _headWidth;
}
@end

@implementation ExteriaUserProfileController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _stickers = [stickers retain];
    _muted = dialog.muted;
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _feed = [[ExteriaProfileFeed alloc] initWithSession:session kind:ExteriaFeedGifts owner:dialog];
    self.screenTitle = dialog.title;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_dialog release];
    [_stickers release];
    [_grid release];
    [_head release];
    [_avatar release];
    [_storyRing release];
    [_name release];
    [_statusAnimation release];
    [_backdrop release];
    [_backdropTitle release];
    [_status release];
    [_ratingBadge release];
    [_messageAction release];
    [_soundAction release];
    [_callAction release];
    [_videoAction release];
    [_storiesAction release];
    [_music release];
    [_channelCard release];
    [_info release];
    _tabs.delegate = nil;
    _folderBar.delegate = nil;
    [_folderBar release];
    [_tabs release];
    [_empty release];
    [_toast release];
    [_feed release];
    [_fullUser release];
    [_storyPeer release];
    [super dealloc];
}

static UILabel *ExteriaUserLabel(UIColor *color, UIFont *font, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = font;
    label.textAlignment = alignment;
    return label;
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[ExteriaGiftGridView alloc] initWithMedia:self.media];
    _grid.avatars = self.avatars;
    _grid.delegate = self;
    [root addSubview:_grid];

    _head = [[UIView alloc] init];
    _head.backgroundColor = [UIColor clearColor];
    _storyRing = [[ExteriaStoryRing alloc] init];
    _storyRing.hidden = YES;
    [_head addSubview:_storyRing];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.seed = _dialog.avatarSeed;
    _avatar.initials = _dialog.initials;
    _avatar.deleted = _dialog.deleted;
    _avatar.circular = YES;
    [_avatar setPhoto:_dialog.photo cache:self.avatars];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)] autorelease]];
    [_head addSubview:_avatar];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.textColor = ExteriaColorTitle();
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.dropsUndrawable = YES;
    /* a long name goes on a second line instead of ending in dots */
    _name.numberOfLines = 0;
    [self showName:_dialog.title emojiStatus:_dialog.emojiStatus premium:_dialog.premium];
    [_head addSubview:_name];
    /* the name draws no touches itself, so the tap on the hammer is taken by the header and placed by where the name ends */
    UITapGestureRecognizer *hammerTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headTapped:)] autorelease];
    hammerTap.delegate = self;
    [_head addGestureRecognizer:hammerTap];
    _status = [[ExteriaStatusLabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.font = ExteriaFontRegular(15);
    _status.textAlignment = ExteriaTextAlignmentCenter;
    [self refreshStatus];
    [_head addSubview:_status];
    _ratingBadge = [[ExteriaRatingBadge alloc] initWithFrame:CGRectZero];
    _ratingBadge.hidden = YES;
    [_ratingBadge addTarget:self action:@selector(openRating) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_ratingBadge];

    _messageAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolChats title:NSLocalizedString(@"profile.action.message", nil)];
    [_messageAction addTarget:self action:@selector(openMessages) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_messageAction];
    _soundAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolBell title:NSLocalizedString(@"channel.action.sound", nil)];
    [_soundAction addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_soundAction];
    [self refreshSound];
    /* a call goes to a person: not to a bot or to the saved messages */
    _callAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolPhone title:NSLocalizedString(@"profile.action.call", nil)];
    _callAction.hidden = ![self canCallPerson];
    [_callAction addTarget:self action:@selector(startCall) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_callAction];
    _videoAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolVideoCamera title:NSLocalizedString(@"profile.action.video", nil)];
    _videoAction.hidden = ![self canCallPerson];
    [_videoAction addTarget:self action:@selector(startVideoCall) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_videoAction];
    _storiesAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolPlay title:NSLocalizedString(@"profile.tab.stories", nil)];
    _storiesAction.hidden = YES;
    [_storiesAction addTarget:self action:@selector(openStories) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_storiesAction];

    _music = [[ExteriaMusicPill alloc] init];
    [_music addTarget:self action:@selector(openMusic) forControlEvents:UIControlEventTouchUpInside];
    ExteriaWeakReference *musicMe = _weak;
    _music.contentHandler = ^{ [(ExteriaUserProfileController *)musicMe.target musicContentChanged]; };
    [_head addSubview:_music];

    _channelCard = [[ExteriaChannelCard alloc] init];
    _channelCard.hidden = YES;
    [_channelCard addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_channelCard];
    _info = [[ExteriaInfoCardView alloc] init];
    ExteriaWeakReference *me = _weak;
    _info.codeCaption = NSLocalizedString(@"profile.username", nil);
    _info.codeHandler = ^{ [(ExteriaUserProfileController *)me.target openCode]; };
    _info.copyHandler = ^{ [(ExteriaUserProfileController *)me.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    [_head addSubview:_info];
    _tabs = [[ExteriaGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media forUser:YES];
    _tabs.delegate = self;
    [_head addSubview:_tabs];
    /* the folders of the gifts of this person, shown over the gifts while that tab is chosen */
    _folderBar = [[ExteriaGiftFolderBar alloc] initWithSession:self.session dialog:_dialog mine:NO];
    _folderBar.delegate = self;
    [_head addSubview:_folderBar];
    _empty = ExteriaUserLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _toast = ExteriaUserLabel([UIColor whiteColor], ExteriaFontSemibold(14), ExteriaTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

/* the line under the name: what the person is doing now, or on line in the accent color, or when they were last seen */
- (void)typingChanged:(NSNotification *)note {
    if (ExteriaTypingChangeConcerns(note, _dialog)) [self refreshStatus];
}

- (void)refreshStatus {
    if (self.isViewLoaded) [self.view setNeedsLayout];
    if (_dialog.kind == EXTERIA_DIALOG_BOT) {
        [_status setStatus:NSLocalizedString(@"profile.bot", nil) kind:ExteriaStatusPlain];
        return;
    }
    ExteriaTypingBoard *board = self.session.typing;
    NSString *typing = ExteriaTypingStatusText([board actionInDialog:_dialog], [board countInDialog:_dialog]);
    if (typing) {
        [_status setStatus:typing kind:ExteriaStatusTyping];
        return;
    }
    BOOL service = _dialog.peerKind == 1 && _dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID;
    [_status setStatus:service ? NSLocalizedString(@"chat.status.telegram", nil) : ExteriaLastSeenText(_dialog.presence, _dialog.seen)
                   kind:!service && _dialog.presence == EXTERIA_PRESENCE_ONLINE ? ExteriaStatusOnline : ExteriaStatusPlain];
}

- (void)viewDidLoad {
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    [super viewDidLoad];
    NSLog(@"exteria: the profile view loaded in %.0f ms", ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:) name:ExteriaTypingDidChangeNotification object:self.session.typing];
    [self refreshMenu];
    [self load];
    NSLog(@"exteria: the profile screen is set up");
}

/* the ring round the picture follows the stories of the person: coloured while one is unseen, grey once all were
   seen */
- (void)loadStories {
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session loadStoriesOfDialog:_dialog completion:^(ExteriaStoryPeer *peer, NSArray *stories, NSString *errorName) {
        [self autorelease];
        ExteriaUserProfileController *profile = me.target;
        if (!profile || errorName) return;
        [profile->_storyPeer release];
        profile->_storyPeer = stories.count ? [peer retain] : nil;
        profile->_storyRing.hidden = !profile->_storyPeer;
        if (profile->_storyPeer) [profile->_storyRing setPeer:profile->_storyPeer];
        [profile.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    if (_storyPeer) [self openStories];
    else [self openAvatars];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_storiesShown) [self loadStories];
    _storiesShown = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_statusAnimation setPlaying:YES];
    NSLog(@"exteria: the profile screen is on screen");
}

/* the recognizer takes the touches over the name only: one that took every touch of the header cancelled the controls under it, the pill of the music among them */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    (void)recognizer;
    return (ExteriaDialogIsDeveloper(_dialog) || _backdropTitle.length) && CGRectContainsPoint(CGRectInset(_name.frame, 0, -8), [touch locationInView:_head]);
}

- (void)headTapped:(UITapGestureRecognizer *)tap {
    if (tap.state != UIGestureRecognizerStateEnded) return;
    CGPoint point = [tap locationInView:_name];
    long long document = [_name customEmojiAtPoint:point];
    if (_backdropTitle.length && document && document == _backdropStatusDocument && point.y >= -8 && point.y <= _name.bounds.size.height + 8) {
        [self toast:_backdropTitle];
        return;
    }
    if (!ExteriaDialogIsDeveloper(_dialog)) return;
    NSUInteger mark = ExteriaMarkForDocument(document);
    if (point.y < -8 || point.y > _name.bounds.size.height + 8 || !mark) return;
    ExteriaShowMarkNotice(_dialog.title, mark);
}

- (void)load {
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session loadFullUserOfDialog:_dialog completion:^(ExteriaFullUser *user, NSString *errorName) {
        [self autorelease];
        ExteriaUserProfileController *profile = me.target;
        if (!profile) return;
        if (!user) {
            NSLog(@"exteria: the profile of %lld did not load: %@", profile->_dialog.peerId, errorName);
            return;
        }
        [profile->_fullUser release];
        profile->_fullUser = [user retain];
        [profile showFull];
    }];
    [self loadStories];
    [_folderBar reload];
    [_feed reload:^{ [(ExteriaUserProfileController *)me.target feedChanged]; }];
}

#pragma mark folders

- (void)giftFolderBar:(ExteriaGiftFolderBar *)bar didSelectFolder:(ExteriaGiftFolder *)folder {
    (void)bar;
    [self reloadFeedOfFolder:folder.folderId];
}

- (void)giftFolderBarDidChange:(ExteriaGiftFolderBar *)bar selectionChanged:(BOOL)selectionChanged {
    if (selectionChanged) [self reloadFeedOfFolder:bar.selectedFolder.folderId];
    [self.view setNeedsLayout];
}

- (void)reloadFeedOfFolder:(int32_t)folderId {
    ExteriaWeakReference *me = _weak;
    _feed.folderId = folderId;
    [_feed reload:^{ [(ExteriaUserProfileController *)me.target feedChanged]; }];
}

#pragma mark content

/* the name with the custom emoji status of the user after it, or the Premium star; the picture is fetched once and the name is drawn
   again when it lands */
- (void)showName:(NSString *)name emojiStatus:(long long)emojiStatus premium:(BOOL)premium {
    NSArray *entities = nil;
    long long badge = _dialog.peerKind == 1 && _dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID ? ExteriaDialogBadgeDocument(_dialog) : (_dialog.saved ? 0 : ExteriaBadgeDocument(emojiStatus, premium));
    _name.text = ExteriaNameWithBadges(name, badge, ExteriaDialogIsDeveloper(_dialog), &entities);
    _name.entities = entities;
    /* only a status that is the badge drawn after the name has a place to move in */
    [self animateStatus:badge == emojiStatus ? emojiStatus : 0];
    if (!emojiStatus) return;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:emojiStatus]], self.session, self.media, ^{
        ExteriaUserProfileController *profile = weak.target;
        if (profile) [profile->_name setNeedsDisplay];
    });
}

- (void)dropStatusAnimation {
    ++_statusAnimationToken;
    _name.hiddenCustomEmoji = 0;
    _statusAnimationDocument = 0;
    [_statusAnimation removeFromSuperview];
    [_statusAnimation release];
    _statusAnimation = nil;
}

/* a status that is an animation (tgs, or a video sticker) is fetched once and plays in place of its still picture; a plain one stays as it is drawn. The same
   status again only puts the animation back at the place the name now leaves for it */
- (void)animateStatus:(long long)document {
    if (document && document == _statusAnimationDocument) {
        [self placeStatusAnimation];
        return;
    }
    [self dropStatusAnimation];
    if (!document || !ExteriaLiteEnabled(EXTERIA_LITE_EMOJI_CHAT)) return;
    _statusAnimationDocument = document;
    NSUInteger token = ++_statusAnimationToken;
    ExteriaWeakReference *weak = _weak;
    [self.session loadCustomEmojiDocuments:[NSArray arrayWithObject:[NSNumber numberWithLongLong:document]] completion:^(NSArray *documents, NSString *errorName) {
        ExteriaUserProfileController *profile = weak.target;
        if (!profile || token != profile->_statusAnimationToken) return;
        ExteriaCustomEmojiDocument *found = documents.count ? [documents objectAtIndex:0] : nil;
        if (!found) {
            if (errorName) NSLog(@"exteria: the status emoji %lld was not looked up: %@", document, errorName);
            return;
        }
        if (!found.file || (found.format != EXTERIA_STICKER_ANIMATED && found.format != EXTERIA_STICKER_VIDEO)) return;
        NSString *key = found.file.key;
        [profile.media loadDataForFile:found.file completion:^(NSData *data) {
            ExteriaUserProfileController *again = weak.target;
            if (!again || token != again->_statusAnimationToken) return;
            ExteriaFileFormat format = data ? ExteriaFileFormatOfData(data) : ExteriaFileFormatUnknown;
            if (format != ExteriaFileFormatGzip && format != ExteriaFileFormatMatroska) {
                NSLog(@"exteria: the status emoji %@ did not load as tgs or webm", key);
                return;
            }
            [again showStatusAnimation:data key:key];
        }];
    }];
}

- (void)showStatusAnimation:(NSData *)data key:(NSString *)key {
    ExteriaLottieView *view = [[[ExteriaLottieView alloc] initWithPackedData:data key:key] autorelease];
    view.userInteractionEnabled = NO;
    view.backgroundColor = [UIColor clearColor];
    [_statusAnimation removeFromSuperview];
    [_statusAnimation release];
    _statusAnimation = [view retain];
    ExteriaWeakReference *weak = _weak;
    NSUInteger token = _statusAnimationToken;
    view.firstFrameHandler = ^{
        ExteriaUserProfileController *profile = weak.target;
        if (profile && token == profile->_statusAnimationToken)
            profile->_name.hiddenCustomEmoji = profile->_statusAnimationDocument;
    };
    [_head addSubview:view];
    [self placeStatusAnimation];
    [view setPlaying:self.isViewLoaded && self.view.window != nil];
}

/* the name keeps the still picture until the animation has its first frame */
- (void)placeStatusAnimation {
    if (!_statusAnimation) return;
    CGRect box = [_name customEmojiRect:_statusAnimationDocument];
    if (CGRectIsNull(box)) {
        _statusAnimation.hidden = YES;
        return;
    }
    CGFloat side = box.size.width;
    _statusAnimation.frame = [_head convertRect:CGRectMake(box.origin.x, CGRectGetMidY(box) - side / 2, side, side) fromView:_name];
    _statusAnimation.hidden = NO;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_statusAnimation setPlaying:NO];
}

/* the head takes the colors of the person: a collectible's own, or those of the color they picked from the server's list, which are asked for once */
- (void)applyBackdropOfPerson:(ExteriaPerson *)person {
    if (person.hasBackdrop) {
        [_backdropTitle release];
        _backdropTitle = [person.backdropTitle copy];
        _backdropStatusDocument = person.emojiStatus;
        [self showBackdropCenter:person.backdropCenter edge:person.backdropEdge pattern:person.backdropPattern text:person.backdropText document:person.backdropPatternDocument];
        return;
    }
    if (!person.hasProfileColor) return;
    ExteriaWeakReference *weak = _weak;
    int32_t colorId = (int32_t)person.profileColorId;
    long long emoji = person.profileColorEmoji;
    [ExteriaProfileColors loadWithSession:self.session completion:^{
        ExteriaUserProfileController *profile = weak.target;
        uint32_t center = 0, edge = 0;
        if (!profile || ![ExteriaProfileColors blendForColorId:colorId dark:ExteriaThemeIsDark() center:&center edge:&edge]) return;
        [profile showBackdropCenter:center edge:edge pattern:0xFFFFFF text:0xFFFFFF document:emoji];
    }];
}

/* the color the bar fills with once the content has scrolled under it: the edge of the ground, darker */
static UIColor *ExteriaDarkenedBackdrop(uint32_t rgb) {
    const CGFloat keep = 0.5;
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 * keep green:((rgb >> 8) & 0xff) / 255.0 * keep blue:(rgb & 0xff) / 255.0 * keep alpha:1];
}

/* the blend behind the photo, the text over it, the action cards as veils with the same ink, and the emoji that tiles the ground */
- (void)showBackdropCenter:(uint32_t)center edge:(uint32_t)edge pattern:(uint32_t)pattern text:(uint32_t)text document:(long long)document {
    if (!_backdrop) {
        _backdrop = [[ExteriaProfileBackdropView alloc] init];
        [_head insertSubview:_backdrop atIndex:0];
    }
    _backdrop.centerColor = ExteriaColorOfRGB(center);
    _backdrop.edgeColor = ExteriaColorOfRGB(edge);
    _backdrop.patternColor = ExteriaColorOfRGB(pattern);
    _backdrop.photoRadius = AVATAR / 2;
    /* the bar over the ground is clear, which makes it the ground's continuation, and darkens with the scroll */
    self.barTint = ExteriaDarkenedBackdrop(edge);
    UIColor *ink = ExteriaColorOfRGB(text);
    _name.textColor = ink;
    _status.plainColor = [ink colorWithAlphaComponent:0.78f];
    _status.activeColor = ink;
    for (ExteriaUserAction *action in [NSArray arrayWithObjects:_messageAction, _soundAction, _callAction, _videoAction, nil]) [action setInk:ink];
    if (document > 0) {
        ExteriaWeakReference *weak = _weak;
        ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:document]], self.session, self.media, ^{
            [(ExteriaUserProfileController *)weak.target showPatternOfDocument:document];
        });
        [self showPatternOfDocument:document];
    }
    [self.view setNeedsLayout];
    [_name setNeedsDisplay];
}

- (void)showPatternOfDocument:(long long)document {
    UIImage *picture = [ExteriaCustomEmoji imageForDocument:document];
    if (picture) _backdrop.patternImage = picture;
}

- (void)showFull {
    ExteriaFullUser *user = _fullUser;
    _ratingBadge.hidden = !user.hasRating;
    _ratingBadge.level = user.rating.level;
    _ratingBadge.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"rating.level", nil), (int)user.rating.level];
    [self applyBackdropOfPerson:user.person];
    if (user.person.name.length) {
        [self showName:user.person.name emojiStatus:user.person.emojiStatus premium:user.person.premium];
        self.screenTitle = user.person.name;
    }
    NSString *birthday = @"";
    if (user.hasBirthday) {
        NSDateComponents *parts = [[[NSDateComponents alloc] init] autorelease];
        parts.day = user.birthdayDay;
        parts.month = user.birthdayMonth;
        parts.year = user.birthdayYear > 0 ? user.birthdayYear : 2000;
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:parts];
        NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
        formatter.dateFormat = user.birthdayYear > 0 ? @"d MMMM yyyy" : @"d MMMM";
        if (date) birthday = [formatter stringFromDate:date];
    }
    ExteriaPerson *person = user.person;
    NSMutableArray *infoRows = [NSMutableArray arrayWithObjects:
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.phone", nil), person.phone.length ? [@"+" stringByAppendingString:person.phone] : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.about", nil), user.about ? user.about : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.username", nil), person.username.length ? [@"@" stringByAppendingString:person.username] : @"", nil],
        [NSArray arrayWithObjects:NSLocalizedString(@"profile.birthday", nil), birthday, nil], nil];
    [infoRows addObjectsFromArray:ExteriaIdentityRows(person.userId, person.photo)];
    [_info setRows:infoRows];
    _channelCard.hidden = user.channel == nil;
    if (user.channel) [_channelCard configureWithChannel:user.channel avatars:self.avatars];
    _music.savedTrack = user.music;
    _callAction.hidden = ![self canCallPerson];
    _videoAction.hidden = ![self canCallPerson];
    [self refreshMenu];
    [self.view setNeedsLayout];
}

- (void)feedChanged {
    /* the gifts show under the tabs only while the Gifts tab is chosen; the other tabs bring their own lists */
    BOOL gifts = _tabs.selectedTab == 0;
    [_grid setTiles:gifts ? _feed.tiles : [NSArray array]];
    BOOL any = _feed.items.count > 0;
    NSString *text = @"";
    if (gifts && _feed.loaded && !any) text = NSLocalizedString(@"gifts.empty", nil);
    if (![_empty.text isEqualToString:text]) _empty.text = text;
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid {
    (void)grid;
    ExteriaWeakReference *me = _weak;
    [_feed loadMore:^{ [(ExteriaUserProfileController *)me.target feedChanged]; }];
}

- (void)giftGrid:(ExteriaGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _feed.items.count) return;
    ExteriaGiftDetailController *detail = [[[ExteriaGiftDetailController alloc] initWithSession:self.session gift:[_feed.items objectAtIndex:index] mine:NO
                                                                                        avatars:self.avatars media:self.media] autorelease];
    detail.ownerName = _dialog.title;
    detail.stickers = _stickers;
    [detail showInViewController:self];
}

#pragma mark tabs

- (void)groupTabsDidResize:(ExteriaGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}

- (void)groupTabsDidChooseTab:(ExteriaGroupTabsView *)tabs {
    (void)tabs;
    [self feedChanged];
}

- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenPerson:(ExteriaPerson *)person {
    (void)tabs;
    (void)person;
}

/* a file or a link opens the chat at its message */
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMessage:(ExteriaMessage *)message {
    (void)tabs;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}

/* a picture or video opens in the viewer, as in the chat, and not the chat at the place where it was sent */
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMedia:(ExteriaMessage *)message among:(NSArray *)messages {
    (void)tabs;
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithMessages:messages selected:message media:self.media senderNames:nil
                                                                     chatTitle:_dialog.title] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark layout

- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat y = 16;
    _avatar.frame = CGRectMake((width - AVATAR) / 2, y, AVATAR, AVATAR);
    CGFloat outset = [ExteriaStoryRing outset];
    _storyRing.frame = CGRectInset(_avatar.frame, -outset, -outset);
    y += AVATAR + 12;
    _name.font = ExteriaFontBold(22);
    CGFloat nameHeight = MAX(28, ceil([_name sizeThatFits:CGSizeMake(contentWidth, 200)].height));
    _name.frame = CGRectMake(x, y, contentWidth, nameHeight);
    [self placeStatusAnimation];
    CGFloat statusWidth = MIN(contentWidth - (_ratingBadge.hidden ? 0 : 28), ceil([_status sizeThatFits:CGSizeMake(contentWidth, 20)].width) + 8);
    CGFloat statusStart = (width - statusWidth - (_ratingBadge.hidden ? 0 : 28)) / 2;
    _ratingBadge.frame = CGRectMake(statusStart, y + nameHeight + 2, 22, 20);
    _status.frame = CGRectMake(statusStart + (_ratingBadge.hidden ? 0 : 28), y + nameHeight + 2, statusWidth, 20);
    y += nameHeight + 22 + GAP + 4;
    NSMutableArray *actions = [NSMutableArray array];
    /* message, sound, call and video stand in one row; the gift is in the menu behind the dots */
    ExteriaUserAction *order[4] = {_messageAction, _soundAction, _callAction, _videoAction};
    for (int i = 0; i < 4; ++i) {
        if (!order[i].hidden) [actions addObject:order[i]];
    }
    y += ExteriaLayoutActions(actions, x, y, contentWidth, ACTION_HEIGHT, 10) + GAP;
    if (_backdrop) {
        /* the ground runs up under the bar and down behind the action cards */
        CGFloat above = 600;
        _backdropBottom = y - GAP + 6;
        _backdrop.frame = CGRectMake(0, -above, width, above + _backdropBottom);
        _backdrop.focus = CGPointMake(width / 2, above + CGRectGetMidY(_avatar.frame));
    }
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
    CGFloat tabsHeight = [_tabs heightForWidth:contentWidth];
    _tabs.frame = CGRectMake(x, y, contentWidth, tabsHeight);
    y += tabsHeight + GAP;
    CGFloat folders = _tabs.selectedTab == 0 ? [_folderBar height] : 0;
    _folderBar.hidden = folders == 0;
    _folderBar.frame = CGRectMake(x, y - GAP, contentWidth, folders);
    if (folders) y += folders;
    CGSize empty = _empty.text.length ? [_empty sizeThatFits:CGSizeMake(contentWidth - 16, 200)] : CGSizeZero;
    _empty.frame = CGRectMake(x + 8, y + 8, contentWidth - 16, empty.height);
    y += empty.height ? empty.height + 24 : 0;
    if (fabs(y - _headHeight) > 0.5 || fabs(width - _headWidth) > 0.5) {
        _headHeight = y;
        _headWidth = width;
        _head.frame = CGRectMake(0, 0, width, y);
        _grid.headerView = _head;
    }
}

- (void)layoutBody:(CGRect)body {
    /* the list runs under the bar when the head has a ground of its own, which then shows through the clear bar; the bar's height is the list's top inset */
    BOOL underBar = _backdrop && !ExteriaThemeIsClassic();
    _grid.frame = underBar ? CGRectMake(body.origin.x, 0, body.size.width, CGRectGetMaxY(body)) : body;
    _grid.topInset = underBar ? body.origin.y : 0;
    _toast.frame = CGRectMake(CGRectGetMidX(body) - 80, body.origin.y + 12, 160, 28);
    [self layoutHead];
}

/* the bar fills once the head has moved a little under it, and clears again at the top */
- (void)giftGrid:(ExteriaGiftGridView *)grid didScrollToOffset:(CGFloat)offset {
    (void)grid;
    if (!_backdrop || ExteriaThemeIsClassic()) return;
    [self setBarShaded:offset > -_grid.topInset + BAR_SHADE_AFTER animated:YES];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

#pragma mark menu

typedef enum { ExteriaUserMenuCopyLink, ExteriaUserMenuGift, ExteriaUserMenuNotifications, ExteriaUserMenuReport, ExteriaUserMenuEditContact, ExteriaUserMenuSharing } ExteriaUserMenuEntry;

- (BOOL)canGift {
    return _dialog.kind == EXTERIA_DIALOG_USER && !_dialog.saved;
}

/* the calls go to a person, not to a bot; the profile that was opened from a mention learns that it is a bot when the full user comes in */
- (BOOL)canCallPerson {
    return [self canGift] && !_fullUser.person.bot && _dialog.peerId != EXTERIA_TELEGRAM_SERVICE_USER_ID;
}

- (NSString *)username {
    return _fullUser.person.username.length ? _fullUser.person.username : nil;
}

/* the saved messages are the account itself, which nobody reports */
- (BOOL)canReport {
    return !_dialog.saved;
}

/* the three dots only show while the menu has something to offer */
- (void)refreshMenu {
    if (![self canGift] && ![self username] && ![self canReport] && !_dialog.saved) {
        [self setActionSymbol:ExteriaSymbolEllipsis label:nil handler:nil];
        return;
    }
    ExteriaWeakReference *me = _weak;
    [self setActionSymbol:ExteriaSymbolEllipsis label:NSLocalizedString(@"profile.more", nil)
                  handler:^{ [(ExteriaUserProfileController *)me.target showMenu]; }];
}

/* the name of the contact is asked as one line, the first word being the first name and the rest the last, as the old Telegram clients ask for it in one field */
- (void)askContactName {
    ExteriaPerson *person = _fullUser.person;
    if (!person) return;
    ExteriaWeakReference *me = _weak;
    ExteriaPromptText(NSLocalizedString(@"profile.contact.edit", nil), nil, person.name, NSLocalizedString(@"profile.contact.placeholder", nil), ^(NSString *text) {
        ExteriaUserProfileController *profile = me.target;
        NSString *full = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!profile || !full.length) return;
        NSRange space = [full rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *first = space.location == NSNotFound ? full : [full substringToIndex:space.location];
        NSString *last = space.location == NSNotFound ? @"" : [[full substringFromIndex:space.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [profile retain];
        [profile.session editContact:person firstName:first lastName:last completion:^(NSString *errorName) {
            [profile autorelease];
            if (errorName) {
                NSLog(@"exteria: the contact was not renamed: %@", errorName);
                ExteriaShowNotice(nil, NSLocalizedString(@"profile.contact.error", nil));
                return;
            }
            /* the profile is read again, and brings the name the server keeps now */
            [profile load];
        }];
    });
}

- (void)showMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    ExteriaSymbol symbols[6];
    if (_fullUser && [self canGift] && !_fullUser.person.bot && _fullUser.person.accessHash && _dialog.peerId != EXTERIA_TELEGRAM_SERVICE_USER_ID) {
        symbols[titles.count] = ExteriaSymbolLock;
        [titles addObject:NSLocalizedString(_fullUser.sharingRestricted ? @"chat.sharing.allow" : @"chat.sharing.disable", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuSharing]];
    }
    /* a person the account can rename: a user with a hash, once the profile is in */
    if ([self canGift] && _fullUser.person.accessHash && !_fullUser.person.bot) {
        symbols[titles.count] = ExteriaSymbolCompose;
        [titles addObject:NSLocalizedString(_fullUser.person.contact ? @"profile.contact.edit" : @"profile.contact.add", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuEditContact]];
    }
    if ([self username]) {
        symbols[titles.count] = ExteriaSymbolLink;
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuCopyLink]];
    }
    if ([self canGift]) {
        symbols[titles.count] = ExteriaSymbolGift;
        [titles addObject:NSLocalizedString(@"gifts.send", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuGift]];
    }
    if (!_dialog.saved) {
        symbols[titles.count] = ExteriaSymbolBell;
        [titles addObject:NSLocalizedString(@"notif.chat.header", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuNotifications]];
    }
    if ([self canReport]) {
        symbols[titles.count] = ExteriaSymbolReport;
        [titles addObject:NSLocalizedString(@"report.title", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaUserMenuReport]];
    }
    if (!titles.count) return;
    ExteriaWeakReference *me = _weak;
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        ExteriaUserProfileController *profile = me.target;
        if (!profile || index >= entries.count) return;
        switch ([[entries objectAtIndex:index] intValue]) {
        case ExteriaUserMenuSharing: {
            BOOL restricted = !profile->_fullUser.sharingRestricted;
            ExteriaConfirm(nil, NSLocalizedString(restricted ? @"chat.sharing.disable.confirm" : @"chat.sharing.allow.confirm", nil),
                           NSLocalizedString(restricted ? @"chat.sharing.disable" : @"chat.sharing.allow", nil), ^{
                ExteriaUserProfileController *owner = me.target;
                if (!owner) return;
                [owner.session setSharingRestricted:restricted ofDialog:owner->_dialog requestId:0 completion:^(NSString *errorName) {
                    ExteriaUserProfileController *current = me.target;
                    if (errorName) ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.sharing.error", nil), errorName]);
                    else {
                        ExteriaShowNotice(nil, NSLocalizedString(@"chat.sharing.sent", nil));
                        [current load];
                    }
                }];
            });
            break;
        }
        case ExteriaUserMenuEditContact: [profile askContactName]; break;
        case ExteriaUserMenuCopyLink: [profile copyLink]; break;
        case ExteriaUserMenuGift: [profile sendGift]; break;
        case ExteriaUserMenuNotifications:
            [profile.navigationController pushViewController:[[[ExteriaNotificationsChatController alloc] initWithSession:profile.session media:profile.media peerKind:profile->_dialog.peerKind
                                                                                                                  peerId:profile->_dialog.peerId peerHash:profile->_dialog.peerHash channel:NO
                                                                                                                   topic:0 title:profile->_dialog.title] autorelease] animated:YES];
            break;
        case ExteriaUserMenuReport: [ExteriaReportFlow startForDialog:profile->_dialog session:profile.session host:profile done:nil]; break;
        }
    }] autorelease];
    [menu showInView:self.view anchor:[self actionSymbolAnchor]];
}

/* the chat the profile was opened from when it is right below, a new one otherwise */
- (void)openMessages {
    ExteriaProfileShowChat(self, self.session, _dialog, self.avatars, self.media, _stickers);
}

- (void)startCall {
    [self.session startCallToDialog:_dialog];
}

- (void)startVideoCall {
    [self.session startVideoCallToDialog:_dialog];
}

- (void)refreshSound {
    [_soundAction setSymbol:_muted ? ExteriaSymbolBellMuted : ExteriaSymbolBell
                      title:NSLocalizedString(_muted ? @"channel.action.muted" : @"channel.action.sound", nil)];
}

- (void)toggleMute {
    if (_muteBusy) return;
    _muteBusy = YES;
    BOOL mute = !_muted;
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session performAction:mute ? ExteriaChatCommandMute : ExteriaChatCommandUnmute onDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaUserProfileController *profile = me.target;
        if (!profile) return;
        profile->_muteBusy = NO;
        if (errorName) {
            [profile toast:ExteriaGiftErrorText(errorName)];
            return;
        }
        profile->_muted = mute;
        [profile refreshSound];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
    }];
}

- (void)copyLink {
    NSString *username = [self username];
    if (!username) return;
    [UIPasteboard generalPasteboard].string = [@"https://t.me/" stringByAppendingString:username];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)openCode {
    ExteriaPerson *person = _fullUser.person;
    if (!person) return;
    ExteriaProfileQrController *code = [[[ExteriaProfileQrController alloc] initWithSession:self.session person:person avatars:self.avatars
                                                                                      media:self.media] autorelease];
    [self.navigationController pushViewController:code animated:YES];
}

- (void)sendGift {
    ExteriaGiftCatalogController *catalog = [[[ExteriaGiftCatalogController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars
                                                                                              media:self.media] autorelease];
    ExteriaWeakReference *me = _weak;
    catalog.sentHandler = ^{
        ExteriaUserProfileController *profile = me.target;
        if (profile) [profile->_feed reload:^{ [(ExteriaUserProfileController *)me.target feedChanged]; }];
    };
    [self.navigationController pushViewController:catalog animated:YES];
}

- (void)openAvatars {
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)openStories {
    if (!_storyPeer) return;
    ExteriaStoryViewerController *viewer = [[[ExteriaStoryViewerController alloc] initWithSession:self.session peers:[NSArray arrayWithObject:_storyPeer] index:0
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)musicContentChanged {
    [self layoutHead];
    [self.view setNeedsLayout];
}

- (void)openMusic {
    ExteriaMusicListController *list = [[[ExteriaMusicListController alloc] initWithSession:self.session dialog:_dialog first:_fullUser.music
                                                                                    avatars:self.avatars media:self.media] autorelease];
    [self.navigationController pushViewController:list animated:YES];
}

- (void)openRating {
    ExteriaShowRating(self.view.window, _fullUser);
}

- (void)openChannel {
    ExteriaPersonalChannel *channel = _fullUser.channel;
    if (!channel) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:channel.dialog avatars:self.avatars media:self.media
                                                                         stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
