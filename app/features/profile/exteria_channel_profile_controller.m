#import "exteria_channel_profile_controller.h"
#import "exteria_notifications_chat_controller.h"
#import "exteria_media_viewer.h"
#import "exteria_text_filter.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_avatar_view.h"
#import "exteria_story.h"
#import "exteria_story_ring.h"
#import "exteria_story_viewer_controller.h"
#import "exteria_avatar_viewer.h"
#import "exteria_channel_errors.h"
#import "exteria_chat_controller.h"
#import "exteria_contact_picker_controller.h"
#import "exteria_emoji_label.h"
#import "exteria_channel_manage_controller.h"
#import "exteria_gift_detail_controller.h"
#import "exteria_gift_facts_view.h"
#import "exteria_gift_grid_view.h"
#import "exteria_group_tabs_view.h"
#import "exteria_user_profile_controller.h"
#import "exteria_info_card_view.h"
#import "exteria_popup_menu.h"
#import "exteria_profile_action.h"
#import "exteria_profile_chat.h"
#import "exteria_profile_qr_controller.h"
#import "exteria_profile_feed.h"
#import "exteria_report_flow.h"
#import "exteria_sheet.h"
#import "exteria_session_channels.h"
#import "exteria_star_gift.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define AVATAR 96.0
#define ACTION_HEIGHT 66.0
#define GAP 14.0
#define LINKED_HEIGHT 64.0

/* the discussion group of a channel as a card: its picture, its name and a line that says what it is, with a chevron */
@interface ExteriaLinkedGroupCard : UIControl {
    ExteriaAvatarView *_picture;
    ExteriaEmojiLabel *_title;
    UILabel *_caption;
    UIImageView *_chevron;
}
- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars;
@end

@implementation ExteriaLinkedGroupCard

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = ExteriaColorCard();
    self.layer.cornerRadius = 14;
    _picture = [[ExteriaAvatarView alloc] init];
    _picture.circular = YES;
    [self addSubview:_picture];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.textColor = ExteriaColorTitle();
    _title.font = ExteriaFontSemibold(17);
    [self addSubview:_title];
    _caption = [[UILabel alloc] init];
    _caption.backgroundColor = [UIColor clearColor];
    _caption.textColor = ExteriaColorSecondary();
    _caption.font = ExteriaFontRegular(14);
    _caption.text = NSLocalizedString(@"channel.discussion.card", nil);
    [self addSubview:_caption];
    _chevron = [[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolChevronRight, 16, ExteriaColorMuted())];
    _chevron.contentMode = UIViewContentModeCenter;
    [self addSubview:_chevron];
    for (UIView *view in self.subviews) view.userInteractionEnabled = NO;
    return self;
}

- (void)dealloc {
    [_picture release];
    [_title release];
    [_caption release];
    [_chevron release];
    [super dealloc];
}

- (void)configureWithDialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars {
    _picture.initials = dialog.initials;
    _picture.seed = dialog.avatarSeed;
    [_picture setPhoto:dialog.photo cache:avatars];
    _title.text = dialog.title;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    _picture.frame = CGRectMake(14, (size.height - 44) / 2, 44, 44);
    _title.frame = CGRectMake(70, 10, size.width - 70 - 40, 22);
    _caption.frame = CGRectMake(70, 34, size.width - 70 - 40, 20);
    _chevron.frame = CGRectMake(size.width - 36, 0, 24, size.height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.7 : 1;
}

@end

@interface ExteriaChannelProfileController () <ExteriaGiftGridDelegate, ExteriaGroupTabsDelegate> {
    ExteriaDialog *_dialog;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    ExteriaGiftGridView *_grid;
    UIView *_head;
    ExteriaAvatarView *_avatar;
    ExteriaStoryRing *_storyRing;
    ExteriaStoryPeer *_storyPeer;
    BOOL _storiesShown;
    ExteriaEmojiLabel *_name;
    UILabel *_status;
    ExteriaUserAction *_joinAction;
    ExteriaUserAction *_messageAction;
    ExteriaUserAction *_addAction;
    ExteriaUserAction *_soundAction;
    ExteriaUserAction *_discussionAction;
    ExteriaUserAction *_linkAction;
    ExteriaInfoCardView *_info;
    ExteriaLinkedGroupCard *_linkedCard;
    ExteriaGiftFactsView *_counts;
    ExteriaGroupTabsView *_groupTabs;
    UILabel *_giftsTitle;
    UILabel *_empty;
    UILabel *_toast;
    ExteriaProfileFeed *_feed;
    ExteriaFullChannel *_full;
    BOOL _muteBusy;
    BOOL _joinBusy;
    BOOL _joined;
    CGFloat _headHeight;
    CGFloat _headWidth;
}
@end

@implementation ExteriaChannelProfileController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _dialog = [dialog retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _feed = [[ExteriaProfileFeed alloc] initWithSession:session kind:ExteriaFeedGifts owner:dialog];
    self.screenTitle = dialog.title;
    return self;
}

/* the ring round the picture follows the stories of the channel, as on the profile of a person */
- (void)loadStories {
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session loadStoriesOfDialog:_dialog completion:^(ExteriaStoryPeer *peer, NSArray *stories, NSString *errorName) {
        [self autorelease];
        ExteriaChannelProfileController *profile = me.target;
        if (!profile || errorName) return;
        [profile->_storyPeer release];
        profile->_storyPeer = stories.count ? [peer retain] : nil;
        profile->_storyRing.hidden = !profile->_storyPeer;
        if (profile->_storyPeer) [profile->_storyRing setPeer:profile->_storyPeer];
        [profile.view setNeedsLayout];
    }];
}

