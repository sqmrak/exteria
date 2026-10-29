#import "exteria_gift_detail_controller.h"
#import "exteria_emoji_label.h"
#import "exteria_chat_controller.h"
#import "exteria_group_call_engine.h"
#import "exteria_location_controller.h"
#import "exteria_status_label.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_chat_search.h"
#import "exteria_attach_flow.h"
#import "exteria_attach_sheet.h"
#import "exteria_avatar_view.h"
#import "exteria_story_ring.h"
#import "exteria_bar_button.h"
#import "exteria_chat_bots.h"
#import "exteria_chat_item.h"
#import "exteria_classic_chrome.h"
#import "exteria_connecting_label.h"
#import "exteria_custom_emoji_loader.h"
#import "exteria_developers.h"
#import "exteria_mini_player.h"
#import "exteria_next_chat_hint.h"
#import "exteria_topics_screen.h"
#import "exteria_name_badge.h"
#import "exteria_peer_colors.h"
#import "exteria_gift_catalog_controller.h"
#import "exteria_report_flow.h"
#import "exteria_compose_context.h"
#import "exteria_dialog_picker_controller.h"
#import "exteria_session_actions.h"
#import "exteria_settings_kit.h"
#import "exteria_session_sendas.h"
#import "exteria_sticker_maker.h"
#import "exteria_sheet.h"
#import "exteria_selection_bar.h"
#import "exteria_gallery_saver.h"
#import "exteria_bookmark_store.h"
#import "exteria_message_menu.h"
#import "exteria_sheet.h"
#import "exteria_bookmarks_controller.h"
#include "exteria_message_actions.h"
#import "exteria_gift_screen.h"
#import "exteria_gifts_controller.h"
#import "exteria_channel_profile_controller.h"
#import "exteria_plural.h"
#import "exteria_greeting_view.h"
#import "exteria_premium_gate_view.h"
#import "exteria_session_channels.h"
#import "exteria_user_profile_controller.h"
#import "exteria_input_bar.h"
#import "exteria_link_router.h"
#import "exteria_input_panel.h"
#import "exteria_sticker_pack_sheet.h"
#import "exteria_media_viewer.h"
#import "exteria_message_cell.h"
#import "exteria_chat_settings.h"
#import "exteria_music_player.h"
#import "exteria_voice.h"
#import "exteria_proximity.h"
#import "exteria_popup_menu.h"
#import "exteria_session_profile.h"
#import "exteria_reaction_picker.h"
#import "exteria_reaction_people_controller.h"
#import "exteria_round_recorder.h"
#import "exteria_voice_recorder.h"
#import "exteria_person.h"
#import "exteria_message_report_flow.h"
#import "exteria_app_sounds.h"
#import "exteria_notifications_chat_controller.h"
#import "exteria_notifier.h"
#import "exteria_platform.h"
#import "exteria_session_stickermanage.h"
#import "exteria_split_controller.h"
#import "exteria_theme.h"
#import "exteria_language.h"
#import "exteria_lite_mode.h"
#import "exteria_animation.h"
#import "exteria_draft.h"
#import "exteria_dust_effect.h"
#import "exteria_session_drafts.h"
#import "exteria_translate_config.h"
#import "exteria_translate_sheet.h"
#import "exteria_translator.h"
#import "exteria_ayu.h"
#import "exteria_edit_history_controller.h"
#import "exteria_session_saved.h"
#import "exteria_falling_view.h"
#import "exteria_wallpaper.h"
#import "exteria_wallpaper_controller.h"
#import "exteria_time.h"
#include "exteria_scroll.h"
#import "exteria_weak_reference.h"
#import "exteria_saved_media_controller.h"

#define BAR_HEIGHT 44.0
#define PINNED_HEIGHT 46.0
#define VOICE_HEIGHT 44.0
/* the pages of older history a tap on the pinned message will fetch looking for it */
#define PINNED_SEARCH_PAGES 12
#define HISTORY_PAGE 40
/* rows below or above the fold whose pictures are fetched ahead, nearest first */
static NSString *ExteriaMessageSummary(ExteriaMessage *message);

#define PREPARE_ROWS_MAX 6
/* more stickers than ExteriaLiteStickerLimit playing at once would starve the main thread of an old device */
#define ANIMATED_STICKERS_MAX ExteriaLiteStickerLimit()
/* a deletion or a new message of more rows than this is a reload of the chat, not an event worth an effect */
#define DUST_ROWS_MAX 4
#define ENTER_ROWS_MAX 3
/* rows one change may tell the table about row by row; more than this is one reload */
#define BULK_ROWS_MAX 40
#define GROUP_GAP_SECONDS 300

@interface ExteriaChatController (ReactionPolling)
- (void)pollReactions;
- (void)flushLiveMessages;
- (void)advanceBottom:(CADisplayLink *)link;
@end

/* NSTimer retains its target, the weak bridge lets a removed chat release its timer */
@interface ExteriaReactionPollTarget : NSObject {
    ExteriaWeakReference *_weak;
}
- (id)initWithReference:(ExteriaWeakReference *)weak;
- (void)fire:(NSTimer *)timer;
@end

@implementation ExteriaReactionPollTarget
- (id)initWithReference:(ExteriaWeakReference *)weak {
    self = [super init];
    if (self) _weak = [weak retain];
    return self;
}
- (void)dealloc { [_weak release]; [super dealloc]; }
- (void)fire:(NSTimer *)timer { (void)timer; [(ExteriaChatController *)_weak.target pollReactions]; }
- (void)display:(CADisplayLink *)link { (void)link; [(ExteriaChatController *)_weak.target flushLiveMessages]; }
- (void)follow:(CADisplayLink *)link { [(ExteriaChatController *)_weak.target advanceBottom:link]; }
- (void)jump:(CADisplayLink *)link { [(ExteriaChatController *)_weak.target advanceJump:link]; }
@end

@interface ExteriaReaderRowView : UIView {
    ExteriaAvatarView *_avatar;
    ExteriaEmojiLabel *_name;
    ExteriaEmojiLabel *_time;
    ExteriaPerson *_person;
    ExteriaAvatarCache *_cache;
}
- (id)initWithPerson:(ExteriaPerson *)person userId:(long long)userId name:(NSString *)name time:(NSString *)time cache:(ExteriaAvatarCache *)cache;
@end

@implementation ExteriaReaderRowView
- (id)initWithPerson:(ExteriaPerson *)person userId:(long long)userId name:(NSString *)name time:(NSString *)time cache:(ExteriaAvatarCache *)cache {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _person = [person retain];
    _cache = [cache retain];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.seed = (NSUInteger)(userId % 1000003);
    _avatar.initials = person ? person.initials : ExteriaInitialsOfName(name);
    _avatar.deleted = person.deleted;
    [self addSubview:_avatar];
    _name = [[ExteriaEmojiLabel alloc] init];
    _name.font = ExteriaFontSemibold(16);
    _name.textColor = ExteriaColorTitle();
    _name.dropsUndrawable = YES;
    _name.text = name;
    [self addSubview:_name];
    _time = [[ExteriaEmojiLabel alloc] init];
    _time.font = ExteriaFontRegular(14);
    _time.textColor = ExteriaColorSecondary();
    _time.text = time;
    [self addSubview:_time];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, time];
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [_avatar setPhoto:_person.photo cache:_cache];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _avatar.frame = CGRectMake(12, 10, 44, 44);
    _name.frame = CGRectMake(68, 8, MAX(0, self.bounds.size.width - 80), 24);
    _time.frame = CGRectMake(68, 32, MAX(0, self.bounds.size.width - 80), 22);
}
- (void)dealloc {
    [_avatar release];
    [_name release];
    [_time release];
    [_person release];
    [_cache release];
    [super dealloc];
}
@end

@interface ExteriaChatController () <UITableViewDataSource, UITableViewDelegate, ExteriaInputBarDelegate, ExteriaInputPanelDelegate, ExteriaAttachSheetDelegate,
                                      ExteriaMessageCellDelegate, UIAlertViewDelegate, ExteriaChatBotsHost, UIDocumentInteractionControllerDelegate> {
    UIDocumentInteractionController *_document;
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;

    UIImageView *_wallpaper;
    ExteriaMiniPlayer *_miniPlayer;
    ExteriaFallingView *_snow;
    ExteriaFallingView *_foxes;
    UITableView *_table;
    BOOL _premium;
    BOOL _premiumKnown;
    /* this account as a person, asked for once when a chip first needs its picture */
    ExteriaPerson *_selfPerson;
    BOOL _selfPersonAsked;
    /* the id of this account, read from its file once */
    NSNumber *_accountId;
    UIView *_header;
    UIView *_headerLine;
    ExteriaBarButton *_back;
    ExteriaAvatarView *_avatar;
    /* the arcs of the stories of the person, round the picture of the bar; hidden while there are none */
    ExteriaStoryRing *_storyRing;
    ExteriaEmojiLabel *_title;
    ExteriaStatusLabel *_subtitle;
    ExteriaInputBar *_input;
    ExteriaInputPanel *_panel;
    UILabel *_status;
    UIButton *_retry;

    /* what the server said, by message id, and what only this screen knows yet */
    NSMutableDictionary *_server;
    NSMutableArray *_local;
    NSMutableDictionary *_people;
    NSDictionary *_senderRoles;
    NSArray *_items;
    NSMutableDictionary *_itemCache;
    NSCache *_replyCache;
    BOOL _loadingReplies;
    BOOL _openingComments;
    NSUInteger _replyGeneration;
    int32_t _oldestId;
    /* the ids the store page held the last time it arrived, so what it stops holding can be told from what it never held */
    NSMutableSet *_storeIds;
    NSMutableSet *_confirmingGone;
    NSMutableSet *_sharingBusy;
    int32_t _sharingPeriod;
    int64_t _sharingOffsetMilliseconds;
    BOOL _canLoadMore;
    BOOL _loadingOlder;
    /* a page of older history arrived while the list was moving, and waits for it to stop */
    BOOL _olderDeferred;
    exteria_scroll_state _scroll;
    BOOL _scrollTargetKnown;
    CGFloat _scrollTargetOffset;
    CGFloat _preparedOffset;
    BOOL _interacting;
    BOOL _updatingItems;
    BOOL _layingOutChat;
    BOOL _followingBottom;
    BOOL _livePending;
    /* the list shows a stretch of old history opened around a message, so its end is not the newest message of the chat */
    BOOL _window;
    BOOL _loadingWindow;
    BOOL _loadingNewer;
    BOOL _canLoadNewer;
    BOOL _rebuildNow;
    NSUInteger _windowToken;
    CADisplayLink *_liveLink;
    CADisplayLink *_followLink;
    /* the quick scroll to a message that was asked for (a reply, a search result, a pinned message, a bookmark): its own frame clock, so the rows load as it moves */
    CADisplayLink *_jumpLink;
    CFTimeInterval _jumpBegan;
    CFTimeInterval _jumpLength;
    CGFloat _jumpFrom;
    CGFloat _jumpTo;
    int32_t _jumpMessageId;
    CFTimeInterval _followTime;
    CFTimeInterval _followBegan;
    BOOL _loadedFirst;
    /* what the chat had read when it was opened, or -1 when it had nothing unread: the line of unread messages stays where it was while they are read */
    int32_t _unreadAnchor;
    BOOL _loading;
    int32_t _markedRead;
    NSMutableSet *_readMentionIds;
    /* ids of the one-time messages opened on this phone, which read as expired at once, before the server's edit of the message comes */
    NSMutableSet *_openedOnce;
    /* the "1" chip of the input bar as it stood when the recording that is being finished ended */
    BOOL _recordingOneTime;
    /* the one-time voice note that plays now: the track, the message, and whether the server was told yet */
    ExteriaMedia *_onceVoice;
    int32_t _onceVoiceId;
    BOOL _onceVoiceOpened;
    BOOL _stickToBottom;
    /* the chat is still settling on its newest message: the kept page and the first fresh page land without a scroll animation, so the list never visibly travels */
    BOOL _opening;
    BOOL _panelShown;
    CGFloat _keyboardOverlap;
    CGFloat _laidOutWidth;
    BOOL _observing;
    BOOL _visible;
    BOOL _pollingReactions;
    BOOL _pollingPolls;
    NSMutableSet *_votingPolls;
    NSTimer *_reactionTimer;
    /* the first and last row on screen when the stickers were last given their turn to run, -2 before the first time */
    NSInteger _animatedFirst;
    NSInteger _animatedLast;
    ExteriaReactionPicker *_reactionPicker;
    int32_t _reactionMessageId;
    NSUInteger _reactionPickerToken;
    NSMutableSet *_reactionSending;
    ExteriaVoiceRecorder *_voice;
    ExteriaRoundRecorder *_roundRecorder;
    /* the phone is watched for the ear, and a voice message is being recorded because it came there */
    BOOL _raiseWatching;
    BOOL _raiseRecording;
    UIView *_roundPreview;
    UIButton *_roundTorch;
    BOOL _roundTorchBusy;
    UILabel *_roundZoomLabel;
    CGFloat _roundZoomStart;
    BOOL _roundFlipping;
    UIView *_roundShade;
    NSTimer *_recordTimer;
    ExteriaAttachFlow *_attach;
    ExteriaFullChannel *_channelFull;
    UIControl *_pinnedBar;
    UIControl *_voiceBar;
    UILabel *_voiceTitle, *_voiceInfo, *_voiceJoin;
    ExteriaVoiceChat *_voiceChat;
    NSUInteger _voiceToken;
    UILabel *_pinnedTitle;
    ExteriaEmojiLabel *_pinnedText;
    int32_t _pinnedId;
    NSUInteger _topicPinnedGeneration;
    int32_t _scrollTarget;
    int _scrollPages;
    UILabel *_toast;
    UIButton *_toEnd;
    /* the heart over the way down: the messages that got a reaction not seen yet, oldest last, and the count on its corner */
    UIButton *_reactionJump;
    UILabel *_reactionBadge;
    NSMutableArray *_unreadReactionIds;
    ExteriaNextChatHint *_nextHint;
    ExteriaDialog *_nextDialog;
    BOOL _toEndShown;
    UIButton *_menuButton;
    UIButton *_callButton;
    ExteriaGreetingView *_greeting;
    ExteriaPremiumGateView *_premiumGate;
    BOOL _greetingAsked;
    BOOL _joinPending;
    BOOL _membershipAsked;
    BOOL _joining;
    ExteriaComposeContext *_context;
    int32_t _replyToId;
    int32_t _editingId;
    int32_t _deleteId;
    BOOL _editBusy;
    ExteriaSelectionBar *_selectionBar;
    NSMutableSet *_selectedIds;
    BOOL _selecting;
    BOOL _inputHiddenBeforeSelection;
    BOOL _pinnedList;
    NSInteger _pinnedCount;
    UIImageView *_pinnedThumb;
    UIButton *_pinnedListButton;
    NSUInteger _pinnedThumbToken;
    ExteriaLinkRouter *_router;
    ExteriaChatBots *_bots;
    NSString *_draftText;
    /* what the field held before a message was opened for editing, which the field gets back when the edit ends */
    ExteriaDraft *_stashedDraft;
    /* the field was filled from the draft of the account, so what it holds now is the person's word and may be saved */
    BOOL _draftsActive;
    BOOL _applyingDraft;
    /* the keyboard is sliding, so the list and the field move together and nothing else may change the rows or the offset until it stops */
    BOOL _keyboardMoving;
    /* the message a draft answers while it is fetched, so a save in between keeps it */
    int32_t _pendingDraftReply;
    NSString *_startParam;
    NSString *_searchQuery;
    /* the search of the modern style, which stays on the chat itself: the bar over the header, the strip over the keyboard, and the matches newest first */
    ExteriaChatSearchBar *_searchBar;
    ExteriaChatSearchNav *_searchNav;
    NSArray *_searchHits;
    NSUInteger _searchPosition;
    NSUInteger _searchToken;
    ExteriaPerson *_historyPerson;
    int32_t _startMessageId;
    NSArray *_menuReactions;
    BOOL _menuReactionsLoading;
    /* the identities the account may write as in this supergroup, once the server listed more than itself */
    NSArray *_sendAsOptions;
    BOOL _sendAsRequested;
    /* the identity the person picked on this screen, which outranks what the full channel said before the pick (that answer does not change) */
    ExteriaSendAsOption *_sendAsPicked;
    NSMutableDictionary *_transcripts;
    /* the reactors already asked for through the message of their reaction, so a user is asked for once per screen */
    NSMutableSet *_reactorLookups;
    /* the full users they came back as; a later history answer carries the min object again and must not take their photo away */
    NSMutableDictionary *_reactorPeople;
}
@end

@implementation ExteriaChatController

@synthesize closeHandler = _closeHandler;
@synthesize nextChatProvider = _nextChatProvider;
@synthesize pinnedList = _pinnedList;
@synthesize searchQuery = _searchQuery;
@synthesize historyPerson = _historyPerson;
@synthesize startMessageId = _startMessageId;
@synthesize draftText = _draftText;
@synthesize startParam = _startParam;

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _animatedFirst = _animatedLast = -2;
    _sharingPeriod = EXTERIA_SHARING_PERIOD_DEFAULT;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _server = [[NSMutableDictionary alloc] init];
    _local = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    [_people setObject:[self chatAsPerson] forKey:[NSNumber numberWithLongLong:0]];
    _items = [[NSArray alloc] init];
    _itemCache = [[NSMutableDictionary alloc] init];
    _replyCache = [[NSCache alloc] init];
    _replyCache.countLimit = 200;
    _reactionSending = [[NSMutableSet alloc] init];
    _readMentionIds = [[NSMutableSet alloc] init];
    _openedOnce = [[NSMutableSet alloc] init];
    _stickToBottom = YES;
    _opening = YES;
    _unreadAnchor = dialog.unreadCount > 0 ? dialog.readInboxMaxId : -1;
    _router = [[ExteriaLinkRouter alloc] initWithSession:session avatars:avatars media:media stickers:stickers];
    _router.anchor = self;
    _bots = [[ExteriaChatBots alloc] initWithSession:session dialog:dialog router:_router media:media host:self];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    [self stopFollowingBottom];
    [_liveLink invalidate];
    [_liveLink release];
    _document.delegate = nil;
    [_document release];
    _router.anchor = nil;
    _bots.host = nil;
    [_bots teardown];
    [_bots release];
    [_router release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    [_searchBar release];
    [_searchNav release];
    [_searchHits release];
    [_searchQuery release];
    [_historyPerson release];
    [_transcripts release];
    [_reactorLookups release];
    [_reactorPeople release];
    [_menuReactions release];
    [_sendAsOptions release];
    [_sendAsPicked release];
    [_votingPolls release];
    [_draftText release];
    [_stashedDraft release];
    [_startParam release];
    [_attach cancel];
    [_attach release];
    [self stopRaiseToSpeak];
    [self discardRecording];
    [_reactionTimer invalidate];
    [_reactionTimer release];
    [_reactionPicker release];
    [_reactionSending release];
    [_weak clear];
    [_weak release];
    [_session stopWatchingForOwner:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    _input.delegate = nil;
    _panel.delegate = nil;
    [_closeHandler release];
    [_nextChatProvider release];
    [_nextHint release];
    [_nextDialog release];
    [_storeIds release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_snow stop];
    [_foxes stop];
    [_snow release];
    [_foxes release];
    _miniPlayer.changeHandler = nil;
    [_miniPlayer release];
    [_toEnd release];
    [_reactionJump release];
    [_reactionBadge release];
    [_unreadReactionIds release];
    [_wallpaper release];
    [_table release];
    [_header release];
    [_headerLine release];
    [_back release];
    [_avatar release];
    [_storyRing release];
    [_title release];
    [_subtitle release];
    [_input release];
    [_panel release];
    [_status release];
    [_channelFull release];
    [_context release];
    [_selectionBar release];
    [_selectedIds release];
    [_pinnedBar release];
    [_voiceBar release];
    [_voiceTitle release];
    [_voiceInfo release];
    [_voiceJoin release];
    [_voiceChat release];
    [_pinnedTitle release];
    [_pinnedText release];
    [_confirmingGone release];
    [_sharingBusy release];
    [_toast release];
    [_menuButton release];
    [_callButton release];
    [_greeting release];
    [_premiumGate release];
    [_pinnedThumb release];
    [_pinnedListButton release];
    [_retry release];
    [_server release];
    [_local release];
    [_people release];
    [_selfPerson release];
    [_accountId release];
    [_senderRoles release];
    [_items release];
    [_replyCache release];
    [_readMentionIds release];
    [_openedOnce release];
    [_onceVoice release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markVisibleMentionsRead) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadReplyPreviews) object:nil];
    [_itemCache release];
    [super dealloc];
}

#pragma mark views

static UILabel *ExteriaChatLabel(UIColor *color, NSInteger alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = alignment;
    return label;
}

/* what the other side is doing in the chat, in words, or nil when nothing */
- (NSString *)typingText {
    if (_dialog.saved || _pinnedList) return nil;
    NSUInteger count = [_session.typing countInDialog:_dialog];
    int action = [_session.typing actionInDialog:_dialog];
    /* a private chat is the person itself; a group names who writes */
    if (_dialog.peerKind == 1) return ExteriaTypingStatusText(action, count);
    return ExteriaTypingStatusTextNamed(action, count, [_session.typing namesInDialog:_dialog]);
}

- (ExteriaStatusKind)statusKind {
    if (_dialog.peerKind == 1 && _dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID) return ExteriaStatusPlain;
    if (!_session.connected) return ExteriaStatusPlain;
    if ([self typingText]) return ExteriaStatusTyping;
    return _dialog.kind == EXTERIA_DIALOG_USER && !_dialog.saved && _dialog.presence == EXTERIA_PRESENCE_ONLINE ? ExteriaStatusOnline : ExteriaStatusPlain;
}

- (NSString *)statusLine {
    if (_dialog.peerKind == 1 && _dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID) return NSLocalizedString(@"chat.status.telegram", nil);
    /* a last seen time read off a dead link is stale, so the original client shows the connecting state instead */
    if (!_session.connected) return ExteriaConnectingText(3);
    NSString *typing = [self typingText];
    if (typing) return typing;
    /* a channel or a group says how many follow it once the full channel is in; until then it names its kind */
    if (_channelFull.participants > 0 && (_dialog.kind == EXTERIA_DIALOG_CHANNEL || _dialog.kind == EXTERIA_DIALOG_GROUP)) {
        NSString *noun = _dialog.kind == EXTERIA_DIALOG_CHANNEL ? @"chat.subscribers." : @"chat.members.";
        return [NSString stringWithFormat:NSLocalizedString([noun stringByAppendingString:ExteriaPluralForm(_channelFull.participants)], nil), (long)_channelFull.participants];
    }
    switch (_dialog.kind) {
    case EXTERIA_DIALOG_USER: return _dialog.saved ? @"" : ExteriaLastSeenText(_dialog.presence, _dialog.seen);
    case EXTERIA_DIALOG_BOT: return NSLocalizedString(@"chat.status.bot", nil);
    case EXTERIA_DIALOG_GROUP: return NSLocalizedString(@"chat.status.group", nil);
    case EXTERIA_DIALOG_CHANNEL: return NSLocalizedString(@"chat.status.channel", nil);
    }
    return @"";
}

/* the status line follows the typing of this chat only */
- (void)typingChanged:(NSNotification *)note {
    if (ExteriaTypingChangeConcerns(note, _dialog)) [self refreshStatusLine];
}

- (void)refreshStatusLine {
    if (_pinnedList) return;
    NSString *line = [self statusLine];
    if (_subtitle) {
        [_subtitle setStatus:line kind:[self statusKind]];
        [self.view setNeedsLayout];
    } else if (ExteriaThemeIsClassic() && [self isViewLoaded]) {
        self.navigationItem.titleView = ExteriaClassicTitleViewWithStatus(_dialog.title, line, (int)[self statusKind]);
        self.navigationItem.titleView.userInteractionEnabled = YES;
        [self.navigationItem.titleView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
    }
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    BOOL classic = ExteriaThemeIsClassic();
    _wallpaper = [[UIImageView alloc] init];
    ExteriaApplyChatWallpaper(_wallpaper, ExteriaThemeIsDark());
    [root addSubview:_wallpaper];
    /* the song that plays follows the person into the chat, with the buttons to change it; the strip has no height while nothing plays */
    _miniPlayer = [[ExteriaMiniPlayer alloc] init];
    ExteriaWeakReference *playerWeak = _weak;
    _miniPlayer.changeHandler = ^{ [[(ExteriaChatController *)playerWeak.target view] setNeedsLayout]; };
    [root addSubview:_miniPlayer];
    if (ExteriaChatFlagGet(ExteriaChatFlagSnow)) {
        /* the snow falls over the background and under the messages */
        _snow = [[ExteriaFallingView alloc] initWithFrame:root.bounds];
        [root addSubview:_snow];
    }

    if (ExteriaChatFlagGet(ExteriaChatFlagFoxes)) {
        _foxes = [[ExteriaFallingView alloc] initWithFrame:root.bounds spriteNamed:@"senko-fall"];
        [root insertSubview:_foxes belowSubview:_miniPlayer];
    }

    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_table);
    ExteriaTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.allowsSelection = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.hidden = YES;
    [root addSubview:_table];
    /* a tap on the empty part of the list puts the keyboard or the panel away */
    UITapGestureRecognizer *dismiss = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissInput)] autorelease];
    dismiss.cancelsTouchesInView = NO;
    [_table addGestureRecognizer:dismiss];

    _status = ExteriaChatLabel(ExteriaColorSecondary(), ExteriaTextAlignmentCenter);
    _status.numberOfLines = 0;
    _status.hidden = YES;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(loadNewest) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];

    _input = [[ExteriaInputBar alloc] init];
    _input.session = _session;
    _input.formatHost = root;
    _joinPending = _dialog.peerKind == 3 && _dialog.left && !_pinnedList;
    _input.actionWithInput = _joinPending && _dialog.kind == EXTERIA_DIALOG_GROUP;
    if (_joinPending) _input.actionTitle = NSLocalizedString(@"chat.join", nil);
    _input.delegate = self;
    if (_dialog.kind == EXTERIA_DIALOG_CHANNEL && !_dialog.canPost) {
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.readonly", nil);
    } else if (_dialog.savedSource && !_dialog.savedSource.saved) {
        /* a message written here would be the account's own note, not one from the chat the list is narrowed to */
        _input.writable = NO;
        _input.readOnlyNote = NSLocalizedString(@"chat.saved.readonly", nil);
    }
    [root addSubview:_input];
    _context = [[ExteriaComposeContext alloc] init];
    _context.hidden = YES;
    ExteriaWeakReference *contextWeak = _weak;
    _context.closeHandler = ^{ [(ExteriaChatController *)contextWeak.target cancelCompose]; };
    [root addSubview:_context];
    _selectionBar = [[ExteriaSelectionBar alloc] init];
    _selectionBar.hidden = YES;
    ExteriaWeakReference *barWeak = _weak;
    _selectionBar.cancelHandler = ^{ [(ExteriaChatController *)barWeak.target endSelection]; };
    _selectionBar.forwardHandler = ^{ [(ExteriaChatController *)barWeak.target forwardSelected]; };
    _selectionBar.copyHandler = ^{ [(ExteriaChatController *)barWeak.target copySelected]; };
    _selectionBar.deleteHandler = ^{ [(ExteriaChatController *)barWeak.target askDeleteSelected]; };
    _selectionBar.rangeHandler = ^{ [(ExteriaChatController *)barWeak.target selectBetween]; };
    [root addSubview:_selectionBar];
    /* the pinned message of a channel stands under the header, over the list */
    _pinnedBar = [[UIControl alloc] init];
    _pinnedBar.backgroundColor = ExteriaColorBar();
    _pinnedBar.hidden = YES;
    [_pinnedBar addTarget:self action:@selector(pinnedTapped) forControlEvents:UIControlEventTouchUpInside];
    UIView *stripe = [[[UIView alloc] initWithFrame:CGRectMake(12, 7, 2, PINNED_HEIGHT - 14)] autorelease];
    stripe.backgroundColor = ExteriaColorAccent();
    stripe.userInteractionEnabled = NO;
    [_pinnedBar addSubview:stripe];
    _pinnedTitle = ExteriaChatLabel(ExteriaColorAccent(), ExteriaTextAlignmentLeft);
    _pinnedTitle.text = NSLocalizedString(@"chat.pinned", nil);
    _pinnedTitle.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedTitle];
    /* the pinned message is somebody's text, so its emoji come from the app's pictures */
    _pinnedText = [[ExteriaEmojiLabel alloc] init];
    _pinnedText.textColor = ExteriaColorTitle();
    _pinnedText.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedText];
    /* a photo or video shows as a small rounded square at the left, and a chat with several pinned messages gets the list button */
    _pinnedThumb = [[UIImageView alloc] init];
    _pinnedThumb.contentMode = UIViewContentModeScaleAspectFill;
    _pinnedThumb.clipsToBounds = YES;
    _pinnedThumb.layer.cornerRadius = 6;
    _pinnedThumb.hidden = YES;
    _pinnedThumb.userInteractionEnabled = NO;
    [_pinnedBar addSubview:_pinnedThumb];
    _pinnedListButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_pinnedListButton setImage:ExteriaSymbolImage(ExteriaSymbolPinnedList, 22, ExteriaColorSecondary()) forState:UIControlStateNormal];
    [_pinnedListButton addTarget:self action:@selector(openPinnedList) forControlEvents:UIControlEventTouchUpInside];
    _pinnedListButton.accessibilityLabel = NSLocalizedString(@"chat.pinned.all", nil);
    _pinnedListButton.hidden = YES;
    [_pinnedBar addSubview:_pinnedListButton];
    [root addSubview:_pinnedBar];
    /* the voice chat that runs in a group or channel: a bar under the pinned message with who is in it and the way to join */
    _voiceBar = [[UIControl alloc] init];
    _voiceBar.backgroundColor = ExteriaColorBar();
    _voiceBar.hidden = YES;
    [_voiceBar addTarget:self action:@selector(openVoiceChat) forControlEvents:UIControlEventTouchUpInside];
    _voiceTitle = ExteriaChatLabel(ExteriaColorTitle(), ExteriaTextAlignmentLeft);
    _voiceTitle.text = NSLocalizedString(@"chat.voice.title", nil);
    _voiceTitle.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceTitle];
    _voiceInfo = ExteriaChatLabel(ExteriaColorSecondary(), ExteriaTextAlignmentLeft);
    _voiceInfo.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceInfo];
    _voiceJoin = ExteriaChatLabel([UIColor whiteColor], ExteriaTextAlignmentCenter);
    _voiceJoin.backgroundColor = ExteriaColorAccent();
    _voiceJoin.layer.cornerRadius = 14;
    _voiceJoin.layer.masksToBounds = YES;
    _voiceJoin.text = NSLocalizedString(@"chat.voice.join", nil);
    _voiceJoin.userInteractionEnabled = NO;
    [_voiceBar addSubview:_voiceJoin];
    [root addSubview:_voiceBar];
    _toast = ExteriaChatLabel([UIColor whiteColor], ExteriaTextAlignmentCenter);
    _toast.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _toast.layer.cornerRadius = 14;
    _toast.layer.masksToBounds = YES;
    _toast.alpha = 0;
    [root addSubview:_toast];
    /* the way back to the newest message, which shows once the list is more than a screen above its end */
    _toEnd = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _toEnd.backgroundColor = ExteriaColorCard();
    _toEnd.layer.cornerRadius = 22;
    _toEnd.layer.shadowColor = [UIColor blackColor].CGColor;
    _toEnd.layer.shadowOpacity = 0.25f;
    _toEnd.layer.shadowRadius = 5;
    _toEnd.layer.shadowOffset = CGSizeMake(0, 2);
    [_toEnd setImage:ExteriaSymbolImage(ExteriaSymbolArrowDown, 20, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_toEnd addTarget:self action:@selector(toEndTapped) forControlEvents:UIControlEventTouchUpInside];
    _toEnd.accessibilityLabel = NSLocalizedString(@"chat.toend", nil);
    _toEnd.alpha = 0;
    _toEnd.hidden = YES;
    [root addSubview:_toEnd];
    _reactionJump = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _reactionJump.layer.cornerRadius = 22;
    if (classic) {
        /* the classic style draws its buttons as a lit red dome, clipped to the circle */
        _reactionJump.layer.masksToBounds = YES;
        [_reactionJump setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossRed, NO) forState:UIControlStateNormal];
        [_reactionJump setBackgroundImage:ExteriaClassicGlossButtonImage(ExteriaClassicGlossRed, YES) forState:UIControlStateHighlighted];
        [_reactionJump setImage:ExteriaSymbolImage(ExteriaSymbolHeart, 20, [UIColor whiteColor]) forState:UIControlStateNormal];
    } else {
        _reactionJump.backgroundColor = ExteriaColorCard();
        _reactionJump.layer.shadowColor = [UIColor blackColor].CGColor;
        _reactionJump.layer.shadowOpacity = 0.25f;
        _reactionJump.layer.shadowRadius = 5;
        _reactionJump.layer.shadowOffset = CGSizeMake(0, 2);
        [_reactionJump setImage:ExteriaSymbolImage(ExteriaSymbolHeartOutline, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
    }
    [_reactionJump addTarget:self action:@selector(reactionJumpTapped) forControlEvents:UIControlEventTouchUpInside];
    _reactionJump.accessibilityLabel = NSLocalizedString(@"chat.reactions.jump", nil);
    _reactionJump.hidden = YES;
    [root addSubview:_reactionJump];
    _reactionBadge = [[UILabel alloc] init];
    _reactionBadge.font = ExteriaFontSemibold(12);
    _reactionBadge.textColor = [UIColor whiteColor];
    _reactionBadge.textAlignment = ExteriaTextAlignmentCenter;
    _reactionBadge.backgroundColor = classic ? [UIColor colorWithRed:0.20 green:0.50 blue:0.92 alpha:1] : ExteriaColorAccent();
    _reactionBadge.layer.cornerRadius = 11;
    _reactionBadge.layer.masksToBounds = YES;
    _reactionBadge.userInteractionEnabled = NO;
    _reactionBadge.hidden = YES;
    [root addSubview:_reactionBadge];
    [self loadUnreadReactions];
    _nextHint = [[ExteriaNextChatHint alloc] init];
    [root addSubview:_nextHint];

    if (classic && _pinnedList) {
        self.title = NSLocalizedString(@"chat.pinned.list", nil);
        _input.hidden = YES;
        return;
    }
    if (classic) {
        /* the system's navigation bar carries the name and the status, the person's picture and the back button */
        self.navigationItem.titleView = ExteriaClassicTitleViewWithStatus(_dialog.title, [self statusLine], (int)[self statusKind]);
        self.navigationItem.titleView.userInteractionEnabled = YES;
        [self.navigationItem.titleView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
        ExteriaAvatarView *mini = [[[ExteriaAvatarView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)] autorelease];
        mini.seed = _dialog.avatarSeed;
        mini.initials = _dialog.initials;
        mini.deleted = _dialog.deleted;
        mini.accent = _dialog.saved;
        mini.showsSymbol = _dialog.saved;
        mini.symbol = ExteriaSymbolBookmark;
        mini.circular = YES;
        [mini setPhoto:_dialog.saved ? nil : _dialog.photo cache:_avatars];
        mini.userInteractionEnabled = YES;
        [mini addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
        /* the ring stands in the bar item, which is a little wider than the picture, so the bar does not clip it */
        CGFloat outset = 3;
        UIView *avatarBox = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 32 + 2 * outset, 32 + 2 * outset)] autorelease];
        _storyRing = [[ExteriaStoryRing alloc] initWithFrame:avatarBox.bounds];
        _storyRing.hidden = YES;
        [avatarBox addSubview:_storyRing];
        mini.frame = CGRectMake(outset, outset, 32, 32);
        [avatarBox addSubview:mini];
        UIBarButtonItem *avatarItem = [[[UIBarButtonItem alloc] initWithCustomView:avatarBox] autorelease];
        UIBarButtonItem *dotsItem = [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 22, [UIColor whiteColor])
                                                                       style:UIBarButtonItemStyleBordered target:self action:@selector(showChatMenu)] autorelease];
        dotsItem.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
        if ([self canCall]) {
            UIBarButtonItem *callItem = [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolPhone, 22, [UIColor whiteColor])
                                                                          style:UIBarButtonItemStyleBordered target:self action:@selector(startCall)] autorelease];
            callItem.accessibilityLabel = NSLocalizedString(@"call.start", nil);
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:dotsItem, callItem, avatarItem, nil];
        } else {
            self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:dotsItem, avatarItem, nil];
        }
        return;
    }
    _header = [[UIView alloc] init];
    _header.backgroundColor = ExteriaColorBar();
    [root addSubview:_header];
    _headerLine = [[UIView alloc] init];
    _headerLine.backgroundColor = ExteriaColorHairline();
    [_header addSubview:_headerLine];
    _back = [[ExteriaBarButton alloc] init];
    _back.chevron = YES;
    _back.title = @"";
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_header addSubview:_back];
    _storyRing = [[ExteriaStoryRing alloc] init];
    _storyRing.hidden = YES;
    [_header addSubview:_storyRing];
    _avatar = [[ExteriaAvatarView alloc] init];
    _avatar.seed = _dialog.avatarSeed;
    _avatar.initials = _dialog.initials;
    _avatar.deleted = _dialog.deleted;
    _avatar.accent = _dialog.saved;
    _avatar.showsSymbol = _dialog.saved;
    _avatar.symbol = ExteriaSymbolBookmark;
    _avatar.circular = YES;
    [_avatar setPhoto:_dialog.saved ? nil : _dialog.photo cache:_avatars];
    _avatar.userInteractionEnabled = YES;
    [_avatar addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
    [_header addSubview:_avatar];
    _title = [[ExteriaEmojiLabel alloc] init];
    _title.textColor = ExteriaColorTitle();
    _title.dropsUndrawable = YES;
    [self showTitleBadge];
    [_header addSubview:_title];
    _subtitle = [[ExteriaStatusLabel alloc] init];
    _subtitle.backgroundColor = [UIColor clearColor];
    _subtitle.textAlignment = ExteriaTextAlignmentLeft;
    [_subtitle setStatus:[self statusLine] kind:[self statusKind]];
    [_header addSubview:_subtitle];
    _menuButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_menuButton setImage:ExteriaSymbolImage(ExteriaSymbolEllipsisVertical, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
    [_menuButton addTarget:self action:@selector(showChatMenu) forControlEvents:UIControlEventTouchUpInside];
    _menuButton.accessibilityLabel = NSLocalizedString(@"profile.more", nil);
    [_header addSubview:_menuButton];
    if ([self canCall]) {
        _callButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        [_callButton setImage:ExteriaSymbolImage(ExteriaSymbolPhone, 22, ExteriaColorTitle()) forState:UIControlStateNormal];
        [_callButton addTarget:self action:@selector(startCall) forControlEvents:UIControlEventTouchUpInside];
        _callButton.accessibilityLabel = NSLocalizedString(@"call.start", nil);
        [_header addSubview:_callButton];
    }
    if (_pinnedList) {
        /* the list of pinned messages has a title and no picture, status, menu or field */
        _avatar.hidden = YES;
        _subtitle.hidden = YES;
        _menuButton.hidden = YES;
        _input.hidden = YES;
        _title.entities = nil;
        _title.text = [self listTitle];
        return;
    }
    /* the name and the status open the profile as the picture does */
    _title.userInteractionEnabled = YES;
    [_title addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chatTitleTapped:)] autorelease]];
    _subtitle.userInteractionEnabled = YES;
    [_subtitle addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileGifts)] autorelease]];
}

