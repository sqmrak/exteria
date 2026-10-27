#import "exteria_classic_search_controller.h"
#import "exteria_lite_mode.h"
#import "exteria_animation.h"

#import "exteria_chat_controller.h"
#import "exteria_community_screen.h"
#import "exteria_topics_screen.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_lottie_view.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_weak_reference.h"

#define STRIP_HEIGHT 40.0
#define TAB_WIDTH 94.0
#define RECENT_MAX 12
#define SERVER_DELAY 0.4
static NSString *const ExteriaRecentChatsKey = @"ExteriaRecentChats";

/* the order of the kinds on the strip */
typedef enum {
    ExteriaClassicTabChats,
    ExteriaClassicTabChannels,
    ExteriaClassicTabApps,
    ExteriaClassicTabPosts,
    ExteriaClassicTabMedia,
    ExteriaClassicTabDownloads,
    ExteriaClassicTabLinks,
    ExteriaClassicTabFiles,
    ExteriaClassicTabMusic,
    ExteriaClassicTabVoice,
    ExteriaClassicTabCount
} ExteriaClassicTab;

typedef enum { ExteriaClassicStateStart, ExteriaClassicStateResults, ExteriaClassicStateLoading, ExteriaClassicStateFailed, ExteriaClassicStateEmpty, ExteriaClassicStateHint } ExteriaClassicState;

static BOOL ExteriaClassicTabIsLocal(NSInteger tab) {
    return tab == ExteriaClassicTabChats || tab == ExteriaClassicTabChannels || tab == ExteriaClassicTabApps;
}

static exteria_search_kind ExteriaClassicServerKind(NSInteger tab) {
    switch (tab) {
    case ExteriaClassicTabPosts: return EXTERIA_SEARCH_POSTS;
    case ExteriaClassicTabMedia: return EXTERIA_SEARCH_MEDIA;
    case ExteriaClassicTabLinks: return EXTERIA_SEARCH_LINKS;
    case ExteriaClassicTabFiles: return EXTERIA_SEARCH_FILES;
    case ExteriaClassicTabMusic: return EXTERIA_SEARCH_MUSIC;
    default: return EXTERIA_SEARCH_VOICE;
    }
}

@interface ExteriaClassicSearchController () <UITableViewDataSource, UITableViewDelegate> {
    ExteriaSession *_session;
    NSArray *_dialogs;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    ExteriaWeakReference *_weak;
    ExteriaClassicSearchInput *_bar;
    UIToolbar *_stripBack;
    UIScrollView *_strip;
    UISegmentedControl *_tabs;
    UITableView *_table;
    UIView *_emptyView;
    ExteriaLottieView *_duck;
    UILabel *_emptyTitle;
    UILabel *_emptyText;
    UIActivityIndicatorView *_spinner;
    UIButton *_retry;
    NSString *_query;
    NSArray *_rows;
    /* the public chats the server found for the text, shown under the local results on the chat kinds */
    NSArray *_global;
    NSArray *_recent;
    ExteriaClassicState _state;
    NSUInteger _generation;
    CGFloat _keyboardOverlap;
    BOOL _focused;
}
@end

@implementation ExteriaClassicSearchController

- (id)initWithSession:(ExteriaSession *)session dialogs:(NSArray *)dialogs avatars:(ExteriaAvatarCache *)avatars
                media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialogs = [dialogs retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    _query = [@"" copy];
    _rows = [[NSArray alloc] init];
    _recent = [[NSArray alloc] init];
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _bar.changeHandler = nil;
    _table.delegate = nil;
    _table.dataSource = nil;
    [_session release];
    [_dialogs release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_bar release];
    [_stripBack release];
    [_strip release];
    [_tabs release];
    [_table release];
    [_emptyView release];
    [_duck release];
    [_emptyTitle release];
    [_emptyText release];
    [_spinner release];
    [_retry release];
    [_query release];
    [_rows release];
    [_global release];
    [_recent release];
    [super dealloc];
}

#pragma mark recent

static NSString *ExteriaClassicKeyOf(ExteriaDialog *dialog) {
    return [NSString stringWithFormat:@"%d:%lld", (int)dialog.peerKind, dialog.peerId];
}

- (void)loadRecent {
    NSMutableArray *found = [NSMutableArray array];
    for (id key in [[NSUserDefaults standardUserDefaults] arrayForKey:ExteriaRecentChatsKey]) {
        if (![key isKindOfClass:[NSString class]]) continue;
        for (ExteriaDialog *dialog in _dialogs) {
            if (!dialog.folder && [ExteriaClassicKeyOf(dialog) isEqualToString:key]) {
                [found addObject:dialog];
                break;
            }
        }
    }
    [_recent release];
    _recent = [found retain];
}

