#import "exteria_country_controller.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_bar_button.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#import "exteria_wave_background_view.h"

#define EXTERIA_BAR_HEIGHT 44.0
#define EXTERIA_SEARCH_HEIGHT 54.0
#define EXTERIA_ROW_HEIGHT 52.0
#define EXTERIA_FLAG_POINTS_WIDTH 32.0
#define EXTERIA_FLAG_POINTS_HEIGHT 24.0
#define SEARCH_GLASS_SIDE 18.0

@interface ExteriaSearchIcon : UIView
@end

@implementation ExteriaSearchIcon

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    return self;
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    [ExteriaSymbolImage(ExteriaSymbolMagnifier, SEARCH_GLASS_SIDE, [UIColor colorWithRed:0.55 green:0.55 blue:0.6 alpha:1])
        drawAtPoint:CGPointMake(w / 2 - SEARCH_GLASS_SIDE / 2, h / 2 - SEARCH_GLASS_SIDE / 2)];
}

@end

@interface ExteriaCountryCell : UITableViewCell {
    UIImageView *_flag;
    UILabel *_name;
    UILabel *_code;
    UIView *_line;
}
- (void)showCountry:(ExteriaCountry *)country flag:(UIImage *)flag;
@end

@implementation ExteriaCountryCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.contentView.backgroundColor = [UIColor clearColor];
    UIView *selected = [[[UIView alloc] init] autorelease];
    selected.backgroundColor = ExteriaColorField();
    self.selectedBackgroundView = selected;
    _flag = [[UIImageView alloc] init];
    _name = [[UILabel alloc] init];
    _name.backgroundColor = [UIColor clearColor];
    _name.textColor = ExteriaColorTitle();
    _name.font = ExteriaFontRegular(17);
    _code = [[UILabel alloc] init];
    _code.backgroundColor = [UIColor clearColor];
    _code.textColor = ExteriaColorMessage();
    _code.font = ExteriaFontRegular(17);
    _code.textAlignment = ExteriaTextAlignmentRight;
    _line = [[UIView alloc] init];
    _line.backgroundColor = ExteriaColorHairline();
    [self.contentView addSubview:_flag];
    [self.contentView addSubview:_name];
    [self.contentView addSubview:_code];
    [self.contentView addSubview:_line];
    return self;
}

- (void)dealloc {
    [_flag release];
    [_name release];
    [_code release];
    [_line release];
    [super dealloc];
}

- (void)showCountry:(ExteriaCountry *)country flag:(UIImage *)flag {
    _flag.image = flag;
    _name.text = country.name;
    _code.text = [@"+" stringByAppendingString:country.code];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ +%@", country.name, country.code];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat hairline = 1.0 / ExteriaScreenScale();
    _flag.frame = CGRectMake(16, (h - EXTERIA_FLAG_POINTS_HEIGHT) / 2, EXTERIA_FLAG_POINTS_WIDTH, EXTERIA_FLAG_POINTS_HEIGHT);
    _code.frame = CGRectMake(w - 16 - 70, 0, 70, h);
    _name.frame = CGRectMake(16 + EXTERIA_FLAG_POINTS_WIDTH + 12, 0, w - 16 - EXTERIA_FLAG_POINTS_WIDTH - 12 - 16 - 74, h);
    _line.frame = CGRectMake(16 + EXTERIA_FLAG_POINTS_WIDTH + 12, h - hairline, w, hairline);
}

@end

@interface ExteriaCountryController () {
    ExteriaCountryBook *_book;
    ExteriaWaveBackgroundView *_backdrop;
    ExteriaBarButton *_cancel;
    UILabel *_titleLabel;
    UIView *_searchBox;
    UITextField *_search;
    UITableView *_table;
    NSArray *_titles;
    NSArray *_groups;
    CGFloat _keyboardHeight;
}
@end

@implementation ExteriaCountryController

@synthesize delegate = _delegate;

- (id)initWithCountryBook:(ExteriaCountryBook *)book {
    self = [super init];
    if (!self) return nil;
    _book = [book retain];
    [self rebuildForQuery:@""];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    _search.delegate = nil;
    [_book release];
    [_backdrop release];
    [_cancel release];
    [_titleLabel release];
    [_searchBox release];
    [_search release];
    [_table release];
    [_titles release];
    [_groups release];
    [super dealloc];
}

static NSString *ExteriaLetter(NSString *name) {
    if (!name.length) return @"#";
    NSString *folded = [[name decomposedStringWithCanonicalMapping] uppercaseString];
    return [folded substringToIndex:1];
}

