#import "exteria_list_controller.h"

#import "exteria_bar_button.h"
#import "exteria_connecting_label.h"
#import "exteria_geometry.h"
#import "exteria_platform.h"
#import "exteria_split_controller.h"
#import "exteria_session_channels.h"
#import "exteria_splash_view.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"
#include "exteria_list_state.h"
#import "exteria_time.h"

#define BAR_HEIGHT 44.0
/* a list older than this is fetched again when its screen comes back */
#define STALE_SECONDS 60.0

@interface ExteriaListController () {
    NSString *_heading;
    CGFloat _bottomInset;
    ExteriaWaveBackgroundView *_backdrop;
    UIView *_barShade;
    ExteriaConnectingLabel *_titleLabel;
    ExteriaBarButton *_back;
    BOOL _showsBack;
    BOOL _titleOnLeft;
    BOOL _showsConnection;
    UIView *_barAccessory;
    UILabel *_status;
    UIButton *_retry;
    NSString *_failure;
    NSDate *_loadedAt;
    BOOL _loading;
    BOOL _failed;
    /* a late answer from a load nobody wants any more must not replace a newer one */
    NSUInteger _generation;
}
@end

@implementation ExteriaListController

@synthesize session = _session;
@synthesize table = _table;
@synthesize bottomInset = _bottomInset;
@synthesize avatars = _avatars;
@synthesize showsBack = _showsBack;
@synthesize titleOnLeft = _titleOnLeft;
@synthesize showsConnection = _showsConnection;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dialogsChanged) name:ExteriaDialogsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(timesChanged) name:ExteriaTimeDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    [_session release];
    [_avatars release];
    [_table release];
    [_heading release];
    [_backdrop release];
    [_barShade release];
    [_titleLabel release];
    [_barAccessory removeFromSuperview];
    [_barAccessory release];
    [_back release];
    [_status release];
    [_retry release];
    [_failure release];
    [_loadedAt release];
    [super dealloc];
}

- (NSString *)heading {
    return _heading;
}

- (void)setHeading:(NSString *)heading {
    if (heading == _heading || [heading isEqualToString:_heading]) return;
    [_heading release];
    _heading = [heading copy];
    [self refreshTitle];
}

/* the first load replaces the heading, later refreshes leave the current list visible */
- (void)refreshTitle {
    BOOL linked = _session.connected;
    BOOL connecting = _showsConnection && !linked;
    BOOL updating = _showsConnection && linked && _loading && !_loadedAt;
    _titleLabel.updating = updating;
    _titleLabel.connecting = connecting || updating;
    if (!connecting && !updating) _titleLabel.text = _heading;
}

- (void)setShowsConnection:(BOOL)showsConnection {
    _showsConnection = showsConnection;
    [self refreshTitle];
}

- (UIView *)barAccessory {
    return _barAccessory;
}

- (void)setBarAccessory:(UIView *)accessory {
    if (accessory == _barAccessory) return;
    [_barAccessory removeFromSuperview];
    [_barAccessory release];
    _barAccessory = [accessory retain];
    if (_barAccessory && [self isViewLoaded]) [self.view addSubview:_barAccessory];
    [self.view setNeedsLayout];
}

- (void)setShowsBack:(BOOL)showsBack {
    _showsBack = showsBack;
    _back.hidden = !showsBack;
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)setBottomInset:(CGFloat)inset {
    _bottomInset = inset;
    [self.view setNeedsLayout];
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

    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
    ExteriaScrollViewOwnsInsets(_table);
    ExteriaTableUsesExactHeights(_table);
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.hidden = YES;
    [root addSubview:_table];

    _barShade = [[UIView alloc] init];
    _barShade.backgroundColor = [ExteriaColorScreen() colorWithAlphaComponent:0.94f];
    _barShade.alpha = 0;
    _barShade.userInteractionEnabled = NO;
    [root addSubview:_barShade];

    _titleLabel = [[ExteriaConnectingLabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.textAlignment = ExteriaTextAlignmentCenter;
    [self refreshTitle];
    [root addSubview:_titleLabel];
    if (_barAccessory) [root addSubview:_barAccessory];

    _back = [[ExteriaBarButton alloc] init];
    _back.chevron = YES;
    _back.title = NSLocalizedString(@"phone.back", nil);
    _back.hidden = !_showsBack;
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_back];

    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaColorSecondary();
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
    _retry = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_retry setTitle:NSLocalizedString(@"list.retry", nil) forState:UIControlStateNormal];
    [_retry setTitleColor:ExteriaColorAccent() forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_retry];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
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

#pragma mark hooks

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    (void)completion;
    [NSException raise:NSInternalInconsistencyException format:@"%@ must override loadItemsWithCompletion:", NSStringFromClass([self class])];
}

