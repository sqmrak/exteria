#import "exteria_status_label.h"
#import "exteria_classic_chats_controller.h"

#import "exteria_alert.h"
#import "exteria_folder_tabs.h"
#import "exteria_chat_settings.h"
#import "exteria_chat_controller.h"
#import "exteria_chat_peek.h"
#import "exteria_dialog_cell.h"
#import "exteria_developers.h"
#import "exteria_classic_chrome.h"
#import "exteria_draft.h"
#import "exteria_dust_effect.h"
#import "exteria_lite_mode.h"
#import "exteria_connecting_label.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_classic_search_controller.h"
#import "exteria_login_prompt.h"
#import "exteria_developers.h"
#import "exteria_name_badge.h"
#import "exteria_perf_probe.h"
#import "exteria_table_update.h"
#import "exteria_platform.h"
#import "exteria_session_channels.h"
#import "exteria_shiro_button.h"
#import "exteria_splash_view.h"
#import "exteria_story_strip.h"
#import "exteria_theme.h"
#import "exteria_community_screen.h"
#import "exteria_topics_screen.h"
#import "exteria_weak_reference.h"
#include "exteria_list_state.h"
#include "exteria_clock.h"
#import "exteria_time.h"

/* a list older than this is fetched again when its screen comes back */
#define STALE_SECONDS 60.0

#define ARCHIVE_PULL_DISTANCE 64.0

@interface ExteriaClassicChatsController () <UIActionSheetDelegate> {
    ExteriaWeakReference *_badgeWeak;
    ExteriaSession *_session;
    ExteriaChatListStyle _listStyle;
    ExteriaChatSwipe _swipe;
    int32_t _folderId;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    UIView *_search;
    UIButton *_searchButton;
    UIView *_header;
    ExteriaFolderTabs *_folders;
    id<ExteriaFolderDialogRequest> _folderLoad;
    ExteriaStoryStrip *_stories;
    ExteriaLoginPrompt *_prompt;
    UIView *_status;
    UILabel *_statusLabel;
    UIButton *_retry;
    NSArray *_dialogs;
    NSArray *_shown;
    /* the rows the table shows now, named by ExteriaClassicKey, so a refresh can move them instead of redrawing the list */
    NSArray *_displayedKeys;
    NSDate *_loadedAt;
    BOOL _loading;
    BOOL _liveRefreshScheduled;
    BOOL _liveRefreshPending;
    uint64_t _lastLiveRefreshMs;
    BOOL _failed;
    BOOL _floodRetried;
    BOOL _archiveHidden;
    BOOL _archiveRevealed;
    NSUInteger _generation;
    /* keys of the chats picked after a long press; nil outside selection */
    NSMutableSet *_selection;
    UIBarButtonItem *_savedLeft;
    UIBarButtonItem *_savedRight;
    void (^_unreadHandler)(NSInteger);
}
@end

@implementation ExteriaClassicChatsController

@synthesize unreadHandler = _unreadHandler;

- (id)initWithSession:(ExteriaSession *)session folderId:(int32_t)folderId avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _badgeWeak = [[ExteriaWeakReference referenceTo:self] retain];
    _session = [session retain];
    _listStyle = ExteriaChatListStyleStored();
    _swipe = ExteriaChatSwipeStored();
    _folderId = folderId;
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _dialogs = [[NSArray alloc] init];
    _shown = [[NSArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timesChanged) name:ExteriaTimeDidChangeNotification object:nil];
    self.navigationItem.title = folderId > 0 ? NSLocalizedString(@"chats.archive", nil) : NSLocalizedString(@"chats.title", nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(archiveSummaryChanged:)
        name:ExteriaArchiveSummaryDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:)
        name:ExteriaTypingDidChangeNotification object:_session.typing];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:)
        name:ExteriaDraftDidChangeNotification object:_session.drafts];
    return self;
}

- (void)timesChanged {
    if (self.isViewLoaded) [self reloadList:NO];
}

- (void)archiveSummaryChanged:(NSNotification *)note {
    if (_folderId != 0) return;
    NSArray *updated = [ExteriaDialogsReplacingArchive(_dialogs, [note.userInfo objectForKey:@"dialog"]) retain];
    [_dialogs release];
    _dialogs = updated;
    [self applyFilters];
    [self reloadList:NO];
}