- (void)avatarTapped {
    if (!_storyPeer) {
        [self openAvatars];
        return;
    }
    ExteriaStoryViewerController *viewer = [[[ExteriaStoryViewerController alloc] initWithSession:self.session peers:[NSArray arrayWithObject:_storyPeer] index:0
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_storiesShown) [self loadStories];
    _storiesShown = YES;
}

- (void)openAvatars {
    ExteriaAvatarViewer *viewer = [[[ExteriaAvatarViewer alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_dialog release];
    [_stickers release];
    [_grid release];
    [_head release];
    [_avatar release];
    [_storyRing release];
    [_storyPeer release];
    [_name release];
    [_status release];
    [_joinAction release];
    [_messageAction release];
    [_addAction release];
    [_soundAction release];
    [_discussionAction release];
    [_linkAction release];
    [_info release];
    [_linkedCard release];
    [_counts release];
    _groupTabs.delegate = nil;
    [_groupTabs release];
    [_giftsTitle release];
    [_empty release];
    [_toast release];
    [_feed release];
    [_full release];
    [super dealloc];
}

static UILabel *ExteriaChannelProfileLabel(UIColor *color, UIFont *font, NSInteger alignment) {
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
    _avatar.circular = YES;
    [_avatar setPhoto:_dialog.photo cache:self.avatars];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped)] autorelease]];
    [_head addSubview:_avatar];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.textColor = ExteriaColorTitle();
    _name.textAlignment = ExteriaTextAlignmentCenter;
    _name.text = _dialog.title;
    [_head addSubview:_name];
    _status = ExteriaChannelProfileLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _status.text = [self kindText];
    [_head addSubview:_status];

    _joinAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolMember title:NSLocalizedString(@"channel.action.join", nil)];
    _joinAction.hidden = YES;
    [_joinAction addTarget:self action:@selector(join) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_joinAction];
    _messageAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolChats title:NSLocalizedString(@"channel.action.message", nil)];
    _messageAction.hidden = YES;
    [_messageAction addTarget:self action:@selector(openMessages) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_messageAction];
    _addAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolPlusCircle title:NSLocalizedString(@"group.action.add", nil)];
    _addAction.hidden = YES;
    [_addAction addTarget:self action:@selector(addMembers) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_addAction];
    _soundAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolBell title:NSLocalizedString(@"channel.action.sound", nil)];
    _soundAction.enabled = NO;
    _soundAction.hidden = YES;
    [_soundAction addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_soundAction];
    _discussionAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolChats title:NSLocalizedString(@"channel.action.discussion", nil)];
    _discussionAction.hidden = YES;
    [_discussionAction addTarget:self action:@selector(openDiscussion) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_discussionAction];
    /* the share glyph profile row; the link is copied, because the share sheet starts at ios 6 */
    _linkAction = [[ExteriaUserAction alloc] initWithSymbol:ExteriaSymbolShare title:NSLocalizedString(@"channel.action.link", nil)];
    _linkAction.hidden = YES;
    [_linkAction addTarget:self action:@selector(copyLink) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_linkAction];

    _info = [[ExteriaInfoCardView alloc] init];
    ExteriaWeakReference *me = _weak;
    _info.copyHandler = ^{ [(ExteriaChannelProfileController *)me.target toast:NSLocalizedString(@"profile.copied", nil)]; };
    /* the code of the link is a button at the right end of the link row, as on a profile, and the row only exists when there is a link to show */
    _info.codeCaption = NSLocalizedString(@"channel.link", nil);
    _info.codeHandler = ^{ [(ExteriaChannelProfileController *)me.target openQr]; };
    [_head addSubview:_info];
    _linkedCard = [[ExteriaLinkedGroupCard alloc] init];
    _linkedCard.hidden = YES;
    [_linkedCard addTarget:self action:@selector(openDiscussion) forControlEvents:UIControlEventTouchUpInside];
    [_head addSubview:_linkedCard];
    _counts = [[ExteriaGiftFactsView alloc] init];
    _counts.hidden = YES;
    [_head addSubview:_counts];
    _giftsTitle = ExteriaChannelProfileLabel(ExteriaColorAccent(), ExteriaFontSemibold(15), ExteriaTextAlignmentLeft);
    _giftsTitle.text = NSLocalizedString(@"gifts.title", nil);
    _giftsTitle.hidden = YES;
    [_head addSubview:_giftsTitle];
    _empty = ExteriaChannelProfileLabel(ExteriaColorSecondary(), ExteriaFontRegular(15), ExteriaTextAlignmentCenter);
    _empty.numberOfLines = 0;
    [_head addSubview:_empty];
    _grid.headerView = _head;

    _toast = ExteriaChannelProfileLabel([UIColor whiteColor], ExteriaFontSemibold(14), ExteriaTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshMenu];
    [self load];
    [self loadStories];
}