- (void)chatTitleTapped:(UITapGestureRecognizer *)tap {
    CGPoint point = [tap locationInView:_title];
    NSUInteger mark = ExteriaMarkForDocument([_title customEmojiAtPoint:point]);
    if (mark) ExteriaShowMarkNotice(_dialog.title, mark);
    else [self openProfileGifts];
}

/* the ring round the picture follows the stories of the person: arcs coloured while unseen, grey once seen */
- (void)loadStories {
    if (_dialog.kind != EXTERIA_DIALOG_USER || _dialog.saved || _pinnedList || !_storyRing) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadStoriesOfDialog:_dialog completion:^(ExteriaStoryPeer *peer, NSArray *stories, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || errorName) return;
        chat->_storyRing.hidden = !stories.count;
        if (stories.count) [chat->_storyRing setPeer:peer];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadStories];
    if (_dialog.peerKind == 1 && !_dialog.saved && !_pinnedList) {
        ExteriaWeakReference *weak = _weak;
        [_session loadSharingPeriod:^(int32_t seconds, int64_t offset, NSString *errorName) {
            ExteriaChatController *chat = weak.target;
            if (!chat) return;
            if (errorName) NSLog(@"exteria: sharing request lifetime was not refreshed: %@", errorName);
            chat->_sharingPeriod = seconds;
            chat->_sharingOffsetMilliseconds = offset;
            [chat rebuildItems];
        }];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liteModeChanged) name:ExteriaLiteModeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(developersChanged) name:ExteriaDevelopersDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(readOutboxChanged:) name:ExteriaReadOutboxDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timesChanged) name:ExteriaTimeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(uploadProgressed:) name:ExteriaUploadProgressNotification object:_session];
    if (_dialog.saved) {
        ExteriaWeakReference *weak = _weak;
        [self whenPremiumKnown:^(BOOL premium) {
            ExteriaChatController *chat = weak.target;
            if (chat && premium) [chat rebuildItems];
        }];
    }
    if (_pinnedList) [self loadPinnedList];
    else [self loadNewest];
    if (_dialog.peerKind == 3) [self loadChannelFull];
    if (!_pinnedList) [self loadPremiumGate];
    /* asked now, so the first menu already has its reaction pill and shows card and pill together */
    if (!_pinnedList && ![self reactionsHidden]) [self loadMenuReactionsThen:nil];
    if (_dialog.kind == EXTERIA_DIALOG_GROUP) {
        ExteriaWeakReference *weak = _weak;
        [_session loadSenderRolesOfDialog:_dialog completion:^(NSDictionary *roles, NSDictionary *people, NSString *errorName) {
            ExteriaChatController *chat = weak.target;
            if (!chat) return;
            if (errorName) {
                NSLog(@"exteria: group sender roles did not load: %@", errorName);
                return;
            }
            [chat->_senderRoles release];
            chat->_senderRoles = [roles copy];
            [chat->_people addEntriesFromDictionary:people];
            [chat rebuildItems];
        }];
    }
    _bots.startParam = _startParam;
    if (!_pinnedList) [_bots start];
    if (_draftText.length) [self applyDraft:_draftText];
    else [self restoreDraft];
    _draftsActive = !_pinnedList && !_dialog.savedSource;
    if (_draftsActive) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftBoardChanged:) name:ExteriaDraftDidChangeNotification object:_session.drafts];
}

#pragma mark bots

- (void)applyDraft:(NSString *)text {
    if (!text.length || !_input) return;
    _input.textView.text = text;
    [_input.textView.delegate textViewDidChange:_input.textView];
    [_input.textView becomeFirstResponder];
}

- (ExteriaInputBar *)botsInputBar { return _input; }
- (UIView *)botsContainerView { return self.view; }
- (long long)botsRandomId { return [self newRandomId]; }
- (CGFloat)botsKeyboardMaxHeight { return [self panelHeight]; }
- (void)botsSetDraft:(NSString *)text { [self applyDraft:text]; }
- (void)botsSendText:(NSString *)text replyTo:(int32_t)replyTo { [self sendText:text entities:nil replyTo:replyTo]; }

- (void)botsRelayout {
    if (!self.isViewLoaded) return;
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
}

/* the people the history named, without the account itself */
- (NSArray *)botsMentionCandidates {
    long long mine = [ExteriaSession accountIdInDirectory:_session.directory];
    NSMutableArray *people = [NSMutableArray arrayWithCapacity:_people.count];
    for (id key in _people) {
        ExteriaPerson *person = [_people objectForKey:key];
        if ([person isKindOfClass:[ExteriaPerson class]] && person.userId > 0 && person.userId != mine) [people addObject:person];
    }
    return people;
}

- (ExteriaPerson *)botsPersonForUserId:(long long)userId {
    return [_people objectForKey:[NSNumber numberWithLongLong:userId]];
}

/* a bot's keyboard stands in for the system keyboard, as the emoji panel does, and the two give way to each other */
- (void)botsSetInputView:(UIView *)view {
    UITextView *text = _input.textView;
    if (view && _panelShown) {
        _panelShown = NO;
        _input.panelShown = NO;
    }
    text.inputView = view;
    if (view && ![text isFirstResponder]) [text becomeFirstResponder];
    else if ([text isFirstResponder]) [text reloadInputViews];
}

- (void)botsRequestLocation {
    [[self attachFlow] chooseLocation];
}

- (ExteriaAttachFlow *)attachFlow {
    if (_attach.cancelled) { [_attach release]; _attach = nil; }
    if (!_attach) {
        ExteriaWeakReference *weak = _weak;
        _attach = [[ExteriaAttachFlow alloc] initWithHost:self handler:^(ExteriaOutgoing *outgoing) {
            ExteriaChatController *chat = weak.target;
            if (chat) [chat sendOutgoing:outgoing];
        }];
        _attach.session=_session;
        _attach.dialog=_dialog;
        _attach.albumHandler = ^(NSArray *outgoings) {
            ExteriaChatController *chat = weak.target;
            if (chat) [chat sendAlbum:outgoings];
        };
    }
    return _attach;
}

- (void)inputBarDidTapMenu:(ExteriaInputBar *)bar { (void)bar; [_bots menuTapped]; }
- (void)inputBarDidTapBotKeyboard:(ExteriaInputBar *)bar { (void)bar; [_bots keyboardButtonTapped]; }
- (void)inputBarDidTapAction:(ExteriaInputBar *)bar {
    (void)bar;
    if (_joinPending) [self joinChannel];
    else [_bots actionTapped];
}
- (void)inputBarDidChangeText:(ExteriaInputBar *)bar {
    (void)bar;
    [_bots inputTextChanged];
    [self draftStateChanged];
}

- (void)messageCell:(ExteriaMessageCell *)cell didPressButton:(ExteriaMarkupButton *)button {
    [_bots pressButton:button ofMessage:cell.item.message cell:cell];
}

#pragma mark pinned list

- (void)loadPinnedList {
    _loading = YES;
    [self stopFollowingBottom];
    _stickToBottom = NO;
    ExteriaWeakReference *weak = _weak;
    ExteriaHistoryCompletion loaded = ^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_loading = NO;
        /* a list of pinned or found messages has no newest message to settle on */
        chat->_opening = NO;
        if (!messages) {
            [chat showStatus:[chat failureTextForError:errorName] retry:YES];
            return;
        }
        chat->_loadedFirst = YES;
        chat->_table.hidden = NO;
        [chat->_people addEntriesFromDictionary:people];
        [chat mergeMessages:messages];
        chat->_canLoadMore = NO;
        NSString *title;
        if ([chat listIsFound]) {
            title = [chat listTitle];
        } else {
            NSString *form = [@"chat.pinned.count." stringByAppendingString:ExteriaPluralForm((NSInteger)messages.count)];
            title = messages.count ? [NSString stringWithFormat:NSLocalizedString(form, nil), (long)messages.count] : NSLocalizedString(@"chat.pinned.list", nil);
        }
        if (chat->_title) {
            chat->_title.entities = nil;
            chat->_title.text = title;
        }
        else chat.title = title;
        if (!messages.count) [chat showStatus:NSLocalizedString([chat listIsFound] ? @"chat.search.none" : @"chat.pinned.none", nil) retry:NO];
        [chat rebuildItems];
    };
    if (_historyPerson) [_session searchMessagesOfDialog:_dialog fromUserId:_historyPerson.userId accessHash:_historyPerson.accessHash completion:loaded];
    else if (_searchQuery.length) [_session searchMessagesOfDialog:_dialog query:_searchQuery completion:loaded];
    else [_session loadPinnedMessagesOfDialog:_dialog completion:loaded];
}

/* the list is the answer to a search of some kind and not the pinned messages */
- (BOOL)listIsFound {
    return _searchQuery.length || _historyPerson;
}

/* the title of a list screen: what was searched for, whose messages these are, or the pinned ones */
- (NSString *)listTitle {
    if (_historyPerson) return [NSString stringWithFormat:NSLocalizedString(@"chat.history.title", nil), _historyPerson.name];
    if (_searchQuery.length) return [NSString stringWithFormat:NSLocalizedString(@"chat.search.title", nil), _searchQuery];
    return NSLocalizedString(@"chat.pinned.list", nil);
}

/* the list of every pinned message of the chat: this same screen, over only those messages */
- (void)openPinnedList {
    ExteriaChatController *list = [[[ExteriaChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    [self.navigationController pushViewController:list animated:YES];
}

#pragma mark channel

#pragma mark send as

/* a supergroup lets the account write as itself or as a channel it administers, or anonymously as the group; the identities are asked for once the
   full channel is in, since it names the one the server keeps */
- (void)loadSendAsOptions {
    if (_sendAsRequested || _pinnedList || _dialog.peerKind != 3 || _dialog.kind != EXTERIA_DIALOG_GROUP || ExteriaChatFlagGet(ExteriaChatFlagHideSendAs)) return;
    _sendAsRequested = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadSendAsOptionsOfDialog:_dialog completion:^(NSArray *options, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!options) {
            NSLog(@"exteria: the identities to write as did not load: %@", errorName);
            chat->_sendAsRequested = NO;
            return;
        }
        [chat->_sendAsOptions release];
        chat->_sendAsOptions = [options retain];
        [chat refreshSendAs];
    }];
}

/* the identity in use: the one chosen on this phone, else the one the server keeps, else the account itself */
- (ExteriaSendAsOption *)currentSendAsOption {
    if (_sendAsPicked) return _sendAsPicked;
    ExteriaDialog *chosen = [_session sendAsIdentityOfDialog:_dialog];
    ExteriaSendAsOption *account = nil;
    for (ExteriaSendAsOption *option in _sendAsOptions) {
        if (option.isAccount) account = option;
        BOOL same = chosen ? (option.identity.peerKind == chosen.peerKind && option.identity.peerId == chosen.peerId)
                           : (_channelFull.sendAsId > 0 && option.identity.peerKind == _channelFull.sendAsKind && option.identity.peerId == _channelFull.sendAsId);
        if (same) return option;
    }
    return account;
}

- (void)refreshSendAs {
    if (_sendAsOptions.count < 2) {
        _input.senderVisible = NO;
        return;
    }
    ExteriaSendAsOption *current = [self currentSendAsOption];
    if (!current) {
        _input.senderVisible = NO;
        return;
    }
    /* what the server keeps becomes what later messages carry */
    [_session adoptSendAsIdentity:current.identity ofDialog:_dialog];
    ExteriaDialog *identity = current.identity;
    _input.senderAvatar.initials = identity.initials;
    _input.senderAvatar.seed = (NSUInteger)(identity.peerId % 1000003);
    [_input.senderAvatar setPhoto:identity.photo cache:_avatars];
    _input.senderVisible = YES;
    [self.view setNeedsLayout];
}

- (void)inputBarDidTapSender:(ExteriaInputBar *)bar {
    (void)bar;
    if (_sendAsOptions.count < 2) return;
    [self dismissInput];
    NSMutableArray *titles = [NSMutableArray arrayWithCapacity:_sendAsOptions.count];
    for (ExteriaSendAsOption *option in _sendAsOptions) {
        NSString *title = option.isAccount ? NSLocalizedString(@"chat.sendas.account", nil) : option.identity.title;
        [titles addObject:option.premiumRequired ? [NSString stringWithFormat:@"%@ (Premium)", title] : title];
    }
    ExteriaWeakReference *weak = _weak;
    void (^pick)(NSUInteger) = ^(NSUInteger index) {
        ExteriaChatController *chat = weak.target;
        if (!chat || index >= chat->_sendAsOptions.count) return;
        ExteriaSendAsOption *option = [chat->_sendAsOptions objectAtIndex:index];
        ExteriaSendAsOption *before = [chat->_sendAsPicked retain];
        [chat->_sendAsPicked release];
        chat->_sendAsPicked = [option retain];
        [chat->_session chooseSendAsIdentity:option.identity ofDialog:chat->_dialog completion:^(NSString *errorName) {
            ExteriaChatController *again = weak.target;
            if (!again) {
                [before release];
                return;
            }
            if (errorName) {
                NSLog(@"exteria: the identity to write as was refused: %@", errorName);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
                [again->_sendAsPicked release];
                again->_sendAsPicked = [before retain];
            }
            [before release];
            [again refreshSendAs];
        }];
        [chat refreshSendAs];
    };
    [ExteriaSheet presentInView:self.view title:NSLocalizedString(@"chat.sendas", nil) message:NSLocalizedString(@"chat.sendas.info", nil) options:titles destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:pick];
}

/* the way in stands where the field would be while the account is outside the channel */
- (void)applyMembership:(BOOL)member {
    if (_joining) return;
    _joinPending = !member && !_pinnedList;
    _input.actionWithInput = _joinPending && _dialog.kind == EXTERIA_DIALOG_GROUP;
    _input.actionTitle = _joinPending ? NSLocalizedString(@"chat.join", nil) : nil;
    [self.view setNeedsLayout];
}

/* a chat opened from a link carries a channel whose flags do not say whether the account is in, so the button used to flash with the first guess and go;
   getParticipant of this account is the answer, asked once per screen */
- (void)checkMembership {
    if (_membershipAsked || _pinnedList) return;
    _membershipAsked = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadMembershipOfDialog:_dialog completion:^(BOOL member, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"exteria: membership of channel %lld was not read: %@", chat->_dialog.peerId, errorName);
            chat->_membershipAsked = NO;
            return;
        }
        [chat applyMembership:member];
    }];
}

- (void)loadChannelFull {
    if (_dialog.topicId > 0 && !_pinnedList) [self loadTopicPinned];
    ExteriaWeakReference *weak = _weak;
    [_session loadFullChannelOfDialog:_dialog completion:^(ExteriaFullChannel *channel, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!channel) {
            NSLog(@"exteria: channel %lld did not load in full: %@", chat->_dialog.peerId, errorName);
            return;
        }
        [chat->_channelFull release];
        chat->_channelFull = [channel retain];
        /* a channel or group the account is not in shows the way in where the field would be */
        /* the flag is only trusted on a full object; a min one says nothing, and the server is asked once */
        if (channel.membershipKnown) [chat applyMembership:!channel.dialog.left];
        else [chat checkMembership];
        [chat refreshStatusLine];
        /* the full channel is the authority on posting rights, whatever the chat list's entry said */
        if (chat->_dialog.kind == EXTERIA_DIALOG_CHANNEL) {
            BOOL canPost = channel.dialog.canPost;
            chat->_input.writable = canPost;
            if (!canPost) chat->_input.readOnlyNote = NSLocalizedString(@"chat.readonly", nil);
            [chat.view setNeedsLayout];
        }
        [chat loadSendAsOptions];
        if (chat->_dialog.topicId > 0) return;
        if (channel.pinnedMessage > 0 && !chat->_pinnedList) {
            [chat loadPinned:channel.pinnedMessage];
            [chat countPinned];
        } else if (!channel.pinnedMessage && chat->_pinnedId && !chat->_pinnedList) {
            /* nothing is pinned any more: the bar goes */
            chat->_pinnedId = 0;
            chat->_pinnedCount = 0;
            chat->_pinnedBar.hidden = YES;
            chat->_pinnedListButton.hidden = YES;
            [chat.view setNeedsLayout];
        }
    }];
}

/* the full channel names a pin of the whole group, not the pins of the open topic */
- (void)loadTopicPinned {
    NSUInteger generation = ++_topicPinnedGeneration;
    ExteriaWeakReference *weak = _weak;
    [_session loadPinnedMessagesOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        ExteriaChatController *chat = weak.target;
        if (!chat || generation != chat->_topicPinnedGeneration) return;
        if (!messages) {
            NSLog(@"exteria: pinned messages of topic %d did not load: %@", (int)chat->_dialog.topicId, errorName);
            return;
        }
        chat->_pinnedCount = (NSInteger)messages.count;
        chat->_pinnedListButton.hidden = messages.count < 2;
        if (messages.count) [chat showPinnedMessage:[messages objectAtIndex:0]];
        else {
            chat->_pinnedId = 0;
            ++chat->_pinnedThumbToken;
            chat->_pinnedThumb.image = nil;
            chat->_pinnedThumb.hidden = YES;
            chat->_pinnedBar.hidden = YES;
            [chat.view setNeedsLayout];
        }
    }];
}

- (void)showPinnedMessage:(ExteriaMessage *)message {
    NSString *line = message.text.length ? message.text : ExteriaPreviewWord(message.media.kind);
    if (!message.text.length && message.media.kind == EXTERIA_PREVIEW_FILE && message.media.name.length) line = message.media.name;
    NSRange newline = [line rangeOfString:@"\n"];
    if (newline.location != NSNotFound) line = [line substringToIndex:newline.location];
    _pinnedId = message.messageId;
    _pinnedText.text = line;
    [self showPinnedThumbOf:message];
    _pinnedBar.hidden = line.length == 0;
    [self.view setNeedsLayout];
}

/* the pinned message is fetched by id, and its first words or the word for its media stand in the bar */
- (void)loadPinned:(int32_t)messageId {
    ExteriaWeakReference *weak = _weak;
    [_session loadMessage:messageId ofChannelDialog:_dialog completion:^(ExteriaMessage *message, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!message) {
            NSLog(@"exteria: the pinned message %d of channel %lld did not load: %@", (int)messageId, chat->_dialog.peerId, errorName);
            return;
        }
        [chat showPinnedMessage:message];
    }];
}

/* how many messages the chat has pinned decides whether the bar offers the list of them */
- (void)countPinned {
    ExteriaWeakReference *weak = _weak;
    [_session loadPinnedMessagesOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!messages) {
            NSLog(@"exteria: the pinned messages of chat %lld were not counted: %@", chat->_dialog.peerId, errorName);
            return;
        }
        chat->_pinnedCount = (NSInteger)messages.count;
        chat->_pinnedListButton.hidden = messages.count < 2;
        [chat.view setNeedsLayout];
    }];
}

/* the small square of a pinned photo or video: the photo itself, or the preview of the video, a gif or a sticker */
- (void)showPinnedThumbOf:(ExteriaMessage *)message {
    ++_pinnedThumbToken;
    NSUInteger token = _pinnedThumbToken;
    ExteriaMedia *media = message.media;
    ExteriaRemoteFile *file = media.kind == EXTERIA_PREVIEW_PHOTO ? media.file : ((media.kind == EXTERIA_PREVIEW_VIDEO || media.kind == EXTERIA_PREVIEW_GIF || media.kind == EXTERIA_PREVIEW_STICKER) ? media.previewFile : nil);
    _pinnedThumb.image = nil;
    _pinnedThumb.hidden = file == nil;
    if (!file) return;
    CGFloat pixels = 34 * ExteriaScreenScale();
    ExteriaWeakReference *weak = _weak;
    [_media loadImageForFile:file maxSide:pixels completion:^(UIImage *image) {
        ExteriaChatController *chat = weak.target;
        if (!chat || token != chat->_pinnedThumbToken) return;
        chat->_pinnedThumb.image = image;
        chat->_pinnedThumb.hidden = image == nil;
        [chat.view setNeedsLayout];
    }];
}

- (void)pinnedTapped {
    _scrollTarget = _pinnedId;
    _scrollPages = 0;
    [self scrollToTargetOrLoadMore];
}

/* a message that is in the list is scrolled to; one that is older asks for pages of older history until it comes or the pages run out */
- (void)stopJump {
    [_jumpLink invalidate];
    [_jumpLink release];
    _jumpLink = nil;
}

/* the row of a message that was asked for comes to the middle of the screen in a fraction of a second and is lit for a moment. A message far off is first jumped to the
   edge of a screen's distance from it, so the part that is seen is always a short, quick move, and the rows are made as it goes since the offset is set each frame */
- (void)scrollQuicklyToRow:(NSUInteger)row {
    int32_t messageId = ((ExteriaChatItem *)[_items objectAtIndex:row]).message.messageId;
    [self stopJump];
    [_table layoutIfNeeded];
    UIEdgeInsets inset = _table.contentInset;
    CGRect rect = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
    CGFloat visible = MAX(1, _table.bounds.size.height - inset.top - inset.bottom);
    CGFloat low = -inset.top;
    CGFloat high = MAX(low, _table.contentSize.height - _table.bounds.size.height + inset.bottom);
    /* a message taller than the screen shows its beginning */
    CGFloat aim = rect.size.height >= visible * 0.9 ? rect.origin.y - inset.top - 8 : CGRectGetMidY(rect) - visible / 2 - inset.top;
    aim = MIN(high, MAX(low, aim));
    CGFloat from = _table.contentOffset.y;
    if (ExteriaReduceMotionEnabled() || fabs(aim - from) < 1) {
        [_table setContentOffset:CGPointMake(0, aim) animated:NO];
        [self flashRowOfMessage:messageId];
        return;
    }
    CGFloat reach = visible * 1.2f;
    if (fabs(aim - from) > reach) {
        from = MIN(high, MAX(low, aim + (aim > from ? -reach : reach)));
        [_table setContentOffset:CGPointMake(0, from) animated:NO];
        [_table layoutIfNeeded];
    }
    _jumpFrom = from;
    _jumpTo = aim;
    _jumpMessageId = messageId;
    _jumpBegan = 0;
    _jumpLength = 0.2 + 0.14 * MIN(1.0, fabs(aim - from) / reach);
    ExteriaReactionPollTarget *target = [[[ExteriaReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _jumpLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(jump:)] retain];
    [_jumpLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)advanceJump:(CADisplayLink *)link {
    /* a finger on the list takes it over */
    if (_table.tracking || _table.dragging) {
        [self stopJump];
        return;
    }
    if (!_jumpBegan) _jumpBegan = link.timestamp;
    double t = MIN(1.0, (link.timestamp - _jumpBegan) / _jumpLength);
    double eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2;
    [_table setContentOffset:CGPointMake(0, (CGFloat)(_jumpFrom + (_jumpTo - _jumpFrom) * eased)) animated:NO];
    if (t < 1.0) return;
    int32_t messageId = _jumpMessageId;
    [self stopJump];
    [self flashRowOfMessage:messageId];
}

- (void)flashRowOfMessage:(int32_t)messageId {
    [_table layoutIfNeeded];
    for (ExteriaMessageCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[ExteriaMessageCell class]] && cell.item.message.messageId == messageId) {
            [cell flashHighlight];
            return;
        }
    }
}

- (int32_t)newestLoadedId {
    int32_t newest = 0;
    for (NSNumber *key in [_server allKeys]) newest = MAX(newest, [key intValue]);
    return newest;
}

- (void)scrollToTargetOrLoadMore {
    if (_scrollTarget <= 0) return;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        if (((ExteriaChatItem *)[_items objectAtIndex:i]).message.messageId != _scrollTarget) continue;
        _scrollTarget = 0;
        [self stopFollowingBottom];
        _stickToBottom = NO;
        [self scrollQuicklyToRow:i];
        return;
    }
    if (_loadingWindow) return;
    /* the message is held but its row is not built yet, which the rebuild that is waiting does */
    if ([_server objectForKey:[NSNumber numberWithInt:_scrollTarget]]) return;
    /* a message outside what is loaded is opened as the official clients do: the stretch of history around it is fetched and shown, instead of paging through
       everything between it and the newest message, which never got to an old message of a busy group */
    BOOL outside = (_oldestId && _scrollTarget < _oldestId) || (_window && _scrollTarget > [self newestLoadedId]);
    if (outside && !_pinnedList && !_loadingOlder) {
        [self openWindowAround:_scrollTarget];
        return;
    }
    if (_canLoadMore && !_loadingOlder && _scrollPages++ < PINNED_SEARCH_PAGES) [self loadOlder];
    else if (!_loadingOlder) _scrollTarget = 0;
}

- (void)openWindowAround:(int32_t)target {
    _loadingWindow = YES;
    NSUInteger token = ++_windowToken;
    ExteriaWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog offsetId:target + 1 addOffset:-(HISTORY_PAGE / 2) limit:HISTORY_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || token != chat->_windowToken) return;
        chat->_loadingWindow = NO;
        BOOL found = NO;
        for (ExteriaMessage *message in messages) if (message.messageId == target) found = YES;
        if (!found) {
            NSLog(@"exteria: the history around message %d of chat %lld did not hold it: %@", (int)target, chat->_dialog.peerId, errorName);
            chat->_scrollTarget = 0;
            ExteriaShowNotice(nil, NSLocalizedString(@"chat.reply.unavailable", nil));
            return;
        }
        [chat enterWindowWithMessages:messages people:people];
        [chat scrollToTargetOrLoadMore];
    }];
}

/* the stretch replaces what the list held; older pages and newer pages are fetched from its two ends as the person scrolls */
- (void)enterWindowWithMessages:(NSArray *)messages people:(NSDictionary *)people {
    [self stopFollowingBottom];
    [_server removeAllObjects];
    _oldestId = 0;
    _window = YES;
    _canLoadNewer = YES;
    _loadingNewer = NO;
    _loadingOlder = NO;
    _olderDeferred = NO;
    _stickToBottom = NO;
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    _canLoadMore = _oldestId > 1;
    _rebuildNow = YES;
    [self rebuildItems];
    _rebuildNow = NO;
    [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:NO];
    [self showToEnd:YES];
}

- (void)loadNewerIfNeeded:(CGFloat)distance {
    if (!_window || !_canLoadNewer || _loadingNewer || _loadingWindow || distance > _table.bounds.size.height * 1.5f) return;
    int32_t newest = [self newestLoadedId];
    if (newest <= 0) return;
    _loadingNewer = YES;
    NSUInteger token = _windowToken;
    ExteriaWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog offsetId:newest addOffset:-(HISTORY_PAGE - 1) limit:HISTORY_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || token != chat->_windowToken) return;
        chat->_loadingNewer = NO;
        if (!messages) {
            /* the list stays as it is and the next scroll to its end asks again */
            NSLog(@"exteria: newer messages of chat %lld not loaded: %@", chat->_dialog.peerId, errorName);
            return;
        }
        NSUInteger fresh = 0;
        for (ExteriaMessage *message in messages) if (message.messageId > newest) ++fresh;
        [chat->_people addEntriesFromDictionary:people];
        [chat mergeMessages:messages];
        /* a page that came back short ends at the newest message of the chat: the list is the chat again, and the live updates of the store join it */
        if (fresh + 2 < HISTORY_PAGE) {
            chat->_window = NO;
            chat->_canLoadNewer = NO;
        }
        [chat rebuildItems];
        if (!chat->_window) [chat markReadIfNeeded];
    }];
}

/* back from the window to the end of the chat: what was loaded goes, and the newest page is fetched as when the chat opened */
- (void)leaveWindow {
    if (!_window && !_loadingWindow) return;
    ++_windowToken;
    _window = NO;
    _loadingWindow = NO;
    _loadingNewer = NO;
    _loadingOlder = NO;
    _olderDeferred = NO;
    _canLoadNewer = NO;
    _scrollTarget = 0;
    [_server removeAllObjects];
    _oldestId = 0;
    _canLoadMore = NO;
    _loadedFirst = NO;
    _stickToBottom = YES;
    [self loadNewest];
}

#pragma mark voice chat

/* the voice chat of a group or channel is asked for each time the chat comes up, and the bar shows only one this app can join */
- (void)refreshVoiceChat {
    if (_pinnedList || _dialog.saved || (_dialog.peerKind != 2 && _dialog.peerKind != 3) || _joinPending) return;
    NSUInteger token = ++_voiceToken;
    ExteriaWeakReference *weak = _weak;
    [_session.groupCalls loadVoiceChatOfDialog:_dialog completion:^(ExteriaVoiceChat *chat, NSString *errorName) {
        ExteriaChatController *controller = weak.target;
        if (!controller || token != controller->_voiceToken) return;
        if (!chat && errorName && ![errorName isEqualToString:@"NOCALL"]) NSLog(@"exteria: the voice chat of the chat was not read: %@", errorName);
        [controller->_voiceChat release];
        controller->_voiceChat = [chat retain];
        BOOL show = chat != nil && chat.joinable;
        if (show) controller->_voiceInfo.text = chat.participantsCount > 0 ? [NSString stringWithFormat:NSLocalizedString(@"group.members", nil), chat.participantsCount]
                                                                           : NSLocalizedString(@"chat.voice.empty", nil);
        if (controller->_voiceBar.hidden == show) {
            controller->_voiceBar.hidden = !show;
            [controller layoutChat];
        }
    }];
}

- (void)openVoiceChat {
    if (_voiceChat) {
        [_session.groupCalls joinVoiceChatOfDialog:_dialog inviteHash:nil];
        return;
    }
    [self askWithMessage:NSLocalizedString(@"chat.voice.start.confirm", nil) action:NSLocalizedString(@"chat.menu.voicechat.start", nil) tag:ExteriaChatAlertStartVoice];
}

#pragma mark menu

typedef enum { ExteriaChatMenuSearch, ExteriaChatMenuPinned, ExteriaChatMenuVoiceChat, ExteriaChatMenuDiscussion, ExteriaChatMenuNotifications, ExteriaChatMenuWallpaper, ExteriaChatMenuClear, ExteriaChatMenuBookmarks, ExteriaChatMenuSavedDialogs, ExteriaChatMenuBotSettings, ExteriaChatMenuBotHelp, ExteriaChatMenuReport, ExteriaChatMenuDelete } ExteriaChatMenuEntry;
enum { ExteriaChatAlertClear = 9101, ExteriaChatAlertDelete, ExteriaChatAlertDeleteMessage, ExteriaChatAlertSearch, ExteriaChatAlertDeleteSelected, ExteriaChatAlertStartVoice };

/* a call goes to a person: not to a bot, a group, a channel or the saved messages */
- (BOOL)canCall {
    if (_dialog.kind != EXTERIA_DIALOG_USER || _dialog.saved || _pinnedList || _dialog.peerId == EXTERIA_TELEGRAM_SERVICE_USER_ID) return NO;
    /* a dialog made from a mention or a link may not know yet that the user is a bot; the user object the history brings does */
    ExteriaPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:_dialog.peerId]];
    return !person.bot;
}

/* asks the question first when the person wants it asked (the setting), then runs the block; declined runs when the answer is no */
- (void)askFirst:(ExteriaChatFlag)flag message:(NSString *)message action:(NSString *)action then:(void (^)(void))go declined:(void (^)(void))declined {
    if (!ExteriaChatFlagGet(flag)) {
        go();
        return;
    }
    void (^yes)(void) = [go copy];
    void (^no)(void) = [declined copy];
    ExteriaShowAlert(nil, message, [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), action, nil], 0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) yes();
        else if (no) no();
        [yes release];
        [no release];
    });
}

- (void)startCall {
    [self askFirst:ExteriaChatFlagAskCall message:[NSString stringWithFormat:NSLocalizedString(@"chat.ask.call", nil), _dialog.title] action:NSLocalizedString(@"chat.ask.call.action", nil) then:^{
        [_session startCallToDialog:_dialog];
    } declined:nil];
}