/* only the rows of the chat that changed are built again; a typing change in a chat that is not on screen touches nothing */
- (void)typingChanged:(NSNotification *)note {
    if (![self isViewLoaded]) return;
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.tableView indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && ExteriaTypingChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count == 0) return;
    [self.tableView reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* a draft the person typed here or the account sent moves its chat to where its date puts it, and the row shows the new words; only that chat is touched */
- (void)draftChanged:(NSNotification *)note {
    if (![self isViewLoaded] || !_dialogs.count) return;
    NSDictionary *info = note.userInfo;
    NSArray *moved = ExteriaDialogsMovedForDraft(_dialogs, _session.drafts, [[info objectForKey:@"kind"] intValue], [[info objectForKey:@"peer"] longLongValue],
                                                 [[info objectForKey:@"top"] intValue]);
    if (moved != _dialogs) {
        [_dialogs release];
        _dialogs = [moved retain];
        [self applyFilters];
        [self reloadList:YES];
        return;
    }
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.tableView indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && ExteriaDraftChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [self.tableView reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLiveDialogs) object:nil];
    [_badgeWeak clear];
    [_badgeWeak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(retryFloodWait) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_unreadHandler release];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_search release];
    [_searchButton release];
    [_stories release];
    [_prompt release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_folders release];
    [_header release];
    [_status release];
    [_statusLabel release];
    [_retry release];
    [_dialogs release];
    [_shown release];
    [_displayedKeys release];
    [_loadedAt release];
    [_selection release];
    [_savedLeft release];
    [_savedRight release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _archiveHidden = ExteriaArchiveHidden();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged) name:ExteriaChatSettingsDidChangeNotification object:nil];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    table.rowHeight = [ExteriaClassicDialogCell rowHeight];
    if (_folderId == 0) {
        self.navigationItem.leftBarButtonItem = self.editButtonItem;
        [self syncChromeWithSettings];
    }
    self.navigationItem.backBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"chats.title", nil)
                                                                              style:UIBarButtonItemStyleBordered target:nil action:nil] autorelease];

    CGFloat width = table.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 44)] autorelease];
    _header = [header retain];
    NSString *searchPlaceholder = NSLocalizedString(@"chats.search", nil);
    _search = [ExteriaClassicSearchFacade(CGRectMake(0, 0, width, 44), searchPlaceholder) retain];
    _search.userInteractionEnabled = NO;
    [header addSubview:_search];
    /* the list opens a search screen, so this tap must not start a text field focus change */
    UIButton *searchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    searchButton.frame = _search.frame;
    searchButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    searchButton.accessibilityLabel = searchPlaceholder;
    [searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:searchButton];
    _searchButton = [searchButton retain];
    [self syncChromeWithSettings];
    if (!_folderId) {
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        _folders = [[ExteriaFolderTabs alloc] initWithSession:_session media:_media changed:^{
            ExteriaClassicChatsController *me = weak.target;
            if (!me || !me->_folders) return;
            [me layoutHeader];
            [me applyFilters];
            [me reloadList:NO];
            ++me->_generation;
            me->_loading = NO;
            [me reload];
        }];
        [header addSubview:_folders];
        [_folders installPagingInView:self.view];
        [_folders refresh];
    }

    table.tableHeaderView = header;
    if (_folderId == 0) {
        /* the strip lives as long as this screen, so its callback must not keep the screen alive */
        ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
        if (!ExteriaChatFlagGet(ExteriaChatFlagHideStories)) {
            _stories = [[ExteriaStoryStrip alloc] initWithSession:_session avatars:_avatars media:_media host:self changed:^{
                [(ExteriaClassicChatsController *)me.target layoutHeader];
            }];
            [self hookStories];
            [header addSubview:_stories.view];
        }
        _prompt = [[ExteriaLoginPrompt alloc] initWithSession:_session changed:^{ [(ExteriaClassicChatsController *)me.target layoutHeader]; }];
        [header addSubview:_prompt.view];
    }

    _status = [[UIView alloc] initWithFrame:table.bounds];
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.textColor = ExteriaThemeIsDark() ? ExteriaColorSecondary() : [UIColor grayColor];
    _statusLabel.textAlignment = ExteriaTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.font = [UIFont systemFontOfSize:16];
    [_status addSubview:_statusLabel];
    _retry = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [_status addSubview:_retry];
    _status.frame = table.backgroundView.bounds;
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:_status];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshConnectionTitle)
                                                 name:ExteriaSessionConnectionDidChangeNotification object:_session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogsChanged) name:ExteriaDialogsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liveDialogsChanged:) name:ExteriaSessionDialogsUpdatedNotification object:_session];
    [self refreshConnectionTitle];
    UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(rowPressed:)] autorelease];
    [table addGestureRecognizer:press];
    [self reload];
}

/* joining or leaving a chat from another screen makes the list old, so it loads again when it is on screen next */
- (void)dialogsChanged {
    [_loadedAt release];
    _loadedAt = [[NSDate distantPast] retain];
}

- (void)liveDialogsChanged:(NSNotification *)note {
    (void)note;
    if (_liveRefreshScheduled || !self.isViewLoaded || !self.view.window) return;
    _liveRefreshScheduled = YES;
    uint64_t now = exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
    uint64_t delay = exteria_list_refresh_delay(now, _lastLiveRefreshMs, 15000, 500);
    [self performSelector:@selector(refreshLiveDialogs) withObject:nil afterDelay:(NSTimeInterval)delay / 1000.0];
}

- (void)refreshLiveDialogs {
    _liveRefreshScheduled = NO;
    if (!self.view.window) return;
    _lastLiveRefreshMs = exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
    if (_loading) _liveRefreshPending = YES;
    else [self reload];
}

