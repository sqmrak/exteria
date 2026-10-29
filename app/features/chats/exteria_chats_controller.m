#import "exteria_draft.h"
#import "exteria_dust_effect.h"
#import "exteria_lite_mode.h"
#import "exteria_status_label.h"
#import "exteria_chats_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_dialog.h"
#import "exteria_session_channels.h"
#import "exteria_folder_tabs.h"
#import "exteria_perf_probe.h"
#import "exteria_table_update.h"
#import "exteria_bookmarks_controller.h"
#import "exteria_chat_controller.h"
#import "exteria_chat_peek.h"
#import "exteria_search_controller.h"
#import "exteria_search_field.h"
#import "exteria_dialog_cell.h"
#import "exteria_login_prompt.h"
#import "exteria_developers.h"
#import "exteria_mini_player.h"
#import "exteria_name_badge.h"
#import "exteria_animation.h"
#import "exteria_platform.h"
#import "exteria_popup_menu.h"
#import "exteria_shiro_button.h"
#import "exteria_story_strip.h"
#import "exteria_symbol.h"
#import "exteria_chat_settings.h"
#import "exteria_person.h"
#import "exteria_falling_view.h"
#import "exteria_sheet.h"
#import "exteria_theme.h"
#import "exteria_community_screen.h"
#import "exteria_topics_screen.h"
#import "exteria_weak_reference.h"
#import "exteria_string_drawing.h"
#include "exteria_clock.h"
#include "exteria_list_state.h"

#define SEARCH_HEIGHT 38.0
#define HEADER_HEIGHT (SEARCH_HEIGHT + 12)
/* the room above the folders when the field of search is hidden */
#define HEADER_HEIGHT_NO_SEARCH 6.0

static CGFloat ExteriaChatsHeaderTop(void) {
    return ExteriaChatFlagGet(ExteriaChatFlagHideSearchBar) ? HEADER_HEIGHT_NO_SEARCH : HEADER_HEIGHT;
}
/* how far past the top the list is pulled to show a hidden archive */
#define ARCHIVE_PULL_DISTANCE 64.0

@interface ExteriaChatsController () <ExteriaDialogCellDelegate, UIAlertViewDelegate> {
    ExteriaWeakReference *_badgeWeak;
    int32_t _folderId;
    /* the picture of the old rows that is leaving while a change of folder slides the new ones in */
    UIView *_leavingRows;
    /* a pull on the list shows the hidden archive until the screen is left */
    BOOL _archiveRevealed;
    BOOL _archiveHidden;
    BOOL _vpnHidden;
    ExteriaDialogCell *_openCell;
    ExteriaChatListStyle _listStyle;
    ExteriaChatSwipe _swipe;
    NSArray *_dialogs;
    NSArray *_mainDialogs;
    NSMutableDictionary *_folderSnapshots;
    NSMutableDictionary *_folderSnapshotDates;
    BOOL _usingFolderSnapshot;
    NSArray *_shown;
    /* the rows the table shows now, named by ExteriaDialogRowKey, so a refresh can move them instead of redrawing the list */
    NSArray *_displayedKeys;
    UIView *_header;
    ExteriaFolderTabs *_folders;
    ExteriaMiniPlayer *_miniPlayer;
    id<ExteriaFolderDialogRequest> _folderLoad;
    NSUInteger _folderProgressToken;
    uint64_t _lastLiveRefreshMs;
    UITextField *_search;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickerLibrary;
    ExteriaStoryStrip *_stories;
    ExteriaFallingView *_snow;
    ExteriaFallingView *_foxes;
    ExteriaLoginPrompt *_prompt;
    BOOL _liveRefreshScheduled;
}
@end

@implementation ExteriaChatsController

@synthesize chatsDelegate = _chatsDelegate;
@synthesize folderId = _folderId;
@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super initWithSession:session];
    if (!self) return nil;
    _badgeWeak = [[ExteriaWeakReference referenceTo:self] retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogListChanged:) name:ExteriaDialogsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liveDialogsChanged:) name:ExteriaSessionDialogsUpdatedNotification object:session];
    self.heading = [self titleForMode:ExteriaChatListTitleStored() person:nil];
    _dialogs = [[NSArray alloc] init];
    _folderSnapshots = [[NSMutableDictionary alloc] init];
    _folderSnapshotDates = [[NSMutableDictionary alloc] init];
    _shown = [[NSArray alloc] init];
    _listStyle = ExteriaChatListStyleStored();
    _swipe = ExteriaChatSwipeStored();
    _archiveHidden = ExteriaArchiveHidden();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(archiveSummaryChanged:)
        name:ExteriaArchiveSummaryDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typingChanged:)
        name:ExteriaTypingDidChangeNotification object:self.session.typing];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(draftChanged:)
        name:ExteriaDraftDidChangeNotification object:self.session.drafts];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(chatSettingsChanged)
        name:ExteriaChatSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(folderRulesChanged:)
        name:ExteriaChatFoldersDidChangeNotification object:session];
    return self;
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
    if (self.view.window) {
        _lastLiveRefreshMs = exteria_system_clock.monotonic_ms(exteria_system_clock.ctx);
        [_folderSnapshotDates removeAllObjects];
        [self reloadAfterCurrent];
    }
}

- (void)dialogListChanged:(NSNotification *)note {
    (void)note;
    if (self.isViewLoaded) [self reloadDiscardingRunning];
}

- (void)folderRulesChanged:(NSNotification *)notification {
    [_folderSnapshots removeAllObjects];
    [_folderSnapshotDates removeAllObjects];
}

/* the title of the main list is the word Chats, or what the person chose to read there; the name and the username come once the account answers */
- (NSString *)titleForMode:(ExteriaChatListTitle)mode person:(ExteriaPerson *)person {
    if (_folderId || self.showsBack) return NSLocalizedString(@"chats.title", nil);
    return ExteriaChatListTitleText(mode, person);
}