- (void)showChatMenu {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *entries = [NSMutableArray array];
    ExteriaSymbol symbols[16];
    BOOL channelLike = _dialog.peerKind == 3;
    BOOL bot = _dialog.kind == EXTERIA_DIALOG_BOT;
/* the rows are the ones the three dots give, in its order */
#define MENU_ROW(symbol, key, entry) do { symbols[titles.count] = (symbol); [titles addObject:NSLocalizedString((key), nil)]; [entries addObject:[NSNumber numberWithInt:(entry)]]; } while (0)
    MENU_ROW(ExteriaSymbolMagnifier, @"chat.menu.search", ExteriaChatMenuSearch);
    MENU_ROW(ExteriaSymbolPinLine, @"chat.menu.pinned", ExteriaChatMenuPinned);
    if ((_dialog.peerKind == 2 || _dialog.peerKind == 3) && !_dialog.saved && !_pinnedList && !_joinPending) {
        MENU_ROW(ExteriaSymbolMicrophone, _voiceChat ? @"chat.menu.voicechat.join" : @"chat.menu.voicechat.start", ExteriaChatMenuVoiceChat);
    }
    if (_dialog.saved && !_dialog.savedSource) MENU_ROW(ExteriaSymbolGroupsMenu, @"chat.menu.saved.dialogs", ExteriaChatMenuSavedDialogs);
    /* the linked chat comes from the full channel, so it waits for it instead of showing a row that cannot work yet */
    if (channelLike && _channelFull.linked) {
        if (_channelFull.megagroup) MENU_ROW(ExteriaSymbolMegaphone, @"chat.menu.linked.channel", ExteriaChatMenuDiscussion);
        else MENU_ROW(ExteriaSymbolGroupsMenu, @"chat.menu.linked.group", ExteriaChatMenuDiscussion);
    }
    if (!_dialog.saved) MENU_ROW(ExteriaSymbolBell, @"notif.chat.header", ExteriaChatMenuNotifications);
    MENU_ROW(ExteriaSymbolBackground, @"chat.menu.wallpaper", ExteriaChatMenuWallpaper);
    if (!channelLike && _server.count) MENU_ROW(ExteriaSymbolClearHistory, @"chat.menu.clear", ExteriaChatMenuClear);
    /* the saved messages are listed once the person has marked any is shown only then */
    if ([[ExteriaBookmarks bookmarksForSession:_session] entries].count) MENU_ROW(ExteriaSymbolFave, @"bookmarks.title", ExteriaChatMenuBookmarks);
    if (bot) {
        MENU_ROW(ExteriaSymbolSettingsOld, @"chat.menu.bot.settings", ExteriaChatMenuBotSettings);
        MENU_ROW(ExteriaSymbolHelp, @"chat.menu.bot.help", ExteriaChatMenuBotHelp);
        if (!_dialog.saved) MENU_ROW(ExteriaSymbolReport, @"report.title", ExteriaChatMenuReport);
    }
    if (_dialog.kind == EXTERIA_DIALOG_USER || bot || (channelLike && !_joinPending)) {
        MENU_ROW(channelLike ? ExteriaSymbolLogout : ExteriaSymbolTrash,
                 channelLike ? (_dialog.kind == EXTERIA_DIALOG_GROUP ? @"channel.menu.leave.group" : @"channel.menu.leave") : @"chat.menu.delete", ExteriaChatMenuDelete);
    }
#undef MENU_ROW
    ExteriaWeakReference *weak = _weak;
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        ExteriaChatController *chat = weak.target;
        if (!chat || index >= entries.count) return;
        switch ([[entries objectAtIndex:index] intValue]) {
        case ExteriaChatMenuSearch: [chat askSearchQuery]; break;
        case ExteriaChatMenuPinned: [chat openPinnedList]; break;
        case ExteriaChatMenuVoiceChat: [chat openVoiceChat]; break;
        case ExteriaChatMenuSavedDialogs: [chat openSavedDialogs]; break;
        case ExteriaChatMenuDiscussion: [chat openDiscussion]; break;
        case ExteriaChatMenuNotifications:
            [chat.navigationController pushViewController:[[[ExteriaNotificationsChatController alloc] initWithSession:chat->_session media:chat->_media peerKind:chat->_dialog.peerKind
                                                                                                              peerId:chat->_dialog.peerId peerHash:chat->_dialog.peerHash
                                                                                                             channel:chat->_dialog.kind == EXTERIA_DIALOG_CHANNEL
                                                                                                               topic:chat->_dialog.topicId title:chat->_dialog.title] autorelease] animated:YES];
            break;
        case ExteriaChatMenuWallpaper: [chat.navigationController pushViewController:[[[ExteriaWallpaperController alloc] init] autorelease] animated:YES]; break;
        case ExteriaChatMenuClear: [chat askWithMessage:NSLocalizedString(@"chat.clear.confirm", nil) action:NSLocalizedString(@"chat.menu.clear", nil) tag:ExteriaChatAlertClear]; break;
        case ExteriaChatMenuBookmarks:
            [chat.navigationController pushViewController:[[[ExteriaBookmarksController alloc] initWithSession:chat->_session avatars:chat->_avatars media:chat->_media
                                                                                                       stickers:chat->_stickers] autorelease] animated:YES];
            break;
        /* a bot answers its own commands, which is all the settings and the help of a bot are */
        case ExteriaChatMenuBotSettings: [chat sendText:@"/settings" entities:nil]; break;
        case ExteriaChatMenuBotHelp: [chat sendText:@"/help" entities:nil]; break;
        case ExteriaChatMenuReport: [ExteriaReportFlow startForDialog:chat->_dialog session:chat->_session host:chat done:nil]; break;
        case ExteriaChatMenuDelete: {
            NSString *message = chat->_dialog.peerKind == 3 ? [NSString stringWithFormat:NSLocalizedString(@"chats.swipe.leave.confirm", nil), chat->_dialog.title] : NSLocalizedString(@"chat.delete.confirm", nil);
            [chat askWithMessage:message action:[titles lastObject] tag:ExteriaChatAlertDelete];
            break;
        }
        }
    }] autorelease];
    menu.bottomInset = _keyboardOverlap;
    CGPoint anchor;
    if (_menuButton) anchor = [_menuButton.superview convertPoint:CGPointMake(CGRectGetMaxX(_menuButton.frame) - 6, CGRectGetMaxY(_menuButton.frame) - 8) toView:self.view];
    else anchor = CGPointMake(self.view.bounds.size.width - 8, 4);
    [menu showInView:self.view anchor:anchor];
}

- (void)joinChannel {
    if (_joining) return;
    _joining = YES;
    ExteriaWeakReference *weak = _weak;
    [_session joinChannelOfDialog:_dialog completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_joining = NO;
        if (errorName) {
            NSLog(@"exteria: joining %lld failed: %@", chat->_dialog.peerId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
        chat->_joinPending = NO;
        chat->_membershipAsked = NO;
        chat->_input.actionWithInput = NO;
        chat->_input.actionTitle = nil;
        /* the full channel is the authority on posting rights and on membership, so it decides what the bar shows now */
        [chat loadChannelFull];
    }];
}

- (BOOL)showsDialog:(ExteriaDialog *)dialog {
    return dialog.peerKind == _dialog.peerKind && dialog.peerId == _dialog.peerId && dialog.topicId == _dialog.topicId;
}

/* the alert with a text field starts at ios 5, which is the lowest this app runs on */
enum { ExteriaChatAlertStylePlainTextInput = 2 };

- (void)askSearchQuery {
    if (!ExteriaThemeIsClassic()) {
        [self beginChatSearch];
        return;
    }
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"chat.search.prompt", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil) otherButtonTitles:NSLocalizedString(@"chat.search.go", nil), nil];
    [alert setAlertViewStyle:ExteriaChatAlertStylePlainTextInput];
    [alert setTag:ExteriaChatAlertSearch];
    [alert show];
    [alert release];
}

#pragma mark search of the chat

/* the bar takes the place of the header and the strip the place of the field, until Cancel; the matches are looked up a moment after the last key, and the
   chat scrolls to the one that is shown */
- (void)beginChatSearch {
    if (_searchBar) {
        [_searchBar.field becomeFirstResponder];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    _searchBar = [[ExteriaChatSearchBar alloc] init];
    _searchBar.changeHandler = ^(NSString *text) { [(ExteriaChatController *)weak.target chatSearchChanged:text]; };
    _searchBar.cancelHandler = ^{ [(ExteriaChatController *)weak.target endChatSearch]; };
    [_header addSubview:_searchBar];
    _searchNav = [[ExteriaChatSearchNav alloc] init];
    _searchNav.olderHandler = ^{ [(ExteriaChatController *)weak.target stepChatSearch:1]; };
    _searchNav.newerHandler = ^{ [(ExteriaChatController *)weak.target stepChatSearch:-1]; };
    [self.view addSubview:_searchNav];
    [self layoutChat];
    [_searchBar.field becomeFirstResponder];
}

- (void)endChatSearch {
    if (!_searchBar) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    ++_searchToken;
    [_searchBar.field resignFirstResponder];
    _searchBar.changeHandler = nil;
    _searchBar.cancelHandler = nil;
    _searchNav.olderHandler = nil;
    _searchNav.newerHandler = nil;
    [_searchBar removeFromSuperview];
    [_searchNav removeFromSuperview];
    [_searchBar release];
    [_searchNav release];
    _searchBar = nil;
    _searchNav = nil;
    [_searchHits release];
    _searchHits = nil;
    [self layoutChat];
}

- (void)chatSearchChanged:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runChatSearch:) object:nil];
    ++_searchToken;
    [_searchHits release];
    _searchHits = nil;
    if (!query.length) {
        [_searchNav showIdle];
        return;
    }
    [_searchNav showSearching];
    [self performSelector:@selector(runChatSearch:) withObject:query afterDelay:0.4];
}

- (void)runChatSearch:(NSString *)query {
    if (!_searchBar) return;
    /* the request takes 256 bytes, so the text is cut to a length that fits whatever script it is in */
    NSRange cut = [query rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN((NSUInteger)60, query.length))];
    NSUInteger token = ++_searchToken;
    ExteriaWeakReference *weak = _weak;
    [_session searchMessagesOfDialog:_dialog query:[query substringWithRange:cut] completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        ExteriaChatController *chat = weak.target;
        if (!chat || !chat->_searchBar || token != chat->_searchToken) return;
        if (errorName || !messages.count) {
            if (errorName) NSLog(@"exteria: chat search failed: %@", errorName);
            [chat->_searchNav showNone];
            return;
        }
        [chat->_searchHits release];
        chat->_searchHits = [messages retain];
        chat->_searchPosition = 0;
        [chat showChatSearchHit];
    }];
}

/* direction 1 goes to an older match, which is further along the list, and -1 to a newer one */
- (void)stepChatSearch:(NSInteger)direction {
    NSInteger next = (NSInteger)_searchPosition + direction;
    if (next < 0 || next >= (NSInteger)_searchHits.count) return;
    _searchPosition = (NSUInteger)next;
    [self showChatSearchHit];
}

- (void)showChatSearchHit {
    [_searchNav showPosition:_searchPosition + 1 of:_searchHits.count];
    ExteriaMessage *hit = [_searchHits objectAtIndex:_searchPosition];
    if (hit.messageId > 0) [self jumpToMessageId:hit.messageId];
}

/* the matches open as a list of their own, the way the pinned messages do */
- (void)openSearchResultsFor:(NSString *)text {
    NSString *query = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) return;
    /* the request takes 256 bytes, so the text is cut to a length that fits whatever script it is in */
    NSRange cut = [query rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN((NSUInteger)60, query.length))];
    ExteriaChatController *list = [[[ExteriaChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    list.searchQuery = [query substringWithRange:cut];
    [self.navigationController pushViewController:list animated:YES];
}

/* a tap on a message of a list that came from this chat takes the chat to it */
- (void)messageCellDidTapBody:(ExteriaMessageCell *)cell {
    if (!_pinnedList || !cell.item.message) return;
    NSArray *stack = self.navigationController.viewControllers;
    NSUInteger at = [stack indexOfObject:self];
    if (at == NSNotFound || at == 0 || ![[stack objectAtIndex:at - 1] isKindOfClass:[ExteriaChatController class]]) return;
    ExteriaChatController *chat = [stack objectAtIndex:at - 1];
    if (![chat showsDialog:_dialog]) return;
    int32_t messageId = cell.item.message.messageId;
    [self.navigationController popViewControllerAnimated:YES];
    [chat jumpToMessageId:messageId];
}

/* the action the setting gives a double tap on a message of this direction; what the message does not allow (the mask) does nothing */
- (void)messageCellDidDoubleTap:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (!message || message.messageId <= 0) return;
    exteria_action_context context = [self actionContextOfMessage:message];
    uint32_t mask = exteria_message_actions_for(&context);
    exteria_message_action action;
    switch (ExteriaChatDoubleTap(message.outgoing)) {
    case ExteriaDoubleTapReaction: [self sendQuickReactionToMessage:message]; return;
    case ExteriaDoubleTapReactionPicker: action = EXTERIA_ACTION_REACT; break;
    case ExteriaDoubleTapTranslate: action = EXTERIA_ACTION_TRANSLATE; break;
    case ExteriaDoubleTapReply: action = EXTERIA_ACTION_REPLY; break;
    case ExteriaDoubleTapForward: action = EXTERIA_ACTION_FORWARD; break;
    case ExteriaDoubleTapSave: action = EXTERIA_ACTION_SAVE; break;
    case ExteriaDoubleTapRepeat: action = EXTERIA_ACTION_REPEAT; break;
    case ExteriaDoubleTapEdit: action = EXTERIA_ACTION_EDIT; break;
    case ExteriaDoubleTapDelete: action = EXTERIA_ACTION_DELETE; break;
    default: return;
    }
    if (mask & action) [self performAction:action onMessage:message];
}

/* a reaction compares by its emoji without the variation selector, since the server writes the heart with it and a keyboard may not */
static NSString *ExteriaBareEmoji(NSString *emoji) {
    return [emoji stringByReplacingOccurrencesOfString:@"\uFE0F" withString:@""];
}

/* the emoji the person chose for the double tap, or the first reaction the chat offers when it is not among them; the list is asked for once, so the first double tap waits for it */
- (void)sendQuickReactionToMessage:(ExteriaMessage *)message {
    if (!message.reactionsPossible || [self reactionsHidden]) return;
    int32_t messageId = message.messageId;
    ExteriaWeakReference *weak = _weak;
    void (^send)(void) = ^{
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        NSString *wanted = ExteriaBareEmoji(ExteriaChatQuickReaction());
        ExteriaReaction *first = nil;
        for (ExteriaReaction *choice in chat->_menuReactions) {
            if (choice.row.kind != EXTERIA_REACTION_EMOJI) continue;
            if ([ExteriaBareEmoji(choice.emoji) isEqualToString:wanted]) {
                [chat chooseReaction:choice messageId:messageId];
                return;
            }
            if (!first) first = choice;
        }
        if (first) [chat chooseReaction:first messageId:messageId];
    };
    if (_menuReactions) send();
    else [self loadMenuReactionsThen:send];
}

- (void)jumpToMessageId:(int32_t)messageId {
    _scrollTarget = messageId;
    _scrollPages = 0;
    [self scrollToTargetOrLoadMore];
}

/* what cannot be undone asks first: a sheet in the modern style, the system alert in the classic one */
- (void)askWithMessage:(NSString *)message action:(NSString *)action tag:(NSInteger)tag {
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirmAction(self, message, action, ^{ [(ExteriaChatController *)weak.target confirmedTag:tag]; });
}

- (void)confirmedTag:(NSInteger)tag {
    if (tag == ExteriaChatAlertStartVoice) {
        [_session.groupCalls startVoiceChatInDialog:_dialog title:nil];
        return;
    }
    if (tag == ExteriaChatAlertDeleteSelected) {
        [self deleteSelectedNow];
        return;
    }
    if (tag == ExteriaChatAlertDeleteMessage) {
        [self deleteMessageNow];
        return;
    }
    BOOL clear = tag == ExteriaChatAlertClear;
    ExteriaWeakReference *weak = _weak;
    [_session performAction:clear ? ExteriaChatCommandClear : ExteriaChatCommandDelete onDialog:_dialog completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
        if (clear) [chat didClearHistory];
        else [chat goBack];
    }];
}

/* the text input of the search is the one alert that is left; the questions about deleting are sheets, or alerts the confirm helper owns */
- (void)alertView:(id)alert clickedButtonAtIndex:(NSInteger)index {
    if (index == [alert cancelButtonIndex] || [alert tag] != ExteriaChatAlertSearch) return;
    [self openSearchResultsFor:[[alert textFieldAtIndex:0] text]];
}

/* what the screen held is gone with the history on the server, and no older page is left to fetch */
- (void)didClearHistory {
    [_server removeAllObjects];
    [_local removeAllObjects];
    [_replyCache removeAllObjects];
    ++_replyGeneration;
    _loadingReplies = NO;
    _oldestId = 0;
    _canLoadMore = NO;
    [self rebuildItems];
    [self showEmptyState];
}

- (void)toast:(NSString *)text {
    _toast.text = text;
    _toast.alpha = 1;
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ _toast.alpha = 0; } completion:nil];
}

- (void)messageCellDidTapShare:(ExteriaMessageCell *)cell {
    int32_t messageId = cell.item.message.messageId;
    if (!_channelFull.username.length) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"chat.share.nolink", nil));
        return;
    }
    [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://t.me/%@/%d", _channelFull.username, (int)messageId];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
}

- (void)messageCellDidTapComments:(ExteriaMessageCell *)cell {
    if (_openingComments || cell.item.message.messageId <= 0) return;
    _openingComments = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadDiscussionOfPost:cell.item.message.messageId dialog:_dialog completion:^(ExteriaDialog *thread, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_openingComments = NO;
        if (!thread) {
            NSLog(@"exteria: post discussion did not load: %@", errorName);
            ExteriaGiftAlert(nil, NSLocalizedString(@"chat.comments.unavailable", nil));
            return;
        }
        if (!chat->_visible) return;
        ExteriaChatController *discussion = [[[ExteriaChatController alloc] initWithSession:chat->_session dialog:thread avatars:chat->_avatars media:chat->_media stickers:chat->_stickers] autorelease];
        [chat.navigationController pushViewController:discussion animated:YES];
    }];
}

- (void)openDiscussion {
    ExteriaDialog *linked = _channelFull.linked;
    if (!linked) return;
    ExteriaChatController *discussion = [[[ExteriaChatController alloc] initWithSession:_session dialog:linked avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:discussion animated:YES];
}

- (void)goBack {
    [_input.textView resignFirstResponder];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark orientation

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

#pragma mark layout

- (CGFloat)panelHeight {
    CGSize windowSize = self.view.window ? self.view.window.bounds.size : [UIScreen mainScreen].bounds.size;
    BOOL landscape = windowSize.width > windowSize.height;
    if (ExteriaIsPad()) return landscape ? 352 : 264;
    return landscape ? 162 : 216;
}

- (void)layoutChat {
    if (_layingOutChat) return;
    _layingOutChat = YES;
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    /* the wallpaper and the bar plate run full width; everything that is read or touched stands in one column, clear of the notch in landscape and no wider
       than a message reads on a tablet */
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_CHAT);
    CGFloat left = column.origin.x, width = column.size.width, edge = CGRectGetMaxX(column);
    /* a classic chat sits under the system's own bar, which the view already starts below or reports in the top inset */
    CGFloat headerHeight = ExteriaThemeIsClassic() ? insets.top : insets.top + BAR_HEIGHT;
    CGFloat pinnedHeight = _pinnedBar.hidden ? 0 : PINNED_HEIGHT;
    CGFloat bottomPad = _keyboardOverlap > 0 ? 0 : insets.bottom;
    BOOL hideReadOnly = _dialog.kind == EXTERIA_DIALOG_CHANNEL && !_input.writable && !_input.actionTitle.length;
    BOOL searching = _searchBar != nil;
    _input.hidden = _pinnedList || hideReadOnly || _selecting || searching;
    CGFloat inputHeight = _pinnedList ? 0 : (searching ? EXTERIA_CHAT_SEARCH_NAV_HEIGHT : (_selecting ? [ExteriaSelectionBar height] : (hideReadOnly ? 0 : [_input preferredHeight])));
    CGFloat inputY = size.height - _keyboardOverlap - bottomPad - inputHeight;
    /* the strip that names what the next send answers or changes stands right over the field, and the list ends above it */
    CGFloat contextHeight = _context.hidden || _pinnedList ? 0 : [ExteriaComposeContext height];
    _context.frame = CGRectMake(left, inputY - contextHeight, width, contextHeight);
    _reactionPicker.frame = self.view.bounds;
    _wallpaper.frame = self.view.bounds;
    _snow.frame = self.view.bounds;
    _foxes.frame = self.view.bounds;
    _header.frame = CGRectMake(0, 0, size.width, headerHeight);
    _headerLine.frame = CGRectMake(0, headerHeight - 1.0 / ExteriaScreenScale(), size.width, 1.0 / ExteriaScreenScale());
    /* the only page of the right pane of a tablet has no left pane to go back to, so the title moves into the room the arrow leaves */
    BOOL alone = ExteriaIsDetailRoot(self);
    CGFloat shift = alone ? 36 : 0;
    _back.hidden = alone;
    _back.frame = CGRectMake(left, insets.top, 52, BAR_HEIGHT);
    _avatar.frame = CGRectMake(left + 48 - shift, insets.top + 5, 34, 34);
    _storyRing.frame = CGRectInset(_avatar.frame, -3, -3);
    _menuButton.frame = CGRectMake(edge - 48, insets.top, 44, BAR_HEIGHT);
    _callButton.frame = CGRectMake(edge - 92, insets.top, 44, BAR_HEIGHT);
    CGFloat textX = left + (_pinnedList ? 60 : 90) - shift, textWidth = edge - textX - (_pinnedList ? 12 : (_callButton ? 100 : 56));
    BOOL hasStatus = _subtitle.text.length > 0;
    _title.font = ExteriaFontSemibold(17);
    _subtitle.font = ExteriaFontRegular(13);
    _title.frame = CGRectMake(textX, insets.top + (hasStatus ? 4 : 11), textWidth, 22);
    _subtitle.frame = CGRectMake(textX, insets.top + 25, textWidth, 16);
    _input.frame = CGRectMake(left, inputY, width, inputHeight + bottomPad);
    _searchBar.frame = CGRectMake(0, 0, size.width, headerHeight - 1.0 / ExteriaScreenScale());
    _searchNav.frame = CGRectMake(left, inputY, width, inputHeight + bottomPad);
    _selectionBar.frame = _input.frame;
    BOOL wasBottom = _stickToBottom;
    CGRect previousViewport = _table.frame;
    CGFloat previousOffset = _table.contentOffset.y;
    _pinnedBar.frame = CGRectMake(left, headerHeight, width, pinnedHeight);
    _pinnedTitle.font = ExteriaFontSemibold(13);
    _pinnedText.font = ExteriaFontRegular(14);
    CGFloat pinnedX = _pinnedThumb.hidden ? 24 : 24 + 34 + 10;
    CGFloat pinnedRight = _pinnedListButton.hidden ? 12 : 52;
    _pinnedThumb.frame = CGRectMake(24, (PINNED_HEIGHT - 34) / 2, 34, 34);
    _pinnedListButton.frame = CGRectMake(width - 48, 0, 44, PINNED_HEIGHT);
    _pinnedTitle.frame = CGRectMake(pinnedX, 6, width - pinnedX - pinnedRight, 17);
    _pinnedText.frame = CGRectMake(pinnedX, 24, width - pinnedX - pinnedRight, 18);
    _toEnd.frame = CGRectMake(CGRectGetMaxX(column) - 56, inputY - contextHeight - 56, 44, 44);
    [self placeReactionJump];
    CGSize hintSize = [_nextHint sizeThatFits:CGSizeMake(width, 0)];
    _nextHint.frame = CGRectMake(CGRectGetMidX(column) - hintSize.width / 2, inputY - contextHeight - hintSize.height - 12, hintSize.width, hintSize.height);
    _toast.frame = CGRectMake(CGRectGetMidX(column) - 60, headerHeight + pinnedHeight + 10, 120, 28);
    headerHeight += pinnedHeight;
    CGFloat voiceHeight = _voiceBar.hidden ? 0 : VOICE_HEIGHT;
    _voiceBar.frame = CGRectMake(left, headerHeight, width, voiceHeight);
    _voiceTitle.font = ExteriaFontSemibold(14);
    _voiceInfo.font = ExteriaFontRegular(12);
    _voiceJoin.font = ExteriaFontSemibold(13);
    _voiceJoin.frame = CGRectMake(width - 112, (VOICE_HEIGHT - 28) / 2, 100, 28);
    _voiceTitle.frame = CGRectMake(24, 5, width - 150, 18);
    _voiceInfo.frame = CGRectMake(24, 23, width - 150, 16);
    headerHeight += voiceHeight;
    /* on a tablet the chat list beside the chat already shows the strip, and a second one would stand over the messages */
    BOOL listHasStrip = ExteriaListShowsPlayer(self);
    CGFloat playerHeight = _miniPlayer.showing && !listHasStrip ? [ExteriaMiniPlayer height] : 0;
    _miniPlayer.hidden = !_miniPlayer.showing || listHasStrip;
    _miniPlayer.frame = CGRectMake(left, headerHeight, width, playerHeight);
    headerHeight += playerHeight;
    CGRect viewport = CGRectMake(left, headerHeight, width, MAX(0, inputY - contextHeight - headerHeight));
    if (!CGRectEqualToRect(_table.frame, viewport)) _table.frame = viewport;
    UIView *suggestions = _bots.panel;
    if (suggestions) {
        CGFloat room = [_bots panelHeightForWidth:width maxHeight:MAX(0, inputY - headerHeight)];
        suggestions.frame = CGRectMake(left, inputY - room, width, room);
    }
    [_bots layoutCardInRect:CGRectMake(left, headerHeight, width, MAX(0, inputY - headerHeight))];
    UIEdgeInsets contentInset = UIEdgeInsetsMake(6, 0, 6, 0);
    if (!UIEdgeInsetsEqualToEdgeInsets(_table.contentInset, contentInset)) _table.contentInset = contentInset;
    CGPoint middle = CGPointMake(CGRectGetMidX(column), headerHeight + (inputY - headerHeight) / 2);
    CGSize fit = [_status sizeThatFits:CGSizeMake(MIN(width - 64, 420), 200)];
    _status.font = ExteriaFontRegular(16);
    _status.frame = CGRectMake(middle.x - fit.width / 2, middle.y - fit.height / 2 - (_retry.hidden ? 0 : 22), fit.width, fit.height);
    if (_premiumGate) {
        CGSize gate = [_premiumGate cardSizeForWidth:width];
        _premiumGate.frame = CGRectMake(middle.x - gate.width / 2, middle.y - gate.height / 2, gate.width, gate.height);
    }
    if (_greeting) {
        _greeting.hidden = _items.count > 0 || _premiumGate != nil;
        CGSize card = [_greeting cardSizeForWidth:width];
        _greeting.frame = CGRectMake(middle.x - card.width / 2, middle.y - card.height / 2, card.width, card.height);
    }
    _retry.titleLabel.font = ExteriaFontSemibold(17);
    _retry.frame = CGRectMake(middle.x - 70, CGRectGetMaxY(_status.frame) + 8, 140, 40);
    if (width != _laidOutWidth) {
        _laidOutWidth = width;
        for (ExteriaChatItem *item in _items) [item invalidateLayout];
        [_table reloadData];
    }
    BOOL touching = _interacting || _table.dragging || _table.decelerating;
    if (wasBottom && !touching && !CGRectEqualToRect(previousViewport, _table.frame)) {
        [self scrollToBottomAnimated:NO];
    } else if (!wasBottom && !touching && _items.count && previousViewport.size.width == _table.frame.size.width) {
        CGFloat shrink = previousViewport.size.height - _table.frame.size.height;
        if (shrink != 0) {
            [_table layoutIfNeeded];
            double next = 0;
            /* UIKit may already clamp the offset when the keyboard closes, so adding the height to its new offset moves twice */
            exteria_status status = exteria_scroll_resize(previousOffset, previousViewport.size.height, _table.bounds.size.height,
                                                          [self scrollLimitMin], [self scrollLimitMax], &next);
            if (status == EXTERIA_OK) [_table setContentOffset:CGPointMake(0, (CGFloat)next) animated:NO];
            else NSLog(@"exteria: chat viewport resize failed: %s", exteria_status_name(status));
        }
    }
    if (!CGRectEqualToRect(previousViewport, _table.frame))
        exteria_scroll_begin(&_scroll, _table.contentOffset.y, CFAbsoluteTimeGetCurrent());
    _layingOutChat = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_panel) {
        CGFloat width = _panel.superview ? _panel.superview.bounds.size.width : self.view.window.bounds.size.width;
        if (width <= 0) width = [UIScreen mainScreen].bounds.size.width;
        CGRect frame = _panel.frame;
        frame.size = CGSizeMake(width, [self panelHeight]);
        if (!CGRectEqualToRect(frame, _panel.frame)) _panel.frame = frame;
    }
    [self layoutChat];
}

- (void)inputBarDidChangeHeight:(ExteriaInputBar *)bar {
    (void)bar;
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
}

#pragma mark keyboard

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _visible = YES;
    [self rebuildItems];
    [self refreshVoiceChat];
    ExteriaNotifierSetOpenChat(_dialog.peerKind, _dialog.peerId);
    if (!_reactionTimer) {
        ExteriaReactionPollTarget *target = [[[ExteriaReactionPollTarget alloc] initWithReference:_weak] autorelease];
        _reactionTimer = [[NSTimer scheduledTimerWithTimeInterval:20 target:target selector:@selector(fire:) userInfo:nil repeats:YES] retain];
    }
    if (!_observing) {
        _observing = YES;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(applicationBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(applicationResignedActive) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(refreshStatusLine) name:ExteriaSessionConnectionDidChangeNotification object:_session];
        [center addObserver:self selector:@selector(typingChanged:) name:ExteriaTypingDidChangeNotification object:_session.typing];
    }
    [self refreshStatusLine];
    [self startRaiseToSpeak];
    /* a swipe that carried on while another screen covered the list may never report its end */
    if (_interacting && !_table.dragging && !_table.decelerating) [self scrollSettled];
    [self flushLiveMessages];
    [self refreshAnimations];
    [_snow start];
    [_foxes start];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    [self stopFollowingBottom];
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
    [_snow stop];
    [_foxes stop];
    ExteriaNotifierSetOpenChat(0, 0);
    [self stopRaiseToSpeak];
    [self discardRecording];
    [_reactionTimer invalidate];
    [_reactionTimer release];
    _reactionTimer = nil;
    [self closeReactionPicker];
    [self stopAnimations];
    [self saveDraftNow];
    if ([self isMovingFromParentViewController]) {
        [_session stopWatchingForOwner:self];
        if (_closeHandler) _closeHandler();
    }
}

#pragma mark raise to speak

/* with "raise to speak" the phone held to the ear in a chat records a voice message and lowering it sends it */
- (void)startRaiseToSpeak {
    if (_raiseWatching || !ExteriaChatRaiseToSpeak() || !_input.writable) return;
    if (!ExteriaProximityStart()) return;
    _raiseWatching = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(raiseChanged) name:ExteriaProximityDidChangeNotification object:nil];
}

- (void)stopRaiseToSpeak {
    if (!_raiseWatching) return;
    _raiseWatching = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaProximityDidChangeNotification object:nil];
    if (_raiseRecording) {
        _raiseRecording = NO;
        [_input endRaisedRecordingCancelled:YES];
    }
    ExteriaProximityStop();
}

- (void)raiseChanged {
    BOOL near = ExteriaProximityNear();
    if (near && !_raiseRecording) {
        if (!ExteriaPhoneIsUpright() || [ExteriaMusicPlayer sharedPlayer].state == ExteriaMusicStatePlaying) return;
        if ([_input beginRaisedRecording]) _raiseRecording = YES;
    } else if (!near && _raiseRecording) {
        _raiseRecording = NO;
        [_input endRaisedRecordingCancelled:NO];
    }
}

- (void)applicationBecameActive {
    if (_visible) [self rebuildItems];
    [self flushLiveMessages];
    [self refreshAnimations];
    if (_visible) {
        [_snow start];
        [_foxes start];
    }
    [self markReadIfNeeded];
    [self pollReactions];
}

- (void)timesChanged {
    [_itemCache removeAllObjects];
    [self rebuildItems];
}

- (void)applicationResignedActive {
    [self saveDraftNow];
    [self stopAnimations];
    [self stopFollowingBottom];
    [_snow stop];
    [_foxes stop];
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
}

- (void)keyboardChanged:(NSNotification *)note {
    UIWindow *window = self.view.window;
    if (!window) return;
    NSDictionary *info = note.userInfo;
    CGFloat overlap = 0;
    if ([note.name isEqualToString:UIKeyboardWillChangeFrameNotification]) {
        CGRect end = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGRect inView = [self.view convertRect:[window convertRect:end fromWindow:nil] fromView:window];
        overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    }
    /* a hide is announced twice (the frame change and the hide), and a second animation over the first one only restarts it */
    if (overlap == _keyboardOverlap) return;
    _keyboardOverlap = overlap;
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSInteger curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    /* the offset UIKit clamps while the table is resized, and a page of messages that lands in the middle of the slide, both read as the chat jumping */
    _keyboardMoving = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(keyboardSettled) object:nil];
    [self performSelector:@selector(keyboardSettled) withObject:nil afterDelay:duration + 0.05];
    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{ [self layoutChat]; } completion:nil];
}

- (void)keyboardSettled {
    _keyboardMoving = NO;
    if (_livePending) [self scheduleLiveMessages];
}

- (void)inputBarDidBeginEditing:(ExteriaInputBar *)bar {
    (void)bar;
    /* a person reading old messages keeps their place when they tap the field */
    if (_stickToBottom) [self scrollToBottomAnimated:NO];
}

#pragma mark panel

- (void)dismissInput {
    if (_panelShown) {
        _panelShown = NO;
        _input.panelShown = NO;
        _input.textView.inputView = nil;
    }
    [_input.textView resignFirstResponder];
}

- (ExteriaInputPanel *)panel {
    if (!_panel) {
        _panel = [[ExteriaInputPanel alloc] initWithMedia:_media library:_stickers];
        _panel.delegate = self;
        CGFloat width = self.view.window ? self.view.window.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
        _panel.frame = CGRectMake(0, 0, width, [self panelHeight]);
        _panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [_panel enableGifsWithSession:_session media:_media library:_stickers dialog:_dialog];
        /* only a Premium account may write custom emoji, so the tab waits for the answer about the signed in user */
        ExteriaWeakReference *weak = _weak;
        [self whenPremiumKnown:^(BOOL premium) {
            ExteriaChatController *chat = weak.target;
            if (chat && premium) [chat->_panel enableCustomEmojiWithSession:chat->_session media:chat->_media];
        }];
    }
    return _panel;
}

- (void)inputBarDidTapPanelButton:(ExteriaInputBar *)bar {
    [_bots emojiPanelWillChange];
    _panelShown = !_panelShown;
    bar.panelShown = _panelShown;
    UITextView *text = bar.textView;
    text.inputView = _panelShown ? [self panel] : nil;
    if ([text isFirstResponder]) [text reloadInputViews];
    else [text becomeFirstResponder];
}

- (void)inputPanel:(ExteriaInputPanel *)panel didPickEmoji:(NSString *)emoji {
    (void)panel;
    [_input insertEmoji:emoji];
}

- (void)inputPanel:(ExteriaInputPanel *)panel didPickCustomEmoji:(ExteriaCustomEmojiDocument *)emoji {
    (void)panel;
    [_input insertCustomEmoji:emoji.documentId alt:emoji.alt];
}

- (void)inputPanelDidTapBackspace:(ExteriaInputPanel *)panel {
    (void)panel;
    [_input deleteBackwardFromPicker];
}

- (void)inputPanel:(ExteriaInputPanel *)panel didPickSticker:(ExteriaSticker *)sticker {
    (void)panel;
    [self sendSticker:sticker.media];
}

/* an animation goes out the way a sticker does: a document of the server, named by its reference */
- (void)inputPanel:(ExteriaInputPanel *)panel didPickGif:(ExteriaMedia *)gif {
    (void)panel;
    [self sendSticker:gif];
}

- (void)inputPanel:(ExteriaInputPanel *)panel didPickInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId {
    (void)panel;
    ExteriaWeakReference *weak = _weak;
    int32_t replyTo = _replyToId;
    [self cancelCompose];
    [_session sendInlineResult:result queryId:queryId toDialog:_dialog randomId:[self newRandomId] replyTo:replyTo completion:^(int32_t messageId, NSString *errorName) {
        (void)messageId;
        ExteriaChatController *chat = weak.target;
        if (chat && errorName) ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
    }];
}