- (void)remember:(ExteriaDialog *)dialog {
    NSMutableArray *keys = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:ExteriaRecentChatsKey]];
    NSString *key = ExteriaClassicKeyOf(dialog);
    [keys removeObject:key];
    [keys insertObject:key atIndex:0];
    while (keys.count > RECENT_MAX) [keys removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:keys forKey:ExteriaRecentChatsKey];
}

#pragma mark views

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _bar = [[ExteriaClassicSearchInput alloc] initWithFrame:CGRectMake(0, 0, 240, 44) placeholder:NSLocalizedString(@"chats.search", nil)];
    ExteriaWeakReference *searchWeak = _weak;
    _bar.changeHandler = ^(NSString *text) { [(ExteriaClassicSearchController *)searchWeak.target searchTextChanged:text]; };
    self.navigationItem.titleView = _bar;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"picker.cancel", nil)
                                                                              style:UIBarButtonItemStyleBordered target:self action:@selector(close)] autorelease];

    NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"search.tab.chats", nil), NSLocalizedString(@"search.tab.channels", nil),
                       NSLocalizedString(@"search.tab.apps", nil), NSLocalizedString(@"search.tab.posts", nil), NSLocalizedString(@"search.tab.media", nil),
                       NSLocalizedString(@"search.tab.downloads", nil), NSLocalizedString(@"search.tab.links", nil), NSLocalizedString(@"search.tab.files", nil),
                       NSLocalizedString(@"search.tab.music", nil), NSLocalizedString(@"search.tab.voice", nil), nil];
    _stripBack = [[UIToolbar alloc] init];
    ExteriaClassicStyleToolbar(_stripBack);
    [root addSubview:_stripBack];
    _strip = [[UIScrollView alloc] init];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.backgroundColor = [UIColor clearColor];
    [root addSubview:_strip];
    _tabs = [[UISegmentedControl alloc] initWithItems:titles];
    ExteriaClassicStyleSegmented(_tabs);
    for (NSUInteger i = 0; i < titles.count; ++i) [_tabs setWidth:TAB_WIDTH forSegmentAtIndex:i];
    _tabs.selectedSegmentIndex = 0;
    _tabs.frame = CGRectMake(8, 5, TAB_WIDTH * titles.count, 30);
    [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];
    [_strip addSubview:_tabs];
    _strip.contentSize = CGSizeMake(_tabs.frame.size.width + 16, STRIP_HEIGHT);

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = [ExteriaClassicDialogCell rowHeight];
    ExteriaClassicStyleTable(_table);
    [root addSubview:_table];

    _emptyView = [[UIView alloc] init];
    _emptyView.hidden = YES;
    [root addSubview:_emptyView];
    _duck = [[ExteriaLottieView alloc] initWithAnimationNamed:@"search_empty"];
    [_emptyView addSubview:_duck];
    _emptyTitle = [[UILabel alloc] init];
    _emptyTitle.backgroundColor = [UIColor clearColor];
    _emptyTitle.textColor = ExteriaColorTitle();
    _emptyTitle.font = [UIFont boldSystemFontOfSize:19];
    _emptyTitle.textAlignment = ExteriaTextAlignmentCenter;
    [_emptyView addSubview:_emptyTitle];
    _emptyText = [[UILabel alloc] init];
    _emptyText.backgroundColor = [UIColor clearColor];
    _emptyText.textColor = ExteriaColorSecondary();
    _emptyText.font = [UIFont systemFontOfSize:15];
    _emptyText.textAlignment = ExteriaTextAlignmentCenter;
    _emptyText.numberOfLines = 0;
    [_emptyView addSubview:_emptyText];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [root addSubview:_spinner];
    _retry = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(runSearch) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES;
    [root addSubview:_retry];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadRecent];
    [self refreshState];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (void)layoutSearch {
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    _stripBack.frame = CGRectMake(0, insets.top, size.width, STRIP_HEIGHT);
    _strip.frame = _stripBack.frame;
    CGFloat bodyY = insets.top + STRIP_HEIGHT;
    CGFloat bodyHeight = MAX(0, size.height - _keyboardOverlap - bodyY);
    _table.frame = CGRectMake(0, bodyY, size.width, bodyHeight);
    _emptyView.frame = _table.frame;
    CGFloat block = 130 + 12 + 24 + 6 + 62;
    CGFloat y = MAX(8, (bodyHeight - block) / 2 - 20);
    _duck.frame = CGRectMake((size.width - 130) / 2, y, 130, 130);
    _emptyTitle.frame = CGRectMake(24, y + 142, size.width - 48, 24);
    _emptyText.frame = CGRectMake(32, y + 172, size.width - 64, 62);
    CGPoint middle = CGPointMake(size.width / 2, bodyY + bodyHeight / 2 - 20);
    _spinner.center = middle;
    _retry.frame = CGRectMake((size.width - 140) / 2, middle.y + 10, 140, 40);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSearch];
}

