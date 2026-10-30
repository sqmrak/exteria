#import "exteria_string_drawing.h"
#import "exteria_developers.h"
#import "exteria_contacts_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_chat_controller.h"
#import "exteria_weak_reference.h"
#import "exteria_session_bots.h"
#import "exteria_alert.h"

#import "exteria_contact_list.h"
#import "exteria_person.h"
#import "exteria_person_cell.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_time.h"

#define SEARCH_HEIGHT 52.0
#define HEADER_HEIGHT 32.0
#define BUTTON_SIDE 44.0

/* the hint of the search stands at the left edge of the typed text and is put on the middle of the field by the
   height of its line, as the field of the chat list does */
@interface ExteriaContactsSearchField : UITextField
@end

@implementation ExteriaContactsSearchField

static const CGFloat ExteriaContactsSearchClear = 30.0;

- (CGRect)placeholderRectForBounds:(CGRect)bounds {
    CGFloat inset = self.leftViewMode == UITextFieldViewModeAlways ? self.leftView.bounds.size.width : 0;
    return CGRectMake(inset, 0, MAX(0, bounds.size.width - inset - ExteriaContactsSearchClear), bounds.size.height);
}

- (void)drawPlaceholderInRect:(CGRect)rect {
    [ExteriaColorSecondary() set];
    CGFloat height = ceil(self.font.lineHeight);
    rect.origin.y += floor((rect.size.height - height) / 2);
    rect.size.height = height;
    ExteriaDrawStringIn(self.placeholder, self.font, rect, ExteriaStringTailTruncate, ExteriaTextAlignmentLeft);
}

@end

@interface ExteriaContactsController () <UITextFieldDelegate> {
    ExteriaContactList *_list;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickerLibrary;
    UITextField *_search;
    UIButton *_sortButton;
    UILabel *_footer;
}
@end

@implementation ExteriaContactsController

@synthesize media = _media;
@synthesize stickerLibrary = _stickerLibrary;

- (id)initWithSession:(ExteriaSession *)session {
    self = [super initWithSession:session];
    if (!self) return nil;
    self.contentUnderBar = YES;
    self.heading = NSLocalizedString(@"tab.contacts", nil);
    /* three buttons stand at the right end of the bar, so the title lines up with the field under it, as the one of the chats does */
    self.titleOnLeft = YES;
    _list = [[ExteriaContactList alloc] init];
    return self;
}

- (void)dealloc {
    _search.delegate = nil;
    [_list release];
    [_media release];
    [_stickerLibrary release];
    [_search release];
    [_sortButton release];
    [_footer release];
    [super dealloc];
}

#pragma mark bar and search

static UIButton *ExteriaContactsBarButton(ExteriaSymbol symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, BUTTON_SIDE, BUTTON_SIDE);
    [button setImage:ExteriaSymbolImage(symbol, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* the sort button shows the order it would switch to: a clock while the list is by name, a person while it is by
   time */
- (void)refreshSortButton {
    BOOL byName = _list.sortByName;
    [_sortButton setImage:ExteriaSymbolImage(byName ? ExteriaSymbolClock : ExteriaSymbolPerson, 24, ExteriaColorTitle()) forState:UIControlStateNormal];
    _sortButton.accessibilityLabel = NSLocalizedString(byName ? @"contacts.sort.totime" : @"contacts.sort.toname", nil);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *searchButton = ExteriaContactsBarButton(ExteriaSymbolMagnifier, self, @selector(searchTapped));
    searchButton.accessibilityLabel = NSLocalizedString(@"contacts.search", nil);
    _sortButton = [ExteriaContactsBarButton(ExteriaSymbolClock, self, @selector(sortTapped)) retain];
    UIButton *addButton = ExteriaContactsBarButton(ExteriaSymbolPlusCircle, self, @selector(addTapped));
    addButton.accessibilityLabel = NSLocalizedString(@"contacts.add", nil);
    UIView *accessory = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 3 * BUTTON_SIDE, BUTTON_SIDE)] autorelease];
    addButton.frame = CGRectMake(0, 0, BUTTON_SIDE, BUTTON_SIDE);
    searchButton.frame = CGRectMake(BUTTON_SIDE, 0, BUTTON_SIDE, BUTTON_SIDE);
    _sortButton.frame = CGRectMake(2 * BUTTON_SIDE, 0, BUTTON_SIDE, BUTTON_SIDE);
    [accessory addSubview:addButton];
    [accessory addSubview:searchButton];
    [accessory addSubview:_sortButton];
    self.barAccessory = accessory;
    [self refreshSortButton];

    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, SEARCH_HEIGHT)] autorelease];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _search = [[ExteriaContactsSearchField alloc] initWithFrame:CGRectMake(16, 8, 288, 36)];
    _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _search.backgroundColor = ExteriaColorField();
    _search.layer.cornerRadius = 18;
    _search.font = ExteriaFontRegular(16);
    _search.textColor = ExteriaColorTitle();
    _search.placeholder = NSLocalizedString(@"contacts.search", nil);
    _search.returnKeyType = UIReturnKeySearch;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.clearButtonMode = UITextFieldViewModeWhileEditing;
    _search.leftView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 36)] autorelease];
    _search.leftViewMode = UITextFieldViewModeAlways;
    /* the hint stands where the typed text will start, and on the middle of the field by its height */
    _search.textAlignment = ExteriaTextAlignmentLeft;
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _search.delegate = self;
    [_search addTarget:self action:@selector(queryChanged) forControlEvents:UIControlEventEditingChanged];
    [header addSubview:_search];
    self.table.tableHeaderView = header;

    _footer = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 56)];
    _footer.backgroundColor = [UIColor clearColor];
    _footer.textColor = ExteriaColorSecondary();
    _footer.font = ExteriaFontRegular(14);
    _footer.textAlignment = ExteriaTextAlignmentCenter;
    _footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.table.tableFooterView = _footer;
}