- (void)inputPanelDidTapCreateSticker:(ExteriaInputPanel *)panel {
    (void)panel;
    [ExteriaStickerMaker startWithSession:_session host:self done:nil];
}

#pragma mark loading

/* a chat with a person says so with a greeting to send; every other chat keeps the plain line */
- (void)showEmptyState {
    BOOL person = _dialog.kind == EXTERIA_DIALOG_USER && !_dialog.saved && !_pinnedList;
    /* a bot's empty chat has its card and the start button instead */
    if (_dialog.kind == EXTERIA_DIALOG_BOT && !_pinnedList) {
        [self showStatus:@"" retry:NO];
        return;
    }
    if (!person) {
        [self showStatus:NSLocalizedString(@"chat.empty", nil) retry:NO];
        return;
    }
    [self showStatus:@"" retry:NO];
    if (!_greeting) {
        _greeting = [[ExteriaGreetingView alloc] initWithMedia:_media];
        ExteriaWeakReference *weak = _weak;
        _greeting.onSend = ^(ExteriaSticker *sticker) {
            ExteriaChatController *chat = weak.target;
            if (chat) [chat sendSticker:sticker.media];
        };
        [self.view addSubview:_greeting];
    }
    if (_greetingAsked) return;
    _greetingAsked = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadGreetingStickers:^(NSArray *stickers, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!stickers) {
            NSLog(@"exteria: greeting stickers did not load: %@", errorName);
            return;
        }
        [chat->_greeting showStickers:stickers];
    }];
}

/* a person who takes messages only from Premium users closes the input of anyone who is not one: the card says why, and the bar says it in a line */
- (void)loadPremiumGate {
    if (_dialog.kind != EXTERIA_DIALOG_USER || _dialog.saved) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadPremiumGateOfDialog:_dialog completion:^(BOOL blocked) {
        ExteriaChatController *chat = weak.target;
        if (!chat || !blocked || chat->_premiumGate) return;
        chat->_premiumGate = [[ExteriaPremiumGateView alloc] initWithName:chat->_dialog.title];
        [chat.view addSubview:chat->_premiumGate];
        chat->_input.writable = NO;
        chat->_input.readOnlyNote = [NSString stringWithFormat:NSLocalizedString(@"chat.premium.note", nil), chat->_dialog.title];
        [chat.view setNeedsLayout];
    }];
}

- (void)showStatus:(NSString *)text retry:(BOOL)retry {
    _status.text = text;
    _status.hidden = text.length == 0;
    _retry.hidden = !retry;
    [self.view setNeedsLayout];
}

- (void)loadNewest {
    if (_pinnedList) {
        if (!_loading) [self loadPinnedList];
        return;
    }
    if (_loading) return;
    _loading = YES;
    [self showStatus:nil retry:NO];
    ExteriaWeakReference *weak = _weak;
    /* the page kept on disk shows while the network works, and stays if the network fails */
    [_session loadCachedHistoryOfDialog:_dialog completion:^(NSArray *kept, NSDictionary *people, NSString *errorName) {
        (void)errorName;
        ExteriaChatController *chat = weak.target;
        if (chat) [chat showKeptMessages:kept people:people];
    }];
    [_session loadHistoryOfDialog:_dialog beforeId:0 limit:HISTORY_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        [chat didLoadNewest:messages people:people error:errorName];
    }];
}

- (NSString *)failureTextForError:(NSString *)name {
    if ([name isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([name isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), name];
}

- (void)showKeptMessages:(NSArray *)kept people:(NSDictionary *)people {
    if (!kept.count || _loadedFirst || _server.count) return;
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:kept];
    [self rebuildItems];
    if (_stickToBottom && _startMessageId <= 0) [self scrollToBottomAnimated:NO];
    _table.hidden = NO;
    /* a network failure can arrive before the cached page */
    [self showStatus:nil retry:NO];
}

- (void)didLoadNewest:(NSArray *)messages people:(NSDictionary *)people error:(NSString *)errorName {
    _loading = NO;
    if (!messages && _server.count) {
        NSLog(@"exteria: chat %lld stays on the kept page, refresh failed: %@", _dialog.peerId, errorName);
        _opening = NO;
        return;
    }
    if (!messages) {
        _opening = NO;
        [self showStatus:[self failureTextForError:errorName] retry:YES];
        return;
    }
    _loadedFirst = YES;
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    _canLoadMore = messages.count >= HISTORY_PAGE;
    if (!messages.count) [self showEmptyState];
    [self rebuildItems];
    /* the list that followed its end already stands on it; this makes sure of the position once the real sizes are in, before anything may animate */
    if (_stickToBottom && _startMessageId <= 0) [self scrollToBottomAnimated:NO];
    _table.hidden = NO;
    _opening = NO;
    if (_startMessageId > 0) {
        /* a bookmark opened this chat: it goes to its message, loading older pages when that one is not in the newest */
        int32_t target = _startMessageId;
        _startMessageId = 0;
        [self jumpToMessageId:target];
    }
    [self markReadIfNeeded];
    ExteriaWeakReference *weak = _weak;
    [_session watchDialog:_dialog owner:self peopleHandler:^(NSArray *page, NSDictionary *people) {
        ExteriaChatController *chat = weak.target;
        if (chat) {
            [chat->_people addEntriesFromDictionary:people];
            [chat storeDidChange:page];
        }
    }];
    [self pollReactions];
}

- (void)loadOlder {
    /* the offset a list passes through while it settles on the newest message would ask for older rows, which then move it again */
    if (_loadingOlder || _olderDeferred || !_canLoadMore || !_loadedFirst || _opening || _oldestId <= 1) return;
    _loadingOlder = YES;
    NSUInteger token = _windowToken;
    ExteriaWeakReference *weak = _weak;
    [_session loadHistoryOfDialog:_dialog beforeId:_oldestId limit:HISTORY_PAGE completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        /* a page asked for before the list moved to another stretch of history belongs to the old one */
        if (!chat || token != chat->_windowToken) return;
        [chat didLoadOlder:messages people:people error:errorName];
    }];
}

- (void)didLoadOlder:(NSArray *)messages people:(NSDictionary *)people error:(NSString *)errorName {
    _loadingOlder = NO;
    if (!messages) {
        /* the list stays as it is and the next scroll to the top asks again */
        NSLog(@"exteria: older messages of chat %lld not loaded: %@", _dialog.peerId, errorName);
        return;
    }
    [_people addEntriesFromDictionary:people];
    [self mergeMessages:messages];
    _canLoadMore = messages.count >= HISTORY_PAGE;
    /* putting rows above the ones in view moves the offset, and moving the offset ends the momentum of a swipe */
    if (_table.dragging || _table.decelerating) {
        _olderDeferred = YES;
        return;
    }
    [self showOlder];
}

- (void)showOlder {
    _olderDeferred = NO;
    [self rebuildItems];
    [self scrollToTargetOrLoadMore];
}

/* the live page of the store: it is the truth for the ids it spans, so a message of those ids that is missing from it was
   deleted, and what it holds replaces what is here */
- (void)storeDidChange:(NSArray *)page {
    if (!_loadedFirst || !page.count) return;
    if (_window) {
        /* the live page of the store is the end of the chat, which a window around an old message is not next to: only a change of a message the window holds
           is taken, so edits and reactions show while the new messages wait for the list to reach them */
        NSMutableArray *held = [NSMutableArray array];
        for (ExteriaMessage *message in page) if ([_server objectForKey:[NSNumber numberWithInt:message.messageId]]) [held addObject:message];
        if (held.count) {
            [self mergeMessages:held];
            [self scheduleLiveMessages];
        }
        return;
    }
    int32_t lowest = INT32_MAX;
    NSMutableSet *present = [NSMutableSet set];
    for (ExteriaMessage *message in page) {
        lowest = MIN(lowest, message.messageId);
        [present addObject:[NSNumber numberWithInt:message.messageId]];
    }
    /* a message is gone when the store held it and holds it no more */
    NSMutableArray *missing = [NSMutableArray array];
    for (NSNumber *key in _storeIds) {
        if ([key intValue] >= lowest && ![present containsObject:key] && [_server objectForKey:key]) [missing addObject:key];
    }
    /* a page read in the middle of a burst of writes can lack a message that is there a moment later, and a message dropped on that word alone vanished from the
       screen in a spam; the server is asked, and only what it does not have any more goes */
    [self confirmGoneMessages:missing];
    if (!_storeIds) _storeIds = [[NSMutableSet alloc] init];
    [_storeIds setSet:present];
    int32_t knownTop = 0;
    for (NSNumber *key in [_server allKeys]) knownTop = MAX(knownTop, [key intValue]);
    [self mergeMessages:page];
    BOOL newest = NO, arrived = NO, pinChanged = NO;
    for (ExteriaMessage *message in page) {
        /* somebody pinned a message: the bar at the top was made when the chat opened, so it is made again */
        if (message.messageId > knownTop && message.service == (int)EXTERIA_SERVICE_PIN + 1) pinChanged = YES;
        if (message.messageId > _markedRead && !message.outgoing) newest = YES;
        /* only a message past everything the screen held is news, so a refresh of the page makes no sound */
        if (message.messageId > knownTop && !message.outgoing) arrived = YES;
    }
    [self scheduleLiveMessages];
    if (pinChanged && _dialog.peerKind == 3 && !_pinnedList) [self loadChannelFull];
    if (newest) {
        [self markReadIfNeeded];
    }
    if (arrived && _visible && !_voice) ExteriaPlayInChatSound(YES);
}

/* asks the server for messages the store stopped showing; a failed ask leaves the list as it is */
- (void)confirmGoneMessages:(NSArray *)ids {
    if (!ids.count) return;
    if (!_confirmingGone) _confirmingGone = [[NSMutableSet alloc] init];
    NSMutableArray *asked = [NSMutableArray array];
    for (NSNumber *key in ids) {
        if ([_confirmingGone containsObject:key] || asked.count >= 100) continue;
        [asked addObject:key];
        [_confirmingGone addObject:key];
    }
    if (!asked.count) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadMessagesWithIds:asked ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        for (NSNumber *key in asked) [chat->_confirmingGone removeObject:key];
        if (!messages) {
            NSLog(@"exteria: the messages missing from the store were not confirmed: %@", errorName);
            return;
        }
        NSMutableSet *held = [NSMutableSet set];
        for (ExteriaMessage *message in messages) [held addObject:[NSNumber numberWithInt:message.messageId]];
        for (NSNumber *key in asked) if (![held containsObject:key]) [chat->_server removeObjectForKey:key];
        [chat mergeMessages:messages];
        [chat scheduleLiveMessages];
    }];
}

- (void)messageCell:(ExteriaMessageCell *)cell answerSharingRequest:(BOOL)accept {
    ExteriaMessage *message = cell.item.message;
    if (message.service != EXTERIA_SERVICE_SHARING_REQUEST + 1 || message.outgoing || [self sharingExpired:message] || message.messageId <= 0) return;
    NSNumber *key = [NSNumber numberWithInt:message.messageId];
    if ([_sharingBusy containsObject:key]) return;
    BOOL restricted = accept ? (message.serviceValue & 2) != 0 : (message.serviceValue & 1) != 0;
    ExteriaWeakReference *weak = _weak;
    ExteriaConfirm(nil, NSLocalizedString(accept ? @"chat.sharing.accept.confirm" : @"chat.sharing.decline.confirm", nil),
                   NSLocalizedString(accept ? @"chat.sharing.accept" : @"chat.sharing.decline", nil), ^{
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if ([chat sharingExpired:message]) { [chat rebuildItems]; return; }
        if (!chat->_sharingBusy) chat->_sharingBusy = [[NSMutableSet alloc] init];
        if ([chat->_sharingBusy containsObject:key]) return;
        [chat->_sharingBusy addObject:key];
        [chat->_session setSharingRestricted:restricted ofDialog:chat->_dialog requestId:key.intValue completion:^(NSString *errorName) {
            ExteriaChatController *current = weak.target;
            if (!current) return;
            [current->_sharingBusy removeObject:key];
            if (errorName) {
                ExteriaShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"chat.sharing.error", nil), errorName]);
                return;
            }
            [current->_session loadMessagesWithIds:[NSArray arrayWithObject:key] ofDialog:current->_dialog completion:^(NSArray *messages, NSString *error) {
                ExteriaChatController *owner = weak.target;
                if (!owner) return;
                if (error) { ExteriaShowNotice(nil, [owner failureTextForError:error]); return; }
                [owner mergeMessages:messages];
                [owner scheduleLiveMessages];
            }];
        }];
    });
}

/* a burst of updates shares one table transaction per frame; a drag keeps its rows until the finger settles */
- (void)scheduleLiveMessages {
    _livePending = YES;
    if (_liveLink || !_visible || _interacting || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    ExteriaReactionPollTarget *target = [[[ExteriaReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _liveLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(display:)] retain];
    _liveLink.frameInterval = 2;
    [_liveLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)flushLiveMessages {
    if ([self replySwipeActive]) return;
    [_liveLink invalidate];
    [_liveLink release];
    _liveLink = nil;
    if (!_livePending || _interacting || !_visible || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    _livePending = NO;
    [self rebuildItems];
}

/* a message of the favorites with no origin in its answer is one of the account's own notes */
- (BOOL)message:(ExteriaMessage *)message isFromSavedSource:(ExteriaDialog *)source {
    if (!message.savedPeerKind) return source.saved;
    return message.savedPeerKind == source.peerKind && message.savedPeerId == source.peerId;
}

- (void)mergeMessages:(NSArray *)messages {
    [_media noteMessages:messages ofDialog:_dialog];
    for (ExteriaMessage *message in messages) {
        if (message.messageId <= 0) continue;
        if (_dialog.saved) [message placeInSavedMessagesOfUser:_dialog.peerId];
        if (_dialog.savedSource && ![self message:message isFromSavedSource:_dialog.savedSource]) continue;
        [_server setObject:message forKey:[NSNumber numberWithInt:message.messageId]];
        _oldestId = _oldestId ? MIN(_oldestId, message.messageId) : message.messageId;
    }
    /* a message sent from here is replaced by the server's copy of it as soon as that arrives */
    for (ExteriaMessage *local in [[_local copy] autorelease]) {
        if (local.messageId > 0 && [_server objectForKey:[NSNumber numberWithInt:local.messageId]]) [_local removeObject:local];
    }
}

- (void)markReadIfNeeded {
    if (_window) return;
    [self scheduleVisibleMentionsRead];
    int32_t newest = 0;
    for (ExteriaMessage *message in [_server allValues]) if (!message.outgoing && message.messageId > newest) newest = message.messageId;
    if (newest <= _markedRead || newest <= _dialog.readInboxMaxId || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    _markedRead = newest;
    [_session markDialogRead:_dialog upTo:newest];
}

- (void)scheduleVisibleMentionsRead {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markVisibleMentionsRead) object:nil];
    [self performSelector:@selector(markVisibleMentionsRead) withObject:nil afterDelay:0];
}

- (void)markVisibleMentionsRead {
    if (!_visible || _pinnedList || ExteriaChatFlagGet(ExteriaChatFlagGhostNoRead) || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        ExteriaMessage *message = ((ExteriaChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (!message.unreadMention || message.outgoing || message.messageId <= 0 || [_readMentionIds containsObject:key]) continue;
        [ids addObject:key];
        [_readMentionIds addObject:key];
        if (ids.count == EXTERIA_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    ExteriaWeakReference *weak = _weak;
    [_session markMentionsRead:ids dialog:_dialog completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) [chat->_readMentionIds minusSet:[NSSet setWithArray:ids]];
        else [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
    }];
}

#pragma mark items

typedef struct { int64_t key; NSUInteger index; } ExteriaMessageOrder;

/* the index breaks a tie, so two messages with one id keep the order they were collected in */
static int ExteriaCompareMessageOrder(const void *first, const void *second) {
    const ExteriaMessageOrder *a = first, *b = second;
    if (a->key != b->key) return a->key < b->key ? -1 : 1;
    return a->index < b->index ? -1 : (a->index > b->index);
}

/* the server's messages and the ones only this screen knows, in the order the chat has them: by id, and a message that has
   no id yet after all of those, in the order it was written */
- (NSArray *)orderedMessages {
    NSArray *server = [_server allValues];
    /* a message on its way belongs to the end of the chat, which a window around an old message does not show */
    NSArray *local = _window ? [NSArray array] : _local;
    NSUInteger count = server.count + local.count;
    ExteriaMessageOrder *order = malloc(sizeof(ExteriaMessageOrder) * (count ? count : 1));
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:count];
    if (!order) {
        NSLog(@"exteria: no memory to order %lu messages", (unsigned long)count);
        return all;
    }
    [all addObjectsFromArray:server];
    [all addObjectsFromArray:local];
    for (NSUInteger i = 0; i < count; ++i) {
        ExteriaMessage *message = [all objectAtIndex:i];
        order[i].index = i;
        order[i].key = message.messageId > 0 ? message.messageId : INT64_MAX / 2 + (int64_t)(i - server.count);
    }
    qsort(order, count, sizeof(*order), ExteriaCompareMessageOrder);
    NSMutableArray *sorted = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; ++i) {
        ExteriaMessage *message = [all objectAtIndex:order[i].index];
        /* a message of someone else whose text a filter of the person matches is not shown */
        if (message.messageId > 0 && !message.outgoing && ExteriaAyuHidesText(message.text)) continue;
        [sorted addObject:message];
    }
    free(order);
    return sorted;
}

/* a pending message keeps its random id after the server numbers it; a clash between the two spaces only costs a rebuild,
   since reflectsMessage: compares both ids */
- (NSNumber *)cacheKeyForMessage:(ExteriaMessage *)message {
    return [NSNumber numberWithLongLong:message.randomId ? message.randomId : (long long)message.messageId];
}

/* one number per calendar day, so a list compares days with one components call per message */
static NSInteger ExteriaDayKey(NSCalendar *calendar, int32_t date) {
    NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
                                          fromDate:[NSDate dateWithTimeIntervalSince1970:date]];
    return parts.year * 10000 + parts.month * 100 + parts.day;
}

/* two messages share a run when the same side wrote both within a few minutes of each other on one day */
- (BOOL)message:(ExteriaMessage *)a joins:(ExteriaMessage *)b {
    if (a.service || b.service || a.outgoing != b.outgoing || a.senderKey != b.senderKey) return NO;
    int32_t gap = a.date > b.date ? a.date - b.date : b.date - a.date;
    return gap < GROUP_GAP_SECONDS;
}

/* custom emoji in the texts and the custom reactions on the messages; their pictures are fetched once, and the
   ordinary emoji each stands for is what a reaction chip shows until its picture is in memory */
/* the name of a private chat is followed by the custom emoji status of the other side, or the Premium star; the picture is fetched once
   and the title is drawn again when it lands */
/* the ids of the developers arrive after the screen is up: the hammers of the title and of the names in the bubbles are decided again */
/* what the dialog said when it was listed, or what an update told since */
- (int32_t)readOutboxMaxId {
    return MAX(_dialog.readOutboxMaxId, [_session readOutboxOfKind:_dialog.peerKind peer:_dialog.peerId]);
}

- (void)readOutboxChanged:(NSNotification *)note {
    if ([[note.userInfo objectForKey:@"kind"] intValue] != _dialog.peerKind || [[note.userInfo objectForKey:@"peer"] longLongValue] != _dialog.peerId) return;
    if (_loadedFirst) [self rebuildItems];
}

/* the ring on the cross of a message that is going up; the row is touched in place, since a rebuild of the list for every part of a file would redraw the screen */
- (void)uploadProgressed:(NSNotification *)note {
    long long randomId = [[note.userInfo objectForKey:@"randomId"] longLongValue];
    float fraction = [[note.userInfo objectForKey:@"fraction"] floatValue];
    for (ExteriaMessage *message in _local) {
        if (message.randomId != randomId) continue;
        message.uploadProgress = fraction;
        for (ExteriaMessageCell *cell in _table.visibleCells) {
            if ([cell isKindOfClass:[ExteriaMessageCell class]] && cell.item.message == message) [cell showUploadProgress];
        }
        return;
    }
}

- (void)developersChanged {
    [self showTitleBadge];
    if (_loadedFirst) [self rebuildItems];
}

- (void)showTitleBadge {
    long long badge = ExteriaDialogBadgeDocument(_dialog);
    NSArray *entities = nil;
    _title.text = ExteriaNameWithBadges(_dialog.title, badge, ExteriaDialogIsDeveloper(_dialog), &entities);
    _title.entities = entities;
    if (!_dialog.emojiStatus) return;
    ExteriaWeakReference *weak = _weak;
    ExteriaLoadBadgePictures([NSArray arrayWithObject:[NSNumber numberWithLongLong:_dialog.emojiStatus]], _session, _media, ^{
        ExteriaChatController *chat = weak.target;
        if (chat) [chat->_title setNeedsDisplay];
    });
}

- (void)loadCustomEmoji {
    NSMutableArray *wanted = [NSMutableArray array];
    for (ExteriaMessage *message in [_server allValues]) {
        for (ExteriaTextEntity *entity in message.entities) {
            if (entity.style == ExteriaTextStyleCustomEmoji && entity.documentId) [wanted addObject:[NSNumber numberWithLongLong:entity.documentId]];
        }
        for (ExteriaReaction *reaction in message.reactions) {
            long long document = reaction.row.document_id;
            if (reaction.row.kind == EXTERIA_REACTION_CUSTOM && document) [wanted addObject:[NSNumber numberWithLongLong:document]];
        }
    }
    /* the statuses that follow the names of the people who wrote */
    for (ExteriaPerson *person in [_people allValues]) {
        if (person.emojiStatus) [wanted addObject:[NSNumber numberWithLongLong:person.emojiStatus]];
    }
    if (!wanted.count) return;
    ExteriaWeakReference *weak = _weak;
    [ExteriaCustomEmojiLoader loadDocuments:wanted session:_session media:_media documents:^(NSArray *documents) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        NSMutableDictionary *texts = [NSMutableDictionary dictionaryWithCapacity:documents.count];
        for (ExteriaCustomEmojiDocument *document in documents) [texts setObject:document.alt forKey:[NSNumber numberWithLongLong:document.documentId]];
        [ExteriaReaction rememberCustomTexts:texts];
        [chat->_itemCache removeAllObjects];
        [chat rebuildItems];
    } picture:^{
        ExteriaChatController *chat = weak.target;
        if (chat) [chat redrawVisibleCells];
    }];
}

/* a picture that arrives changes no size, so the rows on screen are only drawn again */
static void ExteriaRedrawTree(UIView *view) {
    [view setNeedsDisplay];
    for (UIView *child in view.subviews) ExteriaRedrawTree(child);
}

- (void)redrawVisibleCells {
    for (UITableViewCell *cell in _table.visibleCells) ExteriaRedrawTree(cell.contentView);
}

/* this account as a person, for the chips that show who reacted; the chips keep their number until it arrives */
- (void)loadSelfPerson {
    /* asked once per screen: a failed answer leaves the numbers, and no rebuild asks again */
    if (_selfPerson || _selfPersonAsked) return;
    _selfPersonAsked = YES;
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!items.count) {
            NSLog(@"exteria: this account's picture for the reactions did not load: %@", errorName);
            return;
        }
        chat->_selfPerson = [[items objectAtIndex:0] retain];
        [chat rebuildItems];
    }];
}

/* who stands on the chips of a message instead of the numbers: in a private chat the two sides, elsewhere the
   people the server listed while there are few */
- (void)assignFacesOfMessage:(ExteriaMessage *)message {
    NSArray *reactions = message.reactions;
    if (!reactions.count || reactions.count > EXTERIA_REACTIONS_MAX) return;
    BOOL privateChat = (_dialog.kind == EXTERIA_DIALOG_USER || _dialog.kind == EXTERIA_DIALOG_BOT) && !_dialog.saved;
    exteria_reactions all;
    memset(&all, 0, sizeof(all));
    for (ExteriaReaction *reaction in reactions) all.items[all.count++] = reaction.row;
    ExteriaPerson *other = privateChat ? [self chatAsPerson] : nil;
    if (!_accountId) _accountId = [[NSNumber numberWithLongLong:[ExteriaSession accountIdInDirectory:_session.directory]] retain];
    NSNumber *mine = _accountId;
    for (NSUInteger i = 0; i < reactions.count; ++i) {
        ExteriaReaction *reaction = [reactions objectAtIndex:i];
        NSMutableArray *faces = [NSMutableArray array];
        BOOL complete = YES;
        switch (exteria_reaction_faces(&all, i, privateChat)) {
        case EXTERIA_FACES_SELF_AND_OTHER:
            if (_selfPerson) [faces addObject:_selfPerson]; else complete = NO;
            [faces addObject:other];
            break;
        case EXTERIA_FACES_SELF:
            if (_selfPerson) [faces addObject:_selfPerson]; else complete = NO;
            break;
        case EXTERIA_FACES_OTHER:
            [faces addObject:other];
            break;
        case EXTERIA_FACES_REACTORS:
            for (NSNumber *user in reaction.reactorIds) {
                ExteriaPerson *person = [user isEqualToNumber:mine] ? _selfPerson : ([_reactorPeople objectForKey:user] ? [_reactorPeople objectForKey:user] : [_people objectForKey:user]);
                if (person) [faces addObject:person];
                else complete = NO;
                if (![user isEqualToNumber:mine] && (!person || !person.accessHash)) [self resolveReactor:user.longLongValue ofMessage:message];
            }
            break;
        default:
            complete = NO;
            break;
        }
        /* our own picture is the one thing asked for later */
        if (!complete && !_selfPerson && (privateChat || [reaction.reactorIds containsObject:mine])) [self loadSelfPerson];
        reaction.faces = complete && faces.count ? faces : nil;
    }
}

/* min users lack the access hash needed to load their photos */
- (void)resolveReactor:(long long)userId ofMessage:(ExteriaMessage *)message {
    if (userId <= 0 || message.messageId <= 0) return;
    if (!_reactorLookups) _reactorLookups = [[NSMutableSet alloc] init];
    NSNumber *key = [NSNumber numberWithLongLong:userId];
    if ([_reactorLookups containsObject:key]) return;
    [_reactorLookups addObject:key];
    ExteriaWeakReference *weak = _weak;
    [_session loadUser:userId ofMessage:message.messageId inDialog:_dialog completion:^(ExteriaPerson *person, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!person) {
            NSLog(@"exteria: the user %lld who reacted did not load: %@", userId, errorName);
            return;
        }
        if (!chat->_reactorPeople) chat->_reactorPeople = [[NSMutableDictionary alloc] init];
        [chat->_reactorPeople setObject:person forKey:key];
        [chat rebuildItems];
    }];
}

/* a photo or a video, which an album is made of */
- (BOOL)isAlbumPicture:(ExteriaMessage *)message {
    exteria_preview_kind kind = message.media.kind;
    return !message.service && (kind == EXTERIA_PREVIEW_PHOTO || kind == EXTERIA_PREVIEW_VIDEO);
}

- (BOOL)replyIsInThisChat:(ExteriaMessage *)message {
    return !message.replyPeerKind || (message.replyPeerKind == _dialog.peerKind && message.replyPeerId == _dialog.peerId);
}

- (NSString *)replyCacheKey:(int32_t)identifier source:(ExteriaDialog *)source {
    return [NSString stringWithFormat:@"%d/%lld/%d", source.peerKind, source.peerId, identifier];
}

- (ExteriaDialog *)replySourceOfMessage:(ExteriaMessage *)message {
    if ([self replyIsInThisChat:message]) return _dialog;
    long long key = message.replyPeerKind == 1 ? message.replyPeerId : -message.replyPeerId;
    ExteriaPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:key]];
    if ((message.replyPeerKind == 1 || message.replyPeerKind == 3) && !person.accessHash) return nil;
    exteria_dialog_row row;
    memset(&row, 0, sizeof(row));
    row.peer_kind = message.replyPeerKind;
    row.peer_id = message.replyPeerId;
    row.peer_hash = person.accessHash;
    row.kind = row.peer_kind == 1 ? (person.bot ? EXTERIA_DIALOG_BOT : EXTERIA_DIALOG_USER) : EXTERIA_DIALOG_GROUP;
    ExteriaMessage *original = [_replyCache objectForKey:[NSString stringWithFormat:@"%d/%lld/%d", row.peer_kind, row.peer_id, message.replyTo]];
    if ([original isKindOfClass:[ExteriaMessage class]]) {
        if (original.post) row.kind = EXTERIA_DIALOG_CHANNEL;
        if (original.topicId > 1) { row.forum = 1; row.topic_id = original.topicId; }
    }
    NSString *title = person.name.length ? person.name : NSLocalizedString(@"chat.reply.title", nil);
    NSData *utf8 = [title dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger size = MIN(utf8.length, sizeof(row.title) - 1);
    while (size && size < utf8.length && (((const uint8_t *)utf8.bytes)[size] & 0xc0u) == 0x80u) --size;
    memcpy(row.title, utf8.bytes, size);
    return [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
}

- (void)rebuildItems {
    if (!_rebuildNow && (_interacting || _keyboardMoving || _table.dragging || _table.decelerating)) { _livePending = YES; return; }
    if ([self replySwipeActive]) { [self scheduleLiveMessages]; return; }
    _livePending = NO;
    /* the history is what tells that a user is a bot, when the chat was opened from a link that did not */
    if (_callButton && !_callButton.hidden && ![self canCall]) {
        _callButton.hidden = YES;
        [self.view setNeedsLayout];
    }
    [self loadCustomEmoji];
    BOOL group = _dialog.kind == EXTERIA_DIALOG_GROUP;
    NSArray *messages = [self orderedMessages];
    NSTimeInterval serverNow = [[NSDate date] timeIntervalSince1970] + _sharingOffsetMilliseconds / 1000.0;
    NSTimeInterval nextExpiry = 0;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:messages.count + 8];
    NSMutableDictionary *kept = [NSMutableDictionary dictionaryWithCapacity:messages.count];
    ExteriaMessage *previous = nil;
    ExteriaChatItem *previousItem = nil;
    NSCalendar *calendar = ExteriaDisplayCalendar();
    NSInteger previousDay = 0;
    BOOL unreadShown = _unreadAnchor < 0 || _pinnedList || _startMessageId > 0;
    for (NSUInteger at = 0; at < messages.count; ++at) {
        ExteriaMessage *message = [messages objectAtIndex:at];
        BOOL sharingExpired = message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 &&
            exteria_sharing_expired((message.serviceValue & 4) != 0, message.date, _sharingPeriod, (int64_t)serverNow);
        if (message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 && !sharingExpired && message.date > 0) {
            NSTimeInterval deadline = (NSTimeInterval)message.date + _sharingPeriod + 1;
            if (deadline > serverNow && (!nextExpiry || deadline < nextExpiry)) nextExpiry = deadline;
        }
        if (message.messageId > 0 && [_openedOnce containsObject:[NSNumber numberWithInt:message.messageId]]) message.viewOnceOpened = YES;
        /* photos and videos sent together are one item: the run of messages that share an album number, from one sender on one day */
        NSMutableArray *album = nil;
        if (message.groupedId && [self isAlbumPicture:message]) {
            album = [NSMutableArray arrayWithObject:message];
            while (at + 1 < messages.count) {
                ExteriaMessage *next = [messages objectAtIndex:at + 1];
                if (next.groupedId != message.groupedId || next.senderKey != message.senderKey || next.outgoing != message.outgoing || ![self isAlbumPicture:next] ||
                    ExteriaDayKey(calendar, next.date) != ExteriaDayKey(calendar, message.date) || album.count >= 10) break;
                [album addObject:next];
                ++at;
            }
            if (album.count < 2) album = nil;
        }
        NSInteger day = ExteriaDayKey(calendar, message.date);
        if (!previous || day != previousDay) {
            [items addObject:[ExteriaChatItem pillWithText:ExteriaDayText(message.date)]];
            previous = nil;
            previousItem.joinsNext = NO;
            previousItem = nil;
        }
        /* with older history still unloaded the first row is not known to be the first unread one */
        if (!unreadShown && !message.outgoing && message.messageId > _unreadAnchor) {
            unreadShown = YES;
            if (at > 0 || !_canLoadMore) {
                [items addObject:[ExteriaChatItem pillWithText:NSLocalizedString(@"chat.unread.line", nil)]];
                previous = nil;
                previousItem.joinsNext = NO;
                previousItem = nil;
            }
        }
        [self assignFacesOfMessage:message];
        NSNumber *key = [self cacheKeyForMessage:message];
        ExteriaChatItem *item = [_itemCache objectForKey:key];
        NSString *role = [_senderRoles objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
        int32_t replyId = message.replyTo ? message.replyTo : message.sendReplyTo;
        BOOL localReply = [self replyIsInThisChat:message];
        ExteriaDialog *replySource = replyId > 0 ? [self replySourceOfMessage:message] : nil;
        id cachedReply = replySource ? [_replyCache objectForKey:[self replyCacheKey:replyId source:replySource]] : nil;
        ExteriaMessage *original = replyId > 0 && localReply ? [self messageWithId:replyId] : nil;
        if (!original && [cachedReply isKindOfClass:[ExteriaMessage class]]) original = cachedReply;
        NSString *replyTitle = replyId > 0 ? (original ? (original.post && !localReply ? replySource.title : [self senderNameOfMessage:original]) : NSLocalizedString(@"chat.reply.title", nil)) : nil;
        NSString *replyText = replyId > 0 ? (original ? ExteriaMessageSummary(original) : NSLocalizedString(cachedReply || !replySource ? @"chat.reply.unavailable" : @"chat.reply.loading", nil)) : nil;
        if (replyId > 0 && message.replyQuote.length) replyText = message.replyQuote;
        replyText = [[replyText stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        NSArray *replyEntities = original && !message.replyQuote.length ? original.entities : nil;
        if (replyEntities.count && !ExteriaChatFlagGet(ExteriaChatFlagShowReplyCustomEmoji)) {
            NSMutableArray *visible = [NSMutableArray array];
            for (ExteriaTextEntity *entity in replyEntities) if (entity.style != ExteriaTextStyleCustomEmoji) [visible addObject:entity];
            replyEntities = visible;
        }
        UIColor *replyColor = ExteriaColorBubbleLink(message.outgoing);
        if (original && !message.outgoing) {
            ExteriaPerson *author = [_people objectForKey:[NSNumber numberWithLongLong:original.senderKey]];
            if (author && !ExteriaThemeIsClassic() && ExteriaChatFlagGet(ExteriaChatFlagReplyColors)) replyColor = ExteriaNameColor(author.nameColor, llabs(original.senderKey), ExteriaThemeIsDark());
        }
        if (item && (!(item.replyTitle == replyTitle || [item.replyTitle isEqualToString:replyTitle]) ||
                     !(item.replyText == replyText || [item.replyText isEqualToString:replyText]) ||
                     (replyId > 0 && ![item.replyColor isEqual:replyColor]) ||
                     !(item.replyEntities == replyEntities || [item.replyEntities isEqualToArray:replyEntities]))) item = nil;
        if (item && (![item reflectsMessage:message] || ![item reflectsPeople:_people role:role] || ![item reflectsAlbum:album ? album : [NSArray arrayWithObject:message]])) item = nil;
        if (item && message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1 && item.sharingExpired != sharingExpired) item = nil;
        if (!item) {
            item = album ? [ExteriaChatItem itemForAlbum:album group:group people:_people role:role] : [ExteriaChatItem itemForMessage:message group:group people:_people role:role];
            if (message.service == EXTERIA_SERVICE_SHARING_REQUEST + 1) item.sharingExpired = sharingExpired;
            [item setReplyTitle:replyTitle text:replyText color:replyColor];
            item.replyEntities = replyEntities;
            item.reactionsHidden = [self reactionsHidden];
            item.transcript = [_transcripts objectForKey:[NSNumber numberWithInt:message.messageId]];
        }
        [kept setObject:item forKey:key];
        BOOL joins = previous && [self message:previous joins:message];
        previousDay = day;
        /* the gap above a bubble is part of its layout, the tucked in corner below the one before it is only drawing */
        if (item.joinsPrevious != joins) {
            item.joinsPrevious = joins;
            [item invalidateLayout];
        }
        previousItem.joinsNext = joins;
        item.joinsNext = NO;
        item.read = message.outgoing && message.messageId > 0 && message.messageId <= [self readOutboxMaxId];
        [items addObject:item];
        previous = message;
        previousItem = item;
    }
    [_itemCache release];
    _itemCache = [kept retain];
    [self applyItems:items];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sharingExpiryReached) object:nil];
    if (_visible && nextExpiry > serverNow)
        [self performSelector:@selector(sharingExpiryReached) withObject:nil afterDelay:nextExpiry - serverNow];
    [self scheduleReplyPreviews];
    if (!_pinnedList) [_bots messagesChanged:messages loaded:_loadedFirst];
}

- (BOOL)sharingExpired:(ExteriaMessage *)message {
    int64_t now = (int64_t)([[NSDate date] timeIntervalSince1970] + _sharingOffsetMilliseconds / 1000.0);
    return exteria_sharing_expired((message.serviceValue & 4) != 0, message.date, _sharingPeriod, now) != 0;
}

- (void)sharingExpiryReached {
    [self scheduleLiveMessages];
}

/* only missing originals on screen are fetched, in one bounded batch; reply history never adds rows to the chat */
- (void)scheduleReplyPreviews {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(loadReplyPreviews) object:nil];
    [self performSelector:@selector(loadReplyPreviews) withObject:nil afterDelay:0];
}