- (void)loadOwnTitle {
    ExteriaChatListTitle mode = ExteriaChatListTitleStored();
    if (mode != ExteriaChatListTitleUsername && mode != ExteriaChatListTitleName) return;
    [self retain];
    [self.session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items.count) {
            NSLog(@"exteria: the name for the title of the list did not load: %@", errorName);
            return;
        }
        self.heading = [self titleForMode:mode person:[items objectAtIndex:0]];
    }];
}

/* the stories switch of the settings takes the strip away, or brings it back, without leaving the screen */
- (void)syncStoriesWithSettings {
    if (ExteriaChatFlagGet(ExteriaChatFlagHideStories) && _stories) {
        [_stories.view removeFromSuperview];
        [_stories release];
        _stories = nil;
        [self.view setNeedsLayout];
    } else if (!ExteriaChatFlagGet(ExteriaChatFlagHideStories) && !_stories) {
        [self ensureStories];
        [_stories refresh];
        [self.view setNeedsLayout];
    }
}

/* the rows are laid out when they are built, so a new row style (one line of the preview or two) needs them built
   again */
- (void)chatSettingsChanged {
    [self syncStoriesWithSettings];
    if (!_folderId && !self.showsBack && _vpnHidden != ExteriaChatFlagGet(ExteriaChatFlagHideVpnButton)) [self syncVpnButtonWithSettings];
    BOOL archiveChanged = _archiveHidden != ExteriaArchiveHidden();
    _archiveHidden = ExteriaArchiveHidden();
    if (archiveChanged) {
        _archiveRevealed = NO;
        [self applyFilters];
        [self reloadTable];
    }
    ExteriaChatListStyle style = ExteriaChatListStyleStored();
    ExteriaChatSwipe swipe = ExteriaChatSwipeStored();
    if (style == _listStyle && swipe == _swipe) return;
    _listStyle = style;
    _swipe = swipe;
    [self reloadTable];
}

- (void)archiveSummaryChanged:(NSNotification *)note {
    if (_folderId != 0) return;
    NSArray *updated = [ExteriaDialogsReplacingArchive(_dialogs, [note.userInfo objectForKey:@"dialog"]) retain];
    [_dialogs release];
    _dialogs = updated;
    [self applyFilters];
    [self reloadTable];
}

/* only the rows of the chat that changed are built again; a typing change in a chat that is not on screen touches nothing */
- (void)typingChanged:(NSNotification *)note {
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && ExteriaTypingChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count == 0) return;
    [self.table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* a draft the person typed here or the account sent moves its chat to where its date puts it, and the row shows the new words; only that chat is touched */
- (void)draftChanged:(NSNotification *)note {
    if (!self.isViewLoaded || !_dialogs.count) return;
    NSDictionary *info = note.userInfo;
    NSArray *moved = ExteriaDialogsMovedForDraft(_dialogs, self.session.drafts, [[info objectForKey:@"kind"] intValue], [[info objectForKey:@"peer"] longLongValue],
                                                 [[info objectForKey:@"top"] intValue]);
    if (moved != _dialogs) {
        [_dialogs release];
        _dialogs = [moved retain];
        [self applyFilters];
        [self reloadTable];
        return;
    }
    NSMutableArray *affected = [NSMutableArray array];
    for (NSIndexPath *path in [self.table indexPathsForVisibleRows]) {
        if ((NSUInteger)path.row < _shown.count && ExteriaDraftChangeConcerns(note, [_shown objectAtIndex:(NSUInteger)path.row])) [affected addObject:path];
    }
    if (affected.count) [self.table reloadRowsAtIndexPaths:affected withRowAnimation:UITableViewRowAnimationNone];
}

/* the rows on screen as a picture, over the table and under the bar of folders, for the old list to leave in while the new one comes; nil when there is no
   room for rows or the person asked for no motion */
- (UIView *)snapshotOfRowsForSlide {
    UITableView *table = self.table;
    /* a change of folder while the last one still slides: its picture goes at once and the rows that were moving stand still, or the two lists lay over each other and
       the picture taken of the rows held half of the old slide */
    [_leavingRows.layer removeAllAnimations];
    [_leavingRows removeFromSuperview];
    [_leavingRows release];
    _leavingRows = nil;
    for (UITableViewCell *cell in [table visibleCells]) {
        [cell.layer removeAllAnimations];
        cell.transform = CGAffineTransformIdentity;
    }
    if (ExteriaReduceMotionEnabled() || !self.isViewLoaded || !table.window || !_folders.slideDirection) return nil;
    CGFloat top = MAX(0, CGRectGetMaxY(_header.frame) - table.contentOffset.y);
    CGSize size = CGSizeMake(table.bounds.size.width, table.bounds.size.height - top);
    if (size.width <= 0 || size.height <= 0) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextTranslateCTM(UIGraphicsGetCurrentContext(), -table.bounds.origin.x, -(table.bounds.origin.y + top));
    [table.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!picture) return nil;
    UIImageView *view = [[[UIImageView alloc] initWithImage:picture] autorelease];
    view.frame = CGRectMake(table.frame.origin.x, table.frame.origin.y + top, size.width, size.height);
    view.userInteractionEnabled = NO;
    return view;
}

/* the new rows come in from the side the swipe moves toward as the old picture leaves to the other, so a change of
   folder reads as a page turning */
- (void)slideRowsInDirection:(NSInteger)direction replacing:(UIView *)leaving {
    if (!leaving) return;
    CGFloat width = leaving.bounds.size.width;
    CGFloat boundary = leaving.frame.origin.y - self.table.frame.origin.y;
    [_leavingRows release];
    _leavingRows = [leaving retain];
    [self.view insertSubview:leaving aboveSubview:self.table];
    for (UITableViewCell *cell in [self.table visibleCells]) {
        if (CGRectGetMaxY(cell.frame) - self.table.contentOffset.y <= boundary) continue;
        ExteriaAnimateEnter(cell, CGAffineTransformMakeTranslation((CGFloat)direction * width, 0), 1, EXTERIA_MOTION_ENTER);
    }
    ExteriaAnimateView(leaving, CGAffineTransformMakeTranslation((CGFloat)-direction * width, 0), 1, EXTERIA_MOTION_ENTER, ^(BOOL finished) {
        (void)finished;
        [leaving removeFromSuperview];
        if (_leavingRows == leaving) {
            [_leavingRows release];
            _leavingRows = nil;
        }
    });
}

- (BOOL)playerStripShowing { return _miniPlayer.showing; }

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLiveDialogs) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaSessionDialogsUpdatedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaDialogsChangedNotification object:nil];
    [_badgeWeak clear];
    [_badgeWeak release];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaArchiveSummaryDidChangeNotification object:self.session];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaTypingDidChangeNotification object:self.session.typing];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaDraftDidChangeNotification object:self.session.drafts];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaChatSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaChatFoldersDidChangeNotification object:self.session];
    _search.delegate = nil;
    [_openCell release];
    [_dialogs release];
    [_mainDialogs release];
    [_folderSnapshots release];
    [_folderSnapshotDates release];
    [_leavingRows removeFromSuperview];
    [_leavingRows release];
    [_shown release];
    [_displayedKeys release];
    [_folderLoad cancel];
    [_folderLoad release];
    [_folders release];
    [_header release];
    _miniPlayer.changeHandler = nil;
    [_miniPlayer release];
    [_search release];
    [_media release];
    [_stickerLibrary release];
    [_snow stop];
    [_snow release];
    [_foxes stop];
    [_foxes release];
    [_stories release];
    [_prompt release];
    [super dealloc];
}