/* the system bar shows "Connecting..." in place of the title while the link is down; picked chats put their count there */
- (void)refreshConnectionTitle {
    BOOL linked = _session.connected;
    BOOL updating = linked && _loading && !_loadedAt;
    if (_folderId != 0 || _selection || (linked && !updating)) {
        self.navigationItem.titleView = nil;
        return;
    }
    ExteriaConnectingLabel *label = [[[ExteriaConnectingLabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:20];
    label.textAlignment = ExteriaTextAlignmentLeft;
    /* the engraved shadow is part of the look of the old bars; the flat ones have none */
    if (!ExteriaClassicIsFlatSystem()) {
        label.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        label.shadowOffset = CGSizeMake(0, -1);
    }
    label.updating = updating;
    label.connecting = YES;
    CGSize fit = [label sizeThatFits:CGSizeMake(320, 44)];
    label.frame = CGRectMake(0, 0, fit.width, 44);
    self.navigationItem.titleView = label;
}

/* the stories sit under the search bar and push the rows down by their own height */
- (void)layoutHeader {
    CGFloat width = self.tableView.bounds.size.width;
    CGFloat promptHeight = [_prompt heightForWidth:width];
    CGFloat search = _search.hidden ? 0 : 44;
    CGFloat height = search + _folders.height + _stories.height + (promptHeight > 0 ? promptHeight + 16 : 0);
    _folders.frame = CGRectMake(0, search, width, _folders.height);
    [_stories layoutInWidth:width];
    CGRect strip = _stories.view.frame;
    strip.origin = CGPointMake(0, search + _folders.height);
    _stories.view.frame = strip;
    if (promptHeight > 0) [_prompt layoutInWidth:width atY:search + _folders.height + _stories.height + 8];
    if (_header.frame.size.height == height && _header.frame.size.width == width) return;
    CGRect frame = _header.frame;
    frame.size = CGSizeMake(width, height);
    _header.frame = frame;
    self.tableView.tableHeaderView = _header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeader];
    CGSize size = self.tableView.bounds.size;
    CGFloat top = 100;
    _status.frame = self.tableView.backgroundView.bounds;
    _statusLabel.frame = CGRectMake(32, top + 30, size.width - 64, 60);
    _retry.frame = CGRectMake((size.width - 140) / 2, top + 100, 140, 40);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

#pragma mark data

- (void)retryFloodWait {
    if (self.isViewLoaded && self.view.window && _failed && !_loading) [self reload];
}

- (NSString *)listFailureText:(NSString *)name {
    uint32_t seconds = 0;
    if (exteria_list_flood_wait(name.UTF8String, &seconds))
        return [NSString stringWithFormat:NSLocalizedString(@"list.flood.wait", nil), (unsigned)seconds];
    if ([name isEqualToString:@"FLOOD_WAIT"] || [name isEqualToString:@"FLOOD_PREMIUM_WAIT"])
        return NSLocalizedString(@"list.flood.unknown", nil);
    if ([name isEqualToString:@"TIMEOUT"] || [name isEqualToString:@"OFFLINE"]) return NSLocalizedString(@"error.offline", nil);
    if ([name isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"list.load.error", nil), name ? name : @"?"];
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    _failed = NO;
    NSUInteger generation = ++_generation;
    [self refreshConnectionTitle];
    [self refreshStatus];
    [self retain];
    if (!_loadedAt && !_folders.selectedFolder.folderId) {
        /* the kept list stands in until the network answers, and stays if it never does */
        [_session loadCachedDialogsInFolder:_folderId completion:^(NSArray *kept, NSString *keptError) {
            (void)keptError;
            if (generation != _generation || _loadedAt || !kept) return;
            _loadedAt = [[NSDate distantPast] retain];
            [self refreshConnectionTitle];
            [_dialogs release];
            _dialogs = [kept retain];
            [self applyFilters];
            [self reportUnread];
            [self reloadList:NO];
            [self refreshStatus];
        }];
    }
    ExteriaListCompletion loaded = ^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) return;
        _loading = NO;
        [self refreshConnectionTitle];
        if (!items) {
            _failed = YES;
            NSLog(@"exteria: refresh of the chat list failed: %@", errorName);
            _statusLabel.text = [self listFailureText:errorName];
            uint32_t seconds = 0;
            if (_folderId > 0 && !_floodRetried && exteria_list_flood_wait(errorName.UTF8String, &seconds) && seconds <= 60) {
                _floodRetried = YES;
                [self performSelector:@selector(retryFloodWait) withObject:nil afterDelay:(NSTimeInterval)seconds];
            }
            [self refreshStatus];
            if (_liveRefreshPending) { _liveRefreshPending = NO; [self reload]; }
            return;
        }
        _floodRetried = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(retryFloodWait) object:nil];
        [_loadedAt release];
        _loadedAt = [[NSDate date] retain];
        [_dialogs release];
        _dialogs = [items retain];
        [self loadBadgePictures];
        [_stories refresh];
        [_prompt refresh];
        [self applyFilters];
        [self reportUnread];
        [self reloadList:YES];
        [self restoreSelection];
        [self refreshStatus];
        if (_liveRefreshPending) { _liveRefreshPending = NO; [self reload]; }
    };
    [_folderLoad cancel];
    [_folderLoad release];
    _folderLoad = nil;
    if (!_folderId && _folders.selectedFolder.folderId) {
        ExteriaWeakReference *weak = _badgeWeak;
        _folderLoad = [[_session loadDialogsForChatFolder:_folders.selectedFolder progress:^(NSArray *items) {
            ExteriaClassicChatsController *controller = weak.target;
            if (!controller || generation != controller->_generation) return;
            [items retain];
            [controller->_dialogs release];
            controller->_dialogs = items;
            [controller applyFilters];
            [controller reloadList:NO];
            [controller refreshStatus];
        } completion:loaded] retain];
    }
    else [_session loadDialogsInFolder:_folderId completion:loaded];
}

/* the custom emoji statuses that follow the names in the list are fetched once, and the rows on screen are drawn again as they land */
- (void)loadBadgePictures {
    NSMutableArray *documents = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) {
        if (dialog.emojiStatus && !dialog.saved) [documents addObject:[NSNumber numberWithLongLong:dialog.emojiStatus]];
    }
    ExteriaWeakReference *weak = _badgeWeak;
    ExteriaLoadBadgePictures(documents, _session, _media, ^{
        ExteriaClassicChatsController *controller = weak.target;
        if (controller) ExteriaRedrawVisibleRows(controller.tableView);
    });
}