#pragma mark keyboard

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    [center addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    /* coming back from a chat shows the chats opened lately, with the one just opened first */
    /* the screen opens without a push, so it fades in and grows from a little larger, the way the search brings
       its results in */
    if (!_focused) {
        CGFloat scale = ExteriaLiteEnabled(EXTERIA_LITE_CHAT_SCALE) ? 1.04f : 1;
        ExteriaAnimateEnter(self.view, CGAffineTransformMakeScale(scale, scale), 0, EXTERIA_MOTION_ENTER);
    }
    [self loadRecent];
    [_table reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* the keyboard comes up when the screen opens, not again when a chat opened from here is left */
    if (!_focused) {
        _focused = YES;
        [_bar becomeFirstResponder];
    }
    [self updateDuck];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_duck setPlaying:NO];
}

- (void)keyboardShown:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIWindow *window = self.view.window;
    if (!window) return;
    CGRect inView = [self.view convertRect:[window convertRect:end fromWindow:nil] fromView:window];
    _keyboardOverlap = MAX(0, CGRectGetMaxY(self.view.bounds) - inView.origin.y);
    [self layoutSearch];
}

- (void)keyboardHidden:(NSNotification *)note {
    (void)note;
    _keyboardOverlap = 0;
    [self layoutSearch];
}

- (void)close {
    [_bar resignFirstResponder];
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark query

- (void)searchTextChanged:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:_query]) return;
    [_query release];
    _query = [trimmed copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    ++_generation;
    if (ExteriaClassicTabIsLocal(_tabs.selectedSegmentIndex) || !_query.length) {
        [self runSearch];
        return;
    }
    /* the server is asked once the typing pauses, and what is on the screen waits meanwhile */
    _state = ExteriaClassicStateLoading;
    [self refreshState];
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)tabChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    ++_generation;
    [self runSearch];
}

- (BOOL)dialog:(ExteriaDialog *)dialog fitsTab:(NSInteger)tab {
    switch (tab) {
    case ExteriaClassicTabChats: return dialog.kind == EXTERIA_DIALOG_USER || dialog.kind == EXTERIA_DIALOG_GROUP;
    case ExteriaClassicTabChannels: return dialog.kind == EXTERIA_DIALOG_CHANNEL;
    default: return dialog.kind == EXTERIA_DIALOG_BOT;
    }
}

/* looks for the query among the kinds of results the strip has selected */
- (void)runSearch {
    NSInteger tab = _tabs.selectedSegmentIndex;
    NSUInteger generation = _generation;
    [_rows release];
    _rows = [[NSArray alloc] init];
    [_global release];
    _global = nil;
    if (tab == ExteriaClassicTabDownloads) {
        _state = ExteriaClassicStateHint;
    } else if (ExteriaClassicTabIsLocal(tab)) {
        NSMutableArray *found = [NSMutableArray array];
        for (ExteriaDialog *dialog in _dialogs) {
            if (dialog.folder || ![self dialog:dialog fitsTab:tab]) continue;
            if (_query.length && [dialog.title rangeOfString:_query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
            [found addObject:dialog];
        }
        [_rows release];
        _rows = [found retain];
        /* with nothing local the screen waits for the server's public chats before it says there is nothing */
        _state = !_query.length ? ExteriaClassicStateStart : (found.count ? ExteriaClassicStateResults : ExteriaClassicStateLoading);
        [self scheduleGlobal];
    } else if (!_query.length) {
        _state = ExteriaClassicStateHint;
    } else {
        _state = ExteriaClassicStateLoading;
        [self refreshState];
        ExteriaWeakReference *weak = _weak;
        [_session searchGlobal:_query kind:ExteriaClassicServerKind(tab) offsetRate:0 completion:^(NSArray *dialogs, int32_t nextRate, NSString *errorName) {
            (void)nextRate;
            ExteriaClassicSearchController *search = weak.target;
            if (!search || generation != search->_generation) return;
            [search didSearch:dialogs error:errorName];
        }];
        return;
    }
    [self refreshState];
}

/* the server is asked for public chats once the typing pauses */
- (void)scheduleGlobal {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runGlobal) object:nil];
    if (_query.length) [self performSelector:@selector(runGlobal) withObject:nil afterDelay:SERVER_DELAY];
}