- (void)loadReplyPreviews {
    if (_loadingReplies || _interacting || !_visible) return;
    NSMutableArray *ids = [NSMutableArray array];
    ExteriaDialog *source = nil;
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        ExteriaMessage *message = ((ExteriaChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        int32_t reply = message.replyTo ? message.replyTo : message.sendReplyTo;
        if (reply <= 0 || ([self replyIsInThisChat:message] && [self messageWithId:reply])) continue;
        ExteriaDialog *candidate = [self replySourceOfMessage:message];
        if (!candidate || [_replyCache objectForKey:[self replyCacheKey:reply source:candidate]]) continue;
        if (source && (source.peerKind != candidate.peerKind || source.peerId != candidate.peerId)) continue;
        source = candidate;
        NSNumber *key = [NSNumber numberWithInt:reply];
        if (![ids containsObject:key]) [ids addObject:key];
        if (ids.count == EXTERIA_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _loadingReplies = YES;
    NSUInteger generation = _replyGeneration;
    ExteriaWeakReference *weak = _weak;
    [_session loadMessagesWithIds:ids ofDialog:source withPeople:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || generation != chat->_replyGeneration) return;
        chat->_loadingReplies = NO;
        if (errorName) NSLog(@"exteria: reply originals did not load: %@", errorName);
        for (NSNumber *key in ids) [chat->_replyCache setObject:[NSNull null] forKey:[chat replyCacheKey:key.intValue source:source]];
        for (ExteriaMessage *original in messages) [chat->_replyCache setObject:original forKey:[chat replyCacheKey:original.messageId source:source]];
        if (people) [chat->_people addEntriesFromDictionary:people];
        [chat rebuildItems];
    }];
}

- (void)messageCellDidTapReply:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    int32_t reply = message.replyTo ? message.replyTo : message.sendReplyTo;
    if (reply <= 0) return;
    if ([self replyIsInThisChat:message]) { [self jumpToMessageId:reply]; return; }
    ExteriaDialog *source = [self replySourceOfMessage:message];
    if (!source) { ExteriaShowNotice(nil, NSLocalizedString(@"chat.reply.unavailable", nil)); return; }
    ExteriaChatController *page = [[[ExteriaChatController alloc] initWithSession:_session dialog:source avatars:_avatars media:_media stickers:_stickers] autorelease];
    page.startMessageId = reply;
    [self.navigationController pushViewController:page animated:YES];
}

/* swaps the rows in; a change that only adds or only removes rows keeps the others and reloads those whose content
   differs */
- (void)applyItems:(NSArray *)items {
    BOOL moving = _interacting || _table.dragging || _table.decelerating;
    BOOL follows = _stickToBottom && !moving;
    _updatingItems = YES;
    NSArray *oldItems = [_items retain];
    NSUInteger oldCount = oldItems.count;
    NSUInteger newCount = items.count;

    ExteriaChatItem *anchor = nil;
    CGFloat anchorOffset = 0;
    NSArray *visible = [_table indexPathsForVisibleRows];
    if (!follows && visible.count) {
        NSIndexPath *first = [visible objectAtIndex:0];
        if ((NSUInteger)first.row < oldCount) {
            anchor = [[oldItems objectAtIndex:(NSUInteger)first.row] retain];
            anchorOffset = _table.contentOffset.y - [_table rectForRowAtIndexPath:first].origin.y;
        }
    }

    NSUInteger prefix = 0;
    while (prefix < MIN(oldCount, newCount) &&
           [[oldItems objectAtIndex:prefix] isSameRowAs:[items objectAtIndex:prefix]]) ++prefix;

    NSUInteger suffix = 0;
    while (suffix < oldCount - prefix && suffix < newCount - prefix &&
           [[oldItems objectAtIndex:oldCount - suffix - 1] isSameRowAs:[items objectAtIndex:newCount - suffix - 1]]) ++suffix;

    NSUInteger removed = oldCount - prefix - suffix;
    NSUInteger inserted = newCount - prefix - suffix;
    BOOL simple = removed == 0 || inserted == 0;
    NSMutableArray *refresh = [NSMutableArray array];
    BOOL reactionsChanged = NO;
    if (simple) {
        for (NSUInteger i = 0; i < prefix + suffix; ++i) {
            NSUInteger oldIndex = i < prefix ? i : oldCount - suffix + (i - prefix);
            NSUInteger newIndex = i < prefix ? i : newCount - suffix + (i - prefix);
            ExteriaChatItem *before = [oldItems objectAtIndex:oldIndex];
            ExteriaChatItem *after = [items objectAtIndex:newIndex];
            if (![after displaysSameAs:before]) {
                [refresh addObject:[NSIndexPath indexPathForRow:(NSInteger)newIndex inSection:0]];
                if (!removed && !inserted && [after hasDifferentReactionsFrom:before]) reactionsChanged = YES;
            }
        }
    }

    /* the rows that stay slide to their new places while the removed one turns to dust, as the item animator of exteraless moves them, and
       the sizes they start from are those of the screen before the rows change */
    BOOL slide = NO;
    NSMutableDictionary *slideFrom = nil;
    /* ios 6 sorts the index paths of a batch of row updates and measures every row for each step, so hundreds of rows at once (a long list of pinned messages
       that gets its reply previews) held the main thread until the watchdog ended the app; one reload goes through the rows once */
    BOOL bulk = simple && removed + inserted + refresh.count > BULK_ROWS_MAX;
    [_items release];
    _items = [items retain];
    if (_greeting) [self.view setNeedsLayout];

    if (!simple || bulk) {
        [_table reloadData];
    } else {
        if (removed || inserted) {
            NSMutableArray *paths = [NSMutableArray array];
            for (NSUInteger i = 0; i < (removed ? removed : inserted); ++i)
                [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)(prefix + i) inSection:0]];
            BOOL animate = oldCount > 0 && [self rowChangesMayAnimate];
            if (removed) {
                /* fading rows below an anchor would slide while the offset jumps */
                BOOL dust = animate && removed <= DUST_ROWS_MAX && ExteriaLiteEnabled(EXTERIA_LITE_CHAT_THANOS);
                NSMutableArray *pictures = dust ? [NSMutableArray array] : nil, *frames = dust ? [NSMutableArray array] : nil;
                for (NSIndexPath *path in paths) {
                    ExteriaChatItem *gone = [oldItems objectAtIndex:(NSUInteger)path.row];
                    UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
                    if (dust && cell && gone.kind != ExteriaChatItemPill) {
                        UIImage *picture = ExteriaDustSnapshot(cell);
                        if (picture) {
                            [pictures addObject:picture];
                            /* table-owned dust would scroll below the input while the list follows its end */
                            [frames addObject:[NSValue valueWithCGRect:[_table convertRect:cell.frame toView:self.view]]];
                        }
                    }
                }
                if (pictures.count) {
                    slide = YES;
                    slideFrom = [NSMutableDictionary dictionary];
                    for (NSIndexPath *seen in visible) {
                        UITableViewCell *cell = [_table cellForRowAtIndexPath:seen];
                        if (cell) [slideFrom setObject:[NSValue valueWithCGRect:[_table convertRect:cell.frame toView:self.view]] forKey:[NSNumber numberWithInteger:seen.row]];
                    }
                }
                [_table beginUpdates];
                [_table deleteRowsAtIndexPaths:paths withRowAnimation:pictures.count || !animate || anchor ? UITableViewRowAnimationNone : UITableViewRowAnimationFade];
                [_table endUpdates];
                for (NSUInteger i = 0; i < pictures.count; ++i) ExteriaDustDisperse([pictures objectAtIndex:i], [[frames objectAtIndex:i] CGRectValue], self.view);
            } else {
                [_table beginUpdates];
                [_table insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
                [_table endUpdates];
                if (animate && !anchor && inserted <= ENTER_ROWS_MAX) [self animateEnterOfRows:paths items:items];
            }
        }
        if (refresh.count) {
            [_table reloadRowsAtIndexPaths:refresh withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    for (ExteriaChatItem *item in items) [item markDisplayed];
    /* a row swapped for another (the pending message for the copy of the server) reloads the table, and a list that was following its end stays on it */
    [_table layoutIfNeeded];

    if (anchor) {
        for (NSUInteger index = 0; index < newCount; ++index) {
            if (![anchor isSameRowAs:[items objectAtIndex:index]]) continue;
            CGFloat y = [_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]].origin.y + anchorOffset;
            [_table setContentOffset:CGPointMake(0, y) animated:NO];
            break;
        }
    }
    [anchor release];
    [oldItems release];
    _updatingItems = NO;
    if (!moving) _stickToBottom = follows;
    /* a list that follows its end goes there at once under the rows that slide, or the two movements would add up */
    /* a full reload has no anchor, and animating from its old offset would show a jump */
    if (follows && newCount) [self scrollToBottomAnimated:!reactionsChanged && !slide && simple && !bulk && oldCount > 0 && !(inserted && !prefix && suffix) && [self rowChangesMayAnimate]];
    if (slide) {
        [_table layoutIfNeeded];
        for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
            NSUInteger newRow = (NSUInteger)path.row, oldRow = newRow < prefix ? newRow : newRow + removed;
            NSValue *from = [slideFrom objectForKey:[NSNumber numberWithUnsignedInteger:oldRow]];
            UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
            if (!from || !cell) continue;
            CGFloat dy = [from CGRectValue].origin.y - [_table convertRect:cell.frame toView:self.view].origin.y;
            if (fabs(dy) < 0.5) continue;
            CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
            move.fromValue = [NSNumber numberWithDouble:dy];
            move.toValue = [NSNumber numberWithDouble:0];
            /* the move of the item animator with the effect on: 250 ms times 1.9, easing out */
            move.duration = 0.475;
            move.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0 :0 :0.58f :1];
            [cell.layer addAnimation:move forKey:@"exteria.dust.slide"];
        }
    }
    [self refreshAnimations];
}

/* the screen is up and drawing: a row that appears or goes while the app sleeps, or before the first page is on screen, is not worth an effect */
- (BOOL)rowChangesMayAnimate {
    return _visible && _loadedFirst && !_opening && [UIApplication sharedApplication].applicationState == UIApplicationStateActive && ExteriaLiteSmoothTransitions();
}

/* rows added away from the end fade in from their tail; following the end belongs to the scroll driver */
- (void)animateEnterOfRows:(NSArray *)paths items:(NSArray *)items {
    BOOL zoom = ExteriaLiteEnabled(EXTERIA_LITE_CHAT_SCALE);
    if (_stickToBottom) return;
    for (NSIndexPath *path in paths) {
        UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
        if (!cell || (NSUInteger)path.row >= items.count) continue;
        ExteriaChatItem *item = [items objectAtIndex:(NSUInteger)path.row];
        if (item.kind == ExteriaChatItemPill) {
            ExteriaAnimateEnter(cell, CGAffineTransformIdentity, 0, EXTERIA_MOTION_ENTER);
            continue;
        }
        BOOL outgoing = item.message.outgoing;
        CGFloat scale = zoom ? (outgoing ? 0.8f : 0.92f) : 1;
        CGSize size = cell.bounds.size;
        CGPoint corner = CGPointMake(outgoing ? size.width - 14 : 14, size.height);
        CGAffineTransform from = CGAffineTransformMake(scale, 0, 0, scale, (1 - scale) * (corner.x - size.width / 2), (1 - scale) * (corner.y - size.height / 2));
        ExteriaAnimateEnter(cell, from, 0, zoom && outgoing ? EXTERIA_MOTION_SPRING : EXTERIA_MOTION_ENTER);
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (!_items.count) return;
    [_table layoutIfNeeded];
    CGFloat end = _table.contentSize.height - _table.bounds.size.height + _table.contentInset.bottom;
    CGFloat y = MAX(-_table.contentInset.top, end);
    if (!animated || fabs(_table.contentOffset.y - y) <= 0.5) {
        [self stopFollowingBottom];
        [_table setContentOffset:CGPointMake(0, y) animated:NO];
        return;
    }
    if (_followLink) return;
    _followingBottom = YES;
    _followTime = 0;
    ExteriaReactionPollTarget *target = [[[ExteriaReactionPollTarget alloc] initWithReference:_weak] autorelease];
    _followLink = [[CADisplayLink displayLinkWithTarget:target selector:@selector(follow:)] retain];
    [_followLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (BOOL)replySwipeActive {
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[ExteriaMessageCell class]] && [(ExteriaMessageCell *)cell replySwipeActive]) return YES;
    }
    return NO;
}

- (void)stopFollowingBottom {
    [self stopJump];
    [_followLink invalidate];
    [_followLink release];
    _followLink = nil;
    _followingBottom = NO;
    _followTime = 0;
    _followBegan = 0;
}

- (void)advanceBottom:(CADisplayLink *)link {
    if (!_visible || _interacting || _table.tracking || _table.dragging || _table.decelerating) { [self stopFollowingBottom]; return; }
    if ([self replySwipeActive]) { _followTime = link.timestamp; return; }
    CGFloat target = [self scrollLimitMax];
    double next = 0;
    CFTimeInterval elapsed = _followTime ? link.timestamp - _followTime : 1.0 / 60.0;
    _followTime = link.timestamp;
    if (!_followBegan) _followBegan = link.timestamp;
    if (exteria_scroll_follow(_table.contentOffset.y, target, elapsed, &next) != EXTERIA_OK) return;
    /* the pace builds up over the first 150 ms, since the follow used to start at its fastest and showed as a jerk */
    double ramp = MIN(1.0, (link.timestamp - _followBegan) / 0.15);
    next = _table.contentOffset.y + (next - _table.contentOffset.y) * ramp * ramp;
    [_table setContentOffset:CGPointMake(0, (CGFloat)next) animated:NO];
    if (fabs(target - next) <= 0.5) {
        [_table setContentOffset:CGPointMake(0, target) animated:NO];
        [self stopFollowingBottom];
        [self refreshAnimations];
    }
}

#pragma mark table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_items.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    ExteriaChatItem *item = [_items objectAtIndex:(NSUInteger)indexPath.row];
    [item layoutForWidth:tableView.bounds.size.width];
    return item.height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"message";
    ExteriaMessageCell *cell = (ExteriaMessageCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[ExteriaMessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        cell.delegate = self;
    }
    ExteriaChatItem *item = [_items objectAtIndex:(NSUInteger)indexPath.row];
    /* a cell that is reused while its row was coming in must not carry the entrance to the next row */
    ExteriaCancelEnter(cell);
    [item layoutForWidth:tableView.bounds.size.width];
    cell.activationDeferred = _interacting;
    cell.stickerLibrary = _stickers;
    [cell configureWithItem:item media:_media avatars:_avatars];
    [cell setSelecting:_selecting selected:[_selectedIds containsObject:[NSNumber numberWithInt:item.message.messageId]] animated:NO];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if ([cell isKindOfClass:[ExteriaMessageCell class]]) {
        NSUInteger playing = 0;
        for (ExteriaMessageCell *visible in _table.visibleCells) {
            if (visible != cell && [visible isKindOfClass:[ExteriaMessageCell class]] && visible.animatedSticker) ++playing;
        }
        [(ExteriaMessageCell *)cell setAnimating:_visible && playing < ANIMATED_STICKERS_MAX];
        [self scheduleReplyPreviews];
    }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if ([cell isKindOfClass:[ExteriaMessageCell class]]) [(ExteriaMessageCell *)cell setAnimating:NO];
}

#pragma mark scrolling

- (CGFloat)scrollLimitMin {
    return -_table.contentInset.top;
}

- (CGFloat)scrollLimitMax {
    return MAX([self scrollLimitMin], _table.contentSize.height - _table.bounds.size.height + _table.contentInset.bottom);
}

/* where the view will be in a moment, or nothing when the numbers do not allow a guess */
- (BOOL)predictedOffset:(CGFloat *)predicted {
    double value = 0;
    double offset = _table.contentOffset.y;
    if (exteria_scroll_predict(&_scroll, offset, _table.bounds.size.height, _scrollTargetKnown, _scrollTargetOffset,
                               [self scrollLimitMin], [self scrollLimitMax], &value) != EXTERIA_OK) return NO;
    *predicted = (CGFloat)value;
    return YES;
}

/* asks for the next page before the view gets to the top of the loaded rows, as early as the speed calls for */
- (void)loadOlderIfNeeded {
    CGFloat predicted = 0;
    if (![self predictedOffset:&predicted]) return;
    CGFloat top = MIN(_table.contentOffset.y, predicted) + _table.contentInset.top;
    if (exteria_scroll_wants_older(top, _scroll.velocity, _table.bounds.size.height)) [self loadOlder];
}

/* the pictures of the rows the view is about to reach are fetched and decoded before it needs them */
- (void)prepareAhead:(BOOL)force {
    CGFloat height = _table.bounds.size.height;
    CGFloat offset = _table.contentOffset.y;
    if (height < 1 || !_items.count) return;
    if (!force && fabs(offset - _preparedOffset) < height * 0.5) return;
    CGFloat predicted = 0;
    exteria_scroll_window window;
    if (![self predictedOffset:&predicted] || exteria_scroll_prepare_window(offset, predicted, _scroll.velocity, height, &window) != EXTERIA_OK) return;
    _preparedOffset = offset;
    CGRect span = CGRectMake(0, window.min_y, _table.bounds.size.width, window.max_y - window.min_y);
    CGRect shown = _table.bounds;
    NSMutableArray *ahead = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForRowsInRect:span]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        CGRect row = [_table rectForRowAtIndexPath:path];
        if (CGRectIntersectsRect(row, shown)) continue;
        CGFloat gap = row.origin.y > CGRectGetMaxY(shown) ? row.origin.y - CGRectGetMaxY(shown) : CGRectGetMinY(shown) - CGRectGetMaxY(row);
        [ahead addObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:gap], [NSNumber numberWithInteger:path.row], nil]];
    }
    [ahead sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        return [[a objectAtIndex:0] compare:[b objectAtIndex:0]];
    }];
    NSUInteger count = MIN(ahead.count, (NSUInteger)PREPARE_ROWS_MAX);
    for (NSUInteger i = 0; i < count; ++i) {
        NSUInteger row = [[[ahead objectAtIndex:i] objectAtIndex:1] unsignedIntegerValue];
        [ExteriaMessageCell prepareItem:[_items objectAtIndex:row] media:_media];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_updatingItems || _layingOutChat || _keyboardMoving) return;
    CGFloat distance = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.size.height + scrollView.contentInset.bottom;
    BOOL moving = scrollView.tracking || scrollView.dragging || scrollView.decelerating;
    if (!_followingBottom)
        _stickToBottom = exteria_scroll_tracks_bottom(_stickToBottom, _interacting && moving,
                                                     _scroll.last_offset, scrollView.contentOffset.y, [self scrollLimitMax]);
    [self showNextChatHintForOverscroll:-distance scrollView:scrollView];
    if (_window) _stickToBottom = NO;
    [self showToEnd:_window || distance > scrollView.bounds.size.height * 1.2f];
    /* a move the code made, such as a row inserted above or a keyboard, says nothing about how fast a finger goes */
    if (moving)
        exteria_scroll_sample(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent(), scrollView.bounds.size.height);
    else
        exteria_scroll_begin(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent());
    [self loadOlderIfNeeded];
    [self loadNewerIfNeeded:distance];
    [self prepareAhead:NO];
    [self refreshAnimationsIfRowsChanged];
    [self scheduleVisibleMentionsRead];
}

/* pulling past the end of a channel offers the next channel with unread posts; letting go far enough opens it */
- (void)showNextChatHintForOverscroll:(CGFloat)over scrollView:(UIScrollView *)scrollView {
    if (_dialog.kind != EXTERIA_DIALOG_CHANNEL || !_nextChatProvider || _pinnedList || _updatingItems || !scrollView.dragging || over <= 0 || !_stickToBottom) {
        if (_nextHint.progress > 0) _nextHint.progress = 0;
        return;
    }
    if (!_nextDialog) {
        _nextDialog = [_nextChatProvider(_dialog) retain];
        if (_nextDialog) [_nextHint setTitle:_nextDialog.title unread:_nextDialog.unreadCount];
    }
    _nextHint.progress = _nextDialog ? over / [ExteriaNextChatHint pullDistance] : 0;
}

- (void)openNextChat {
    ExteriaDialog *next = [[_nextDialog retain] autorelease];
    UINavigationController *navigation = self.navigationController;
    if (!next || !navigation || navigation.topViewController != self) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:next avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.nextChatProvider = _nextChatProvider;
    chat.closeHandler = _closeHandler;
    /* the new chat takes this one's place, so back goes to the list as it did before */
    NSMutableArray *stack = [NSMutableArray arrayWithArray:navigation.viewControllers];
    [stack removeObject:self];
    [stack addObject:chat];
    [_nextDialog release];
    _nextDialog = nil;
    [navigation setViewControllers:stack animated:YES];
}

- (void)showToEnd:(BOOL)show {
    if (show == _toEndShown) return;
    _toEndShown = show;
    if (show) _toEnd.hidden = NO;
    [UIView animateWithDuration:0.18 animations:^{
        _toEnd.alpha = show ? 1 : 0;
        [self placeReactionJump];
    } completion:^(BOOL finished) {
        if (finished && !_toEndShown) _toEnd.hidden = YES;
    }];
}

/* the heart takes the place of the way down when that is hidden, and stands over it when it shows */
- (void)placeReactionJump {
    CGRect base = _toEnd.frame;
    CGFloat y = _toEndShown ? base.origin.y - 52 : base.origin.y;
    _reactionJump.frame = CGRectMake(base.origin.x, y, 44, 44);
    CGFloat width = MAX(22, ceil([_reactionBadge sizeThatFits:CGSizeMake(80, 22)].width) + 12);
    _reactionBadge.frame = CGRectMake(CGRectGetMaxX(_reactionJump.frame) - width + 6, y - 6, width, 22);
}

- (void)refreshReactionJump {
    BOOL show = _unreadReactionIds.count > 0;
    _reactionJump.hidden = !show;
    _reactionBadge.hidden = !show;
    _reactionBadge.text = _unreadReactionIds.count > 999 ? @"999+" : [NSString stringWithFormat:@"%lu", (unsigned long)_unreadReactionIds.count];
    [self placeReactionJump];
}

/* the server lists the messages that got a reaction we have not seen; a chat opened from the list knows how many there are before it asks */
- (void)loadUnreadReactions {
    if (_dialog.reactions <= 0 || self.pinnedList) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadUnreadReactionsOfDialog:_dialog completion:^(NSArray *messages, NSDictionary *people, NSString *errorName) {
        (void)people;
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!messages) {
            NSLog(@"exteria: the unread reactions of chat %lld did not load: %@", chat->_dialog.peerId, errorName);
            return;
        }
        NSMutableArray *ids = [[NSMutableArray alloc] init];
        for (ExteriaMessage *message in messages) if (message.messageId > 0) [ids addObject:[NSNumber numberWithInt:message.messageId]];
        [chat->_unreadReactionIds release];
        chat->_unreadReactionIds = ids;
        [chat refreshReactionJump];
    }];
}

/* the oldest unseen reaction first, which reads forward; the last one seen tells the server that all of them were */
- (void)reactionJumpTapped {
    if (!_unreadReactionIds.count) return;
    int32_t messageId = [[_unreadReactionIds lastObject] intValue];
    [_unreadReactionIds removeLastObject];
    if (!_unreadReactionIds.count) [_session markReactionsReadOfDialog:_dialog];
    [self refreshReactionJump];
    [self jumpToMessageId:messageId];
}

- (void)toEndTapped {
    if (_window) {
        [self leaveWindow];
        return;
    }
    _stickToBottom = YES;
    [self scrollToBottomAnimated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self stopFollowingBottom];
    _interacting = YES;
    _scrollTargetKnown = NO;
    exteria_scroll_begin(&_scroll, scrollView.contentOffset.y, CFAbsoluteTimeGetCurrent());
    if (!_panelShown) [_input.textView resignFirstResponder];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    (void)scrollView;
    (void)velocity;
    if (!targetContentOffset) return;
    _scrollTargetKnown = YES;
    _scrollTargetOffset = targetContentOffset->y;
    [self loadOlderIfNeeded];
    [self prepareAhead:YES];
}

/* the list rests: what waited for it is let go */
- (void)scrollSettled {
    _scrollTargetKnown = NO;
    exteria_scroll_begin(&_scroll, _table.contentOffset.y, CFAbsoluteTimeGetCurrent());
    _interacting = NO;
    BOOL hadOlder = _olderDeferred;
    if (hadOlder) [self showOlder];
    else [self flushLiveMessages];
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[ExteriaMessageCell class]]) ((ExteriaMessageCell *)cell).activationDeferred = NO;
    }
    if (!hadOlder) [self scrollToTargetOrLoadMore];
    [self loadOlderIfNeeded];
    [self prepareAhead:YES];
    [self refreshAnimations];
    [self scheduleReplyPreviews];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    (void)scrollView;
    BOOL opens = _nextHint.progress >= 1 && _nextDialog;
    _nextHint.progress = 0;
    if (opens) {
        [self openNextChat];
        return;
    }
    [_nextDialog release];
    _nextDialog = nil;
    if (!decelerate) [self scrollSettled];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    [self scrollSettled];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    (void)scrollView;
    if (!_followLink) _followingBottom = NO;
    [self refreshAnimations];
}

/* the power saving settings changed, or the power saver came or went: stickers and big emoji on screen are made again, to play or to stand still, and
   the ones that may play are chosen again */
- (void)liteModeChanged {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if (path.row < 0 || (NSUInteger)path.row >= _items.count) continue;
        ExteriaChatItemKind kind = ((ExteriaChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).kind;
        if (kind == ExteriaChatItemSticker || kind == ExteriaChatItemEmoji) [paths addObject:path];
    }
    if (paths.count) [_table reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
    [self refreshAnimations];
}

/* the newest stickers on screen play, the rest rest on their first frame */
/* which stickers may run only depends on the rows on screen, and a scroll event comes sixty times a second while the same rows stay */
- (void)refreshAnimationsIfRowsChanged {
    NSArray *rows = [_table indexPathsForVisibleRows];
    NSIndexPath *first = rows.count ? [rows objectAtIndex:0] : nil, *last = rows.count ? [rows lastObject] : nil;
    if ((first ? first.row : -1) == _animatedFirst && (last ? last.row : -1) == _animatedLast) return;
    [self refreshAnimations];
}

- (void)refreshAnimations {
    if (!_visible || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        [self stopAnimations];
        return;
    }
    NSArray *rows = [_table indexPathsForVisibleRows];
    NSIndexPath *first = rows.count ? [rows objectAtIndex:0] : nil, *last = rows.count ? [rows lastObject] : nil;
    _animatedFirst = first ? first.row : -1;
    _animatedLast = last ? last.row : -1;
    NSMutableArray *animated = [NSMutableArray array];
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[ExteriaMessageCell class]] && [(ExteriaMessageCell *)cell animatedSticker]) [animated addObject:cell];
    }
    [animated sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.frame.origin.y > b.frame.origin.y ? NSOrderedAscending : (a.frame.origin.y < b.frame.origin.y ? NSOrderedDescending : NSOrderedSame);
    }];
    for (NSUInteger i = 0; i < animated.count; ++i) [[animated objectAtIndex:i] setAnimating:i < ANIMATED_STICKERS_MAX];
}

- (void)stopAnimations {
    for (UITableViewCell *cell in _table.visibleCells) {
        if ([cell isKindOfClass:[ExteriaMessageCell class]]) [(ExteriaMessageCell *)cell setAnimating:NO];
    }
}

- (void)messageCellDidRevealSpoiler:(ExteriaMessageCell *)cell {
    (void)cell;
    [self refreshAnimations];
}

#pragma mark reactions

- (void)closeReactionPicker {
    ++_reactionPickerToken;
    [_reactionPicker dismissAnimated:self.view.window != nil];
    [_reactionPicker release];
    _reactionPicker = nil;
    _reactionMessageId = 0;
}

- (void)showReactionError:(NSString *)error {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(@"chat.reaction.failed", nil)
        message:[self failureTextForError:error] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (void)loadReactionChoices {
    if (!_reactionPicker) return;
    [_reactionPicker setLoading];
    NSUInteger token = ++_reactionPickerToken;
    ExteriaWeakReference *weak = _weak;
    [self whenPremiumKnown:^(BOOL premium) {
    ExteriaChatController *again = weak.target;
    if (!again || token != again->_reactionPickerToken || !again->_reactionPicker) return;
    /* the picker opened before the account was known as Premium or not, and its custom emoji wear locks until it is told */
    [again->_reactionPicker attachSession:again->_session media:again->_media premium:premium];
    [again->_session loadAvailableReactionsForDialog:again->_dialog premium:premium completion:^(NSArray *choices, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || token != chat->_reactionPickerToken || !chat->_reactionPicker) return;
        if (!choices) {
            [chat->_reactionPicker setFailure:[chat failureTextForError:errorName]];
            return;
        }
        ExteriaMessage *message = [chat->_server objectForKey:[NSNumber numberWithInt:chat->_reactionMessageId]];
        NSMutableArray *marked = [NSMutableArray arrayWithCapacity:choices.count];
        for (ExteriaReaction *choice in choices) {
            exteria_reaction row = choice.row;
            for (ExteriaReaction *current in message.reactions)
                if ([current.key isEqualToString:choice.key]) row.chosen = current.chosen;
            [marked addObject:[ExteriaReaction reactionWithRow:&row]];
        }
        [chat->_reactionPicker setReactions:marked];
        [chat loadCustomEmojiOfChoices:marked];
    }];
    }];
}

/* the custom reactions the picker offers show their emoji and picture once the documents are known, and the chips are built again then */
- (void)loadCustomEmojiOfChoices:(NSArray *)choices {
    NSMutableArray *wanted = [NSMutableArray array];
    for (ExteriaReaction *choice in choices) {
        if (choice.row.kind == EXTERIA_REACTION_CUSTOM && choice.row.document_id) [wanted addObject:[NSNumber numberWithLongLong:choice.row.document_id]];
    }
    if (!wanted.count) return;
    ExteriaWeakReference *weak = _weak;
    NSUInteger token = _reactionPickerToken;
    [ExteriaCustomEmojiLoader loadDocuments:wanted session:_session media:_media documents:^(NSArray *documents) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        NSMutableDictionary *texts = [NSMutableDictionary dictionaryWithCapacity:documents.count];
        for (ExteriaCustomEmojiDocument *document in documents) [texts setObject:document.alt forKey:[NSNumber numberWithLongLong:document.documentId]];
        [ExteriaReaction rememberCustomTexts:texts];
        if (token == chat->_reactionPickerToken && chat->_reactionPicker) [chat->_reactionPicker setReactions:choices];
    } picture:^{
        ExteriaChatController *chat = weak.target;
        if (chat && token == chat->_reactionPickerToken && chat->_reactionPicker) ExteriaRedrawTree(chat->_reactionPicker);
    }];
}

/* whether the account has Telegram Premium, asked once; custom emoji in the panel and in the reaction choices depend on it */
- (void)whenPremiumKnown:(void (^)(BOOL premium))block {
    if (_premiumKnown) {
        block(_premium);
        return;
    }
    void (^then)(BOOL) = [block copy];
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        ExteriaPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (chat && me) {
            chat->_premium = ExteriaPremiumEffective(me.premium);
            chat->_premiumKnown = YES;
        } else if (!me) {
            NSLog(@"exteria: premium state unknown: %@", errorName);
        }
        if (chat) then(ExteriaPremiumEffective(me.premium));
        [then release];
    }];
}

/* a song's menu: the song goes on the profile, and the reactions stay one entry away */
- (void)showSongMenuForCell:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    NSMutableArray *titles = [NSMutableArray arrayWithObject:NSLocalizedString(@"music.add", nil)];
    ExteriaSymbol symbols[2] = {ExteriaSymbolMusic, ExteriaSymbolHeart};
    BOOL reactions = message.messageId > 0 && message.reactionsPossible && ![self reactionsHidden];
    if (reactions) [titles addObject:NSLocalizedString(@"chat.reactions", nil)];
    ExteriaWeakReference *weak = _weak;
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (index == 0) [chat addSongToProfile:message.media];
        else [chat showReactionPickerForMessage:message];
    }] autorelease];
    CGRect bubble = [self.view convertRect:cell.item.bubbleFrame fromView:cell.contentView];
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(bubble), CGRectGetMaxY(bubble))];
}

- (void)addSongToProfile:(ExteriaMedia *)song {
    [self retain];
    [_session saveMusic:song unsave:NO completion:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            NSLog(@"exteria: song not saved to the profile: %@", errorName);
            ExteriaGiftAlert(nil, [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]);
            return;
        }
        ExteriaGiftAlert(nil, NSLocalizedString(@"music.added", nil));
    }];
}

- (void)messageCellDidLongPress:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (message.media.kind == EXTERIA_PREVIEW_AUDIO && message.media.file && message.media.ref.ref_len) {
        [self dismissInput];
        [self showSongMenuForCell:cell];
        return;
    }
    [self showMessageMenuForCell:cell];
}

/* the bubble of a message that is on screen, in the coordinates of the chat view; empty when its row is out of sight */
- (CGRect)visibleBubbleOfMessageId:(int32_t)messageId {
    for (NSUInteger i = 0; i < _items.count; ++i) {
        ExteriaChatItem *item = [_items objectAtIndex:i];
        if (item.message.messageId != messageId) continue;
        UITableViewCell *cell = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0]];
        if (!cell) return CGRectZero;
        CGRect bubble = CGRectIntersection([self.view convertRect:item.bubbleFrame fromView:cell.contentView], _table.frame);
        return CGRectIsNull(bubble) ? CGRectZero : bubble;
    }
    return CGRectZero;
}

- (void)showReactionPickerForMessage:(ExteriaMessage *)message {
    if (message.messageId <= 0 || !message.reactionsPossible || [self reactionsHidden]) return;
    [self dismissInput];
    [self closeReactionPicker];
    _reactionMessageId = message.messageId;
    _reactionPicker = [[ExteriaReactionPicker alloc] initWithFrame:self.view.bounds];
    _reactionPicker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _reactionPicker.anchorRect = [self visibleBubbleOfMessageId:message.messageId];
    _reactionPicker.anchorOutgoing = message.outgoing;
    [_reactionPicker attachSession:_session media:_media premium:_premiumKnown && _premium];
    ExteriaWeakReference *weak = _weak;
    _reactionPicker.cancelHandler = ^{ [(ExteriaChatController *)weak.target closeReactionPicker]; };
    _reactionPicker.retryHandler = ^{ [(ExteriaChatController *)weak.target loadReactionChoices]; };
    _reactionPicker.pickHandler = ^(ExteriaReaction *reaction) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        int32_t messageId = chat->_reactionMessageId;
        [chat closeReactionPicker];
        [chat chooseReaction:reaction messageId:messageId];
    };
    _reactionPicker.customPickHandler = ^(ExteriaCustomEmojiDocument *emoji) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        int32_t messageId = chat->_reactionMessageId;
        if (!chat->_premiumKnown || !chat->_premium) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"chat.reaction.premium", nil));
            return;
        }
        exteria_reaction row;
        memset(&row, 0, sizeof(row));
        row.kind = EXTERIA_REACTION_CUSTOM;
        row.document_id = emoji.documentId;
        ExteriaReaction *reaction = [ExteriaReaction reactionWithRow:&row];
        /* the chip that shows the choice needs the emoji the document stands for */
        if (emoji.alt.length) [ExteriaReaction rememberCustomTexts:[NSDictionary dictionaryWithObject:emoji.alt forKey:[NSNumber numberWithLongLong:emoji.documentId]]];
        [chat closeReactionPicker];
        [chat chooseReaction:reaction messageId:messageId];
    };
    [self.view addSubview:_reactionPicker];
    [self loadReactionChoices];
}