/* the menu of the main list, with the VPN button left of it unless the settings hide it; the list gives the pair the width of both */
- (void)syncVpnButtonWithSettings {
    _vpnHidden = ExteriaChatFlagGet(ExteriaChatFlagHideVpnButton);
    UIButton *dots = [UIButton buttonWithType:UIButtonTypeCustom];
    [dots setImage:ExteriaSymbolImage(ExteriaSymbolEllipsis, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [dots addTarget:self action:@selector(showMenu:) forControlEvents:UIControlEventTouchUpInside];
    dots.accessibilityLabel = NSLocalizedString(@"chats.menu", nil);
    UIView *pair;
    if (_vpnHidden) {
        pair = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 52, 44)] autorelease];
        dots.frame = CGRectMake(0, 0, 52, 44);
    } else {
        ExteriaShiroButton *vpn = [[[ExteriaShiroButton alloc] initWithShiro:self.session.shiro host:self] autorelease];
        CGSize pill = [vpn preferredSize];
        pair = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, pill.width + 4 + 52, 44)] autorelease];
        vpn.frame = CGRectMake(0, (44 - pill.height) / 2, pill.width, pill.height);
        vpn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        dots.frame = CGRectMake(pill.width + 4, 0, 52, 44);
        [pair addSubview:vpn];
    }
    dots.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [pair addSubview:dots];
    self.barAccessory = pair;
}

- (void)loadView {
    [super loadView];
    if (!_folderId && !self.showsBack) {
        /* the main list carries the menu; the title steps to the left edge of the field under it */
        self.titleOnLeft = YES;
        self.showsConnection = YES;
        [self syncVpnButtonWithSettings];
    }
    _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, HEADER_HEIGHT)];
    _header.backgroundColor = [UIColor clearColor];

    _search = [[ExteriaSearchField alloc] init];
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _search.backgroundColor = ExteriaColorField();
    _search.layer.cornerRadius = SEARCH_HEIGHT / 2;
    _search.delegate = self;
    _search.placeholder = NSLocalizedString(@"chats.search", nil);
    _search.font = ExteriaFontRegular(16);
    _search.textColor = ExteriaColorTitle();
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    UIImageView *glass = [[[UIImageView alloc] initWithImage:ExteriaSymbolImage(ExteriaSymbolMagnifier, 16, ExteriaColorMuted())] autorelease];
    glass.contentMode = UIViewContentModeCenter;
    glass.frame = CGRectMake(0, 0, 38, SEARCH_HEIGHT);
    _search.leftView = glass;
    _search.leftViewMode = UITextFieldViewModeAlways;
    [_header addSubview:_search];
    /* the song that plays has its strip over the folders, with the buttons to change it */
    ExteriaWeakReference *playerWeak = [ExteriaWeakReference referenceTo:self];
    _miniPlayer = [[ExteriaMiniPlayer alloc] init];
    _miniPlayer.changeHandler = ^{ [[(ExteriaChatsController *)playerWeak.target view] setNeedsLayout]; };
    [_header addSubview:_miniPlayer];

    if (!_folderId && !self.showsBack) {
        /* the card lives as long as this screen, so its callback must not keep the screen alive */
        ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
        _prompt = [[ExteriaLoginPrompt alloc] initWithSession:self.session changed:^{ [[(ExteriaChatsController *)me.target view] setNeedsLayout]; }];
        [_header addSubview:_prompt.view];
    }
    if (!_folderId && !self.showsBack) {
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        _folders = [[ExteriaFolderTabs alloc] initWithSession:self.session media:_media changed:^{
            ExteriaChatsController *me = weak.target;
            if (!me || !me->_folders) return;
            [me closeOpenCell];
            UIView *leaving = [me snapshotOfRowsForSlide];
            [me.view setNeedsLayout];
            NSNumber *key = [NSNumber numberWithInt:me->_folders.selectedFolder.folderId];
            NSArray *known = [me->_folderSnapshots objectForKey:key];
            if (!known) known = me->_mainDialogs;
            if (!known) known = [NSArray array];
            if (known != me->_dialogs) {
                [known retain];
                [me->_dialogs release];
                me->_dialogs = known;
            }
            [me applyFilters];
            [me reloadTable];
            [me reloadDiscardingRunning];
            [me slideRowsInDirection:me->_folders.slideDirection replacing:leaving];
        }];
        [_header addSubview:_folders];
        [_folders installPagingInView:self.view];
        [_folders refresh];
    }
    self.table.tableHeaderView = _header;
    UILongPressGestureRecognizer *peek = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(peekChat:)] autorelease];
    [self.table addGestureRecognizer:peek];
    [self loadOwnTitle];
}