- (void)reportUnread {
    if (_folders.selectedFolder.folderId) return;
    NSInteger total = 0;
    for (ExteriaDialog *dialog in _dialogs) if (dialog.unread && !dialog.folder && !dialog.muted && !(dialog.peerKind == 3 && dialog.left)) total += dialog.unreadCount;
    if (_unreadHandler) _unreadHandler(total);
}

/* a row follows the stories of the user it is with; the strip fills in after the list, so it calls back to dress the rows on screen */
- (void)showStoriesOfCell:(ExteriaClassicDialogCell *)cell dialog:(ExteriaDialog *)dialog {
    [cell setStoryPeer:[_stories peerForDialog:dialog]];
}

- (void)hookStories {
    ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
    _stories.peersChanged = ^{
        ExteriaClassicChatsController *controller = me.target;
        if (!controller) return;
        for (NSIndexPath *path in controller.tableView.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row >= controller->_shown.count) continue;
            ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[controller.tableView cellForRowAtIndexPath:path];
            [controller showStoriesOfCell:cell dialog:[controller->_shown objectAtIndex:(NSUInteger)path.row]];
        }
    };
}

/* the arrow on the avatar of a chat that was added to a community opens that community: the chats the account is in, and the ones it may look at */
- (void)linkCommunityOfCell:(ExteriaClassicDialogCell *)cell dialog:(ExteriaDialog *)dialog {
    if (!dialog.linkedCommunityId) return;
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    cell.communityHandler = ^{
        ExteriaClassicChatsController *me = weak.target;
        ExteriaDialog *community = [dialog linkedCommunity];
        if (!me || !community) return;
        [me.navigationController pushViewController:ExteriaCommunityScreen(me->_session, community, me->_dialogs, me->_avatars, me->_media, me->_stickers,
                                                                           ^{ me->_loading = NO; [me reload]; }) animated:YES];
    };
}

/* a refresh that brings the same chats in a new order moves the rows that jumped and leaves the rest, where reloadData would redraw the whole list */
- (void)reloadList:(BOOL)animated {
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:_shown.count];
    for (ExteriaDialog *dialog in _shown) [keys addObject:[NSString stringWithFormat:@"%d:%lld:%d", (int)dialog.peerKind, dialog.peerId, dialog.folder ? dialog.folderId + 1 : 0]];
    NSArray *before = [_displayedKeys autorelease];
    _displayedKeys = [keys retain];
    BOOL moved = animated && before && ExteriaTableUpdateRows(self.tableView, before, keys, ^(UITableViewCell *cell, NSUInteger index) {
        ExteriaClassicDialogCell *row = (ExteriaClassicDialogCell *)cell;
        ExteriaDialog *dialog = [_shown objectAtIndex:index];
        row.media = _media;
        [row configureWithDialog:dialog avatars:_avatars];
        [row showDraft:ExteriaVisibleDraft(_session.drafts, dialog)];
        [row showTypingText:ExteriaTypingTextForDialog(_session.typing, dialog)];
        [self linkCommunityOfCell:row dialog:dialog];
        [self showStoriesOfCell:row dialog:dialog];
        [row layoutIfNeeded];
    });
    if (!moved) [self.tableView reloadData];
}

/* the stories switch of the settings takes the strip away, or brings it back, without leaving the screen */
- (void)syncStoriesWithSettings {
    if (_folderId != 0 || !self.isViewLoaded) return;
    BOOL hide = ExteriaChatFlagGet(ExteriaChatFlagHideStories);
    if (hide && _stories) {
        [_stories.view removeFromSuperview];
        [_stories release];
        _stories = nil;
        [self layoutHeader];
    } else if (!hide && !_stories) {
        ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
        _stories = [[ExteriaStoryStrip alloc] initWithSession:_session avatars:_avatars media:_media host:self changed:^{
            [(ExteriaClassicChatsController *)me.target layoutHeader];
        }];
        [self hookStories];
        [_header addSubview:_stories.view];
        [_stories refresh];
        [self layoutHeader];
    }
}

/* the main list takes three choices of the appearance page: the VPN button, the field of search, and the words of the title; the archive list keeps its own */
- (void)syncChromeWithSettings {
    if (_folderId != 0 || _selection) return;
    BOOL hideVpn = ExteriaChatFlagGet(ExteriaChatFlagHideVpnButton);
    if (hideVpn) self.navigationItem.rightBarButtonItem = nil;
    else if (!self.navigationItem.rightBarButtonItem) self.navigationItem.rightBarButtonItem = [[[ExteriaShiroBarItem alloc] initWithShiro:_session.shiro host:self] autorelease];
    BOOL hideSearch = ExteriaChatFlagGet(ExteriaChatFlagHideSearchBar);
    _search.hidden = hideSearch;
    _searchButton.hidden = hideSearch;
    if (_header) [self layoutHeader];
    ExteriaChatListTitle mode = ExteriaChatListTitleStored();
    self.navigationItem.title = ExteriaChatListTitleText(mode, nil);
    if (mode != ExteriaChatListTitleUsername && mode != ExteriaChatListTitleName) return;
    ExteriaWeakReference *weak = _badgeWeak;
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaClassicChatsController *me = weak.target;
        if (!me) return;
        if (!items.count) {
            NSLog(@"exteria: the name for the title of the list did not load: %@", errorName);
            return;
        }
        if (ExteriaChatListTitleStored() == mode) me.navigationItem.title = ExteriaChatListTitleText(mode, [items objectAtIndex:0]);
    }];
}