- (void)loadKeptItemsWithCompletion:(ExteriaListCompletion)completion {
    completion(nil, nil);
}

- (void)didReceiveItems:(NSArray *)items {
    (void)items;
    [NSException raise:NSInternalInconsistencyException format:@"%@ must override didReceiveItems:", NSStringFromClass([self class])];
}

- (NSInteger)itemCount {
    return 0;
}

- (NSString *)emptyText {
    return NSLocalizedString(@"list.empty", nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [self itemCount];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    [NSException raise:NSInternalInconsistencyException format:@"%@ must override tableView:cellForRowAtIndexPath:", NSStringFromClass([self class])];
    return nil;
}

#pragma mark loading

- (void)reload {
    if (_loading) return;
    _loading = YES;
    _failed = NO;
    [self refreshTitle];
    NSUInteger generation = ++_generation;
    [self refreshStatus];
    /* the screen can be released while the request runs, when the theme change builds the tabs again */
    [self retain];
    if (!_loadedAt) {
        /* what the last run kept shows at once, and stays if the network never answers */
        [self loadKeptItemsWithCompletion:^(NSArray *kept, NSString *keptError) {
            (void)keptError;
            if (generation != _generation || _loadedAt || !kept) return;
            _loadedAt = [[NSDate distantPast] retain];
            [self refreshTitle];
            [self didReceiveItems:kept];
            [self reloadTable];
        }];
    }
    [self loadItemsWithCompletion:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) return;
        _loading = NO;
        [self refreshTitle];
        if (!items) {
            _failed = YES;
            [_failure release];
            _failure = [[self failureTextForError:errorName] retain];
            NSLog(@"exteria: refresh of %@ failed: %@", NSStringFromClass([self class]), errorName);
            [self refreshStatus];
            return;
        }
        [_loadedAt release];
        _loadedAt = [[NSDate date] retain];
        [self didReceiveItems:items];
        [self reloadTable];
    }];
}

- (void)reloadDiscardingRunning {
    /* the generation moves on inside reload, so the answer of the running request finds itself stale and is ignored */
    _loading = NO;
    [self reload];
}

- (NSString *)failureTextForError:(NSString *)name {
    uint32_t seconds = 0;
    if (exteria_list_flood_wait(name.UTF8String, &seconds))
        return [NSString stringWithFormat:NSLocalizedString(@"list.flood.wait", nil), (unsigned)seconds];
    if ([name isEqualToString:@"FLOOD_WAIT"] || [name isEqualToString:@"FLOOD_PREMIUM_WAIT"])
        return NSLocalizedString(@"list.flood.unknown", nil);
    if ([name isEqualToString:@"TIMEOUT"] || [name isEqualToString:@"OFFLINE"]) return NSLocalizedString(@"error.offline", nil);
    if ([name isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"list.load.error", nil), name ? name : @"?"];
}

- (void)refreshStatus {
    if (!_status) return;
    exteria_list_presentation presentation = exteria_list_present((size_t)[self itemCount], _loading, _failed, _table.tableHeaderView != nil);
    _table.hidden = !presentation.table_visible;
    _retry.hidden = presentation.state != EXTERIA_LIST_FAILED;
    _status.hidden = presentation.state != EXTERIA_LIST_FAILED && presentation.state != EXTERIA_LIST_EMPTY;
    if (presentation.state != EXTERIA_LIST_LOADING) [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaFirstScreenReadyNotification object:self];
    if (presentation.state == EXTERIA_LIST_FAILED) _status.text = _failure;
    else if (presentation.state == EXTERIA_LIST_EMPTY) _status.text = [self emptyText];
    [self.view setNeedsLayout];
}

/* the waves under the list hold still while it moves; the screens that react to a drag call these first */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != _table) return;
    CGFloat distance = scrollView.contentOffset.y + scrollView.contentInset.top;
    _barShade.alpha = MIN(1.0f, MAX(0.0f, distance / 32.0f));
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    (void)scrollView;
    if (!decelerate) _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    (void)scrollView;
    _backdrop.scrolling = NO;
}