- (void)peekChat:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *path = [self.table indexPathForRowAtPoint:[gesture locationInView:self.table]];
    if (!path || (NSUInteger)path.row >= _shown.count) return;
    ExteriaDialog *dialog = [_shown objectAtIndex:(NSUInteger)path.row];
    if (dialog.folder || dialog.community) return;
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:path];
    UIWindow *window = self.view.window;
    if (!cell || !window) return;
    [self closeOpenCell];
    CGRect source = [self.table convertRect:cell.frame toView:window];
    ExteriaWeakReference *weak = _badgeWeak;
    ExteriaShowChatPeek(window, source, dialog, self.session, self.avatars, _media, NO, ^(ExteriaChatPeekAction action) {
        ExteriaChatsController *controller = weak.target;
        if (!controller) return;
        NSUInteger index = NSNotFound;
        for (NSUInteger i = 0; i < controller->_shown.count; ++i) {
            ExteriaDialog *current = [controller->_shown objectAtIndex:i];
            if (current.peerKind == dialog.peerKind && current.peerId == dialog.peerId && current.topicId == dialog.topicId) { index = i; break; }
        }
        if (index == NSNotFound) return;
        NSIndexPath *currentPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
        ExteriaDialog *current = [controller->_shown objectAtIndex:index];
        if (action == ExteriaChatPeekOpen) [controller tableView:controller.table didSelectRowAtIndexPath:currentPath];
        else if (action == ExteriaChatPeekPin || action == ExteriaChatPeekMute) {
            ExteriaChatCommand command = action == ExteriaChatPeekPin ? (current.pinned ? ExteriaChatCommandUnpin : ExteriaChatCommandPin)
                                                                        : (current.muted ? ExteriaChatCommandUnmute : ExteriaChatCommandMute);
            [controller runCommand:command onDialog:current cell:(ExteriaDialogCell *)[controller.table cellForRowAtIndexPath:currentPath]];
        } else if (action == ExteriaChatPeekArchive) {
            [controller.session moveDialog:current toFolder:current.folderId ? 0 : 1 completion:^(NSString *error) {
                ExteriaChatsController *again = weak.target;
                if (!again) return;
                if (error) [again showFailureText:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), error]];
                else [again reload];
            }];
        }
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.table.bounds.size.width;
    CGRect frame = _header.frame;
    CGFloat promptHeight = [_prompt heightForWidth:width];
    CGFloat top = ExteriaChatsHeaderTop();
    CGFloat player = _miniPlayer.showing ? [ExteriaMiniPlayer height] : 0;
    CGFloat height = top + player + _folders.height + _stories.height + (promptHeight > 0 ? promptHeight + 8 : 0);
    if (frame.size.width != width || frame.size.height != height) {
        frame.size.width = width;
        frame.size.height = height;
        _header.frame = frame;
        self.table.tableHeaderView = _header;
    }
    _search.frame = CGRectMake(14, 4, width - 28, SEARCH_HEIGHT);
    _search.hidden = ExteriaChatFlagGet(ExteriaChatFlagHideSearchBar);
    _miniPlayer.frame = CGRectMake(0, top, width, player);
    _folders.frame = CGRectMake(0, top + player, width, _folders.height);
    [_stories layoutInWidth:width];
    CGRect strip = _stories.view.frame;
    strip.origin = CGPointMake(0, top + player + _folders.height);
    _stories.view.frame = strip;
    if (promptHeight > 0) [_prompt layoutInWidth:width atY:top + player + _folders.height + _stories.height];
}

/* only the main list has stories; the archive and a pushed list do not */
- (void)ensureStories {
    if (_stories || _folderId || self.showsBack || !_media || !self.isViewLoaded || ExteriaChatFlagGet(ExteriaChatFlagHideStories)) return;
    /* the strip lives as long as this screen, so its callback must not keep the screen alive */
    ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
    _stories = [[ExteriaStoryStrip alloc] initWithSession:self.session avatars:self.avatars media:_media host:self changed:^{
        [[(ExteriaChatsController *)me.target view] setNeedsLayout];
    }];
    _stories.peersChanged = ^{
        ExteriaChatsController *controller = (ExteriaChatsController *)me.target;
        if (!controller) return;
        for (NSIndexPath *path in controller->_table.indexPathsForVisibleRows) {
            if ((NSUInteger)path.row >= controller->_shown.count) continue;
            ExteriaDialogCell *cell = (ExteriaDialogCell *)[controller->_table cellForRowAtIndexPath:path];
            [cell setStoryPeer:[controller->_stories peerForDialog:[controller->_shown objectAtIndex:(NSUInteger)path.row]]];
        }
    };
    [_header addSubview:_stories.view];
}

#pragma mark data

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    NSUInteger token = ++_folderProgressToken;
    [_folderLoad cancel];
    [_folderLoad release];
    _folderLoad = nil;
    _usingFolderSnapshot = NO;
    if (!_folderId && _folders.selectedFolder.folderId) {
        NSNumber *key = [NSNumber numberWithInt:_folders.selectedFolder.folderId];
        NSArray *snapshot = [_folderSnapshots objectForKey:key];
        NSDate *date = [_folderSnapshotDates objectForKey:key];
        if (snapshot && date && -[date timeIntervalSinceNow] < 60) {
            _usingFolderSnapshot = YES;
            completion(snapshot, nil);
            return;
        }
        ExteriaWeakReference *weak = _badgeWeak;
        _folderLoad = [[self.session loadDialogsForChatFolder:_folders.selectedFolder progress:^(NSArray *items) {
            ExteriaChatsController *controller = weak.target;
            if (!controller || token != controller->_folderProgressToken) return;
            NSNumber *key = [NSNumber numberWithInt:controller->_folders.selectedFolder.folderId];
            [controller->_folderSnapshots setObject:items forKey:key];
            [items retain];
            [controller->_dialogs release];
            controller->_dialogs = items;
            [controller applyFilters];
            [controller reloadTable];
        } completion:completion] retain];
    } else [self.session loadDialogsInFolder:_folderId completion:completion];
}

