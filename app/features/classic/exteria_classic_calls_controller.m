#import "exteria_classic_calls_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_platform.h"
#import "exteria_session_calllog.h"
#import "exteria_theme.h"

@interface ExteriaClassicCallsController () <UIActionSheetDelegate> {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    NSArray *_entries;
    UILabel *_status;
    UIActivityIndicatorView *_spinner;
    ExteriaCallLogEntry *_chosen;
    BOOL _loading;
    BOOL _loaded;
}
@end

@implementation ExteriaClassicCallsController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    self.title = NSLocalizedString(@"tab.calls", nil);
    return self;
}

- (void)dealloc {
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_entries release];
    [_status release];
    [_spinner release];
    [_chosen release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    table.rowHeight = [ExteriaClassicDialogCell rowHeight];
    UIView *backdrop = [[[UIView alloc] initWithFrame:table.bounds] autorelease];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:ExteriaThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [backdrop addSubview:_spinner];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = ExteriaThemeIsDark() ? ExteriaColorSecondary() : [UIColor grayColor];
    _status.textAlignment = ExteriaTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.font = [UIFont systemFontOfSize:16];
    [backdrop addSubview:_status];
    backdrop.frame = table.backgroundView.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [table.backgroundView addSubview:backdrop];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.tableView.bounds.size;
    _spinner.center = CGPointMake(size.width / 2, 160);
    _status.frame = CGRectMake(32, 130, size.width - 64, 60);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ExteriaAllowsOrientation(orientation);
}

- (void)reload {
    if (_loading) return;
    _loading = YES;
    if (!_loaded) [_spinner startAnimating];
    [self retain];
    [_session loadCallLog:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        [_spinner stopAnimating];
        if (!items) {
            if (!_loaded) _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil) : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName];
            return;
        }
        _loaded = YES;
        [_entries release];
        _entries = [items retain];
        _status.text = items.count ? @"" : NSLocalizedString(@"calls.empty", nil);
        self.tableView.separatorStyle = items.count ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"call";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithCall:[_entries objectAtIndex:(NSUInteger)indexPath.row] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    ExteriaCallLogEntry *entry = [_entries objectAtIndex:(NSUInteger)indexPath.row];
    if (![entry dialog]) return;
    [_chosen release];
    _chosen = [entry retain];
    Class sheetClass = NSClassFromString(@"UIActionSheet");
    id sheet = [[sheetClass alloc] initWithTitle:entry.name delegate:self cancelButtonTitle:NSLocalizedString(@"picker.cancel", nil) destructiveButtonTitle:nil
                               otherButtonTitles:NSLocalizedString(@"calls.callback", nil), NSLocalizedString(@"calls.openchat", nil), nil];
    [sheet showInView:self.tabBarController.view ? self.tabBarController.view : self.view];
    [sheet release];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    ExteriaCallLogEntry *entry = [[_chosen retain] autorelease];
    if (!entry || index == sheet.cancelButtonIndex) return;
    if (index == 0) {
        [_session startCallToDialog:[entry dialog]];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:[entry dialog] avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:chat animated:YES];
}

@end