- (BOOL)updateTableAnimated {
    return NO;
}

- (void)reloadTable {
    if (![self updateTableAnimated]) [_table reloadData];
    [self refreshStatus];
}

- (void)refreshIfStale {
    if (_loadedAt && -[_loadedAt timeIntervalSinceNow] > STALE_SECONDS) [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self stopWatching];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshIfStale)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTitle)
                                                 name:ExteriaSessionConnectionDidChangeNotification object:_session];
    [self refreshTitle];
    [self refreshIfStale];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopWatching];
}

/* only the two the screen adds while it is up; the one about the chat list changing stays for the life of the screen */
- (void)stopWatching {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaSessionConnectionDidChangeNotification object:_session];
}

/* joining or leaving a chat from another screen makes what this list holds old, so it loads again the next time it is on screen */
- (void)dialogsChanged {
    [_loadedAt release];
    _loadedAt = [[NSDate distantPast] retain];
}

- (void)timesChanged {
    if (self.isViewLoaded) [self reloadTable];
}

#pragma mark layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat barBottom = insets.top + BAR_HEIGHT;
    /* the rows and the bar stand in one column, clear of the notch in landscape and no wider than a list reads on a tablet; the wave runs full width */
    CGRect column = ExteriaContentColumn(size, insets, EXTERIA_COLUMN_LIST);
    CGFloat left = column.origin.x, edge = CGRectGetMaxX(column);
    _backdrop.frame = self.view.bounds;
    _barShade.frame = CGRectMake(0, 0, size.width, barBottom);
    _titleLabel.font = ExteriaFontBold(ExteriaIsPad() ? 24 : 20);
    _back.frame = CGRectMake(left, insets.top, 96, BAR_HEIGHT);
    /* the only page of the right pane of a tablet has no left pane to go back to */
    _back.hidden = !_showsBack || ExteriaIsDetailRoot(self);
    if (_titleOnLeft) {
        /* the title lines up with the field under it, and the accessory takes the other end of the bar */
        CGFloat accessoryWidth = _barAccessory ? MAX(52, _barAccessory.bounds.size.width) : 0;
        _titleLabel.textAlignment = ExteriaTextAlignmentLeft;
        _titleLabel.frame = CGRectMake(left + 14, insets.top, column.size.width - 28 - accessoryWidth, BAR_HEIGHT);
        _barAccessory.frame = CGRectMake(edge - accessoryWidth - 2, insets.top, accessoryWidth, BAR_HEIGHT);
    } else {
        /* the back arrow takes 52 points and nothing else stands in the bar, so the name has all the rest; a name cut at 100 points a side lost its end */
        /* the back button is a chevron and the word "Back", about 90 points wide, and a long name that began at 56 ran under the word */
        CGFloat backEnd = _back.hidden ? 56 : 92;
        _titleLabel.frame = CGRectMake(left + backEnd, insets.top, column.size.width - backEnd - 56, BAR_HEIGHT);
        /* a centered title leaves the accessory the right end too, as a bar with buttons is never drawn from the corner of the screen */
        CGFloat accessoryWidth = _barAccessory ? MAX(52, _barAccessory.bounds.size.width) : 0;
        _barAccessory.frame = CGRectMake(edge - accessoryWidth - 2, insets.top, accessoryWidth, BAR_HEIGHT);
    }
    _table.frame = CGRectMake(left, barBottom, column.size.width, size.height - barBottom);
    _table.contentInset = UIEdgeInsetsMake(0, 0, MAX(_bottomInset, insets.bottom), 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    CGFloat contentTop = barBottom + _table.tableHeaderView.bounds.size.height;
    CGFloat midY = contentTop + MAX(0, size.height - contentTop - MAX(_bottomInset, insets.bottom)) / 2;
    _status.font = ExteriaFontRegular(16);
    CGSize fit = [_status sizeThatFits:CGSizeMake(MIN(column.size.width - 64, 420), 200)];
    _status.frame = CGRectMake(CGRectGetMidX(column) - fit.width / 2, midY - fit.height / 2 - (_retry.hidden ? 0 : 22), fit.width, fit.height);
    _retry.titleLabel.font = ExteriaFontSemibold(17);
    _retry.frame = CGRectMake(CGRectGetMidX(column) - 70, CGRectGetMaxY(_status.frame) + 8, 140, 40);
}

@end