- (void)loadKeptItemsWithCompletion:(ExteriaListCompletion)completion {
    if (!_folderId && _folders.selectedFolder.folderId) { completion(nil, nil); return; }
    [self.session loadCachedDialogsInFolder:_folderId completion:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    [_openCell release];
    _openCell = nil;
    [_dialogs release];
    _dialogs = [items retain];
    if (!_folderId && _folders.selectedFolder.folderId) {
        if (!_usingFolderSnapshot) {
            NSNumber *key = [NSNumber numberWithInt:_folders.selectedFolder.folderId];
            [_folderSnapshots setObject:items forKey:key];
            [_folderSnapshotDates setObject:[NSDate date] forKey:key];
        }
    } else if (!_folderId) {
        [_mainDialogs release];
        _mainDialogs = [items retain];
    }
    [self loadBadgePictures];
    [self refreshCounts];
    [self applyFilters];
    [self ensureStories];
    [_stories refresh];
    [_prompt refresh];
}

/* the custom emoji statuses that follow the names in the list are fetched once, and the rows on screen are drawn again as they land */
- (void)loadBadgePictures {
    NSMutableArray *documents = [NSMutableArray array];
    for (ExteriaDialog *dialog in _dialogs) {
        if (dialog.emojiStatus && !dialog.saved) [documents addObject:[NSNumber numberWithLongLong:dialog.emojiStatus]];
    }
    ExteriaWeakReference *weak = _badgeWeak;
    ExteriaLoadBadgePictures(documents, self.session, _media, ^{
        ExteriaChatsController *controller = weak.target;
        if (controller) ExteriaRedrawVisibleRows(controller->_table);
    });
}

- (void)refreshCounts {
    if (_folders.selectedFolder.folderId) return;
    NSInteger total = 0;
    for (ExteriaDialog *dialog in _dialogs) {
        if (dialog.unread && !dialog.folder && !dialog.muted && !(dialog.peerKind == 3 && dialog.left)) total += dialog.unreadCount;
    }
    [_chatsDelegate chatsController:self didChangeUnreadTotal:total];
}

/* the archive entry is a shortcut that the person may hide on this device; the archive itself is the account's */
- (void)applyFilters {
    NSMutableArray *shown = [NSMutableArray array];
    BOOL archiveShown = !ExteriaArchiveHidden() || _archiveRevealed;
    for (ExteriaDialog *dialog in _dialogs) {
        if (!dialog.folder && dialog.peerKind == 3 && dialog.left) continue;
        if (_folders.selectedFolder.folderId && ![_folders.selectedFolder containsDialog:dialog]) continue;
        if (dialog.folder && !archiveShown) continue;
        [shown addObject:dialog];
    }
    [_shown release];
    _shown = [shown retain];
}

- (NSInteger)itemCount {
    return (NSInteger)[_shown count];
}

- (NSString *)emptyText {
    if (_folderId > 0 && ![_dialogs count]) return NSLocalizedString(@"chats.archive.empty", nil);
    return [_dialogs count] ? NSLocalizedString(@"chats.nothing", nil) : NSLocalizedString(@"chats.empty", nil);
}

/* the field on the list is a button: a tap opens the search screen, which has the keyboard, the kinds of results and the
   recent chats, and the list itself stays as it was */
- (BOOL)textFieldShouldBeginEditing:(UITextField *)field {
    (void)field;
    [self openSearch];
    return NO;
}

#pragma mark menu

- (void)showMenu:(UIView *)button {
    BOOL dark = ExteriaThemeIsDark();
    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(dark ? @"menu.day" : @"menu.night", nil), NSLocalizedString(@"menu.group", nil),
                       NSLocalizedString(@"menu.channel", nil), NSLocalizedString(@"menu.saved", nil), NSLocalizedString(@"bookmarks.title", nil), nil];
    ExteriaSymbol symbols[] = {dark ? ExteriaSymbolSun : ExteriaSymbolMoon, ExteriaSymbolPerson, ExteriaSymbolMegaphone, ExteriaSymbolBookmark, ExteriaSymbolStar};
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        switch (index) {
        case 0: [self toggleDayNight]; break;
        case 1: [self askNameForMegagroup:YES]; break;
        case 2: [self askNameForMegagroup:NO]; break;
        case 3: [self openSavedMessages]; break;
        default: [self openBookmarks]; break;
        }
    }] autorelease];
    CGPoint anchor = [button.superview convertPoint:CGPointMake(CGRectGetMaxX(button.frame) - 6, CGRectGetMaxY(button.frame) - 8) toView:self.view];
    [menu showInView:self.view anchor:anchor];
}

- (void)openBookmarks {
    [self.navigationController pushViewController:[[[ExteriaBookmarksController alloc] initWithSession:self.session avatars:self.avatars media:_media
                                                                                               stickers:_stickerLibrary] autorelease] animated:YES];
}

- (void)toggleDayNight {
    ExteriaThemeStoreDark(!ExteriaThemeIsDark());
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
}