- (NSString *)kindText {
    if (_full.megagroup || _dialog.kind == EXTERIA_DIALOG_GROUP) return NSLocalizedString(@"channel.kind.group", nil);
    return NSLocalizedString(_full.username.length ? @"channel.kind.public" : @"channel.kind.private", nil);
}

- (void)load {
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session loadFullChannelOfDialog:_dialog completion:^(ExteriaFullChannel *channel, NSString *errorName) {
        [self autorelease];
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        if (!channel) {
            NSLog(@"exteria: the profile of channel %lld did not load: %@", profile->_dialog.peerId, errorName);
            return;
        }
        [profile->_full release];
        profile->_full = [channel retain];
        [profile showFull];
    }];
    [_feed reload:^{ [(ExteriaChannelProfileController *)me.target feedChanged]; }];
}

#pragma mark content

/* who is in the channel gets sound and, in a group, the chat; mute needs a member, so it waits for the full
   channel instead of showing a button that would fail */
- (BOOL)isMember {
    return _full != nil && (_joined || !(_full.membershipKnown ? _full.dialog.left : _dialog.left));
}

- (void)refreshActions {
    BOOL member = [self isMember];
    BOOL loaded = _full != nil;
    BOOL group = _full.megagroup || _dialog.kind == EXTERIA_DIALOG_GROUP;
    _joinAction.hidden = !loaded || member;
    _messageAction.hidden = !(member && group);
    _addAction.hidden = !(member && _full.megagroup);
    _soundAction.hidden = !member;
    _soundAction.enabled = member;
    BOOL muted = _full.muted;
    [_soundAction setSymbol:muted ? ExteriaSymbolBellMuted : ExteriaSymbolBell
                      title:NSLocalizedString(muted ? @"channel.action.muted" : @"channel.action.sound", nil)];
    _discussionAction.hidden = _full.linked == nil;
    _linkAction.hidden = !_full.webLink.length;
}