- (void)chooseReaction:(ExteriaReaction *)reaction messageId:(int32_t)messageId {
    NSNumber *key = [NSNumber numberWithInt:messageId];
    ExteriaMessage *message = [_server objectForKey:key];
    if (!message || !message.reactionsPossible || [self reactionsHidden] || [_reactionSending containsObject:key]) return;
    /* a custom emoji is a reaction only for an account with Premium, which the picker has already checked; a chip we already chose can always be taken back */
    if (reaction.row.kind == EXTERIA_REACTION_PAID || (reaction.row.kind == EXTERIA_REACTION_CUSTOM && !reaction.chosen && !(_premiumKnown && _premium))) {
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"chat.reaction.unsupported", nil)
            delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }
    BOOL removing = NO;
    NSMutableArray *choices = [NSMutableArray array];
    for (ExteriaReaction *current in message.reactions) {
        if (!current.chosen || current.row.kind == EXTERIA_REACTION_PAID) continue;
        if ([current.key isEqualToString:reaction.key]) removing = YES;
        else [choices addObject:current];
    }
    /* the picker replaces our ordinary choice, removing a chip preserves choices made in other clients */
    if (!removing) [choices setArray:[NSArray arrayWithObject:reaction]];
    else [choices sortUsingComparator:^NSComparisonResult(ExteriaReaction *a, ExteriaReaction *b) {
        return a.row.chosen_order < b.row.chosen_order ? NSOrderedAscending :
            (a.row.chosen_order > b.row.chosen_order ? NSOrderedDescending : NSOrderedSame);
    }];
    [_reactionSending addObject:key];
    ExteriaWeakReference *weak = _weak;
    [_session sendReactions:choices messageId:messageId dialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        [chat->_reactionSending removeObject:key];
        if (errorName) {
            NSLog(@"exteria: sending reaction to chat %lld message %d failed: %@", chat->_dialog.peerId, messageId, errorName);
            if (chat->_visible) [chat showReactionError:errorName];
            return;
        }
        [chat mergeMessages:messages];
        [chat rebuildItems];
    }];
}

- (void)messageCell:(ExteriaMessageCell *)cell didTapReaction:(ExteriaReaction *)reaction {
    [self chooseReaction:reaction messageId:cell.item.message.messageId];
}

#pragma mark polls

/* the polls on screen that can still change are asked for again with the reactions, so the counts move while the chat is open */
- (void)pollPolls {
    if (_pollingPolls || !_visible || !_loadedFirst || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        ExteriaMessage *message = ((ExteriaChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (message.messageId > 0 && message.poll && !message.poll.closed && ![_votingPolls containsObject:key]) [ids addObject:key];
        if (ids.count == EXTERIA_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _pollingPolls = YES;
    [self refreshPollsOfMessageIds:ids];
}

/* the server's copy of the polls replaces what the messages carry when the counts or the votes differ; the picks not yet sent carry over */
- (void)refreshPollsOfMessageIds:(NSArray *)ids {
    ExteriaWeakReference *weak = _weak;
    [_session loadMessagesWithIds:ids ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_pollingPolls = NO;
        if (!messages) {
            NSLog(@"exteria: the polls did not refresh: %@", errorName);
            return;
        }
        BOOL changed = NO;
        for (ExteriaMessage *fresh in messages) {
            ExteriaMessage *current = [chat->_server objectForKey:[NSNumber numberWithInt:fresh.messageId]];
            if (!current || !current.poll || !fresh.poll || [chat->_votingPolls containsObject:[NSNumber numberWithInt:fresh.messageId]]) continue;
            [fresh.poll inheritPickedFrom:current.poll];
            if ([fresh.poll.stateKey isEqualToString:current.poll.stateKey]) continue;
            current.poll = fresh.poll;
            changed = YES;
        }
        if (!changed || !chat->_visible) return;
        [chat rebuildItems];
    }];
}

- (void)votePollOfMessage:(ExteriaMessage *)message options:(NSArray *)tokens {
    NSNumber *key = [NSNumber numberWithInt:message.messageId];
    if ([_votingPolls containsObject:key]) return;
    if (!_votingPolls) _votingPolls = [[NSMutableSet alloc] init];
    [_votingPolls addObject:key];
    ExteriaWeakReference *weak = _weak;
    [_session sendVoteOptions:tokens forMessageId:message.messageId ofDialog:_dialog completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        [chat->_votingPolls removeObject:key];
        if (errorName) {
            NSLog(@"exteria: the vote in message %@ was not taken: %@", key, errorName);
            ExteriaGiftAlert(NSLocalizedString(@"poll.failed", nil), ExteriaGiftErrorText(errorName));
            return;
        }
        /* the vote is in; the picks are spent and the counts come from the server */
        ExteriaMessage *current = [chat messageWithId:key.intValue];
        [current.poll clearPicked];
        chat->_pollingPolls = YES;
        [chat refreshPollsOfMessageIds:[NSArray arrayWithObject:key]];
    }];
}

/* a tap on an answer votes for it, or marks it in a poll with several answers; the button under the answers sends the marks or takes the vote back */
- (void)messageCell:(ExteriaMessageCell *)cell didTapPollAnswer:(NSInteger)index {
    ExteriaMessage *message = cell.item.message;
    ExteriaPoll *poll = message.poll;
    if (!poll || message.messageId <= 0 || _pinnedList) return;
    if (poll.closed) {
        [self toast:NSLocalizedString(@"poll.closed", nil)];
        return;
    }
    if (index < 0) {
        if (poll.voted) {
            [self votePollOfMessage:message options:[NSArray array]];
            return;
        }
        NSMutableArray *tokens = [NSMutableArray array];
        [poll.picked enumerateIndexesUsingBlock:^(NSUInteger at, BOOL *stop) {
            (void)stop;
            if (at < poll.answers.count) [tokens addObject:((ExteriaPollAnswer *)[poll.answers objectAtIndex:at]).option];
        }];
        if (tokens.count) [self votePollOfMessage:message options:tokens];
        return;
    }
    if ((NSUInteger)index >= poll.answers.count) return;
    ExteriaPollAnswer *answer = [poll.answers objectAtIndex:(NSUInteger)index];
    if (poll.voted) {
        /* a quiz and a poll that forbids it keep the first answer, and one with several answers is changed from the button */
        if (poll.quiz || poll.revotingDisabled || poll.multiple) return;
        [self votePollOfMessage:message options:answer.chosen ? [NSArray array] : [NSArray arrayWithObject:answer.option]];
        return;
    }
    if (poll.multiple) {
        [poll togglePicked:(NSUInteger)index];
        [self rebuildItems];
        return;
    }
    [self votePollOfMessage:message options:[NSArray arrayWithObject:answer.option]];
}

- (void)pollReactions {
    [self pollPolls];
    if (!_visible || !_loadedFirst || _pollingReactions || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSIndexPath *path in [_table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row >= _items.count) continue;
        ExteriaMessage *message = ((ExteriaChatItem *)[_items objectAtIndex:(NSUInteger)path.row]).message;
        NSNumber *key = [NSNumber numberWithInt:message.messageId];
        if (message.messageId > 0 && !message.outgoing && message.hasReactions && ![_reactionSending containsObject:key]) [ids addObject:key];
        if (ids.count == EXTERIA_MESSAGES_MAX) break;
    }
    if (!ids.count) return;
    _pollingReactions = YES;
    ExteriaWeakReference *weak = _weak;
    [_session refreshReactionsForMessages:ids dialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_pollingReactions = NO;
        if (!messages) { NSLog(@"exteria: polling reactions failed: %@", errorName); return; }
        if (!chat->_visible) return;
        BOOL changed = NO;
        for (ExteriaMessage *message in messages) {
            NSNumber *key = [NSNumber numberWithInt:message.messageId];
            ExteriaMessage *previous = [chat->_server objectForKey:key];
            if (previous && ![previous.reactionKey isEqualToString:message.reactionKey] && ![chat->_reactionSending containsObject:key]) {
                [chat->_server setObject:message forKey:key];
                changed = YES;
            }
        }
        if (changed) {
            [chat rebuildItems];
        }
    }];
}

#pragma mark sending

- (long long)newRandomId {
    long long random;
    do {
        random = (long long)(((uint64_t)arc4random() << 32 | arc4random()) & 0x7fffffffffffffffULL);
    } while (random == 0);
    return random;
}

#pragma mark attaching

- (void)inputBarDidTapAttach:(ExteriaInputBar *)bar {
    (void)bar;
    [self.view endEditing:YES];
    ExteriaAttachSheet *sheet = [[[ExteriaAttachSheet alloc] init] autorelease];
    sheet.delegate = self;
    sheet.offersGift = [self canReceiveGift];
    [sheet showInView:self.view];
}

- (void)attachSheet:(ExteriaAttachSheet *)sheet didChoose:(ExteriaAttachChoice)choice {
    (void)sheet;
    [self attachFlow];
    switch (choice) {
    case ExteriaAttachGallery: [_attach chooseGallery]; break;
    case ExteriaAttachFile: [_attach chooseFile]; break;
    case ExteriaAttachLocation: [_attach chooseLocation]; break;
    case ExteriaAttachGift: [self openGiftCatalog]; break;
    case ExteriaAttachContact: [_attach chooseContact]; break;
    case ExteriaAttachCamera: [_attach chooseCamera]; break;
    }
}

- (void)attachSheet:(ExteriaAttachSheet *)sheet didChooseAssets:(NSArray *)urls options:(ExteriaAttachOptions *)options {
    (void)sheet;
    [[self attachFlow] chooseAssets:urls options:options];
}

#pragma mark message actions

/* one line that says what a message is, for the strip and the details */
static NSString *ExteriaMessageSummary(ExteriaMessage *message) {
    if (message.text.length) return message.text;
    switch (message.media.kind) {
    case EXTERIA_PREVIEW_PHOTO: return NSLocalizedString(@"preview.photo", nil);
    case EXTERIA_PREVIEW_VIDEO: return NSLocalizedString(@"preview.video", nil);
    case EXTERIA_PREVIEW_VIDEO_MESSAGE: return NSLocalizedString(@"preview.videomessage", nil);
    case EXTERIA_PREVIEW_VOICE: return NSLocalizedString(@"preview.voice", nil);
    case EXTERIA_PREVIEW_AUDIO: return NSLocalizedString(@"preview.audio", nil);
    case EXTERIA_PREVIEW_STICKER: return NSLocalizedString(@"preview.sticker", nil);
    case EXTERIA_PREVIEW_GIF: return NSLocalizedString(@"preview.gif", nil);
    /* a file is told by its name, as the row in the chat tells it */
    case EXTERIA_PREVIEW_FILE: return message.media.name.length ? message.media.name : NSLocalizedString(@"preview.file", nil);
    case EXTERIA_PREVIEW_LOCATION: return NSLocalizedString(@"preview.location", nil);
    case EXTERIA_PREVIEW_CONTACT: return NSLocalizedString(@"preview.contact", nil);
    case EXTERIA_PREVIEW_POLL: return NSLocalizedString(@"preview.poll", nil);
    default: break;
    }
    return NSLocalizedString(@"preview.message", nil);
}

- (NSString *)senderNameOfMessage:(ExteriaMessage *)message {
    if (message.outgoing) return NSLocalizedString(@"chat.msg.you", nil);
    if (message.post) return _dialog.title;
    NSString *name = [[_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]] name];
    return name.length ? name : (_dialog.kind == EXTERIA_DIALOG_USER || _dialog.kind == EXTERIA_DIALOG_BOT ? _dialog.title : NSLocalizedString(@"chat.someone", nil));
}

/* the setting hides the reactions of one kind of chat: the chips, the pill of the menu and the reaction itself */
- (BOOL)reactionsHidden {
    /* the reactions of the favorites are tags, which the server takes from Premium accounts only and answers REACTION_INVALID to the rest */
    if (_dialog.saved) return !(_premiumKnown && _premium);
    switch (_dialog.kind) {
    case EXTERIA_DIALOG_USER:
    case EXTERIA_DIALOG_BOT: return ExteriaChatFlagGet(ExteriaChatFlagHideReactionsPrivate);
    case EXTERIA_DIALOG_GROUP: return ExteriaChatFlagGet(ExteriaChatFlagHideReactionsGroups);
    case EXTERIA_DIALOG_CHANNEL: return ExteriaChatFlagGet(ExteriaChatFlagHideReactionsChannels);
    }
    return NO;
}

- (exteria_action_context)actionContextOfMessage:(ExteriaMessage *)message {
    exteria_action_context context;
    memset(&context, 0, sizeof(context));
    context.peer_kind = _dialog.peerKind;
    context.message_id = message.messageId;
    context.broadcast = _dialog.kind == EXTERIA_DIALOG_CHANNEL;
    context.can_post = _channelFull ? _channelFull.dialog.canPost : _dialog.canPost;
    context.outgoing = message.outgoing;
    context.service = message.service;
    context.has_text = message.text.length > 0;
    context.has_entities = message.entities.count > 0;
    context.media = message.media.kind;
    context.reactions_possible = message.reactionsPossible && ![self reactionsHidden];
    ExteriaPerson *sender = message.outgoing ? nil : [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    context.sender_user = sender && sender.userId > 0 && sender.accessHash != 0;
    context.has_username = _channelFull.username.length > 0;
    context.pinned_now = _pinnedId && _pinnedId == message.messageId;
    context.saved_chat = _dialog.saved;
    context.media_fetchable = message.media.file != nil;
    context.translate_wanted = [self translateWantedForMessage:message];
    context.bookmarked = [[ExteriaBookmarks bookmarksForSession:_session] containsMessageId:message.messageId inDialog:_dialog];
    return context;
}

typedef struct { uint32_t action; ExteriaSymbol symbol; NSString *key; BOOL destructive; } ExteriaMessageActionRow;

/* the glyph row at the bottom of the menu, in the order exteraGram has them, with the translation among them so it is one tap away; the row has five when the message can be translated */
static const ExteriaMessageActionRow ExteriaMessageActionIcons[] = {
    {EXTERIA_ACTION_REPLY, ExteriaSymbolReply, @"chat.msg.reply", NO},
    {EXTERIA_ACTION_COPY, ExteriaSymbolCopy, @"chat.msg.copy", NO},
    {EXTERIA_ACTION_TRANSLATE, ExteriaSymbolTranslate, @"tr.translate", NO},
    {EXTERIA_ACTION_DELETE, ExteriaSymbolTrash, @"chat.msg.delete", YES},
    {EXTERIA_ACTION_FORWARD, ExteriaSymbolForward, @"chat.msg.forward", NO},
};

/* the text rows under the line about the message; the first few show and the rest wait behind "More" */
static const ExteriaMessageActionRow ExteriaMessageActionRows[] = {
    {EXTERIA_ACTION_EDIT, ExteriaSymbolCompose, @"chat.msg.edit", NO},
    {EXTERIA_ACTION_PIN, ExteriaSymbolPin, @"chat.msg.pin", NO},
    {EXTERIA_ACTION_UNPIN, ExteriaSymbolUnpin, @"chat.msg.unpin", NO},
    {EXTERIA_ACTION_COPY_LINK, ExteriaSymbolLink, @"profile.qr.copy", NO},
    {EXTERIA_ACTION_GALLERY, ExteriaSymbolGallery, @"media.save", NO},
    {EXTERIA_ACTION_TRANSCRIBE, ExteriaSymbolMicrophone, @"chat.msg.transcribe", NO},
    {EXTERIA_ACTION_BOOKMARK, ExteriaSymbolStar, @"chat.msg.bookmark", NO},
    {EXTERIA_ACTION_UNBOOKMARK, ExteriaSymbolStar, @"chat.msg.unbookmark", NO},
    {EXTERIA_ACTION_SAVE, ExteriaSymbolBookmark, @"chat.msg.save", NO},
    {EXTERIA_ACTION_FORWARD_HIDDEN, ExteriaSymbolEyeSlash, @"chat.msg.forwardhidden", NO},
    {EXTERIA_ACTION_COPY_PHOTO, ExteriaSymbolGallery, @"chat.msg.copyphoto", NO},
    {EXTERIA_ACTION_REPEAT, ExteriaSymbolRepeat, @"chat.msg.repeat", NO},
    {EXTERIA_ACTION_HISTORY, ExteriaSymbolMagnifier, @"chat.msg.history", NO},
    {EXTERIA_ACTION_REPLY_PRIVATE, ExteriaSymbolChats, @"chat.msg.replyprivate", NO},
    {EXTERIA_ACTION_REMIND, ExteriaSymbolClock, @"chat.msg.remind", NO},
    {EXTERIA_ACTION_SELECT, ExteriaSymbolCheck, @"chat.msg.select", NO},
    {EXTERIA_ACTION_EDIT_HISTORY, ExteriaSymbolClock, @"chat.msg.edithistory", NO},
    {EXTERIA_ACTION_REACTORS, ExteriaSymbolHeartOutline, @"chat.reactors.title", NO},
    {EXTERIA_ACTION_DETAILS, ExteriaSymbolInfo, @"chat.msg.details", NO},
    {EXTERIA_ACTION_REPORT, ExteriaSymbolReport, @"chat.msg.report", YES},
};

static NSArray *ExteriaMenuItems(const ExteriaMessageActionRow *table, size_t count, uint32_t mask) {
    NSMutableArray *items = [NSMutableArray array];
    for (size_t i = 0; i < count; ++i) {
        if (!(mask & table[i].action)) continue;
        [items addObject:[ExteriaMenuItem itemWithTitle:NSLocalizedString(table[i].key, nil) symbol:table[i].symbol tag:table[i].action destructive:table[i].destructive]];
    }
    return items;
}

/* the reactions of the pill, marked with the ones this message already carries from us */
- (NSArray *)menuReactionsForMessage:(ExteriaMessage *)message {
    NSMutableArray *marked = [NSMutableArray array];
    for (ExteriaReaction *choice in _menuReactions) {
        if (choice.row.kind != EXTERIA_REACTION_EMOJI) continue;
        exteria_reaction row = choice.row;
        row.chosen = 0;
        for (ExteriaReaction *current in message.reactions) if ([current.key isEqualToString:choice.key]) row.chosen = current.chosen;
        [marked addObject:[ExteriaReaction reactionWithRow:&row]];
    }
    return marked;
}

/* the reactions the chat offers are asked for once and kept, so the next menu has its pill at once */
- (void)loadMenuReactionsThen:(void (^)(void))then {
    if (_menuReactions || _menuReactionsLoading) return;
    _menuReactionsLoading = YES;
    ExteriaWeakReference *weak = _weak;
    [self whenPremiumKnown:^(BOOL premium) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        [chat->_session loadAvailableReactionsForDialog:chat->_dialog premium:premium completion:^(NSArray *choices, NSString *errorName) {
            ExteriaChatController *again = weak.target;
            if (!again) return;
            again->_menuReactionsLoading = NO;
            if (!choices) {
                NSLog(@"exteria: the reactions for the menu did not load: %@", errorName);
                return;
            }
            again->_menuReactions = [choices copy];
            if (then) then();
        }];
    }];
}

- (void)fillReadersPage:(ExteriaSettingsPageController *)page readers:(NSArray *)readers people:(NSDictionary *)people {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *reader in readers) {
        NSNumber *user = [reader objectForKey:@"user"];
        ExteriaPerson *person = [people objectForKey:user];
        NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", user];
        int32_t date = [[reader objectForKey:@"date"] intValue];
        NSString *time = date > 0 ? ExteriaMediaTimeText(date) : NSLocalizedString(@"chat.msg.readtime.unavailable", nil);
        ExteriaReaderRowView *view = [[[ExteriaReaderRowView alloc] initWithPerson:person userId:user.longLongValue name:name time:time cache:_avatars] autorelease];
        [rows addObject:[ExteriaSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return 64; }]];
    }
    page.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:nil rows:rows]];
    [page reloadSettings];
}

- (void)showMessageMenuForCell:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    exteria_action_context context = [self actionContextOfMessage:message];
    uint32_t mask = exteria_message_actions_for(&context);
    /* a list of search results or pinned messages has no field to give way to the bar, so nothing is picked there */
    if (_pinnedList) mask &= ~(uint32_t)EXTERIA_ACTION_SELECT;
    /* the extra entries are the person's choice; the actions themselves stay available to a double tap */
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuCopyPhoto)) mask &= ~(uint32_t)EXTERIA_ACTION_COPY_PHOTO;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuHistory)) mask &= ~(uint32_t)EXTERIA_ACTION_HISTORY;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuReport)) mask &= ~(uint32_t)EXTERIA_ACTION_REPORT;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuNoQuote)) mask &= ~(uint32_t)EXTERIA_ACTION_FORWARD_HIDDEN;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuRemind)) mask &= ~(uint32_t)EXTERIA_ACTION_REMIND;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuSave)) mask &= ~(uint32_t)EXTERIA_ACTION_SAVE;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuRepeat)) mask &= ~(uint32_t)EXTERIA_ACTION_REPEAT;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuDetails)) mask &= ~(uint32_t)EXTERIA_ACTION_DETAILS;
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuBookmark)) mask &= ~(uint32_t)(EXTERIA_ACTION_BOOKMARK | EXTERIA_ACTION_UNBOOKMARK);
    if (!ExteriaChatFlagGet(ExteriaChatFlagMenuReplyPrivate)) mask &= ~(uint32_t)EXTERIA_ACTION_REPLY_PRIVATE;
    /* a message that was edited may have kept its earlier texts, and the person sees them from here */
    if (message.edited && !message.deletedLocally && ExteriaChatFlagGet(ExteriaChatFlagAyuSaveEdits)) mask |= EXTERIA_ACTION_EDIT_HISTORY;
    /* what was deleted is only read: it cannot be answered, changed, pinned or sent on, since the server no longer has it */
    if (message.deletedLocally) mask &= EXTERIA_ACTION_COPY | EXTERIA_ACTION_DETAILS | EXTERIA_ACTION_TRANSLATE | EXTERIA_ACTION_SELECT;
    else if (message.messageId > 0 && message.reactions.count) mask |= EXTERIA_ACTION_REACTORS;
    /* a one-time file must not be kept, sent on or sent again by this client */
    if (ExteriaMessageIsViewOnce(message)) mask &= ~(uint32_t)(EXTERIA_ACTION_FORWARD | EXTERIA_ACTION_FORWARD_HIDDEN | EXTERIA_ACTION_SAVE | EXTERIA_ACTION_GALLERY |
                                                              EXTERIA_ACTION_COPY_PHOTO | EXTERIA_ACTION_REPEAT | EXTERIA_ACTION_BOOKMARK | EXTERIA_ACTION_UNBOOKMARK);
    if (!mask) return;
    [self dismissInput];
    ExteriaWeakReference *weak = _weak;
    int32_t messageId = message.messageId;
    ExteriaMessageMenu *menu = [[[ExteriaMessageMenu alloc] init] autorelease];
    menu.icons = ExteriaMenuItems(ExteriaMessageActionIcons, sizeof(ExteriaMessageActionIcons) / sizeof(ExteriaMessageActionIcons[0]), mask);
    menu.rows = ExteriaMenuItems(ExteriaMessageActionRows, sizeof(ExteriaMessageActionRows) / sizeof(ExteriaMessageActionRows[0]), mask);
    menu.pickHandler = ^(NSUInteger tag) {
        ExteriaChatController *chat = weak.target;
        /* the message may have gone while the menu was open */
        ExteriaMessage *current = chat ? [chat messageWithId:messageId] : nil;
        if (current) [chat performAction:(exteria_message_action)tag onMessage:current];
    };
    menu.reactionHandler = ^(ExteriaReaction *reaction) {
        ExteriaChatController *chat = weak.target;
        if (chat && [chat messageWithId:messageId]) [chat chooseReaction:reaction messageId:messageId];
    };
    menu.moreReactionsHandler = ^{
        ExteriaChatController *chat = weak.target;
        ExteriaMessage *current = chat ? [chat messageWithId:messageId] : nil;
        if (current) [chat showReactionPickerForMessage:current];
    };
    /* the pill: at once when the reactions are known, as they arrive otherwise */
    BOOL reactable = message.messageId > 0 && message.reactionsPossible && ![self reactionsHidden];
    if (reactable && _menuReactions) {
        [menu setReactions:[self menuReactionsForMessage:message]];
    } else if (reactable) {
        ExteriaMessageMenu *shown = menu;
        [self loadMenuReactionsThen:^{
            ExteriaChatController *chat = weak.target;
            ExteriaMessage *current = chat ? [chat messageWithId:messageId] : nil;
            if (current) [shown setReactions:[chat menuReactionsForMessage:current]];
        }];
    }
    /* a message of ours in a private chat says whether it was read and when */
    if (message.outgoing && message.messageId > 0 && (_dialog.kind == EXTERIA_DIALOG_USER || _dialog.kind == EXTERIA_DIALOG_BOT) && !_dialog.saved) {
        BOOL read = message.messageId <= [self readOutboxMaxId];
        if (read) [menu setHeaderText:NSLocalizedString(@"chat.msg.read", nil) read:YES];
        else {
            [menu setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.sentat", nil), ExteriaClockText(message.date)] read:NO];
        }
        ExteriaMessageMenu *shown = menu;
        [_session loadReadDateOfMessageId:message.messageId ofDialog:_dialog completion:^(int32_t date, NSString *errorName) {
            if (errorName || date <= 0) {
                if (read) [shown setHeaderText:NSLocalizedString(@"chat.msg.readtime.unavailable", nil) read:YES];
                return;
            }
            [shown setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.readat", nil), ExteriaMediaTimeText(date)] read:YES];
        }];
    } else if (message.outgoing && message.messageId > 0 && _dialog.kind == EXTERIA_DIALOG_GROUP && !_dialog.saved) {
        ExteriaMessageMenu *shown = menu;
        [menu setHeaderText:NSLocalizedString(@"chat.msg.readtime.loading", nil) read:NO];
        [_session loadGroupReadDatesOfMessageId:message.messageId ofDialog:_dialog completion:^(NSArray *readers, NSString *errorName) {
            if (errorName) [shown setHeaderText:NSLocalizedString(@"chat.msg.readtime.unavailable", nil) read:NO];
            else if (!readers.count) [shown setHeaderText:NSLocalizedString(@"chat.msg.unread", nil) read:NO];
            else {
                shown.headerHandler = ^{
                    ExteriaChatController *chat = weak.target;
                    if (!chat) return;
                    ExteriaSettingsPageController *page = [[[ExteriaSettingsPageController alloc] init] autorelease];
                    page.pageTitle = NSLocalizedString(@"chat.msg.readers", nil);
                    [chat fillReadersPage:page readers:readers people:chat->_people];
                    [chat.navigationController pushViewController:page animated:YES];
                    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:readers.count];
                    for (NSDictionary *reader in readers) [ids addObject:[reader objectForKey:@"user"]];
                    [chat->_session loadCachedPeopleWithIds:ids completion:^(NSDictionary *people) {
                        ExteriaChatController *again = weak.target;
                        if (!again) return;
                        for (NSNumber *key in people) {
                            ExteriaPerson *known = [again->_people objectForKey:key], *cached = [people objectForKey:key];
                            if (!known || (!known.photo && cached.photo)) [again->_people setObject:cached forKey:key];
                        }
                        [again fillReadersPage:page readers:readers people:again->_people];
                    }];
                    if (chat->_dialog.peerKind == 2) {
                        [chat->_session loadSenderRolesOfDialog:chat->_dialog completion:^(NSDictionary *roles, NSDictionary *people, NSString *error) {
                            (void)roles;
                            ExteriaChatController *again = weak.target;
                            if (!again) return;
                            if (error) { NSLog(@"exteria: read participants could not be loaded: %@", error); return; }
                            [again->_people addEntriesFromDictionary:people];
                            [again fillReadersPage:page readers:readers people:again->_people];
                        }];
                    }
                    if (chat->_dialog.peerKind == 3) {
                        [chat->_session loadMembersOfDialog:chat->_dialog list:ExteriaChannelListSubscribers query:nil offset:0 completion:^(NSArray *members, NSInteger total, NSString *error) {
                            (void)total;
                            ExteriaChatController *again = weak.target;
                            if (!again) return;
                            if (error) { NSLog(@"exteria: read participants' names could not be loaded: %@", error); return; }
                            for (ExteriaChannelMember *member in members) {
                                if (member.person.userId > 0) [again->_people setObject:member.person forKey:[NSNumber numberWithLongLong:member.person.userId]];
                            }
                            [again fillReadersPage:page readers:readers people:again->_people];
                        }];
                    }
                };
                [shown setHeaderText:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.readers.count", nil), (unsigned long)readers.count] read:YES];
            }
        }];
    }
    CGRect bubble = [self.view convertRect:cell.item.bubbleFrame fromView:cell.contentView];
    CGRect rowFrame = [self.view convertRect:cell.contentView.bounds fromView:cell.contentView];
    CGRect clip = CGRectIntersection(rowFrame, _table.frame);
    if (CGRectIsNull(clip)) clip = CGRectZero;
    /* a message that is no taller than the list is lit whole, over the bar it was scrolled under, and the menu slides it into place; only a taller one
       (or half under the field) is lit and measured by the part of it that the list shows */
    BOOL fits = rowFrame.size.height <= _table.frame.size.height;
    CGRect litArea = _table.frame;
    if (fits) {
        litArea = self.view.bounds;
        CGRect whole = CGRectIntersection(bubble, self.view.bounds);
        if (!CGRectIsNull(whole) && !CGRectIsEmpty(whole)) bubble = whole;
    } else {
        CGRect shown = CGRectIntersection(bubble, _table.frame);
        if (!CGRectIsNull(shown) && !CGRectIsEmpty(shown)) bubble = shown;
    }
    [menu showInView:self.view bubble:bubble outgoing:message.outgoing snapshot:CGRectIsEmpty(clip) ? nil : [cell contentSnapshot] snapshotFrame:rowFrame clip:litArea];
}

- (BOOL)messageCellCanSwipeReply:(ExteriaMessageCell *)cell {
    if (_pinnedList || (_joinPending && _dialog.kind != EXTERIA_DIALOG_GROUP) || !cell.item.message) return NO;
    exteria_action_context context = [self actionContextOfMessage:cell.item.message];
    return (exteria_message_actions_for(&context) & EXTERIA_ACTION_REPLY) != 0;
}

- (void)messageCellDidSwipeReply:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = [self messageWithId:cell.item.message.messageId];
    if (message) [self beginReplyToMessage:message];
}

- (ExteriaMessage *)messageWithId:(int32_t)messageId {
    ExteriaMessage *message = [_server objectForKey:[NSNumber numberWithInt:messageId]];
    /* a reply to a message that was deleted shows its words only when the person asked for it, and is a reply to a message that is gone otherwise */
    if (message && message.deletedLocally && !ExteriaChatFlagGet(ExteriaChatFlagAyuReplyQuote)) return nil;
    if (message) return message;
    for (ExteriaMessage *local in _local) if (local.messageId == messageId) return local;
    return nil;
}

- (void)performAction:(exteria_message_action)action onMessage:(ExteriaMessage *)message {
    switch (action) {
    case EXTERIA_ACTION_REACT: [self showReactionPickerForMessage:message]; break;
    case EXTERIA_ACTION_REPLY: [self beginReplyToMessage:message]; break;
    case EXTERIA_ACTION_COPY:
        [UIPasteboard generalPasteboard].string = message.text;
        [self toast:NSLocalizedString(@"profile.copied", nil)];
        break;
    case EXTERIA_ACTION_COPY_LINK: [self copyLinkOfMessage:message]; break;
    case EXTERIA_ACTION_REMIND: [self chooseReminderForMessage:message]; break;
    case EXTERIA_ACTION_REPLY_PRIVATE: [self replyInPrivateToMessage:message]; break;
    case EXTERIA_ACTION_EDIT: [self beginEditingMessage:message]; break;
    case EXTERIA_ACTION_FORWARD: [self forwardMessage:message hideAuthor:NO]; break;
    case EXTERIA_ACTION_FORWARD_HIDDEN: [self forwardMessage:message hideAuthor:YES]; break;
    case EXTERIA_ACTION_COPY_PHOTO: [self copyPhotoOfMessage:message]; break;
    case EXTERIA_ACTION_HISTORY: [self openHistoryOfMessage:message]; break;
    case EXTERIA_ACTION_REPORT:
        [ExteriaMessageReportFlow startForMessageIds:[NSArray arrayWithObject:[NSNumber numberWithInt:message.messageId]] dialog:_dialog session:_session host:self];
        break;
    case EXTERIA_ACTION_SAVE: [self saveMessageToFavorites:message]; break;
    case EXTERIA_ACTION_GALLERY: [self saveMediaOfMessage:message]; break;
    case EXTERIA_ACTION_SELECT: [self beginSelectionWith:message]; break;
    case EXTERIA_ACTION_BOOKMARK: [self bookmarkMessage:message]; break;
    case EXTERIA_ACTION_UNBOOKMARK:
        if ([[ExteriaBookmarks bookmarksForSession:_session] removeMessageId:message.messageId inDialog:_dialog]) [self toast:NSLocalizedString(@"chat.msg.unbookmarked", nil)];
        else ExteriaGiftAlert(nil, NSLocalizedString(@"bookmarks.failed", nil));
        break;
    case EXTERIA_ACTION_TRANSCRIBE: [self transcribeMessage:message]; break;
    case EXTERIA_ACTION_TRANSLATE: [self translateMessage:message]; break;
    case EXTERIA_ACTION_REPEAT: {
        NSString *again = [[message.text copy] autorelease];
        [self askFirst:ExteriaChatFlagAskRepeat message:NSLocalizedString(@"chat.ask.repeat", nil) action:NSLocalizedString(@"chat.ask.repeat.action", nil) then:^{
            [self sendText:again entities:nil];
        } declined:nil];
        break;
    }
    case EXTERIA_ACTION_PIN: [self pinMessage:message unpin:NO]; break;
    case EXTERIA_ACTION_UNPIN: [self pinMessage:message unpin:YES]; break;
    case EXTERIA_ACTION_DETAILS: [self showDetailsOfMessage:message]; break;
    case EXTERIA_ACTION_REACTORS: {
        ExteriaReactionPeopleController *page = [[[ExteriaReactionPeopleController alloc] initWithSession:_session dialog:_dialog messageId:message.messageId] autorelease];
        [self.navigationController pushViewController:page animated:YES];
        break;
    }
    case EXTERIA_ACTION_EDIT_HISTORY: [self showEditHistoryOfMessage:message]; break;
    case EXTERIA_ACTION_DELETE:
        _deleteId = message.messageId;
        [self askWithMessage:NSLocalizedString(@"chat.msg.delete.confirm", nil) action:NSLocalizedString(@"chat.msg.delete", nil) tag:ExteriaChatAlertDeleteMessage];
        break;
    }
}

#pragma mark edit history

/* the texts the message had before its edits, the oldest first, and the one it has now at the end */
- (void)showEditHistoryOfMessage:(ExteriaMessage *)message {
    ExteriaWeakReference *weak = _weak;
    NSString *current = message.text;
    int32_t editedAt = message.date;
    [_session loadEditVersionsOfMessage:message.messageId dialog:_dialog completion:^(NSArray *versions) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!versions.count) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"chat.edithistory.none", nil));
            return;
        }
        [chat.navigationController pushViewController:[[[ExteriaEditHistoryController alloc] initWithVersions:versions current:current date:editedAt] autorelease] animated:YES];
    }];
}