- (void)chatSettingsChanged {
    [self syncChromeWithSettings];
    [self syncStoriesWithSettings];
    BOOL hidden = ExteriaArchiveHidden();
    if (hidden == _archiveHidden) return;
    _archiveHidden = hidden;
    _archiveRevealed = NO;
    [self applyFilters];
    [self.tableView reloadData];
}

- (void)applyFilters {
    NSMutableArray *shown = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) {
        if (!dialog.folder && dialog.peerKind == 3 && dialog.left) continue;
        if (dialog.folder && ExteriaArchiveHidden() && !_archiveRevealed) continue;
        if (!_folders.selectedFolder.folderId || [_folders.selectedFolder containsDialog:dialog]) [shown addObject:dialog];
    }
    [_shown release];
    _shown = [shown retain];
}

- (void)refreshStatus {
    exteria_list_presentation presentation = exteria_list_present(_shown.count, _loading, _failed, self.tableView.tableHeaderView != nil);
    if (presentation.state != EXTERIA_LIST_LOADING) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaFirstScreenReadyNotification object:self];
    _retry.hidden = presentation.state != EXTERIA_LIST_FAILED;
    _statusLabel.hidden = presentation.state != EXTERIA_LIST_FAILED && presentation.state != EXTERIA_LIST_EMPTY;
    if (presentation.state == EXTERIA_LIST_EMPTY) _statusLabel.text = _dialogs.count ? NSLocalizedString(@"chats.nothing", nil) : (_folderId > 0 ? NSLocalizedString(@"chats.archive.empty", nil) : NSLocalizedString(@"chats.empty", nil));
    self.tableView.separatorStyle = _shown.count ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_folders refresh];
    /* the chat settings are a page over this list: a new style of the rows or a new swipe is applied when the person comes back */
    ExteriaChatListStyle style = ExteriaChatListStyleStored();
    ExteriaChatSwipe swipe = ExteriaChatSwipeStored();
    if (style != _listStyle || swipe != _swipe) {
        _listStyle = style;
        _swipe = swipe;
        [self reloadList:NO];
    }
    if (_loadedAt && -[_loadedAt timeIntervalSinceNow] > STALE_SECONDS) [self reload];
}

#pragma mark archive

/* pulling the list down past the top brings a hidden archive back, as in the modern list; scrolling away from it or leaving the screen hides it again */
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView.contentOffset.y + scrollView.contentInset.top <= -ARCHIVE_PULL_DISTANCE && ExteriaArchiveHidden() && !_archiveRevealed) {
        BOOL hasArchive = NO;
        for (ExteriaDialog *dialog in _dialogs) hasArchive = hasArchive || dialog.folder;
        if (hasArchive) {
            _archiveRevealed = YES;
            [self applyFilters];
            [self reloadList:YES];
            [self refreshStatus];
        }
    }
    if (!decelerate) [self hideRevealedArchiveIfScrolledAway];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    [self hideRevealedArchiveIfScrolledAway];
}

/* the rows under a revealed archive move up by its height and the offset moves with them, so what is on screen does not jump */
- (void)hideRevealedArchiveIfScrolledAway {
    if (!_archiveRevealed || !ExteriaArchiveHidden()) return;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _shown.count; ++i) {
        if (((ExteriaDialog *)[_shown objectAtIndex:i]).folder) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) return;
    CGRect row = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
    CGPoint offset = self.tableView.contentOffset;
    if (CGRectGetMaxY(row) > offset.y) return;
    _archiveRevealed = NO;
    [self applyFilters];
    [self reloadList:NO];
    offset.y -= row.size.height;
    self.tableView.contentOffset = offset;
    [self refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_archiveRevealed) {
        _archiveRevealed = NO;
        [self applyFilters];
        [self reloadList:NO];
        [self refreshStatus];
    }
}

#pragma mark search