- (void)showFull {
    ExteriaFullChannel *full = _full;
    _status.text = [self kindText];
    [self refreshActions];
    NSMutableArray *rows = [NSMutableArray array];
    if (full.about.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"channel.description", nil), full.about, nil]];
    if (full.shownLink.length) [rows addObject:[NSArray arrayWithObjects:NSLocalizedString(@"channel.link", nil), full.shownLink, nil]];
    [rows addObjectsFromArray:ExteriaIdentityRows(_dialog.peerId, _dialog.photo)];
    [_info setRows:rows];
    _linkedCard.hidden = full.linked == nil;
    if (full.linked) [_linkedCard configureWithDialog:full.linked avatars:self.avatars];
    [self fillCounts];
    if ((full.megagroup || _dialog.kind == EXTERIA_DIALOG_CHANNEL) && !_groupTabs) {
        _groupTabs = [[ExteriaGroupTabsView alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media];
        _groupTabs.delegate = self;
        [_head addSubview:_groupTabs];
    }
    [self refreshMenu];
    [self.view setNeedsLayout];
}

- (void)fillCounts {
    ExteriaFullChannel *full = _full;
    /* a fresh table replaces the old one, which cannot drop rows */
    [_counts removeFromSuperview];
    [_counts release];
    _counts = [[ExteriaGiftFactsView alloc] init];
    [_head addSubview:_counts];
    BOOL any = NO;
    if (full.participants > 0) {
        [_counts addRow:NSLocalizedString(full.megagroup ? @"channel.members" : @"channel.subscribers", nil) text:[NSString stringWithFormat:@"%ld", (long)full.participants] pill:nil];
        any = YES;
    }
    if (full.admins > 0) {
        [_counts addRow:NSLocalizedString(@"channel.admins", nil) text:[NSString stringWithFormat:@"%ld", (long)full.admins] pill:nil];
        any = YES;
    }
    if (full.banned > 0) {
        [_counts addRow:NSLocalizedString(@"channel.banned", nil) text:[NSString stringWithFormat:@"%ld", (long)full.banned] pill:nil];
        any = YES;
    }
    _counts.hidden = !any;
}

- (void)feedChanged {
    [_grid setTiles:_feed.tiles];
    BOOL any = _feed.items.count > 0;
    _giftsTitle.hidden = !any;
    NSString *text = @"";
    if (_feed.loaded && !any && _full.giftsAvailable) text = NSLocalizedString(@"gifts.empty", nil);
    if (![_empty.text isEqualToString:text]) _empty.text = text;
    [self.view setNeedsLayout];
}

- (void)giftGridReachedEnd:(ExteriaGiftGridView *)grid {
    (void)grid;
    ExteriaWeakReference *me = _weak;
    [_feed loadMore:^{ [(ExteriaChannelProfileController *)me.target feedChanged]; }];
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

#pragma mark layout

- (void)layoutHead {
    CGFloat width = _grid.bounds.size.width;
    if (width <= 0) return;
    CGFloat contentWidth = MIN(width - 32, 460);
    CGFloat x = (width - contentWidth) / 2;
    CGFloat y = 16;
    _avatar.frame = CGRectMake((width - AVATAR) / 2, y, AVATAR, AVATAR);
    _storyRing.frame = CGRectInset(_avatar.frame, -[ExteriaStoryRing outset], -[ExteriaStoryRing outset]);
    y += AVATAR + 12;
    _name.font = ExteriaFontBold(22);
    _name.frame = CGRectMake(x, y, contentWidth, 28);
    _status.frame = CGRectMake(x, y + 30, contentWidth, 20);
    y += 50 + GAP + 4;
    NSMutableArray *actions = [NSMutableArray array];
    ExteriaUserAction *order[6] = {_joinAction, _messageAction, _addAction, _soundAction, _discussionAction, _linkAction};
    for (int i = 0; i < 6; ++i) {
        if (!order[i].hidden) [actions addObject:order[i]];
    }
    if (actions.count) y += ExteriaLayoutActions(actions, x, y, contentWidth, ACTION_HEIGHT, 10) + GAP;
    CGFloat height = [_info heightForWidth:contentWidth];
    _info.hidden = height <= 0;
    if (!_info.hidden) {
        _info.frame = CGRectMake(x, y, contentWidth, height);
        y += height + GAP;
    }
    if (!_linkedCard.hidden) {
        _linkedCard.frame = CGRectMake(x, y, contentWidth, LINKED_HEIGHT);
        y += LINKED_HEIGHT + GAP;
    }
    if (!_counts.hidden) {
        CGFloat countsHeight = [_counts heightForWidth:contentWidth];
        _counts.frame = CGRectMake(x, y, contentWidth, countsHeight);
        y += countsHeight + GAP;
    }
    if (_groupTabs) {
        CGFloat tabsHeight = [_groupTabs heightForWidth:contentWidth];
        _groupTabs.frame = CGRectMake(x, y, contentWidth, tabsHeight);
        y += tabsHeight + GAP;
    }
    if (!_giftsTitle.hidden) {
        _giftsTitle.frame = CGRectMake(x + 8, y, contentWidth - 16, 20);
        y += 28;
    }
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
    _grid.frame = body;
    _toast.frame = CGRectMake(CGRectGetMidX(body) - 80, body.origin.y + 12, 160, 28);
    [self layoutHead];
}

#pragma mark group tabs

/* a person is picked from the contacts and added at once; the member list under the tabs is read again when the server took them */
- (void)addMembers {
    ExteriaContactPickerController *picker = [[[ExteriaContactPickerController alloc] initWithSession:self.session avatars:self.avatars media:self.media] autorelease];
    ExteriaWeakReference *me = _weak;
    picker.pickHandler = ^(ExteriaDialog *user) {
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        [profile.navigationController popViewControllerAnimated:YES];
        [profile invite:user];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)invite:(ExteriaDialog *)user {
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session inviteUserDialog:user toDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        if (errorName) {
            NSLog(@"exteria: inviting %lld to channel %lld failed: %@", user.peerId, profile->_dialog.peerId, errorName);
            ExteriaGiftAlert(nil, ExteriaChannelErrorText(errorName));
            return;
        }
        [profile toast:NSLocalizedString(@"group.action.added", nil)];
        [profile load];
        [profile reloadGroupTabs];
    }];
}