- (void)askNameForMegagroup:(BOOL)megagroup {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(megagroup ? @"create.group.title" : @"create.channel.title", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"create.action", nil), nil];
    /* the plain text input style came with ios 5 */
    [alert setValue:[NSNumber numberWithInt:2] forKey:@"alertViewStyle"];
    [[alert textFieldAtIndex:0] setPlaceholder:NSLocalizedString(@"create.name", nil)];
    [alert setTag:megagroup ? 1 : 2];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *name = [[[alertView textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) return;
    [self retain];
    [self.session createChannelTitled:name megagroup:alertView.tag == 1 completion:^(NSString *errorName) {
        [self autorelease];
        if (errorName) {
            [self showFailureText:[NSString stringWithFormat:NSLocalizedString(@"create.failed", nil), errorName]];
            return;
        }
        [self reloadDiscardingRunning];
    }];
}

- (void)openSavedMessages {
    [self retain];
    [self.session loadSelf:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        ExteriaPerson *person = [items count] ? [items objectAtIndex:0] : nil;
        ExteriaDialog *saved = person ? [ExteriaDialog savedMessagesWithPerson:person] : nil;
        if (!saved) {
            [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"]];
            return;
        }
        ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:saved avatars:self.avatars media:_media stickers:_stickerLibrary] autorelease];
        chat.closeHandler = ^{ [self reload]; };
        [self.navigationController pushViewController:chat animated:YES];
    }];
}

- (void)openSearch {
    ExteriaSearchController *search = [[[ExteriaSearchController alloc] initWithSession:self.session dialogs:_dialogs avatars:self.avatars
                                                                                  media:_media stickers:_stickerLibrary] autorelease];
    CATransition *fade = [CATransition animation];
    fade.type = kCATransitionFade;
    fade.duration = 0.2;
    [self.navigationController.view.layer addAnimation:fade forKey:@"search"];
    [self.navigationController pushViewController:search animated:NO];
}

#pragma mark table

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [ExteriaDialogCell rowHeight];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"dialog";
    ExteriaDialogCell *cell = (ExteriaDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaDialog *dialog = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    double began = ExteriaPerfNow();
    [self configureCell:cell dialog:dialog];
    ExteriaPerfRecord("modern configure", ExteriaPerfNow() - began);
    began = ExteriaPerfNow();
    [cell layoutIfNeeded];
    ExteriaPerfRecord("modern layout", ExteriaPerfNow() - began);
    return cell;
}

- (void)configureCell:(ExteriaDialogCell *)cell dialog:(ExteriaDialog *)dialog {
    cell.swipeDelegate = self;
    [cell yieldSwipeToRecognizers:_folders.pagingRecognizers];
    cell.media = _media;
    [cell configureWithDialog:dialog avatars:self.avatars action:[self swipeActionForDialog:dialog]];
    [cell showDraft:ExteriaVisibleDraft(self.session.drafts, dialog)];
    [cell showTypingText:ExteriaTypingTextForDialog(self.session.typing, dialog)];
    [cell setStoryPeer:[_stories peerForDialog:dialog]];
    if (dialog.linkedCommunityId) {
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        cell.communityHandler = ^{ [(ExteriaChatsController *)weak.target openCommunityOfDialog:dialog]; };
    }
}

/* the arrow on the avatar of a chat that was added to a community opens that community: the chats the account is in, and the ones it may look at */
- (void)openCommunityOfDialog:(ExteriaDialog *)dialog {
    ExteriaDialog *community = [dialog linkedCommunity];
    if (!community) return;
    [self closeOpenCell];
    [self.navigationController pushViewController:ExteriaCommunityScreen(self.session, community, _dialogs, self.avatars, _media, _stickerLibrary,
                                                                         ^{ [self reload]; }) animated:YES];
}

/* a chat keeps its name through a refresh, a topic has its forum's peer and its own id, and the archive entry is told apart by its folder */
static NSString *ExteriaDialogRowKey(ExteriaDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld:%d:%d", dialog.peerKind, dialog.peerId, dialog.topicId, dialog.folder ? dialog.folderId + 1 : 0];
}

- (NSArray *)shownKeys {
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:_shown.count];
    for (ExteriaDialog *dialog in _shown) [keys addObject:ExteriaDialogRowKey(dialog)];
    return keys;
}

/* a new order of the same chats is the common refresh: the ones that moved travel and the rest keep their place */
- (BOOL)updateTableAnimated {
    NSArray *keys = [self shownKeys];
    NSArray *before = [_displayedKeys autorelease];
    _displayedKeys = [keys retain];
    if (!before) return NO;
    return ExteriaTableUpdateRows(self.table, before, keys, ^(UITableViewCell *cell, NSUInteger index) {
        [self configureCell:(ExteriaDialogCell *)cell dialog:[_shown objectAtIndex:index]];
        [cell layoutIfNeeded];
    });
}

/* the archive entry has its own swipe, and the archive itself always offers to take a chat out of it; in the main list the swipe is the one the chat
   settings chose, which is the archive until the person chooses another */
- (ExteriaDialogAction)swipeActionForDialog:(ExteriaDialog *)dialog {
    if (dialog.folder) return ExteriaArchiveHidden() ? ExteriaDialogActionPin : ExteriaDialogActionHide;
    return ExteriaDialogSwipeAction(dialog, _folderId);
}