- (void)runGlobal {
    NSUInteger generation = _generation;
    NSInteger tab = _tabs.selectedSegmentIndex;
    ExteriaWeakReference *weak = _weak;
    [_session searchPeers:_query completion:^(NSArray *dialogs, NSString *errorName) {
        ExteriaClassicSearchController *search = weak.target;
        if (!search || generation != search->_generation) return;
        [search didFindGlobal:dialogs forTab:tab error:errorName];
    }];
}

- (void)didFindGlobal:(NSArray *)dialogs forTab:(NSInteger)tab error:(NSString *)errorName {
    if (!dialogs) NSLog(@"exteria: global search failed: %@", errorName);
    NSMutableSet *known = [NSMutableSet set];
    for (ExteriaDialog *dialog in _rows) [known addObject:ExteriaClassicKeyOf(dialog)];
    NSMutableArray *fresh = [NSMutableArray array];
    for (ExteriaDialog *dialog in dialogs) {
        if (![self dialog:dialog fitsTab:tab] || [known containsObject:ExteriaClassicKeyOf(dialog)]) continue;
        [fresh addObject:dialog];
    }
    [_global release];
    _global = fresh.count ? [fresh retain] : nil;
    _state = (_rows.count || _global.count) ? ExteriaClassicStateResults : ExteriaClassicStateEmpty;
    [self refreshState];
}

- (void)didSearch:(NSArray *)dialogs error:(NSString *)errorName {
    if (!dialogs) {
        NSLog(@"exteria: search failed: %@", errorName);
        _state = ExteriaClassicStateFailed;
    } else {
        [_rows release];
        _rows = [dialogs retain];
        _state = dialogs.count ? ExteriaClassicStateResults : ExteriaClassicStateEmpty;
    }
    [self refreshState];
}

#pragma mark state

- (void)updateDuck {
    [_duck setPlaying:!_emptyView.hidden && self.view.window != nil];
}

- (void)refreshState {
    BOOL showsEmpty = _state == ExteriaClassicStateEmpty || _state == ExteriaClassicStateHint;
    _emptyView.hidden = !showsEmpty;
    _duck.hidden = _state != ExteriaClassicStateEmpty;
    if (_state == ExteriaClassicStateEmpty) {
        _emptyTitle.text = NSLocalizedString(@"search.empty.title", nil);
        _emptyText.text = [NSString stringWithFormat:NSLocalizedString(@"search.empty.text", nil), _query];
    } else if (_state == ExteriaClassicStateHint) {
        BOOL downloads = _tabs.selectedSegmentIndex == ExteriaClassicTabDownloads;
        _emptyTitle.text = downloads ? NSLocalizedString(@"search.downloads.title", nil) : @"";
        _emptyText.text = downloads ? NSLocalizedString(@"search.downloads.text", nil) : NSLocalizedString(@"search.hint", nil);
    }
    if (_state == ExteriaClassicStateLoading) [_spinner startAnimating];
    else [_spinner stopAnimating];
    _retry.hidden = _state != ExteriaClassicStateFailed;
    _table.hidden = !(_state == ExteriaClassicStateResults || _state == ExteriaClassicStateStart);
    [_table reloadData];
    [self updateDuck];
    [self layoutSearch];
}

#pragma mark table

/* the recent chats show on the chat kinds they fit; the rest of the screen shows what the last search found */
- (NSArray *)visibleRows {
    if (_state != ExteriaClassicStateStart) return _rows;
    NSMutableArray *fitting = [NSMutableArray array];
    for (ExteriaDialog *dialog in _recent) if ([self dialog:dialog fitsTab:_tabs.selectedSegmentIndex]) [fitting addObject:dialog];
    return fitting;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return _global.count && _state == ExteriaClassicStateResults ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 1 ? (NSInteger)_global.count : (NSInteger)[[self visibleRows] count];
}

- (ExteriaDialog *)dialogAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 ? [_global objectAtIndex:(NSUInteger)indexPath.row] : [[self visibleRows] objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 1) return NSLocalizedString(@"search.global", nil);
    return _state == ExteriaClassicStateStart && [[self visibleRows] count] ? NSLocalizedString(@"search.recent", nil) : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"result";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithDialog:[self dialogAtIndexPath:indexPath] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_bar resignFirstResponder];
    ExteriaDialog *dialog = [self dialogAtIndexPath:indexPath];
    [self remember:dialog];
    if (dialog.community) {
        [self.navigationController pushViewController:ExteriaCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    if (dialog.forum) {
        [self.navigationController pushViewController:ExteriaTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil) animated:YES];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == _table) [_bar resignFirstResponder];
}

@end