- (void)reloadGroupTabs {
    [_groupTabs reloadMembers];
}

- (void)groupTabsDidResize:(ExteriaGroupTabsView *)tabs {
    (void)tabs;
    [self.view setNeedsLayout];
}

- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenPerson:(ExteriaPerson *)person {
    (void)tabs;
    if (!person) return;
    ExteriaUserProfileController *profile = [[[ExteriaUserProfileController alloc] initWithSession:self.session dialog:[ExteriaDialog dialogWithPerson:person]
                                                                                           avatars:self.avatars media:self.media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}

- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMessage:(ExteriaMessage *)message {
    (void)tabs;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:_dialog avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    chat.startMessageId = message.messageId;
    [self.navigationController pushViewController:chat animated:YES];
}

/* a picture or video of the media tab opens in the viewer, as in the chat itself, and not the chat at the place where it was sent */
- (void)groupTabs:(ExteriaGroupTabsView *)tabs didOpenMedia:(ExteriaMessage *)message among:(NSArray *)messages {
    (void)tabs;
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithMessages:messages selected:message media:self.media senderNames:nil
                                                                     chatTitle:_dialog.title] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark actions

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

- (void)toggleMute {
    if (!_full || _muteBusy) return;
    _muteBusy = YES;
    BOOL mute = !_full.muted;
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session performAction:mute ? ExteriaChatCommandMute : ExteriaChatCommandUnmute onDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        profile->_muteBusy = NO;
        if (errorName) {
            [profile toast:ExteriaGiftErrorText(errorName)];
            return;
        }
        /* the answer carries no new state, so the screen asks the server again for the full channel */
        [profile load];
    }];
}