/* the number first, then the name: two short questions, since the system alert has one field */
- (void)addTapped {
    ExteriaWeakReference *me = [ExteriaWeakReference referenceTo:self];
    ExteriaPromptText(NSLocalizedString(@"contacts.add.phone", nil), nil, @"+", NSLocalizedString(@"contacts.add.phone.hint", nil), ^(NSString *text) {
        NSString *phone = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" -()"]] componentsJoinedByString:@""];
        if (!phone.length || [phone isEqualToString:@"+"]) return;
        ExteriaPromptText(NSLocalizedString(@"contacts.add.name", nil), nil, @"", NSLocalizedString(@"profile.contact.placeholder", nil), ^(NSString *name) {
            ExteriaContactsController *controller = me.target;
            NSString *full = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!controller || !full.length) return;
            NSRange space = [full rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *first = space.location == NSNotFound ? full : [full substringToIndex:space.location];
            NSString *last = space.location == NSNotFound ? @"" : [[full substringFromIndex:space.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [controller retain];
            [controller.session addContactPhone:phone firstName:first lastName:last completion:^(BOOL found, NSString *errorName) {
                [controller autorelease];
                if (errorName) {
                    NSLog(@"exteria: the contact was not added: %@", errorName);
                    ExteriaShowNotice(nil, NSLocalizedString(@"contacts.add.error", nil));
                    return;
                }
                if (!found) {
                    ExteriaShowNotice(nil, NSLocalizedString(@"contacts.add.notfound", nil));
                    return;
                }
                [controller reloadDiscardingRunning];
            }];
        });
    });
}

- (void)searchTapped {
    [self.table setContentOffset:CGPointZero animated:YES];
    [_search becomeFirstResponder];
}

- (void)sortTapped {
    _list.sortByName = !_list.sortByName;
    [ExteriaContactList storeSortByName:_list.sortByName];
    [self refreshSortButton];
    [self reloadTable];
    if (_list.count) [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
}

- (void)queryChanged {
    _list.query = _search.text;
    [self reloadTable];
}

- (void)textFieldDidBeginEditing:(UITextField *)field {
    field.textAlignment = ExteriaTextAlignmentLeft;
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    if (!field.text.length) field.textAlignment = ExteriaTextAlignmentCenter;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return NO;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [super scrollViewWillBeginDragging:scrollView];
    [_search resignFirstResponder];
}

#pragma mark list

- (void)loadItemsWithCompletion:(ExteriaListCompletion)completion {
    [self.session loadContacts:completion];
}

- (void)didReceiveItems:(NSArray *)items {
    _list.people = items;
}

/* the screen is empty when the account has no contacts; a search that finds nobody leaves the field where it is and says so under it */
- (NSInteger)itemCount {
    return (NSInteger)_list.people.count;
}

- (NSString *)emptyText {
    return NSLocalizedString(@"contacts.empty", nil);
}

- (void)reloadTable {
    [super reloadTable];
    BOOL searching = [_list.query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
    _footer.text = _list.count || !searching ? [NSString stringWithFormat:NSLocalizedString(@"contacts.count", nil), (unsigned long)_list.count] : NSLocalizedString(@"chats.nothing", nil);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_list.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[(NSArray *)[_list.sections objectAtIndex:(NSUInteger)section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [ExteriaPersonCell rowHeight];
}

/* a gray strip with the letter, which stays at the top while its people scroll under it; the list by time has none */
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_list.titles objectAtIndex:(NSUInteger)section] isKindOfClass:[NSString class]] ? HEADER_HEIGHT : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    id title = [_list.titles objectAtIndex:(NSUInteger)section];
    if (![title isKindOfClass:[NSString class]]) return nil;
    UIView *strip = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, HEADER_HEIGHT)] autorelease];
    strip.backgroundColor = [ExteriaColorField() colorWithAlphaComponent:0.96f];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(20, 0, tableView.bounds.size.width - 40, HEADER_HEIGHT)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ExteriaColorAccent();
    label.font = ExteriaFontSemibold(14);
    label.text = title;
    [strip addSubview:label];
    return strip;
}

/* the letters at the right edge, which jump to a section; there is nothing to jump to by time or while the list is narrowed by a search */
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
    ExteriaPersonCell *cell = (ExteriaPersonCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaPersonCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaPerson *person = [_list personAtIndexPath:indexPath];
    BOOL online = person.presence == EXTERIA_PRESENCE_ONLINE;
    cell.developer = ExteriaPersonIsDeveloper(person);
    cell.mutual = person.mutual;
    [cell configureWithName:person.name initials:person.initials seed:(NSUInteger)(person.userId % 1000003)
                   subtitle:person.bot ? NSLocalizedString(@"seen.bot", nil) : ExteriaLastSeenText(person.presence, person.seen)
              subtitleColor:online ? ExteriaColorAccent() : nil
                   trailing:nil symbol:ExteriaSymbolChevronRight showsSymbol:NO nameColor:nil
                      photo:person.photo avatars:self.avatars];
    cell.avatarDeleted = person.deleted;
    return cell;
}

/* a contact opens into its chat; one that has no access hash yet cannot be written to from here */
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
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:self.session dialog:dialog avatars:self.avatars
                                                                           media:_media stickers:_stickerLibrary] autorelease];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