- (void)showFailureText:(NSString *)text {
    Class alertClass = NSClassFromString(@"UIAlertView");
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

#pragma mark swipe

- (void)dialogCellDidBeginSwipe:(ExteriaDialogCell *)cell {
    if (_openCell != cell) [_openCell closeSwipeAnimated:YES];
    [cell retain];
    [_openCell release];
    _openCell = cell;
}

- (void)closeOpenCell {
    [_openCell closeSwipeAnimated:YES];
    [_openCell release];
    _openCell = nil;
}

/* the row has left the screen on the client side; the table animates it away without a reload, which
   would also snap every other row */
- (void)removeShownRowAtIndexPath:(NSIndexPath *)indexPath animation:(UITableViewRowAnimation)animation {
    NSUInteger before = [_shown count];
    [self applyFilters];
    if ([_shown count] + 1 != before || [_shown count] == 0) {
        [self reloadTable];
        return;
    }
    [self.table beginUpdates];
    [self.table deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:animation];
    [self.table endUpdates];
    [_displayedKeys release];
    _displayedKeys = [[self shownKeys] retain];
}

/* the swipe moves the chat on the server; the row leaves at once and comes back if the server refuses */
- (void)moveDialog:(ExteriaDialog *)dialog atIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    NSArray *before = [[_dialogs retain] autorelease];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self refreshCounts];
    [self removeShownRowAtIndexPath:indexPath animation:UITableViewRowAnimationLeft];
    [self retain];
    [self.session moveDialog:dialog toFolder:_folderId > 0 ? 0 : 1 completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            /* the other list changed too, and the archive entry with its count; a refresh already on its way carries the old
               list, so it is dropped for a new one */
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"exteria: moving chat %lld to folder failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self refreshCounts];
        [self applyFilters];
        [self reloadTable];
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

/* the swipes that change one flag of the chat on the server: the row slides back, and the list is asked for again, which carries the new state and the
   new order of the pinned chats */
- (void)runCommand:(ExteriaChatCommand)command onDialog:(ExteriaDialog *)dialog cell:(ExteriaDialogCell *)cell {
    [cell closeSwipeAnimated:YES];
    if (_folders.selectedFolder.folderId && (command == ExteriaChatCommandPin || command == ExteriaChatCommandUnpin)) {
        ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
        [self.session setDialogs:[NSArray arrayWithObject:dialog] pinned:command == ExteriaChatCommandPin inChatFolder:_folders.selectedFolder completion:^(NSString *errorName) {
            ExteriaChatsController *me = weak.target;
            if (errorName) [me showFailureText:[NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
        }];
        return;
    }
    [self retain];
    [self.session performAction:command onDialog:dialog completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"exteria: command %d on chat %lld failed: %@", (int)command, dialog.peerId, errorName);
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

/* deleting asks first: a channel or a supergroup is left, a chat with a person or a basic group loses its history for this account only */
- (void)confirmDeleteOfDialog:(ExteriaDialog *)dialog cell:(ExteriaDialogCell *)cell {
    [cell closeSwipeAnimated:YES];
    BOOL leaves = dialog.kind == EXTERIA_DIALOG_CHANNEL || dialog.kind == EXTERIA_DIALOG_GROUP;
    NSString *format = NSLocalizedString(leaves ? @"chats.swipe.leave.confirm" : @"chats.swipe.delete.confirm", nil);
    ExteriaWeakReference *weak = [ExteriaWeakReference referenceTo:self];
    ExteriaConfirmAction(self, [NSString stringWithFormat:format, dialog.title], NSLocalizedString(leaves ? @"chats.swipe.leave" : @"chats.swipe.delete", nil), ^{
        [(ExteriaChatsController *)weak.target deleteDialog:dialog];
    });
}

/* the row leaves at once and comes back if the server refuses, as for the archive */
- (void)deleteDialog:(ExteriaDialog *)dialog {
    NSUInteger shownIndex = [_shown indexOfObjectIdenticalTo:dialog];
    NSMutableArray *remaining = [NSMutableArray arrayWithArray:_dialogs];
    [remaining removeObject:dialog];
    NSArray *before = [[_dialogs retain] autorelease];
    [_dialogs release];
    _dialogs = [remaining retain];
    [self refreshCounts];
    /* the chat breaks into dust where it stood when the effect is on, as a deleted message does */
    NSIndexPath *shownPath = shownIndex == NSNotFound ? nil : [NSIndexPath indexPathForRow:(NSInteger)shownIndex inSection:0];
    UITableViewCell *shownCell = shownPath ? [self.table cellForRowAtIndexPath:shownPath] : nil;
    UIImage *dustPicture = shownCell && ExteriaLiteEnabled(EXTERIA_LITE_CHAT_THANOS) && ExteriaLiteSmoothTransitions() ? ExteriaDustSnapshot(shownCell) : nil;
    CGRect dustFrame = shownCell.frame;
    if (shownPath) [self removeShownRowAtIndexPath:shownPath animation:dustPicture ? UITableViewRowAnimationNone : UITableViewRowAnimationLeft];
    else [self reloadTable];
    if (dustPicture) ExteriaDustDisperse(dustPicture, dustFrame, self.table);
    [self retain];
    [self.session performAction:ExteriaChatCommandDelete onDialog:dialog completion:^(NSString *errorName) {
        [self autorelease];
        if (!errorName) {
            [self reloadDiscardingRunning];
            return;
        }
        NSLog(@"exteria: deleting chat %lld failed: %@", dialog.peerId, errorName);
        [_dialogs release];
        _dialogs = [before retain];
        [self refreshCounts];
        [self applyFilters];
        [self reloadTable];
        [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName]];
    }];
}

- (void)dialogCell:(ExteriaDialogCell *)cell didTriggerAction:(ExteriaDialogAction)action {
    NSIndexPath *indexPath = [self.table indexPathForCell:cell];
    if (_openCell == cell) {
        [_openCell release];
        _openCell = nil;
    }
    if (!indexPath || (NSUInteger)indexPath.row >= [_shown count]) return;
    ExteriaDialog *dialog = [[[_shown objectAtIndex:(NSUInteger)indexPath.row] retain] autorelease];
    switch (action) {
    case ExteriaDialogActionHide:
        ExteriaArchiveSetHidden(YES);
        _archiveRevealed = NO;
        [self removeShownRowAtIndexPath:indexPath animation:UITableViewRowAnimationTop];
        break;
    case ExteriaDialogActionPin:
        /* the row stays, so it slides back and the next swipe on it offers to hide it */
        ExteriaArchiveSetHidden(NO);
        _archiveRevealed = NO;
        [cell setSwipeAction:ExteriaDialogActionHide];
        [cell closeSwipeAnimated:YES];
        break;
    case ExteriaDialogActionArchive:
    case ExteriaDialogActionUnarchive:
        [self moveDialog:dialog atIndexPath:indexPath];
        break;
    case ExteriaDialogActionPinChat:
        [self runCommand:ExteriaChatCommandPin onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionUnpinChat:
        [self runCommand:ExteriaChatCommandUnpin onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionMute:
        [self runCommand:ExteriaChatCommandMute onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionUnmute:
        [self runCommand:ExteriaChatCommandUnmute onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionMarkRead:
        /* a chat that is only marked unread has nothing to read, and the mark is taken off instead */
        [self runCommand:dialog.unreadCount > 0 ? ExteriaChatCommandMarkRead : ExteriaChatCommandClearUnreadMark onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionMarkUnread:
        [self runCommand:ExteriaChatCommandMarkUnread onDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionDeleteChat:
        [self confirmDeleteOfDialog:dialog cell:cell];
        break;
    case ExteriaDialogActionNone:
        break;
    }
}

/* a chat opens into its messages; the archive entry opens the archive */
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_openCell) {
        [self closeOpenCell];
        return;
    }
    ExteriaDialog *selected = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    if (selected.folder) {
        ExteriaChatsController *archive = [[[ExteriaChatsController alloc] initWithSession:self.session] autorelease];
        archive.folderId = selected.folderId > 0 ? selected.folderId : 1;
        archive.heading = NSLocalizedString(@"chats.archive", nil);
        archive.avatars = self.avatars;
        archive.media = _media;
        archive.stickerLibrary = _stickerLibrary;
        archive.showsBack = YES;
        [self.navigationController pushViewController:archive animated:YES];
        return;
    }
    if (selected.community) {
        [self.navigationController pushViewController:ExteriaCommunityScreen(self.session, selected, _dialogs, self.avatars, _media, _stickerLibrary,
                                                                             ^{ [self reload]; }) animated:YES];
        return;
    }
    if (selected.forum) {
        [self.navigationController pushViewController:ExteriaTopicsScreen(self.session, selected, self.avatars, _media, _stickerLibrary,
                                                                          ^{ [self reload]; }) animated:YES];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:selected avatars:self.avatars
                                                                           media:_media stickers:_stickerLibrary] autorelease];
    /* reading changed the counts of the list, so it asks again once the person is back */
    chat.closeHandler = ^{ [self reload]; };
    chat.nextChatProvider = ^ExteriaDialog *(ExteriaDialog *current) { return [self nextUnreadChannelAfter:current]; };
    [self.navigationController pushViewController:chat animated:YES];
}

/* the first broadcast channel of the list with unread posts that is not the one read now, in the order of the list as exteraGram takes it */
- (ExteriaDialog *)nextUnreadChannelAfter:(ExteriaDialog *)current {
    for (ExteriaDialog *dialog in _dialogs) {
        if (dialog.kind == EXTERIA_DIALOG_CHANNEL && dialog.unread && !dialog.forum && !dialog.community && !(dialog.peerKind == current.peerKind && dialog.peerId == current.peerId)) return dialog;
    }
    return nil;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [super scrollViewWillBeginDragging:scrollView];
    [self closeOpenCell];
}

/* a revealed archive that the list has scrolled out of sight goes away again where the list stands, so it need not
   wait for the person to leave the screen */
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
    CGRect row = [self.table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
    CGPoint offset = self.table.contentOffset;
    if (CGRectGetMaxY(row) > offset.y) return;
    _archiveRevealed = NO;
    [self applyFilters];
    [self reloadTable];
    offset.y -= row.size.height;
    self.table.contentOffset = offset;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [super scrollViewDidEndDecelerating:scrollView];
    [self hideRevealedArchiveIfScrolledAway];
}

/* pulling the list down past the top brings a hidden archive back; scrolling away from it or leaving the screen hides it again */
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [super scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    if (!decelerate) [self hideRevealedArchiveIfScrolledAway];
    if (scrollView.contentOffset.y > -ARCHIVE_PULL_DISTANCE || !ExteriaArchiveHidden() || _archiveRevealed) return;
    BOOL hasArchive = NO;
    for (ExteriaDialog *dialog in _dialogs) hasArchive = hasArchive || dialog.folder;
    if (!hasArchive) return;
    NSArray *before = [[_shown retain] autorelease];
    _archiveRevealed = YES;
    [self applyFilters];
    NSUInteger archiveIndex = NSNotFound;
    for (NSUInteger i = 0; i < _shown.count; ++i) {
        if (((ExteriaDialog *)[_shown objectAtIndex:i]).folder) { archiveIndex = i; break; }
    }
    if (archiveIndex == NSNotFound) {
        _archiveRevealed = NO;
        return;
    }
    NSMutableArray *withoutArchive = [NSMutableArray arrayWithArray:_shown];
    [withoutArchive removeObjectAtIndex:archiveIndex];
    if (![withoutArchive isEqualToArray:before] || [self.table numberOfRowsInSection:0] != (NSInteger)before.count) {
        [self reloadTable];
        return;
    }
    [self.table beginUpdates];
    [self.table insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)archiveIndex inSection:0]]
                      withRowAnimation:UITableViewRowAnimationTop];
    [self.table endUpdates];
    [_displayedKeys release];
    _displayedKeys = [[self shownKeys] retain];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_folderId || self.showsBack) return;
    if (ExteriaChatFlagGet(ExteriaChatFlagSnow)) {
        if (!_snow) {
            _snow = [[ExteriaFallingView alloc] initWithFrame:self.view.bounds];
            _snow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view addSubview:_snow];
        }
        [_snow start];
    }
    if (ExteriaChatFlagGet(ExteriaChatFlagFoxes)) {
        if (!_foxes) {
            _foxes = [[ExteriaFallingView alloc] initWithFrame:self.view.bounds spriteNamed:@"senko-fall"];
            _foxes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view insertSubview:_foxes belowSubview:self.table];
        }
        [_foxes start];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_snow stop];
    [_foxes stop];
    [self closeOpenCell];
    if (_archiveRevealed) {
        _archiveRevealed = NO;
        [self applyFilters];
        [self reloadTable];
    }
}

@end