- (void)join {
    if (!_full || _joinBusy) return;
    _joinBusy = YES;
    _joinAction.enabled = NO;
    ExteriaWeakReference *me = _weak;
    [self retain];
    [self.session joinChannelOfDialog:_dialog completion:^(NSString *errorName) {
        [self autorelease];
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        profile->_joinBusy = NO;
        profile->_joinAction.enabled = YES;
        if (errorName) {
            NSLog(@"exteria: joining channel %lld failed: %@", profile->_dialog.peerId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
        profile->_joined = YES;
        /* the answer carries no new state, so the screen asks the server again for the full channel */
        [profile load];
    }];
}

- (void)report {
    [ExteriaReportFlow startForDialog:_dialog session:self.session host:self done:nil];
}

/* a group has its chat to go to: the one this profile came from when that is right below, a new one otherwise */
- (void)openMessages {
    ExteriaProfileShowChat(self, self.session, _dialog, self.avatars, self.media, _stickers);
}

- (void)openDiscussion {
    ExteriaDialog *linked = _full.linked;
    if (!linked) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:linked avatars:self.avatars media:self.media
                                                                          stickers:_stickers] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)openQr {
    if (!_full.webLink.length) return;
    [self.navigationController pushViewController:[[[ExteriaProfileQrController alloc] initWithSession:self.session channel:_full avatars:self.avatars
                                                                                                  media:self.media] autorelease] animated:YES];
}

- (void)openManage {
    if (!_full.isAdmin) return;
    ExteriaChannelManageController *manage = [[[ExteriaChannelManageController alloc] initWithSession:self.session channel:_full avatars:self.avatars
                                                                                                media:self.media] autorelease];
    ExteriaWeakReference *me = _weak;
    manage.changedHandler = ^(ExteriaFullChannel *channel) {
        ExteriaChannelProfileController *profile = me.target;
        if (!profile) return;
        [profile->_full release];
        profile->_full = [channel retain];
        [profile showFull];
    };
    [self.navigationController pushViewController:manage animated:YES];
}

#pragma mark menu

typedef enum { ExteriaChannelMenuCopyLink, ExteriaChannelMenuManage, ExteriaChannelMenuDiscussion, ExteriaChannelMenuNotifications, ExteriaChannelMenuReport } ExteriaChannelMenuEntry;

- (void)refreshMenu {
    if (!_full) {
        [self setActionSymbol:ExteriaSymbolEllipsis label:nil handler:nil];
        return;
    }
    ExteriaWeakReference *me = _weak;
    [self setActionSymbol:ExteriaSymbolEllipsis label:NSLocalizedString(@"profile.more", nil)
                  handler:^{ [(ExteriaChannelProfileController *)me.target showMenu]; }];
}

- (void)showMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    ExteriaSymbol symbols[5];
    if (_full.webLink.length) {
        symbols[titles.count] = ExteriaSymbolLink;
        [titles addObject:NSLocalizedString(@"profile.qr.copy", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaChannelMenuCopyLink]];
    }
    if ([self isMember] && _full.isAdmin) {
        symbols[titles.count] = ExteriaSymbolGear;
        [titles addObject:NSLocalizedString(@"channel.action.manage", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaChannelMenuManage]];
    }
    if (_full.linked) {
        symbols[titles.count] = ExteriaSymbolChats;
        [titles addObject:NSLocalizedString(@"channel.menu.discussion", nil)];
        [entries addObject:[NSNumber numberWithInt:ExteriaChannelMenuDiscussion]];
    }
    symbols[titles.count] = ExteriaSymbolBell;
    [titles addObject:NSLocalizedString(@"notif.chat.header", nil)];
    [entries addObject:[NSNumber numberWithInt:ExteriaChannelMenuNotifications]];
    symbols[titles.count] = ExteriaSymbolReport;
    [titles addObject:NSLocalizedString(@"report.title", nil)];
    [entries addObject:[NSNumber numberWithInt:ExteriaChannelMenuReport]];
    ExteriaWeakReference *me = _weak;
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        ExteriaChannelProfileController *profile = me.target;
        if (!profile || index >= entries.count) return;
        switch ([[entries objectAtIndex:index] intValue]) {
        case ExteriaChannelMenuCopyLink: [profile copyLink]; break;
        case ExteriaChannelMenuManage: [profile openManage]; break;
        case ExteriaChannelMenuDiscussion: [profile openDiscussion]; break;
        case ExteriaChannelMenuNotifications:
            [profile.navigationController pushViewController:[[[ExteriaNotificationsChatController alloc] initWithSession:profile.session media:profile.media peerKind:profile->_dialog.peerKind
                                                                                                                  peerId:profile->_dialog.peerId peerHash:profile->_dialog.peerHash
                                                                                                                 channel:profile->_dialog.kind == EXTERIA_DIALOG_CHANNEL topic:0
                                                                                                                   title:profile->_dialog.title] autorelease] animated:YES];
            break;
        case ExteriaChannelMenuReport: [profile report]; break;
        }
    }] autorelease];
    [menu showInView:self.view anchor:[self actionSymbolAnchor]];
}

- (void)copyLink {
    if (!_full.webLink.length) return;
    [UIPasteboard generalPasteboard].string = _full.webLink;
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

@end