#pragma mark reply and edit

- (void)showComposeSymbol:(ExteriaSymbol)symbol title:(NSString *)title text:(NSString *)text {
    [_context showSymbol:symbol title:title text:text];
    _context.hidden = NO;
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
}

- (void)beginReplyToMessage:(ExteriaMessage *)message {
    [self showReplyToMessage:message];
    [_input.textView becomeFirstResponder];
}

/* the strip over the field names the message answered; a draft that answers one brings it back without the keyboard */
- (void)showReplyToMessage:(ExteriaMessage *)message {
    [self cancelCompose];
    _pendingDraftReply = 0;
    _replyToId = message.messageId;
    [self showComposeSymbol:ExteriaSymbolReply title:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.reply.title", nil), [self senderNameOfMessage:message]]
                       text:ExteriaMessageSummary(message)];
    [self draftStateChanged];
}

- (void)beginEditingMessage:(ExteriaMessage *)message {
    /* the words in the field are a draft, and editing another message must not turn them into that message's draft: they wait to come back */
    BOOL wasEditing = _editingId != 0;
    ExteriaDraft *keep = wasEditing ? nil : [self fieldDraft];
    [self cancelCompose];
    if (wasEditing) keep = [self fieldDraft];
    [_stashedDraft release];
    _stashedDraft = [keep retain];
    _editingId = message.messageId;
    [self showComposeSymbol:ExteriaSymbolCompose title:NSLocalizedString(@"chat.msg.edit.title", nil) text:message.text];
    [self applyDraft:message.text];
}

/* drops the strip; a message that was being edited takes its text out of the field with it */
- (void)cancelCompose {
    BOOL editing = _editingId != 0;
    _replyToId = 0;
    _pendingDraftReply = 0;
    _editingId = 0;
    if (_context.hidden) {
        [self draftStateChanged];
        return;
    }
    _context.hidden = YES;
    if (editing) {
        ExteriaDraft *back = [[_stashedDraft retain] autorelease];
        [_stashedDraft release];
        _stashedDraft = nil;
        _applyingDraft = YES;
        if (back.text.length) [_input setText:back.text entities:back.entities];
        else [_input clear];
        _applyingDraft = NO;
        if (back.replyTo) [self restoreDraftReplyTo:back.replyTo];
    }
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
    [self draftStateChanged];
}

#pragma mark drafts

/* the field and the strip as a draft would keep them */
- (ExteriaDraft *)fieldDraft {
    NSString *text = [_input trimmedText];
    return [[[ExteriaDraft alloc] initWithText:text entities:text.length ? [_input sendEntities] : nil replyTo:_replyToId ? _replyToId : _pendingDraftReply
                                     noWebpage:ExteriaChatFlagGet(ExteriaChatFlagNoLinkPreview) date:0] autorelease];
}

/* what two lists of entities say about the text, offsets and targets included */
static NSString *ExteriaEntitySignature(NSArray *entities) {
    NSMutableString *signature = [NSMutableString string];
    for (ExteriaTextEntity *entity in entities) {
        [signature appendFormat:@"%d:%lu:%lu:%@:%lld:%lld;", (int)entity.style, (unsigned long)entity.range.location, (unsigned long)entity.range.length,
                                entity.url ? entity.url : @"", entity.documentId, entity.userId];
    }
    return signature;
}

- (void)restoreDraft {
    if (_pinnedList || _dialog.savedSource) return;
    ExteriaDraft *draft = [_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId];
    [self applyBoardDraft:draft];
}

/* puts a draft of the account in the field and the strip, without the keyboard and without taking it for something the person typed */
- (void)applyBoardDraft:(ExteriaDraft *)draft {
    _applyingDraft = YES;
    if (draft.text.length) [_input setText:draft.text entities:draft.entities];
    else [_input clear];
    [self cancelCompose];
    _applyingDraft = NO;
    if (draft.replyTo) [self restoreDraftReplyTo:draft.replyTo];
}

- (void)restoreDraftReplyTo:(int32_t)messageId {
    ExteriaMessage *known = [self messageWithId:messageId];
    if (known) {
        [self showReplyToMessage:known];
        return;
    }
    _pendingDraftReply = messageId;
    ExteriaWeakReference *weak = _weak;
    [_session loadMessagesWithIds:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] ofDialog:_dialog completion:^(NSArray *messages, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat || chat->_pendingDraftReply != messageId) return;
        chat->_pendingDraftReply = 0;
        ExteriaMessage *found = messages.count ? [messages objectAtIndex:0] : nil;
        if (!found) {
            /* the message is gone, so the draft no longer answers anything and the next save says so */
            NSLog(@"exteria: the message %d a draft answers did not load: %@", (int)messageId, errorName ? errorName : @"missing");
            [chat draftStateChanged];
            return;
        }
        if (chat->_replyToId || chat->_editingId) return;
        [chat showReplyToMessage:found];
    }];
}

- (void)draftStateChanged {
    if (!_draftsActive || _applyingDraft || _editingId) return;
    /* a save for every key press would be a request for every key press */
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil];
    [self performSelector:@selector(saveDraftNow) withObject:nil afterDelay:1.0];
}

- (void)saveDraftNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveDraftNow) object:nil];
    if (!_draftsActive || _applyingDraft || _editingId) return;
    ExteriaDraft *field = [self fieldDraft];
    ExteriaDraft *kept = [_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId];
    if (field.empty && !kept) return;
    if (kept && [kept.text isEqualToString:field.text] && kept.replyTo == field.replyTo &&
        [ExteriaEntitySignature(kept.entities) isEqualToString:ExteriaEntitySignature(field.entities)]) return;
    [_session saveDraftText:field.text entities:field.entities replyTo:field.replyTo noWebpage:field.noWebpage forDialog:_dialog];
}

/* the account sent another draft for this chat, such as one typed on another phone */
- (void)draftBoardChanged:(NSNotification *)note {
    if (!_draftsActive || _editingId || [[note.userInfo objectForKey:@"local"] boolValue] || !ExteriaDraftChangeConcerns(note, _dialog)) return;
    /* what the person is typing here is not replaced under their fingers */
    if (_input.textView.isFirstResponder && [_input trimmedText].length) return;
    [self applyBoardDraft:[_session.drafts draftForKind:_dialog.peerKind peer:_dialog.peerId top:_dialog.topicId]];
}

- (void)commitEditWithText:(NSString *)text {
    if (_editBusy) return;
    int32_t messageId = _editingId;
    ExteriaMessage *original = [self messageWithId:messageId];
    if (!original || [original.text isEqualToString:text]) {
        [self cancelCompose];
        return;
    }
    _editBusy = YES;
    ExteriaWeakReference *weak = _weak;
    /* a message with a picture, a video or a file changes its caption, and the media stays */
    exteria_preview_kind kind = original.media.kind;
    BOOL caption = kind != EXTERIA_PREVIEW_NONE && kind != EXTERIA_PREVIEW_TEXT;
    void (^edited)(NSString *) = ^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_editBusy = NO;
        /* the server saying nothing changed is the text it already has */
        if (errorName && ![errorName isEqualToString:@"MESSAGE_NOT_MODIFIED"]) {
            NSLog(@"exteria: editing message %d failed: %@", (int)messageId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        if (!errorName) {
            /* the server's copy comes back through the store, and reads the same; until it does the row says edited with the new words */
            ExteriaMessage *shown = [chat messageWithId:messageId];
            [shown noteEditedToText:text];
            for (ExteriaMessage *local in chat->_local) if (local.messageId == messageId) [local noteEditedToText:text];
            [chat rebuildItems];
        }
        if (chat->_editingId == messageId) [chat cancelCompose];
    };
    if (caption) [_session editCaptionOfMessageId:messageId ofDialog:_dialog text:text completion:edited];
    else [_session editMessageId:messageId ofDialog:_dialog text:text completion:edited];
}

#pragma mark pin, forward, delete, details

- (void)pinMessage:(ExteriaMessage *)message unpin:(BOOL)unpin {
    ExteriaWeakReference *weak = _weak;
    [_session pinMessageId:message.messageId ofDialog:_dialog unpin:unpin completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"exteria: pin of message %d failed: %@", (int)message.messageId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [chat toast:NSLocalizedString(unpin ? @"chat.msg.unpinned" : @"chat.msg.pinned", nil)];
        /* the pinned bar of a channel follows the full channel */
        if (chat->_dialog.peerKind == 3) [chat loadChannelFull];
    }];
}

- (void)forwardMessage:(ExteriaMessage *)message hideAuthor:(BOOL)hideAuthor {
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"chat.msg.forward.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(ExteriaDialog *dialog) {
        return !dialog.folder && !dialog.community && (dialog.kind != EXTERIA_DIALOG_CHANNEL || dialog.canPost);
    };
    ExteriaWeakReference *weak = _weak;
    NSNumber *messageId = [NSNumber numberWithInt:message.messageId];
    picker.pickHandler = ^(NSArray *dialogs) {
        ExteriaChatController *chat = weak.target;
        ExteriaDialog *target = [dialogs lastObject];
        if (!chat || !target) return;
        [chat->_session forwardMessageIds:[NSArray arrayWithObject:messageId] fromDialog:chat->_dialog toDialog:target hideAuthor:hideAuthor completion:^(NSString *errorName) {
            ExteriaChatController *again = weak.target;
            if (errorName) {
                NSLog(@"exteria: forward of message %@ failed: %@", messageId, errorName);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.forwarded", nil)];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

/* the address of a message: from the name of a public channel, or from the server for a private one */
- (void)copyLinkOfMessage:(ExteriaMessage *)message {
    if (_channelFull.username.length) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://t.me/%@/%d", _channelFull.username, (int)message.messageId];
        [self toast:NSLocalizedString(@"chat.link.copied", nil)];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    [_session exportLinkOfMessageId:message.messageId ofDialog:_dialog completion:^(NSString *link, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (!link) {
            NSLog(@"exteria: the link of a message was not made: %@", errorName);
            ExteriaGiftAlert(NSLocalizedString(@"chat.link.failed", nil), ExteriaGiftErrorText(errorName));
            return;
        }
        [UIPasteboard generalPasteboard].string = link;
        [chat toast:NSLocalizedString(@"chat.link.copied", nil)];
    }];
}

/* a reminder is a message the server sends to the favorites later: the person picks the time from a few, and the text names the message */
- (void)chooseReminderForMessage:(ExteriaMessage *)message {
    NSString *summary = ExteriaMessageSummary(message);
    if (summary.length > 200) summary = [[summary substringToIndex:200] stringByAppendingString:@"\u2026"];
    NSString *line = [NSString stringWithFormat:NSLocalizedString(@"chat.remind.text", nil), summary];
    if (_channelFull.username.length) line = [NSString stringWithFormat:@"%@\nhttps://t.me/%@/%d", line, _channelFull.username, (int)message.messageId];
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"chat.remind.hour", nil), NSLocalizedString(@"chat.remind.three", nil),
                       NSLocalizedString(@"chat.remind.tomorrow", nil), NSLocalizedString(@"chat.remind.week", nil), nil];
    ExteriaWeakReference *weak = _weak;
    [ExteriaSheet presentInView:self.view title:NSLocalizedString(@"chat.remind.title", nil) message:nil options:titles destructive:nil
                    cancelTitle:NSLocalizedString(@"picker.cancel", nil) handler:^(NSUInteger index) {
        ExteriaChatController *chat = weak.target;
        if (chat) [chat scheduleReminder:line choice:index];
    }];
}

- (void)scheduleReminder:(NSString *)line choice:(NSUInteger)choice {
    NSDate *now = [NSDate date], *when = nil;
    switch (choice) {
    case 0: when = [now dateByAddingTimeInterval:3600]; break;
    case 1: when = [now dateByAddingTimeInterval:3 * 3600]; break;
    case 2: {
        /* the next 9:00 in the person's calendar, tomorrow's even when it is not yet 9:00 today */
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *parts = [calendar components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:[now dateByAddingTimeInterval:86400]];
        parts.hour = 9;
        when = [calendar dateFromComponents:parts];
        break;
    }
    default: when = [now dateByAddingTimeInterval:7 * 86400]; break;
    }
    if (!when) return;
    ExteriaWeakReference *weak = _weak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        ExteriaPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (!chat) return;
        if (!me) {
            NSLog(@"exteria: the account is not known for a reminder: %@", errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [chat->_session scheduleText:line atDate:(int32_t)[when timeIntervalSince1970] toDialog:[ExteriaDialog savedMessagesOfUserId:me.userId]
                          completion:^(NSString *scheduleError) {
            ExteriaChatController *again = weak.target;
            if (!again) return;
            if (scheduleError) {
                NSLog(@"exteria: the reminder was not set: %@", scheduleError);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(scheduleError));
                return;
            }
            [again toast:NSLocalizedString(@"chat.remind.set", nil)];
        }];
    }];
}

/* the private chat with the sender of a group message, with the words of the message quoted in the field */
- (void)replyInPrivateToMessage:(ExteriaMessage *)message {
    ExteriaPerson *sender = [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    ExteriaDialog *dialog = sender ? [ExteriaDialog dialogWithPerson:sender] : nil;
    if (!dialog) {
        [self toast:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    NSString *summary = ExteriaMessageSummary(message);
    if (summary.length > 120) summary = [[summary substringToIndex:120] stringByAppendingString:@"\u2026"];
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.draftText = [NSString stringWithFormat:@"\u00ab%@\u00bb\n", summary];
    [self.navigationController pushViewController:chat animated:YES];
}

/* the picture of a photo goes to the pasteboard */
- (void)copyPhotoOfMessage:(ExteriaMessage *)message {
    ExteriaWeakReference *weak = _weak;
    [ExteriaGallerySaver copyPhotoOfMedia:message.media cache:_media completion:^(NSString *failureKey) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (failureKey) ExteriaGiftAlert(nil, NSLocalizedString(failureKey, nil));
        else [chat toast:NSLocalizedString(@"profile.copied", nil)];
    }];
}

/* everything the sender wrote in this group, as a list over the chat like the search results */
- (void)openHistoryOfMessage:(ExteriaMessage *)message {
    ExteriaPerson *sender = [_people objectForKey:[NSNumber numberWithLongLong:message.senderKey]];
    if (!sender) return;
    ExteriaChatController *list = [[[ExteriaChatController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    list.pinnedList = YES;
    list.historyPerson = sender;
    [self.navigationController pushViewController:list animated:YES];
}

/* the photo or video goes to the library of the phone; a large video takes a while, so the person is told it started */
- (void)saveMediaOfMessage:(ExteriaMessage *)message {
    [self toast:NSLocalizedString(@"chat.msg.gallery.saving", nil)];
    ExteriaWeakReference *weak = _weak;
    [ExteriaGallerySaver saveMedia:message.media cache:_media completion:^(NSString *failureKey) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (failureKey) ExteriaGiftAlert(nil, NSLocalizedString(failureKey, nil));
        else [chat toast:NSLocalizedString(@"media.saved", nil)];
    }];
}

#pragma mark selection

/* the messages that are picked, oldest first, and only those the screen still holds */
- (NSArray *)selectedMessages {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSNumber *identifier in _selectedIds) {
        ExteriaMessage *message = [self messageWithId:identifier.intValue];
        if (message) [messages addObject:message];
    }
    [messages sortUsingComparator:^NSComparisonResult(ExteriaMessage *a, ExteriaMessage *b) {
        return a.messageId < b.messageId ? NSOrderedAscending : (a.messageId > b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    return messages;
}

/* the bar says how many are picked and offers what all of them allow together */
- (void)refreshSelectionBar {
    NSArray *messages = [self selectedMessages];
    uint32_t masks[EXTERIA_MESSAGES_MAX];
    size_t count = MIN(messages.count, (NSUInteger)EXTERIA_MESSAGES_MAX);
    for (size_t i = 0; i < count; ++i) {
        exteria_action_context context = [self actionContextOfMessage:[messages objectAtIndex:i]];
        masks[i] = exteria_message_actions_for(&context);
    }
    uint32_t together = exteria_selection_actions(masks, count);
    [_selectionBar setCount:messages.count forward:(together & EXTERIA_ACTION_FORWARD) != 0 copy:(together & EXTERIA_ACTION_COPY) != 0
                     delete:(together & EXTERIA_ACTION_DELETE) != 0 range:messages.count >= 2];
}

/* every message of the screen between the oldest and the newest of those picked joins them, as far as one request can carry */
- (void)selectBetween {
    if (_selectedIds.count < 2) return;
    NSInteger first = NSNotFound, last = NSNotFound;
    for (NSUInteger i = 0; i < _items.count; ++i) {
        ExteriaChatItem *item = [_items objectAtIndex:i];
        if (!item.message || item.kind == ExteriaChatItemPill || ![_selectedIds containsObject:[NSNumber numberWithInt:item.message.messageId]]) continue;
        if (first == NSNotFound) first = (NSInteger)i;
        last = (NSInteger)i;
    }
    if (first == NSNotFound || last <= first) return;
    for (NSInteger i = first; i <= last && _selectedIds.count < EXTERIA_MESSAGES_MAX; ++i) {
        ExteriaChatItem *item = [_items objectAtIndex:(NSUInteger)i];
        if (item.message && item.kind != ExteriaChatItemPill && item.message.messageId > 0) [_selectedIds addObject:[NSNumber numberWithInt:item.message.messageId]];
    }
    [self refreshSelectionBar];
    [self refreshSelectionOnCells];
}

- (void)refreshSelectionOnCells {
    for (UITableViewCell *row in _table.visibleCells) {
        ExteriaMessageCell *cell = (ExteriaMessageCell *)row;
        if (![cell isKindOfClass:[ExteriaMessageCell class]]) continue;
        [cell setSelecting:_selecting selected:[_selectedIds containsObject:[NSNumber numberWithInt:cell.item.message.messageId]] animated:YES];
    }
}

- (void)beginSelectionWith:(ExteriaMessage *)message {
    [self cancelCompose];
    [self dismissInput];
    _selecting = YES;
    [_selectedIds release];
    _selectedIds = [[NSMutableSet alloc] initWithObjects:[NSNumber numberWithInt:message.messageId], nil];
    _inputHiddenBeforeSelection = _input.hidden;
    _input.hidden = YES;
    _selectionBar.hidden = NO;
    [self refreshSelectionBar];
    [self refreshSelectionOnCells];
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
}

- (void)endSelection {
    if (!_selecting) return;
    _selecting = NO;
    [_selectedIds removeAllObjects];
    _selectionBar.hidden = YES;
    _input.hidden = _inputHiddenBeforeSelection;
    [self refreshSelectionOnCells];
    [UIView animateWithDuration:0.15 animations:^{ [self layoutChat]; }];
}

- (void)messageCellDidToggleSelection:(ExteriaMessageCell *)cell {
    NSNumber *identifier = [NSNumber numberWithInt:cell.item.message.messageId];
    if ([_selectedIds containsObject:identifier]) {
        [_selectedIds removeObject:identifier];
    } else if (_selectedIds.count >= EXTERIA_MESSAGES_MAX) {
        /* one request carries this many, which is as many as can be forwarded or deleted together */
        [self toast:NSLocalizedString(@"chat.select.limit", nil)];
        return;
    } else {
        [_selectedIds addObject:identifier];
    }
    [cell setSelecting:YES selected:[_selectedIds containsObject:identifier] animated:YES];
    [self refreshSelectionBar];
}

- (void)copySelected {
    NSMutableArray *texts = [NSMutableArray array];
    for (ExteriaMessage *message in [self selectedMessages]) if (message.text.length) [texts addObject:message.text];
    if (!texts.count) return;
    [UIPasteboard generalPasteboard].string = [texts componentsJoinedByString:@"\n"];
    [self toast:NSLocalizedString(@"profile.copied", nil)];
    [self endSelection];
}

- (void)forwardSelected {
    NSMutableArray *ids = [NSMutableArray array];
    for (ExteriaMessage *message in [self selectedMessages]) [ids addObject:[NSNumber numberWithInt:message.messageId]];
    if (!ids.count) return;
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"chat.msg.forward.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(ExteriaDialog *dialog) {
        return !dialog.folder && !dialog.community && (dialog.kind != EXTERIA_DIALOG_CHANNEL || dialog.canPost);
    };
    ExteriaWeakReference *weak = _weak;
    picker.pickHandler = ^(NSArray *dialogs) {
        ExteriaChatController *chat = weak.target;
        ExteriaDialog *target = [dialogs lastObject];
        if (!chat || !target) return;
        [chat->_session forwardMessageIds:ids fromDialog:chat->_dialog toDialog:target hideAuthor:NO completion:^(NSString *errorName) {
            ExteriaChatController *again = weak.target;
            if (errorName) {
                NSLog(@"exteria: forward of %lu messages failed: %@", (unsigned long)ids.count, errorName);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.forwarded", nil)];
            [again endSelection];
        }];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)askDeleteSelected {
    if (![self selectedMessages].count) return;
    [self askWithMessage:[NSString stringWithFormat:NSLocalizedString(@"chat.select.delete.confirm", nil), (long)[self selectedMessages].count]
                  action:NSLocalizedString(@"chat.msg.delete", nil) tag:ExteriaChatAlertDeleteSelected];
}

- (void)deleteSelectedNow {
    NSMutableArray *ids = [NSMutableArray array];
    for (ExteriaMessage *message in [self selectedMessages]) [ids addObject:[NSNumber numberWithInt:message.messageId]];
    if (!ids.count) return;
    ExteriaWeakReference *weak = _weak;
    [_session deleteMessageIds:ids ofDialog:_dialog revoke:!ExteriaChatFlagGet(ExteriaChatFlagDeleteForMe) completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"exteria: delete of %lu messages failed: %@", (unsigned long)ids.count, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        for (NSNumber *identifier in ids) {
            [chat->_server removeObjectForKey:identifier];
            for (ExteriaMessage *local in [[chat->_local copy] autorelease]) if (local.messageId == identifier.intValue) [chat->_local removeObject:local];
            if (chat->_replyToId == identifier.intValue || chat->_editingId == identifier.intValue) [chat cancelCompose];
        }
        [chat endSelection];
        [chat rebuildItems];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
    }];
}

/* the message goes into the list of bookmarks of this phone, with a line to know it by */
- (void)bookmarkMessage:(ExteriaMessage *)message {
    if ([[ExteriaBookmarks bookmarksForSession:_session] addMessageId:message.messageId date:message.date text:ExteriaMessageSummary(message) inDialog:_dialog]) {
        [self toast:NSLocalizedString(@"chat.msg.bookmarked", nil)];
    } else {
        ExteriaGiftAlert(nil, NSLocalizedString(@"bookmarks.failed", nil));
    }
}

#pragma mark transcript

/* the server writes a voice message down; it may still be listening, so a pending answer is asked for again a moment later */
#pragma mark translation

/* the button is off until the settings turn it on, and a message in a language the person left alone has none; a text whose language cannot be told has it */
- (BOOL)translateWantedForMessage:(ExteriaMessage *)message {
    if (!ExteriaTranslateButtonEnabled() || !message.text.length) return NO;
    NSString *guess = ExteriaGuessLanguageOfText(message.text);
    return !(guess && ExteriaTranslateSkips(guess));
}

/* the lines before the message, for an AI translator that was asked to read them */
- (NSString *)translationContextBefore:(ExteriaMessage *)message {
    if (ExteriaTranslateProviderChoice() != ExteriaTranslateProviderLLM || !ExteriaLlmUsesContext()) return nil;
    NSMutableArray *before = [NSMutableArray array];
    for (ExteriaMessage *other in [_server allValues]) {
        if (other.messageId > 0 && other.messageId < message.messageId && other.text.length && !other.service) [before addObject:other];
    }
    [before sortUsingComparator:^NSComparisonResult(ExteriaMessage *a, ExteriaMessage *b) {
        return a.messageId > b.messageId ? NSOrderedAscending : (a.messageId < b.messageId ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger count = MIN(before.count, (NSUInteger)ExteriaLlmContextCount());
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = count; i > 0; --i) {
        ExteriaMessage *other = [before objectAtIndex:i - 1];
        [lines addObject:[NSString stringWithFormat:@"%@: %@", [self senderNameOfMessage:other], other.text]];
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : nil;
}

- (void)translateMessage:(ExteriaMessage *)message {
    if (!message.text.length) return;
    NSString *context = [self translationContextBefore:message];
    if (!ExteriaThemeIsClassic()) {
        [ExteriaTranslateSheet presentInView:self.view text:message.text entities:message.entities session:_session context:context];
        return;
    }
    /* the classic style keeps to the system alert: a toast while the service works, then the words with Copy */
    [self toast:NSLocalizedString(@"tr.translating", nil)];
    [ExteriaTranslateJob translateText:message.text entities:message.entities to:ExteriaTranslateTargetLanguage() context:context session:_session
                             completion:^(ExteriaTranslation *translation, NSString *failure) {
        if (!translation) {
            ExteriaShowNotice(NSLocalizedString(@"tr.sheet.title", nil), failure);
            return;
        }
        NSString *words = translation.text;
        ExteriaShowAlert(NSLocalizedString(@"tr.sheet.title", nil), words, [NSArray arrayWithObjects:NSLocalizedString(@"tr.sheet.close", nil), NSLocalizedString(@"tr.copy", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            if (index == 1) [UIPasteboard generalPasteboard].string = words;
        });
    }];
}

- (void)transcribeMessage:(ExteriaMessage *)message {
    if (!_transcripts) _transcripts = [[NSMutableDictionary alloc] init];
    [self toast:NSLocalizedString(@"chat.msg.transcribing", nil)];
    [self requestTranscriptOfMessageId:message.messageId attempt:0];
}

- (void)requestTranscriptOfMessageId:(int32_t)messageId attempt:(NSUInteger)attempt {
    ExteriaWeakReference *weak = _weak;
    [_session transcribeMessageId:messageId ofDialog:_dialog completion:^(NSString *text, BOOL pending, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"exteria: transcription of message %d failed: %@", (int)messageId, errorName);
            ExteriaGiftAlert(nil, [errorName isEqualToString:@"PREMIUM_ACCOUNT_REQUIRED"] ? NSLocalizedString(@"chat.msg.transcribe.premium", nil)
                                                                                      : ExteriaGiftErrorText(errorName));
            return;
        }
        if (text.length) [chat showTranscript:text ofMessageId:messageId];
        if (pending && attempt < 12) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [(ExteriaChatController *)weak.target requestTranscriptOfMessageId:messageId attempt:attempt + 1];
            });
        } else if (!text.length) {
            ExteriaGiftAlert(nil, NSLocalizedString(@"chat.msg.transcribe.empty", nil));
        }
    }];
}

/* the words go under the voice message; its item is built again to carry them */
- (void)showTranscript:(NSString *)text ofMessageId:(int32_t)messageId {
    ExteriaMessage *message = [self messageWithId:messageId];
    if (!message) return;
    [_transcripts setObject:text forKey:[NSNumber numberWithInt:messageId]];
    [_itemCache removeObjectForKey:[self cacheKeyForMessage:message]];
    [self rebuildItems];
}

/* one tap passes the message to the favorites, with no list of chats to pick from; the favorites are the chat with the account's own user id */
- (void)saveMessageToFavorites:(ExteriaMessage *)message {
    ExteriaWeakReference *weak = _weak;
    NSNumber *messageId = [NSNumber numberWithInt:message.messageId];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        ExteriaPerson *me = items.count ? [items objectAtIndex:0] : nil;
        if (!chat) return;
        if (!me) {
            NSLog(@"exteria: the account is not known for the favorites: %@", errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [chat->_session forwardMessageIds:[NSArray arrayWithObject:messageId] fromDialog:chat->_dialog toDialog:[ExteriaDialog savedMessagesOfUserId:me.userId] hideAuthor:NO
                               completion:^(NSString *forwardError) {
            ExteriaChatController *again = weak.target;
            if (!again) return;
            if (forwardError) {
                NSLog(@"exteria: saving message %@ failed: %@", messageId, forwardError);
                ExteriaGiftAlert(nil, ExteriaGiftErrorText(forwardError));
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
            [again toast:NSLocalizedString(@"chat.msg.saved", nil)];
        }];
    }];
}

- (void)deleteMessageNow {
    int32_t messageId = _deleteId;
    _deleteId = 0;
    if (messageId <= 0) return;
    ExteriaWeakReference *weak = _weak;
    [_session deleteMessageIds:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] ofDialog:_dialog revoke:!ExteriaChatFlagGet(ExteriaChatFlagDeleteForMe) completion:^(NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        if (errorName) {
            NSLog(@"exteria: delete of message %d failed: %@", (int)messageId, errorName);
            ExteriaGiftAlert(nil, ExteriaGiftErrorText(errorName));
            return;
        }
        [chat->_server removeObjectForKey:[NSNumber numberWithInt:messageId]];
        for (ExteriaMessage *local in [[chat->_local copy] autorelease]) if (local.messageId == messageId) [chat->_local removeObject:local];
        if (chat->_replyToId == messageId || chat->_editingId == messageId) [chat cancelCompose];
        [chat rebuildItems];
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaDialogsChangedNotification object:nil];
    }];
}

- (void)showDetailsOfMessage:(ExteriaMessage *)message {
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.id", nil), (int)message.messageId]];
    NSDate *sent = [NSDate dateWithTimeIntervalSince1970:message.date];
    [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.sent", nil),
        [NSDateFormatter localizedStringFromDate:sent dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]]];
    if (!message.post) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.from", nil), [self senderNameOfMessage:message]]];
    if (message.forwarded) {
        [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.forward", nil),
            ExteriaForwardName(message, _people).length ? ExteriaForwardName(message, _people) : NSLocalizedString(@"chat.someone", nil)]];
    }
    if (message.views > 0) [lines addObject:[NSString stringWithFormat:NSLocalizedString(@"chat.msg.details.views", nil), (int)message.views]];
    ExteriaGiftAlert(NSLocalizedString(@"chat.msg.details", nil), [lines componentsJoinedByString:@"\n"]);
}

#pragma mark gifts

/* a gift goes to a person: not to a bot, a group, a channel or the chat with oneself */
- (BOOL)canReceiveGift {
    return _dialog.kind == EXTERIA_DIALOG_USER && !_dialog.saved;
}

- (void)openGiftCatalog {
    ExteriaGiftCatalogController *catalog = [[[ExteriaGiftCatalogController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:catalog animated:YES];
}

/* the picture and name at the top of the chat open the gifts of that person, or our own for the saved messages */
/* the favorites split by the chat each message came from, as the saved chats of exteraGram */
- (void)openSavedDialogs {
    [self.navigationController pushViewController:ExteriaTopicsScreen(_session, _dialog, _avatars, _media, _stickers, nil) animated:YES];
}

- (void)openProfileGifts {
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    BOOL channelLike = _dialog.peerKind == 3;
    if (!_dialog.saved && _dialog.kind != EXTERIA_DIALOG_USER && _dialog.kind != EXTERIA_DIALOG_BOT && !channelLike) return;
    [_input.textView resignFirstResponder];
    UIViewController *screen;
    if (_dialog.saved) {
        screen = [[[ExteriaSavedMediaController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media] autorelease];
    } else if (channelLike) {
        screen = [[[ExteriaChannelProfileController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    } else {
        screen = [[[ExteriaUserProfileController alloc] initWithSession:_session dialog:_dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    }
    [self.navigationController pushViewController:screen animated:YES];
    NSLog(@"exteria: the profile screen was made and pushed in %.0f ms", ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
}

/* the chat as a sender: what an anonymous admin's message shows as its name and picture */
- (ExteriaPerson *)chatAsPerson {
    exteria_person_row row;
    memset(&row, 0, sizeof(row));
    row.id = _dialog.peerId;
    row.access_hash = _dialog.peerHash;
    snprintf(row.name, sizeof(row.name), "%s", _dialog.title.UTF8String);
    if (_dialog.photo) row.photo = _dialog.photo.ref;
    return [[[ExteriaPerson alloc] initWithRow:&row] autorelease];
}

- (void)messageCellDidTapSender:(ExteriaMessageCell *)cell {
    [self openSender:cell.item.senderPerson key:cell.item.message.senderKey messageId:cell.item.message.messageId];
}

/* the line "forwarded from" opens the profile or the channel of whoever wrote the message, as in exteraGram; one who hid the link to their account cannot be opened,
   and the plate says so */
- (void)messageCellDidTapForward:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    long long key = message.forwardKey;
    if (!key) {
        NSString *name = ExteriaForwardName(message, _people);
        ExteriaShowNotice(nil, name.length ? [NSString stringWithFormat:NSLocalizedString(@"chat.forward.hidden.named", nil), name] : NSLocalizedString(@"chat.forward.hidden", nil));
        return;
    }
    ExteriaPerson *person = [_people objectForKey:[NSNumber numberWithLongLong:key]];
    if (key > 0 && !person) {
        [_router openProfileOfUser:key inMessage:message.messageId dialog:_dialog];
        return;
    }
    [self openSender:person key:key messageId:message.messageId];
}

- (void)openSender:(ExteriaPerson *)person key:(long long)key messageId:(int32_t)messageId {
    /* the group itself wrote it: its own profile is the place to go */
    if (!key) {
        [self openProfileGifts];
        return;
    }
    if (!person) return;
    if (key > 0 && !person.accessHash) {
        [_router openProfileOfUser:key inMessage:messageId dialog:_dialog];
        return;
    }
    if (key < 0 && !person.accessHash) {
        ExteriaWeakReference *weak = _weak;
        [_session loadChannelSender:-key ofMessage:messageId inDialog:_dialog completion:^(ExteriaPerson *sender, NSString *errorName) {
            ExteriaChatController *chat = weak.target;
            if (!chat || chat.navigationController.topViewController != chat) return;
            if (errorName) {
                [chat toast:[ExteriaLinkRouter textForError:errorName]];
                return;
            }
            [chat->_people setObject:sender forKey:[NSNumber numberWithLongLong:key]];
            [chat rebuildItems];
            [chat openSender:sender key:key messageId:messageId];
        }];
        return;
    }
    ExteriaDialog *dialog = nil;
    if (key > 0) dialog = [ExteriaDialog dialogWithPerson:person];
    else {
        exteria_dialog_row row;
        memset(&row, 0, sizeof(row));
        row.peer_kind = 3;
        row.peer_id = -key;
        row.peer_hash = person.accessHash;
        row.kind = EXTERIA_DIALOG_CHANNEL;
        row.verified = person.verified;
        if (person.photo) row.photo = person.photo.ref;
        snprintf(row.title, sizeof(row.title), "%s", person.name.UTF8String);
        dialog = [[[ExteriaDialog alloc] initWithRow:&row] autorelease];
    }
    if (!dialog) {
        [self toast:NSLocalizedString(@"error.internal", nil)];
        return;
    }
    [_input.textView resignFirstResponder];
    UIViewController *profile = key > 0
        ? [[[ExteriaUserProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease]
        : [[[ExteriaChannelProfileController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}

#pragma mark recording

/* the round video is limited to a minute, as the other clients limit it */
#define ROUND_SECONDS_MAX 60.0
#define ROUND_PREVIEW_SIDE 240.0

static UIImage *ExteriaRoundTorchImage(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 22), NO, 0);
    UIBezierPath *bolt = [UIBezierPath bezierPath];
    [bolt moveToPoint:CGPointMake(12, 1)];
    [bolt addLineToPoint:CGPointMake(4, 12)];
    [bolt addLineToPoint:CGPointMake(10, 12)];
    [bolt addLineToPoint:CGPointMake(8, 21)];
    [bolt addLineToPoint:CGPointMake(18, 9)];
    [bolt addLineToPoint:CGPointMake(12, 9)];
    [bolt closePath];
    [color setFill];
    [bolt fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)showRecordingFailure:(NSString *)reason {
    Class alertClass = NSClassFromString(@"UIAlertView");
    NSString *text = reason.length ? [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"chat.record.unavailable", nil), reason]
                                   : NSLocalizedString(@"chat.record.unavailable", nil);
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

- (BOOL)inputBar:(ExteriaInputBar *)bar didBeginRecording:(ExteriaRecordMode)mode {
    (void)bar;
    if (_voice || _roundRecorder) return NO;
    [self.view endEditing:YES];
    if (mode == ExteriaRecordVoice) {
        _voice = [[ExteriaVoiceRecorder alloc] init];
        if (![_voice start]) {
            [_voice release];
            _voice = nil;
            [self showRecordingFailure:nil];
            return NO;
        }
    } else {
        _roundRecorder = [[ExteriaRoundRecorder alloc] init];
        if (![_roundRecorder start]) {
            NSString *reason = [[_roundRecorder.failure copy] autorelease];
            [_roundRecorder release];
            _roundRecorder = nil;
            [self showRecordingFailure:reason];
            return NO;
        }
        [self showRoundPreview];
        [[ExteriaMusicPlayer sharedPlayer] pauseForRecording];
    }
    _recordTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(recordTick) userInfo:nil repeats:YES] retain];
    return YES;
}

/* the screen behind the picture dims while the clip records; the input bar stays above the shade with its record button and hints */
- (void)showRoundShade {
    _roundShade = [[UIView alloc] initWithFrame:self.view.bounds];
    _roundShade.backgroundColor = [UIColor blackColor];
    _roundShade.alpha = 0;
    _roundShade.userInteractionEnabled = NO;
    _roundShade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:_roundShade belowSubview:_input];
    [UIView animateWithDuration:0.2 animations:^{ _roundShade.alpha = 0.5; }];
}

- (void)removeRoundShade {
    UIView *shade = _roundShade;
    _roundShade = nil;
    if (!shade) return;
    [UIView animateWithDuration:0.2 animations:^{ shade.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [shade removeFromSuperview];
        [shade release];
    }];
}

/* the picture grows out of the record button, overshoots a little and settles, as the other clients do it */
- (void)showRoundPreview {
    [self showRoundShade];
    CGSize size = self.view.bounds.size;
    CGRect frame = CGRectMake((size.width - ROUND_PREVIEW_SIDE) / 2, MAX(60, (_input.frame.origin.y - ROUND_PREVIEW_SIDE) / 2),
                              ROUND_PREVIEW_SIDE, ROUND_PREVIEW_SIDE);
    _roundPreview = [[UIView alloc] initWithFrame:frame];
    UIView *disc = [[[UIView alloc] initWithFrame:_roundPreview.bounds] autorelease];
    disc.layer.cornerRadius = ROUND_PREVIEW_SIDE / 2;
    disc.layer.masksToBounds = YES;
    disc.layer.borderWidth = 3;
    disc.layer.borderColor = ExteriaColorAccent().CGColor;
    disc.backgroundColor = [UIColor blackColor];
    CALayer *picture = _roundRecorder.previewLayer;
    picture.frame = disc.bounds;
    [disc.layer addSublayer:picture];
    [_roundPreview addSubview:disc];
    UIImageView *flip = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolCameraFlip, 22, [UIColor whiteColor])] autorelease];
    flip.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    flip.contentMode = UIViewContentModeCenter;
    flip.frame = CGRectMake(ROUND_PREVIEW_SIDE * 0.7, ROUND_PREVIEW_SIDE * 0.7, 36, 36);
    flip.layer.cornerRadius = 18;
    [_roundPreview addSubview:flip];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(flipRoundCamera)] autorelease];
    [disc addGestureRecognizer:tap];
    _roundTorch = [UIButton buttonWithType:UIButtonTypeCustom];
    _roundTorch.frame = CGRectMake(ROUND_PREVIEW_SIDE * 0.7, ROUND_PREVIEW_SIDE * 0.14, 40, 40);
    _roundTorch.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    _roundTorch.layer.cornerRadius = 20;
    _roundTorch.accessibilityLabel = NSLocalizedString(@"chat.round.torch", nil);
    [_roundTorch addTarget:self action:@selector(toggleRoundTorch) forControlEvents:UIControlEventTouchUpInside];
    [_roundPreview addSubview:_roundTorch];
    [self refreshRoundTorch];
    UIPinchGestureRecognizer *pinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchedRoundPreview:)] autorelease];
    [_roundPreview addGestureRecognizer:pinch];
    [self.view addSubview:_roundPreview];

    CGPoint origin = [_input recordButtonCenterInView:self.view];
    CGPoint center = _roundPreview.center;
    CGAffineTransform small = CGAffineTransformScale(CGAffineTransformMakeTranslation(origin.x - center.x, origin.y - center.y), 0.1, 0.1);
    _roundPreview.alpha = 0;
    _roundPreview.transform = small;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        _roundPreview.alpha = 1;
        _roundPreview.transform = CGAffineTransformMakeScale(1.07, 1.07);
    } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.1 animations:^{ _roundPreview.transform = CGAffineTransformIdentity; }];
    }];
}

