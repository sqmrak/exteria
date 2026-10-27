#import "exteria_classic_contacts_controller.h"

#import "exteria_chat_controller.h"
#import "exteria_classic_chrome.h"
#import "exteria_classic_dialog_cell.h"
#import "exteria_contact_list.h"
#import "exteria_person.h"
#import "exteria_platform.h"
#import "exteria_theme.h"

@interface ExteriaClassicContactsController () {
    ExteriaSession *_session;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    UISearchBar *_search;
    UILabel *_status;
    UIActivityIndicatorView *_spinner;
    ExteriaContactList *_list;
    UIBarButtonItem *_sortItem;
    BOOL _loaded;
    BOOL _loading;
}
@end

@implementation ExteriaClassicContactsController

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _list = [[ExteriaContactList alloc] init];
    self.title = NSLocalizedString(@"tab.contacts", nil);
    return self;
}

- (void)dealloc {
    _search.delegate = nil;
    /* a tab nobody opened has no view, and asking for it here would load one while the controller is being freed */
    if ([self isViewLoaded]) {
        self.tableView.delegate = nil;
        self.tableView.dataSource = nil;
    }
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_search release];
    [_status release];
    [_spinner release];
    [_list release];
    [_sortItem release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    ExteriaClassicStyleTable(table);
    if (ExteriaThemeIsDark()) {
        if ([table respondsToSelector:NSSelectorFromString(@"setSectionIndexBackgroundColor:")])
            [table setValue:ExteriaColorField() forKey:@"sectionIndexBackgroundColor"];
        if ([table respondsToSelector:NSSelectorFromString(@"setSectionIndexColor:")])
            [table setValue:ExteriaColorTitle() forKey:@"sectionIndexColor"];
        if ([table respondsToSelector:NSSelectorFromString(@"setSectionIndexTrackingBackgroundColor:")])
            [table setValue:ExteriaColorBar() forKey:@"sectionIndexTrackingBackgroundColor"];
    }
    table.rowHeight = [ExteriaClassicDialogCell rowHeight];
    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 44)];
    _search.placeholder = NSLocalizedString(@"contacts.search", nil);
    _search.delegate = self;
    _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    ExteriaClassicStyleSearchBar(_search);
    table.tableHeaderView = _search;
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
    /* the order is the one the person picked, by name in sections of a letter or by when they were last seen; the
       button names the order the list is in */
    _sortItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStyleBordered target:self action:@selector(sortTapped)];
    self.navigationItem.rightBarButtonItem = _sortItem;
    [self refreshSortItem];
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
    [_spinner startAnimating];
    _status.text = @"";
    [self retain];
    [_session loadContacts:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        _loading = NO;
        [_spinner stopAnimating];
        if (!items) {
            _status.text = [errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil) : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName];
            return;
        }
        _loaded = YES;
        _list.people = items;
        [self applyQuery];
        [self.tableView reloadData];
    }];
}

- (void)refreshSortItem {
    _sortItem.title = NSLocalizedString(_list.sortByName ? @"contacts.sort.name" : @"contacts.sort.time", nil);
    _sortItem.accessibilityLabel = NSLocalizedString(_list.sortByName ? @"contacts.sort.totime" : @"contacts.sort.toname", nil);
}

- (void)sortTapped {
    _list.sortByName = !_list.sortByName;
    [ExteriaContactList storeSortByName:_list.sortByName];
    [self refreshSortItem];
    [self.tableView reloadData];
}

- (void)applyQuery {
    _list.query = _search.text;
    if (_loaded) _status.text = _list.count ? @"" : (_list.people.count ? NSLocalizedString(@"chats.nothing", nil) : NSLocalizedString(@"contacts.empty", nil));
    self.tableView.separatorStyle = _list.count ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    (void)searchText;
    [self applyQuery];
    [self.tableView reloadData];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
    [self searchBar:searchBar textDidChange:@""];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_list.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[(NSArray *)[_list.sections objectAtIndex:(NSUInteger)section] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    id title = [_list.titles objectAtIndex:(NSUInteger)section];
    return [title isKindOfClass:[NSString class]] ? title : nil;
}

/* the system header of a plain table is a grey-blue strip that ignores the accent color, so the letter sits on a strip of the accent of the theme, as the bars do */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForHeaderInSection:section];
    if (!text.length) return nil;
    BOOL dark = ExteriaThemeIsDark();
    UIView *strip = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 22)] autorelease];
    strip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    strip.backgroundColor = ExteriaThemeTinted(dark ? [UIColor colorWithRed:0.40 green:0.27 blue:0.56 alpha:1] : [UIColor colorWithRed:0.60 green:0.44 blue:0.78 alpha:1]);
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(12, 0, strip.bounds.size.width - 24, 22)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.shadowColor = [UIColor colorWithWhite:0 alpha:0.35];
    label.shadowOffset = CGSizeMake(0, 1);
    label.font = [UIFont boldSystemFontOfSize:17];
    label.text = text;
    [strip addSubview:label];
    return strip;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section].length ? 22 : 0;
}

/* the letters at the right edge jump to a section; there is nothing to jump to by time or while a search narrows the list */
- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    (void)tableView;
    if (!_list.sortByName || _list.query.length || _list.titles.count < 2) return nil;
    return _list.titles;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    (void)tableView;
    (void)title;
    return index;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"person";
    ExteriaClassicDialogCell *cell = (ExteriaClassicDialogCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaClassicDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [cell configureWithPerson:[_list personAtIndexPath:indexPath] avatars:_avatars];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_search resignFirstResponder];
    ExteriaDialog *dialog = [ExteriaDialog dialogWithPerson:[_list personAtIndexPath:indexPath]];
    if (!dialog) {
        Class alertClass = NSClassFromString(@"UIAlertView");
        id alert = [[alertClass alloc] initWithTitle:nil message:NSLocalizedString(@"contacts.nochat", nil) delegate:nil
                                   cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show];
        [alert release];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    chat.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    (void)scrollView;
    [_search resignFirstResponder];
}

@end