- (void)openSearch {
    if (self.navigationController.topViewController != self) return;
    ExteriaClassicSearchController *search = [[[ExteriaClassicSearchController alloc] initWithSession:_session dialogs:_dialogs avatars:_avatars
                                                                                              media:_media stickers:_stickers] autorelease];
    [self.navigationController pushViewController:search animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_shown.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"dialog";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    double began = ExteriaPerfNow();
    cell.media = _media;
    ExteriaDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    [cell configureWithDialog:dialog avatars:_avatars];
    [cell showDraft:ExteriaVisibleDraft(_session.drafts, dialog)];
    [cell showTypingText:ExteriaTypingTextForDialog(_session.typing, dialog)];
    [self linkCommunityOfCell:cell dialog:dialog];
    [self showStoriesOfCell:cell dialog:dialog];
    ExteriaPerfRecord("classic configure", ExteriaPerfNow() - began);
    began = ExteriaPerfNow();
    [cell layoutIfNeeded];
    ExteriaPerfRecord("classic layout", ExteriaPerfNow() - began);
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    ExteriaDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    return !dialog.folder && ExteriaDialogSwipeAction(dialog, _folderId) != ExteriaDialogActionNone;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    /* the system shows one button for a swipe, which carries the word of the action the chat settings chose */
    return ExteriaDialogActionText(ExteriaDialogSwipeAction([_shown objectAtIndex:(NSUInteger)indexPath.row], _folderId));
}

- (void)showFailure:(NSString *)errorName {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                             : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]
                                        delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

/* the swipes that change one flag of the chat on the server: the row slides back, and the list is asked for again,
   which carries the new state and the new order of the pinned chats */
- (void)performSwipeAction:(ExteriaDialogAction)action onDialog:(ExteriaDialog *)dialog atIndexPath:(NSIndexPath *)indexPath {
    ExteriaChatCommand command;
    switch (action) {
    case ExteriaDialogActionPinChat: command = ExteriaChatCommandPin; break;
    case ExteriaDialogActionUnpinChat: command = ExteriaChatCommandUnpin; break;
    case ExteriaDialogActionMute: command = ExteriaChatCommandMute; break;
    case ExteriaDialogActionUnmute: command = ExteriaChatCommandUnmute; break;
    case ExteriaDialogActionMarkRead: command = dialog.unreadCount > 0 ? ExteriaChatCommandMarkRead : ExteriaChatCommandClearUnreadMark; break;
    case ExteriaDialogActionMarkUnread: command = ExteriaChatCommandMarkUnread; break;
    case ExteriaDialogActionDeleteChat: command = ExteriaChatCommandDelete; break;
    default: return;
    }
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    void (^run)(void) = ^{
        ExteriaClassicChatsController *me = weak.target;
        if (!me) return;
        if (me->_folders.selectedFolder.folderId && (command == ExteriaChatCommandPin || command == ExteriaChatCommandUnpin)) {
            [me->_session setDialogs:[NSArray arrayWithObject:dialog] pinned:command == ExteriaChatCommandPin inChatFolder:me->_folders.selectedFolder completion:^(NSString *errorName) {
                if (errorName) [(ExteriaClassicChatsController *)weak.target showFailure:errorName];
            }];
            return;
        }
        NSArray *before = nil;
        if (command == ExteriaChatCommandDelete) {
            /* the chat leaves at once, in dust when the effect is on, and comes back if the server refuses */
            NSUInteger shownIndex = [me->_shown indexOfObjectIdenticalTo:dialog];
            UITableViewCell *cell = shownIndex == NSNotFound ? nil : [me.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0]];
            BOOL dust = cell && ExteriaLiteEnabled(EXTERIA_LITE_CHAT_THANOS) && ExteriaLiteSmoothTransitions();
            UIImage *picture = dust ? ExteriaDustSnapshot(cell) : nil;
            CGRect frame = cell.frame;
            before = [[me->_dialogs retain] autorelease];
            NSMutableArray *remaining = [NSMutableArray arrayWithArray:me->_dialogs];
            [remaining removeObject:dialog];
            [me->_dialogs release];
            me->_dialogs = [remaining retain];
            [me applyFilters];
            [me reportUnread];
            if (shownIndex != NSNotFound && [me->_shown count]) {
                [me.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0]]
                                    withRowAnimation:picture ? UITableViewRowAnimationNone : UITableViewRowAnimationLeft];
            } else {
                [me.tableView reloadData];
            }
            [me refreshStatus];
            if (picture) ExteriaDustDisperse(picture, frame, me.tableView);
        }
        [me retain];
        [me->_session performAction:command onDialog:dialog completion:^(NSString *errorName) {
            [me autorelease];
            if (errorName && before) {
                [me->_dialogs release];
                me->_dialogs = [before retain];
                [me applyFilters];
                [me reportUnread];
                [me.tableView reloadData];
                [me refreshStatus];
            }
            if (!errorName) {
                me->_loading = NO;
                [me reload];
                return;
            }
            NSLog(@"exteria: command %d on chat %lld failed: %@", (int)command, dialog.peerId, errorName);
            [me showFailure:errorName];
            [me reloadList:NO];
        }];
    };
    if (action != ExteriaDialogActionDeleteChat) {
        [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        run();
        return;
    }
    BOOL leaves = dialog.kind == EXTERIA_DIALOG_CHANNEL || dialog.kind == EXTERIA_DIALOG_GROUP;
    NSString *format = NSLocalizedString(leaves ? @"chats.swipe.leave.confirm" : @"chats.swipe.delete.confirm", nil);
    [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    ExteriaConfirm(nil, [NSString stringWithFormat:format, dialog.title], NSLocalizedString(leaves ? @"chats.swipe.leave" : @"chats.swipe.delete", nil), run);
}

/* the swipe or the red minus moves the chat on the server; the row leaves at once and comes back if the server refuses */
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    ExteriaDialog *dialog = [[[_shown objectAtIndex:(NSUInteger)indexPath.row] retain] autorelease];
    ExteriaDialogAction action = ExteriaDialogSwipeAction(dialog, _folderId);
    if (action != ExteriaDialogActionArchive && action != ExteriaDialogActionUnarchive) {
        [self performSwipeAction:action onDialog:dialog atIndexPath:indexPath];
        return;
    }
    NSArray *before = [[_dialogs retain] autorelease];
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self applyFilters];
    [self reportUnread];
    [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationLeft];
    [self refreshStatus];
    [self retain];
    [_session moveDialog:dialog toFolder:_folderId > 0 ? 0 : 1 completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            /* the other list changed too, and the archive entry with its count */
            _loading = NO;
            [self reload];
            return;
        }
        NSLog(@"exteria: moving chat %lld to folder failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self applyFilters];
        [self reportUnread];
        [self reloadList:NO];
        [self refreshStatus];
        [self showFailure:errorName];
    }];
}