static BOOL ExteriaCountryMatches(ExteriaCountry *country, NSString *query) {
    NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if ([country.name rangeOfString:query options:options].location != NSNotFound) return YES;
    if ([country.iso rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    NSString *digits = [query hasPrefix:@"+"] ? [query substringFromIndex:1] : query;
    return digits.length && [country.code hasPrefix:digits];
}

/* a search shows one flat list; without one the names group under their first letter */
- (void)rebuildForQuery:(NSString *)query {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *groups = [NSMutableArray array];
    BOOL searching = query.length > 0;
    for (ExteriaCountry *country in _book.countries) {
        if (searching && !ExteriaCountryMatches(country, query)) continue;
        NSString *letter = searching ? @"" : ExteriaLetter(country.name);
        if (![titles.lastObject isEqualToString:letter]) {
            [titles addObject:letter];
            [groups addObject:[NSMutableArray array]];
        }
        [groups.lastObject addObject:country];
    }
    [_titles release];
    _titles = [titles copy];
    [_groups release];
    _groups = [groups copy];
    [_table reloadData];
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = ExteriaColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[ExteriaWaveBackgroundView alloc] initWithFrame:root.bounds];
    [root addSubview:_backdrop];

    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStylePlain];
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = EXTERIA_ROW_HEIGHT;
    _table.dataSource = self;
    _table.delegate = self;
    /* both colours are ios 6 properties, set by name so ios 5 never sees the selectors */
    if ([_table respondsToSelector:NSSelectorFromString(@"setSectionIndexColor:")]) {
        [_table setValue:ExteriaColorAccent() forKey:@"sectionIndexColor"];
        [_table setValue:[UIColor clearColor] forKey:@"sectionIndexTrackingBackgroundColor"];
    }
    [root addSubview:_table];

    _searchBox = [[UIView alloc] init];
    _searchBox.backgroundColor = [UIColor whiteColor];
    _searchBox.layer.cornerRadius = 10;
    [root addSubview:_searchBox];
    ExteriaSearchIcon *icon = [[[ExteriaSearchIcon alloc] initWithFrame:CGRectMake(6, 0, 28, 38)] autorelease];
    [_searchBox addSubview:icon];
    _search = [[UITextField alloc] init];
    _search.delegate = self;
    _search.placeholder = NSLocalizedString(@"picker.search", nil);
    _search.font = ExteriaFontRegular(17);
    _search.textColor = ExteriaColorTitle();
    _search.clearButtonMode = UITextFieldViewModeWhileEditing;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.returnKeyType = UIReturnKeyDone;
    _search.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    [_search addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    [_searchBox addSubview:_search];

    _cancel = [[ExteriaBarButton alloc] init];
    _cancel.chevron = NO;
    _cancel.title = NSLocalizedString(@"picker.cancel", nil);
    [_cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancel];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textAlignment = ExteriaTextAlignmentCenter;
    _titleLabel.textColor = ExteriaColorTitle();
    _titleLabel.font = ExteriaFontSemibold(17);
    _titleLabel.text = NSLocalizedString(@"picker.title", nil);
    [root addSubview:_titleLabel];
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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = ExteriaLayoutInsets(self);
    CGFloat top = insets.top;
    _backdrop.frame = self.view.bounds;
    _cancel.frame = CGRectMake(insets.left, top, 96, EXTERIA_BAR_HEIGHT);
    _titleLabel.frame = CGRectMake(insets.left + 96, top, size.width - insets.left - insets.right - 192, EXTERIA_BAR_HEIGHT);
    CGFloat searchTop = top + EXTERIA_BAR_HEIGHT;
    CGFloat margin = 12 + insets.left;
    _searchBox.frame = CGRectMake(margin, searchTop + 8, size.width - margin - 12 - insets.right, 38);
    _search.frame = CGRectMake(34, 0, _searchBox.bounds.size.width - 34 - 8, 38);
    CGFloat tableTop = searchTop + EXTERIA_SEARCH_HEIGHT;
    _table.frame = CGRectMake(0, tableTop, size.width, size.height - tableTop);
    _table.contentInset = UIEdgeInsetsMake(0, 0, MAX(0, _keyboardHeight - insets.bottom), 0);
    _table.scrollIndicatorInsets = _table.contentInset;
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [self.view convertRect:[[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    _keyboardHeight = MAX(0, self.view.bounds.size.height - end.origin.y);
    [self.view setNeedsLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.view endEditing:YES];
}

- (void)searchChanged {
    NSString *query = [_search.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    [self rebuildForQuery:query];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    return YES;
}

- (void)cancelTapped {
    [_delegate countryControllerDidCancel:self];
}

#pragma mark table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[_groups objectAtIndex:(NSUInteger)section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    static NSString *identifier = @"country";
    ExteriaCountryCell *cell = (ExteriaCountryCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[ExteriaCountryCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    ExteriaCountry *country = [[_groups objectAtIndex:(NSUInteger)path.section] objectAtIndex:(NSUInteger)path.row];
    [cell showCountry:country flag:[_book flagForCountry:country]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [[_titles objectAtIndex:(NSUInteger)section] length] ? 28 : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [_titles objectAtIndex:(NSUInteger)section];
    if (!title.length) return nil;
    UIView *header = [[[UIView alloc] init] autorelease];
    header.backgroundColor = [ExteriaColorBackdrop() colorWithAlphaComponent:0.96];
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(16, 0, 200, 28)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ExteriaColorMessage();
    label.font = ExteriaFontSemibold(14);
    label.text = title;
    [header addSubview:label];
    return header;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [[_titles lastObject] length] ? _titles : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    ExteriaCountry *country = [[_groups objectAtIndex:(NSUInteger)path.section] objectAtIndex:(NSUInteger)path.row];
    [_delegate countryController:self didPickCountry:country];
}

@end