/* the circle dims and shrinks a little while the camera is swapped (the picture goes black for a moment while the
   session is held) */
- (void)flipRoundCamera {
    if (!_roundRecorder || !_roundPreview || _roundFlipping || _roundTorchBusy) return;
    _roundFlipping = YES;
    [self refreshRoundTorch];
    UIView *preview = _roundPreview;
    UIView *disc = [preview.subviews count] ? [preview.subviews objectAtIndex:0] : nil;
    UIView *flip = [preview.subviews count] > 1 ? [preview.subviews objectAtIndex:1] : nil;
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        disc.alpha = 0.25f;
        disc.transform = CGAffineTransformMakeScale(0.94f, 0.94f);
        flip.transform = CGAffineTransformMakeRotation((CGFloat)M_PI);
    } completion:nil];
    ExteriaWeakReference *weak = _weak;
    [_roundRecorder switchCameraWithCompletion:^(BOOL switched) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        chat->_roundFlipping = NO;
        [chat refreshRoundTorch];
        /* a little later than the swap, so the first frame of the new camera is already in the layer */
        [UIView animateWithDuration:0.3 delay:switched ? 0.12 : 0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            disc.alpha = 1;
            disc.transform = CGAffineTransformIdentity;
            flip.transform = CGAffineTransformMakeRotation(0);
        } completion:nil];
    }];
}

- (void)refreshRoundTorch {
    _roundTorch.hidden = !_roundRecorder || _roundFlipping || !_roundRecorder.canUseTorch;
    _roundTorch.enabled = !_roundTorchBusy;
    [_roundTorch setImage:ExteriaRoundTorchImage(_roundRecorder.torchOn ? ExteriaColorAccent() : [UIColor whiteColor]) forState:UIControlStateNormal];
    _roundTorch.accessibilityValue = NSLocalizedString(_roundRecorder.torchOn ? @"chat.round.torch.on" : @"chat.round.torch.off", nil);
}

- (void)toggleRoundTorch {
    if (!_roundRecorder || _roundFlipping || _roundTorchBusy) return;
    _roundTorchBusy = YES;
    [self refreshRoundTorch];
    ExteriaRoundRecorder *recorder = _roundRecorder;
    ExteriaWeakReference *weak = _weak;
    [recorder setTorchOn:!recorder.torchOn completion:^(BOOL success) {
        ExteriaChatController *chat = weak.target;
        if (!chat || chat->_roundRecorder != recorder) return;
        chat->_roundTorchBusy = NO;
        [chat refreshRoundTorch];
        if (!success) ExteriaShowNotice(nil, NSLocalizedString(@"chat.round.torch.failed", nil));
    }];
}

/* two fingers on the circle zoom the camera, and a small label says how far; ios 7 and later, where the lens has the zoom */
- (void)pinchedRoundPreview:(UIPinchGestureRecognizer *)pinch {
    if (!_roundRecorder || !_roundRecorder.canZoom) return;
    if (pinch.state == UIGestureRecognizerStateBegan) _roundZoomStart = _roundRecorder.zoom;
    if (pinch.state != UIGestureRecognizerStateBegan && pinch.state != UIGestureRecognizerStateChanged) return;
    [_roundRecorder setZoom:_roundZoomStart * pinch.scale];
    CGFloat shown = MAX(1, MIN(5, _roundZoomStart * pinch.scale));
    if (!_roundZoomLabel) {
        _roundZoomLabel = [[UILabel alloc] init];
        _roundZoomLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
        _roundZoomLabel.textColor = [UIColor whiteColor];
        _roundZoomLabel.font = ExteriaFontSemibold(13);
        _roundZoomLabel.textAlignment = ExteriaTextAlignmentCenter;
        _roundZoomLabel.layer.cornerRadius = 11;
        _roundZoomLabel.layer.masksToBounds = YES;
        _roundZoomLabel.frame = CGRectMake((ROUND_PREVIEW_SIDE - 52) / 2, 14, 52, 22);
        [_roundPreview addSubview:_roundZoomLabel];
    }
    _roundZoomLabel.text = [NSString stringWithFormat:@"%.1f\u00d7", shown];
    _roundZoomLabel.alpha = 1;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [self performSelector:@selector(hideRoundZoomLabel) withObject:nil afterDelay:0.9];
}

- (void)hideRoundZoomLabel {
    [UIView animateWithDuration:0.25 animations:^{ _roundZoomLabel.alpha = 0; }];
}

/* the picture flies back into the button when it is sent */
- (void)dismissRoundPreviewSent:(BOOL)sent {
    UIView *preview = _roundPreview;
    _roundPreview = nil;
    _roundTorch = nil;
    _roundTorchBusy = NO;
    if (!preview) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [_roundZoomLabel release];
    _roundZoomLabel = nil;
    CGPoint center = preview.center;
    CGPoint target;
    if (sent) {
        target = [_input recordButtonCenterInView:self.view];
    } else {
        BOOL leaves = _roundRecorder.elapsed > 0.3;
        target = CGPointMake(leaves ? 24 : center.x, CGRectGetMidY(_input.frame));
    }
    CGAffineTransform gone = CGAffineTransformScale(CGAffineTransformMakeTranslation(target.x - center.x, target.y - center.y), 0.1, 0.1);
    preview.userInteractionEnabled = NO;
    [UIView animateWithDuration:sent ? 0.28 : 0.18 delay:0 options:sent ? UIViewAnimationOptionCurveEaseIn : UIViewAnimationOptionCurveEaseOut animations:^{
        preview.alpha = 0;
        preview.transform = gone;
    } completion:^(BOOL finished) {
        (void)finished;
        [preview removeFromSuperview];
        [preview release];
    }];
}

- (void)recordTick {
    NSTimeInterval elapsed = _voice ? _voice.elapsed : _roundRecorder.elapsed;
    [_input setRecordingElapsed:elapsed];
    /* a note that reaches the limit of the encoder goes by itself, a second short of it */
    if ((_roundRecorder && elapsed >= ROUND_SECONDS_MAX) || (_voice && elapsed >= EXTERIA_VOICE_SECONDS_MAX - 1)) {
        /* the minute is up: the clip goes now, and the hold that is still down ends without a second send */
        [self finishRecordingCancelled:NO];
        [_input releaseHold];
    }
}

- (void)stopRecordTimer {
    [_recordTimer invalidate];
    [_recordTimer release];
    _recordTimer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideRoundZoomLabel) object:nil];
    [_roundZoomLabel release];
    _roundZoomLabel = nil;
    [_roundPreview removeFromSuperview];
    [_roundPreview release];
    _roundPreview = nil;
    _roundTorch = nil;
    _roundTorchBusy = NO;
    [self removeRoundShade];
}

/* the screen goes away or the app is left: whatever was recording is dropped */
- (void)discardRecording {
    [self stopRecordTimer];
    [_voice cancel];
    [_voice release];
    _voice = nil;
    [_roundRecorder cancel];
    [_roundRecorder release];
    _roundRecorder = nil;
    [[ExteriaMusicPlayer sharedPlayer] resumeAfterRecording];
}

- (void)inputBar:(ExteriaInputBar *)bar didFinishRecordingCancelled:(BOOL)cancelled {
    /* the choice of the chip belongs to this recording alone: it is read now and the chip goes back to off */
    _recordingOneTime = !cancelled && bar.oneTimeRecording;
    [bar clearOneTimeRecording];
    [self finishRecordingCancelled:cancelled];
}

- (void)finishRecordingCancelled:(BOOL)cancelled {
    if (!_voice && !_roundRecorder) return;
    [self dismissRoundPreviewSent:!cancelled];
    if (cancelled) {
        [self discardRecording];
        return;
    }
    ExteriaWeakReference *weak = _weak;
    BOOL once = _recordingOneTime;
    _recordingOneTime = NO;
    ExteriaVoiceRecorder *voice = _voice;
    ExteriaRoundRecorder *round = _roundRecorder;
    _voice = nil;
    _roundRecorder = nil;
    [self stopRecordTimer];
    [[ExteriaMusicPlayer sharedPlayer] resumeAfterRecording];
    if (voice) {
        [voice finishWithCompletion:^(NSString *path, int32_t durationMs, NSData *waveform) {
            ExteriaChatController *chat = weak.target;
            if (path && chat) [chat sendRecordingAtPath:path durationMs:durationMs side:0 waveform:waveform viewOnce:once];
            else if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            else if (voice.failed) ExteriaGiftAlert(nil, NSLocalizedString(@"chat.voice.failed", nil));
            [voice release];
        }];
    } else {
        [round finishWithCompletion:^(NSString *path, int32_t durationMs, int32_t side) {
            ExteriaChatController *chat = weak.target;
            if (path && chat) [chat sendRecordingAtPath:path durationMs:durationMs side:side waveform:nil viewOnce:once];
            else if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [round release];
        }];
    }
}

- (void)sendRecordingAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side waveform:(NSData *)waveform viewOnce:(BOOL)once {
    NSString *file = [[path copy] autorelease];
    NSData *bars = [[waveform copy] autorelease];
    /* a recording nobody wants goes away with its file */
    [self askFirst:ExteriaChatFlagAskRecording message:NSLocalizedString(side > 0 ? @"chat.ask.round" : @"chat.ask.voice", nil) action:NSLocalizedString(@"chat.ask.record.action", nil) then:^{
        [self sendConfirmedRecordingAtPath:file durationMs:durationMs side:side waveform:bars viewOnce:once];
    } declined:^{
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
    }];
}

- (void)sendConfirmedRecordingAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side waveform:(NSData *)waveform viewOnce:(BOOL)once {
    ExteriaOutgoing *outgoing = [[[ExteriaOutgoing alloc] init] autorelease];
    outgoing->kind = side > 0 ? ExteriaOutgoingRound : ExteriaOutgoingVoice;
    outgoing->path = [path copy];
    outgoing->name = [path.lastPathComponent copy];
    outgoing->durationMs = durationMs;
    outgoing->width = side;
    outgoing->height = side;
    outgoing->waveform = [waveform copy];
    outgoing->temporary = YES;
    outgoing->viewOnce = once;
    [self sendOutgoing:outgoing];
}

/* the message shows at once as pending, and the file or point goes up behind it */
/* several photos and videos at once go out as one album: a pending message for each shows at once, and one request sends them together */
- (void)sendAlbum:(NSArray *)outgoings {
    [self leaveWindow];
    int32_t now = (int32_t)[[NSDate date] timeIntervalSince1970];
    NSMutableArray *messages = [NSMutableArray arrayWithCapacity:outgoings.count], *randomIds = [NSMutableArray arrayWithCapacity:outgoings.count];
    long long albumNumber = [self newRandomId];
    for (ExteriaOutgoing *outgoing in outgoings) {
        long long randomId = [self newRandomId];
        outgoing->replyTo = _replyToId;
        ExteriaMessage *message = [ExteriaMessage pendingOutgoing:outgoing randomId:randomId date:now];
        message.sendReplyTo = _replyToId;
        message.state = ExteriaMessageStateSending;
        message.groupedId = albumNumber;
        [messages addObject:message];
        [randomIds addObject:[NSNumber numberWithLongLong:randomId]];
        if (_dialog.kind == EXTERIA_DIALOG_CHANNEL) [message showAsChannelPost];
        [_local addObject:message];
    }
    [self cancelCompose];
    _stickToBottom = YES;
    [_table setHidden:NO];
    [self showStatus:nil retry:NO];
    [self rebuildItems];
    ExteriaWeakReference *weak = _weak;
    [_session sendAlbumOfOutgoings:outgoings toDialog:_dialog randomIds:randomIds completion:^(NSArray *messageIds, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        for (NSUInteger i = 0; i < messages.count; ++i) {
            [chat didSend:[messages objectAtIndex:i] messageId:messageIds ? [[messageIds objectAtIndex:i] intValue] : 0 error:errorName];
        }
    }];
}

- (void)sendOutgoing:(ExteriaOutgoing *)outgoing {
    ExteriaMessage *message = [ExteriaMessage pendingOutgoing:outgoing randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    [self afterAppendingLocal:message];
    [self dispatchLocal:message];
}

- (void)inputBarDidTapSend:(ExteriaInputBar *)bar {
    NSString *text = [bar trimmedText];
    if (!text.length) return;
    if (_editingId) {
        [self commitEditWithText:text];
        return;
    }
    NSArray *entities = [bar sendEntities];
    int32_t replyTo = _replyToId ? _replyToId : [_bots replyTargetForText];
    [bar clear];
    [_bots didSendText];
    [self cancelCompose];
    [self sendText:text entities:entities replyTo:replyTo];
    /* the message is on its way, and the draft that held its words goes at once instead of after the pause */
    [self saveDraftNow];
}

- (void)afterAppendingLocal:(ExteriaMessage *)message {
    [self leaveWindow];
    if (!_voice) ExteriaPlayInChatSound(NO);
    if (_dialog.kind == EXTERIA_DIALOG_CHANNEL) [message showAsChannelPost];
    if (!message.sendReplyTo) message.sendReplyTo = _replyToId;
    [self cancelCompose];
    [_local addObject:message];
    _interacting = NO;
    _stickToBottom = YES;
    [_table setHidden:NO];
    [self showStatus:nil retry:NO];
    [self rebuildItems];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities {
    [self sendText:text entities:entities replyTo:0];
}

- (void)sendText:(NSString *)text entities:(NSArray *)entities replyTo:(int32_t)replyTo {
    ExteriaMessage *message = [ExteriaMessage pendingText:text entities:entities randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    message.sendReplyTo = replyTo;
    [self afterAppendingLocal:message];
    [self dispatchLocal:message];
}

- (void)sendSticker:(ExteriaMedia *)sticker {
    ExteriaMessage *message = [ExteriaMessage pendingSticker:sticker randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    [self afterAppendingLocal:message];
    [self dispatchLocal:message];
    [self promoteSetOfSticker:sticker];
}

/* the set a sticker came from goes to the front of the panel; a set the account does not have, or one that is
   first already, changes nothing */
- (void)promoteSetOfSticker:(ExteriaMedia *)sticker {
    long long setId = sticker.stickerSetId;
    if (!setId || !ExteriaChatDynamicPackOrder()) return;
    ExteriaSession *session = _session;
    [_stickers loadSets:^(NSArray *sets, NSString *errorName) {
        (void)errorName;
        if (!sets.count || [(ExteriaStickerSet *)[sets objectAtIndex:0] setId] == setId) return;
        for (ExteriaStickerSet *set in sets) {
            if (set.setId != setId) continue;
            [session moveStickerSetToTop:set among:sets completion:^(NSString *error) {
                if (error) NSLog(@"exteria: the sticker set did not move to the front: %@", error);
            }];
            return;
        }
    }];
}

/* sends what the screen holds for a message that has not gone out, or whose last try failed */
- (void)dispatchLocal:(ExteriaMessage *)message {
    ExteriaWeakReference *weak = _weak;
    message.state = ExteriaMessageStateSending;
    ExteriaSendCompletion done = ^(int32_t messageId, NSString *errorName) {
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        [chat didSend:message messageId:messageId error:errorName];
    };
    ExteriaOutgoing *out = message.pendingSend;
    if (out) {
        [_session sendOutgoing:out toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo completion:done];
    } else if (message.media.kind == EXTERIA_PREVIEW_STICKER || message.media.kind == EXTERIA_PREVIEW_GIF) [_session sendSticker:message.media toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo completion:done];
    else [_session sendText:message.text entities:message.entities toDialog:_dialog randomId:message.randomId replyTo:message.sendReplyTo completion:done];
}

- (void)didSend:(ExteriaMessage *)message messageId:(int32_t)messageId error:(NSString *)errorName {
    if (![_local containsObject:message]) return;
    if (errorName) {
        NSLog(@"exteria: sending to chat %lld failed: %@", _dialog.peerId, errorName);
        message.state = ExteriaMessageStateFailed;
    } else {
        message.state = ExteriaMessageStateSent;
        message.messageId = messageId;
        /* the server has the file, the copy that waited for a retry is no use now; a text or a sticker has no file */
        ExteriaOutgoing *sent = message.pendingSend;
        if (sent && sent->temporary && sent->path) [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
        /* the server's copy may have arrived already */
        if (messageId > 0 && [_server objectForKey:[NSNumber numberWithInt:messageId]]) [_local removeObject:message];
    }
    [self rebuildItems];
}

- (void)messageCellDidTapSticker:(ExteriaMessageCell *)cell {
    ExteriaWeakReference *weak = _weak;
    [ExteriaStickerPackSheet presentInView:self.view forSticker:cell.item.message.media session:_session media:_media sender:^(ExteriaMedia *sticker) {
        ExteriaChatController *chat = weak.target;
        if (chat && chat->_input.writable && !chat->_pinnedList) [chat sendSticker:sticker];
    }];
}

/* the sender looks at their own file while the other side has not: nothing is reported and nothing burns */
- (void)previewViewOnce:(ExteriaMessage *)message {
    if (message.media.kind == EXTERIA_PREVIEW_VOICE) {
        /* the player fetches by the file of the server, which a note that is still going up does not have */
        if (!message.media.file) {
            ExteriaShowAlert(nil, NSLocalizedString(@"viewonce.preview.wait", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
            return;
        }
        ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
        if ([player isCurrentTrack:message.media]) [player togglePause];
        else [player playTrack:message.media queue:[NSArray arrayWithObject:message.media] media:_media];
        return;
    }
    [self dismissInput];
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithOneTimePreviewOfMessage:message media:_media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

/* a one-time voice note plays through the player of the app, alone in its queue; the server hears that it was opened when the sound starts, and the card burns
   when the note is no longer the track of the player (it ended, or the person stopped it), which is when it is gone */
- (void)playViewOnceVoice:(ExteriaMessage *)message {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    ExteriaMedia *track = message.media;
    [_onceVoice release];
    _onceVoice = [track retain];
    _onceVoiceId = message.messageId;
    _onceVoiceOpened = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaMusicPlayerDidChangeNotification object:player];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onceVoiceChanged:) name:ExteriaMusicPlayerDidChangeNotification object:player];
    [player playTrack:track queue:[NSArray arrayWithObject:track] media:_media];
}

- (void)endOnceVoice {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaMusicPlayerDidChangeNotification object:[ExteriaMusicPlayer sharedPlayer]];
    [_onceVoice release];
    _onceVoice = nil;
}

- (void)onceVoiceChanged:(NSNotification *)note {
    (void)note;
    if (!_onceVoice) return;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    BOOL current = [player isCurrentTrack:_onceVoice];
    int32_t messageId = _onceVoiceId;
    if (current && player.state == ExteriaMusicStateFailed) {
        NSLog(@"exteria: the one-time voice note did not play, so it stays unopened");
        [self endOnceVoice];
        return;
    }
    if (current && player.state == ExteriaMusicStatePlaying && !_onceVoiceOpened) {
        _onceVoiceOpened = YES;
        [_openedOnce addObject:[NSNumber numberWithInt:messageId]];
        ExteriaMessage *message = [self messageWithId:messageId];
        message.viewOnceOpened = YES;
        [_session markContentsRead:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:_dialog completion:^(NSString *errorName) {
            if (errorName) NSLog(@"exteria: the server was not told that a one-time voice note was heard: %@", errorName);
        }];
        return;
    }
    if (current) return;
    BOOL opened = _onceVoiceOpened;
    [self endOnceVoice];
    if (!opened) return;
    ExteriaWeakReference *weak = _weak;
    for (ExteriaMessageCell *visible in _table.visibleCells) {
        if ([visible isKindOfClass:[ExteriaMessageCell class]] && visible.item.message.messageId == messageId) {
            [visible playBurnWithCompletion:^{ [(ExteriaChatController *)weak.target rebuildItems]; }];
            return;
        }
    }
    [self rebuildItems];
}

/* a tap on the card of a one-time file: it opens in a viewer of its own, the server hears that it was opened when the picture is on the screen, and the card burns when the viewer is closed */
- (void)messageCellDidTapViewOnce:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (!ExteriaMessageIsViewOnce(message)) return;
    /* the note that plays now pauses and resumes on a tap, even after the server has marked it opened */
    if (message.media.kind == EXTERIA_PREVIEW_VOICE && _onceVoice && message.messageId == _onceVoiceId && [[ExteriaMusicPlayer sharedPlayer] isCurrentTrack:_onceVoice]) {
        [[ExteriaMusicPlayer sharedPlayer] togglePause];
        return;
    }
    if (message.outgoing) {
        if (ExteriaViewOnceExpired(message)) {
            ExteriaShowAlert(nil, NSLocalizedString(@"viewonce.seen", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        } else {
            [self previewViewOnce:message];
        }
        return;
    }
    if (ExteriaViewOnceExpired(message)) {
        ExteriaShowAlert(nil, NSLocalizedString(@"viewonce.gone", nil), [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        return;
    }
    if (message.messageId <= 0) return;
    if (message.media.kind == EXTERIA_PREVIEW_VOICE) {
        [self playViewOnceVoice:message];
        return;
    }
    [self dismissInput];
    ExteriaWeakReference *weak = _weak;
    int32_t messageId = message.messageId;
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithOneTimeMessage:message media:_media opened:^{
        ExteriaChatController *chat = weak.target;
        if (!chat) return;
        message.viewOnceOpened = YES;
        [chat->_openedOnce addObject:[NSNumber numberWithInt:messageId]];
        [chat->_session markContentsRead:[NSArray arrayWithObject:[NSNumber numberWithInt:messageId]] dialog:chat->_dialog completion:^(NSString *errorName) {
            if (errorName) NSLog(@"exteria: the server was not told that a one-time file was opened: %@", errorName);
        }];
    } closed:^{
        ExteriaChatController *chat = weak.target;
        if (!chat || ![chat->_openedOnce containsObject:[NSNumber numberWithInt:messageId]]) return;
        /* the card burns where it stands, and the row is built again as an expired one once the sparks are gone */
        for (ExteriaMessageCell *visible in chat->_table.visibleCells) {
            if ([visible isKindOfClass:[ExteriaMessageCell class]] && visible.item.message.messageId == messageId) {
                [visible playBurnWithCompletion:^{ [(ExteriaChatController *)weak.target rebuildItems]; }];
                return;
            }
        }
        [chat rebuildItems];
    }] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

- (void)messageCellDidTapMedia:(ExteriaMessageCell *)cell {
    ExteriaMessage *selected = cell.tappedMediaMessage;
    if (selected.media.kind == EXTERIA_PREVIEW_LOCATION && selected.media.location.valid) {
        [self dismissInput];
        ExteriaLocationController *viewer=[[[ExteriaLocationController alloc] initWithSession:_session dialog:_dialog location:selected.media.location selection:nil] autorelease];
        UINavigationController *navigation=[[[UINavigationController alloc] initWithRootViewController:viewer] autorelease];
        if (ExteriaThemeIsClassic()) ExteriaClassicStyleNavigationBar(navigation.navigationBar);
        [self presentViewController:navigation animated:YES completion:nil];
        return;
    }
    if (!exteria_media_opens_viewer(selected.media.kind)) return;
    [self dismissInput];
    NSMutableArray *messages = [NSMutableArray array];
    for (ExteriaChatItem *item in _items) {
        /* an album brings all its pictures, in order */
        for (ExteriaMessage *message in (item.albumMessages ? item.albumMessages : (item.message ? [NSArray arrayWithObject:item.message] : nil))) {
            exteria_preview_kind kind = message.media.kind;
            if (message.media.file && exteria_media_opens_viewer(kind) && !message.media.viewOnce) [messages addObject:message];
        }
    }
    /* the cell may still hold the message of a list that was rebuilt since, so the viewer is given the copy that is in the list */
    if (![messages containsObject:selected]) {
        ExteriaMessage *current = nil;
        for (ExteriaMessage *message in messages) if (message.messageId == selected.messageId) { current = message; break; }
        if (!current) return;
        selected = current;
    }
    NSMutableDictionary *senderNames = [NSMutableDictionary dictionary];
    for (NSNumber *key in _people) {
        ExteriaPerson *person = [_people objectForKey:key];
        if (person.name.length) [senderNames setObject:person.name forKey:key];
    }
    ExteriaMediaViewer *viewer = [[[ExteriaMediaViewer alloc] initWithMessages:messages selected:selected media:_media
        senderNames:senderNames chatTitle:_dialog.title] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

/* a tap on the card of a gift opens the same detail as the profile shows; the chat has no say over what the gift may do, so it is read only */
- (void)messageCellDidTapGift:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (!message.gift) return;
    exteria_saved_gift row;
    memset(&row, 0, sizeof(row));
    row.gift = message.gift.row;
    row.from_id = message.fromId;
    row.date = message.date;
    snprintf(row.note, sizeof(row.note), "%s", [message.text UTF8String]);
    ExteriaGiftDetailController *detail = [[[ExteriaGiftDetailController alloc] initWithSession:_session gift:[ExteriaSavedGift savedGiftWithRow:&row] mine:NO
                                                                                        avatars:_avatars media:_media] autorelease];
    detail.stickers = _stickers;
    [detail showInViewController:self];
}

/* a tap on a song plays it, and the songs of this chat from there on follow it; a tap on the one that plays pauses it */
- (void)messageCellDidTapAudio:(ExteriaMessageCell *)cell {
    ExteriaMedia *track = cell.item.message.media;
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if ([player isCurrentTrack:track] && player.state != ExteriaMusicStateFailed) {
        [player togglePause];
        return;
    }
    /* voice notes follow one another and songs follow songs, but a note does not lead into a song */
    NSMutableArray *queue = [NSMutableArray array];
    for (ExteriaChatItem *item in _items) {
        ExteriaMedia *media = item.message.media;
        if (media.kind == track.kind && media.file) [queue addObject:media];
    }
    [player playTrack:track queue:queue media:_media];
}

/* a round message that ended is followed by the next one of the chat, brought into view first when it is off screen */
/* a document that has come opens in the preview of the system, or offers the apps that take it; the cache names its files by key only, so a link with the real
   extension is what tells the system the type */
- (void)messageCell:(ExteriaMessageCell *)cell didOpenFileAtPath:(NSString *)path name:(NSString *)name {
    NSURL *url = ExteriaNamedLink(path, name.length ? name : @"file.bin", @"document");
    if (!url) {
        ExteriaGiftAlert(nil, NSLocalizedString(@"chat.file.open.failed", nil));
        return;
    }
    [self dismissInput];
    _document.delegate = nil;
    [_document release];
    _document = [[UIDocumentInteractionController interactionControllerWithURL:url] retain];
    _document.delegate = self;
    if ([_document presentPreviewAnimated:YES]) return;
    if (![_document presentOpenInMenuFromRect:cell.bounds inView:cell animated:YES]) ExteriaGiftAlert(nil, NSLocalizedString(@"chat.file.open.failed", nil));
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    (void)controller;
    return self;
}

- (void)messageCellDidFinishRound:(ExteriaMessageCell *)cell {
    NSUInteger index = [_items indexOfObjectIdenticalTo:cell.item];
    if (index == NSNotFound) return;
    for (NSUInteger next = index + 1; next < _items.count; ++next) {
        ExteriaChatItem *item = [_items objectAtIndex:next];
        if (item.kind != ExteriaChatItemRound || !item.message.media.file) continue;
        NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)next inSection:0];
        if (![[_table indexPathsForVisibleRows] containsObject:path]) {
            [_table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
            [_table layoutIfNeeded];
        }
        [(ExteriaMessageCell *)[_table cellForRowAtIndexPath:path] startRound];
        return;
    }
}

/* the cross on a message that is going up: the upload stops and the pending message goes, as if it was never sent */
- (void)messageCellDidCancelSending:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (![_local containsObject:message] || message.state != ExteriaMessageStateSending) return;
    [_session cancelSendWithRandomId:message.randomId];
    ExteriaOutgoing *sent = message.pendingSend;
    if (sent && sent->temporary && sent->path) [[NSFileManager defaultManager] removeItemAtPath:sent->path error:NULL];
    [_local removeObject:message];
    [self rebuildItems];
}

- (void)messageCellDidTapFailed:(ExteriaMessageCell *)cell {
    ExteriaMessage *message = cell.item.message;
    if (![_local containsObject:message]) return;
    /* the failed copy goes and a new one with a new random id takes its place at the end */
    ExteriaMessage *again = message.pendingSend
        ? [ExteriaMessage pendingOutgoing:message.pendingSend randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]]
        : message.media.kind == EXTERIA_PREVIEW_STICKER
        ? [ExteriaMessage pendingSticker:message.media randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]]
        : [ExteriaMessage pendingText:message.text entities:message.entities randomId:[self newRandomId] date:(int32_t)[[NSDate date] timeIntervalSince1970]];
    again.sendReplyTo = message.sendReplyTo;
    [_local removeObject:message];
    [self afterAppendingLocal:again];
    [self dispatchLocal:again];
}

/* a link whose words are not its address: the message carries the address as an entity over other text */
- (BOOL)isHiddenLink:(NSString *)url inMessage:(ExteriaMessage *)message {
    for (ExteriaTextEntity *entity in message.entities) if ([entity.url isEqualToString:url]) return YES;
    return NO;
}

- (void)messageCell:(ExteriaMessageCell *)cell didTapLink:(NSString *)url {
    ExteriaWeakReference *weak = _weak;
    /* a name written over a user opens that user, whatever the words say */
    if ([url hasPrefix:@"exteria-user:"]) {
        long long userId = [[url substringFromIndex:[@"exteria-user:" length]] longLongValue];
        if (userId > 0) [_router openProfileOfUser:userId inMessage:cell.item.message.messageId dialog:_dialog];
        return;
    }
    /* a date is shown whole, in the words of the device, since the text over it is whatever the sender wrote */
    if ([url hasPrefix:@"exteria-date:"]) {
        NSArray *parts = [[url substringFromIndex:[@"exteria-date:" length]] componentsSeparatedByString:@":"];
        NSDate *moment = [NSDate dateWithTimeIntervalSince1970:[[parts objectAtIndex:0] doubleValue]];
        NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
        format.dateStyle = NSDateFormatterFullStyle;
        format.timeStyle = NSDateFormatterShortStyle;
        ExteriaShowAlert(nil, [format stringFromDate:moment], [NSArray arrayWithObject:NSLocalizedString(@"notice.ok", nil)], 0, NO, nil);
        return;
    }
    if ([url hasPrefix:@"exteria-command:"]) {
        NSString *command = [url substringFromIndex:[@"exteria-command:" length]];
        [self askFirst:ExteriaChatFlagAskBotCommand message:[NSString stringWithFormat:NSLocalizedString(@"chat.ask.command", nil), command]
                action:NSLocalizedString(@"chat.ask.command.action", nil) then:^{ [((ExteriaChatController *)weak.target)->_bots openLink:url]; } declined:nil];
        return;
    }
    /* the links that stay inside the app need no question; an address out in the web does */
    BOOL web = [url hasPrefix:@"http://"] || [url hasPrefix:@"https://"];
    NSRange host = [url rangeOfString:@"//t.me/"];
    ExteriaLinkConfirm mode = ExteriaChatLinkConfirm();
    BOOL ask = web && host.location == NSNotFound && (mode == ExteriaLinkConfirmAlways || (mode == ExteriaLinkConfirmHidden && [self isHiddenLink:url inMessage:cell.item.message]));
    if (!ask) {
        [_bots openLink:url];
        return;
    }
    ExteriaShowAlert(nil, [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"chat.ask.link", nil), url],
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"chat.ask.link.action", nil), nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        if (index == 1) [((ExteriaChatController *)weak.target)->_bots openLink:url];
    });
}

@end