#pragma mark selection

static NSString *ExteriaClassicKey(ExteriaDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (NSArray *)selectedDialogs {
    NSMutableArray *picked = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) if ([_selection containsObject:ExteriaClassicKey(dialog)]) [picked addObject:dialog];
    return picked;
}

- (UIBarButtonItem *)selectionButtonWithSymbol:(ExteriaSymbol)symbol action:(SEL)action {
    UIBarButtonItem *item = [[[UIBarButtonItem alloc] initWithImage:ExteriaSymbolImage(symbol, 22, [UIColor whiteColor])
                                                              style:UIBarButtonItemStyleBordered target:self action:action] autorelease];
    return item;
}

/* the bar shows what the whole pick can do: pin only when some chat is not pinned, mute only when some is not muted */
- (void)updateSelectionBar {
    NSArray *picked = [self selectedDialogs];
    if (!picked.count) {
        [self endSelection];
        return;
    }
    self.navigationItem.title = [NSString stringWithFormat:@"%lu", (unsigned long)picked.count];
    BOOL allPinned = YES, allMuted = YES;
    for (ExteriaDialog *dialog in picked) {
        if (!dialog.pinned) allPinned = NO;
        if (!dialog.muted) allMuted = NO;
    }
    UIBarButtonItem *pin = [self selectionButtonWithSymbol:ExteriaSymbolPin action:@selector(pinSelected)];
    UIBarButtonItem *mute = [self selectionButtonWithSymbol:ExteriaSymbolBellSlash action:@selector(muteSelected)];
    UIBarButtonItem *archive = [self selectionButtonWithSymbol:ExteriaSymbolArchive action:@selector(archiveSelected)];
    UIBarButtonItem *trash = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteSelected)] autorelease];
    pin.title = allPinned ? NSLocalizedString(@"chats.unpin", nil) : NSLocalizedString(@"chats.pin", nil);
    mute.title = allMuted ? NSLocalizedString(@"chats.unmute", nil) : NSLocalizedString(@"chats.mute", nil);
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:trash, archive, mute, pin, nil];
}

- (void)beginSelectionAt:(NSIndexPath *)path {
    _selection = [[NSMutableSet alloc] init];
    [self refreshConnectionTitle];
    _savedLeft = [self.navigationItem.leftBarButtonItem retain];
    _savedRight = [self.navigationItem.rightBarButtonItem retain];
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(endSelection)] autorelease];
    self.tableView.allowsMultipleSelection = YES;
    [_selection addObject:ExteriaClassicKey([_shown objectAtIndex:(NSUInteger)path.row])];
    [self.tableView selectRowAtIndexPath:path animated:YES scrollPosition:UITableViewScrollPositionNone];
    [self updateSelectionBar];
}

- (void)endSelection {
    if (!_selection) return;
    [_selection release];
    _selection = nil;
    self.tableView.allowsMultipleSelection = NO;
    NSArray *rows = [[self.tableView indexPathsForSelectedRows] retain];
    for (NSIndexPath *path in rows) [self.tableView deselectRowAtIndexPath:path animated:YES];
    [rows release];
    self.navigationItem.leftBarButtonItem = _savedLeft;
    self.navigationItem.rightBarButtonItems = _savedRight ? [NSArray arrayWithObject:_savedRight] : nil;
    [_savedLeft release];
    _savedLeft = nil;
    [_savedRight release];
    _savedRight = nil;
    if (_folderId > 0) self.navigationItem.title = NSLocalizedString(@"chats.archive", nil);
    else [self syncChromeWithSettings];
    [self refreshConnectionTitle];
}

/* a reload or a filter rebuilds the rows, which drops the table's own selection */
- (void)restoreSelection {
    if (!_selection) return;
    for (NSUInteger i = 0; i < _shown.count; ++i) {
        if ([_selection containsObject:ExteriaClassicKey([_shown objectAtIndex:i])]) {
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

- (void)rowPressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan || _selection || self.editing) return;
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[press locationInView:self.tableView]];
    if (!path || (NSUInteger)path.row >= _shown.count) return;
    ExteriaDialog *dialog = [_shown objectAtIndex:(NSUInteger)path.row];
    if (dialog.folder || dialog.community) return;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    UIWindow *window = self.view.window;
    if (!cell || !window) return;
    CGRect source = [self.tableView convertRect:cell.frame toView:window];
    ExteriaWeakReference *weak = _badgeWeak;
    ExteriaShowChatPeek(window, source, dialog, _session, _avatars, _media, YES, ^(ExteriaChatPeekAction action) {
        ExteriaClassicChatsController *controller = weak.target;
        if (!controller) return;
        NSUInteger index = NSNotFound;
        for (NSUInteger i = 0; i < controller->_shown.count; ++i) {
            ExteriaDialog *current = [controller->_shown objectAtIndex:i];
            if (current.peerKind == dialog.peerKind && current.peerId == dialog.peerId && current.topicId == dialog.topicId) { index = i; break; }
        }
        if (index == NSNotFound) return;
        NSIndexPath *currentPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        ExteriaDialog *current = [controller->_shown objectAtIndex:index];
        if (action == ExteriaChatPeekOpen) [controller tableView:controller.tableView didSelectRowAtIndexPath:currentPath];
        else if (action == ExteriaChatPeekSelect) [controller beginSelectionAt:currentPath];
        else if (action == ExteriaChatPeekPin || action == ExteriaChatPeekMute) {
            ExteriaChatCommand command = action == ExteriaChatPeekPin ? (current.pinned ? ExteriaChatCommandUnpin : ExteriaChatCommandPin)
                                                                        : (current.muted ? ExteriaChatCommandUnmute : ExteriaChatCommandMute);
            [controller applyAction:command toDialogs:[NSArray arrayWithObject:current]];
        } else if (action == ExteriaChatPeekArchive) {
            [controller applyToDialogs:[NSArray arrayWithObject:current] perform:^(ExteriaDialog *item, void (^finished)(NSString *)) {
                [controller->_session moveDialog:item toFolder:item.folderId ? 0 : 1 completion:finished];
            }];
        }
    });
}

/* runs the action on every picked chat, then asks for the list again; the first refusal is shown once */
- (void)applyToDialogs:(NSArray *)dialogs perform:(void (^)(ExteriaDialog *dialog, void (^finished)(NSString *errorName)))perform {
    [self endSelection];
    __block NSUInteger waiting = dialogs.count;
    __block NSString *firstError = nil;
    [self retain];
    for (ExteriaDialog *dialog in dialogs) {
        void (^finished)(NSString *) = ^(NSString *errorName) {
            if (errorName && !firstError) firstError = [errorName retain];
            if (--waiting) return;
            [self autorelease];
            _loading = NO;
            [self reload];
            if (firstError) {
                NSLog(@"exteria: chat action failed: %@", firstError);
                [self showFailure:firstError];
                [firstError release];
            }
        };
        perform(dialog, finished);
    }
}

- (void)applyAction:(ExteriaChatCommand)action toDialogs:(NSArray *)dialogs {
    if (_folders.selectedFolder.folderId && (action == ExteriaChatCommandPin || action == ExteriaChatCommandUnpin)) {
        [self endSelection];
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        [_session setDialogs:dialogs pinned:action == ExteriaChatCommandPin inChatFolder:_folders.selectedFolder completion:^(NSString *errorName) {
            if (errorName) [(ExteriaClassicChatsController *)weak.target showFailure:errorName];
        }];
        return;
    }
    [self applyToDialogs:dialogs perform:^(ExteriaDialog *dialog, void (^finished)(NSString *)) {
        [_session performAction:action onDialog:dialog completion:finished];
    }];
}

- (void)pinSelected {
    NSArray *picked = [self selectedDialogs];
    BOOL allPinned = YES;
    for (ExteriaDialog *dialog in picked) if (!dialog.pinned) allPinned = NO;
    [self applyAction:allPinned ? ExteriaChatCommandUnpin : ExteriaChatCommandPin toDialogs:picked];
}

- (void)muteSelected {
    NSArray *picked = [self selectedDialogs];
    BOOL allMuted = YES;
    for (ExteriaDialog *dialog in picked) if (!dialog.muted) allMuted = NO;
    [self applyAction:allMuted ? ExteriaChatCommandUnmute : ExteriaChatCommandMute toDialogs:picked];
}

- (void)archiveSelected {
    int32_t target = _folderId > 0 ? 0 : 1;
    [self applyToDialogs:[self selectedDialogs] perform:^(ExteriaDialog *dialog, void (^finished)(NSString *)) {
        [_session moveDialog:dialog toFolder:target completion:finished];
    }];
}

- (void)deleteSelected {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"notice.cancel", nil)
                                          destructiveButtonTitle:NSLocalizedString(@"chats.delete.action", nil) otherButtonTitles:nil];
    [sheet showFromTabBar:self.tabBarController.tabBar];
    [sheet release];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    if (index != sheet.destructiveButtonIndex) return;
    [self applyAction:ExteriaChatCommandDelete toDialogs:[self selectedDialogs]];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (!_selection) return;
    [_selection removeObject:ExteriaClassicKey([_shown objectAtIndex:(NSUInteger)indexPath.row])];
    [self updateSelectionBar];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_selection) {
        ExteriaDialog *picked = [_shown objectAtIndex:(NSUInteger)indexPath.row];
        if (picked.folder) {
            [tableView deselectRowAtIndexPath:indexPath animated:NO];
            return;
        }
        [_selection addObject:ExteriaClassicKey(picked)];
        [self updateSelectionBar];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaDialog *selected = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    if (selected.folder) {
        ExteriaClassicChatsController *archive = [[[ExteriaClassicChatsController alloc] initWithSession:_session folderId:selected.folderId > 0 ? selected.folderId : 1
                                                                                                avatars:_avatars media:_media stickers:_stickers] autorelease];
        [self.navigationController pushViewController:archive animated:YES];
        return;
    }
    if (selected.community) {
        [self.navigationController pushViewController:ExteriaCommunityScreen(_session, selected, _dialogs, _avatars, _media, _stickers,
                                                                             ^{ _loading = NO; [self reload]; }) animated:YES];
        return;
    }
    if (selected.forum) {
        [self.navigationController pushViewController:ExteriaTopicsScreen(_session, selected, _avatars, _media, _stickers,
                                                                          ^{ _loading = NO; [self reload]; }) animated:YES];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:selected avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    /* reading changed the counts of the list, so it asks again once the person is back */
    chat.closeHandler = ^{ _loading = NO; [self reload]; };
    [self.navigationController pushViewController:chat animated:YES];
}

@end
