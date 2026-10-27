#import "exteria_file_picker.h"

#import <sys/stat.h>
#import <unistd.h>

#import "exteria_chat_item.h"
#import "exteria_classic_chrome.h"
#import "exteria_platform.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"

@interface ExteriaFilePicker () <UISearchBarDelegate> {
    NSString *_directory;
    NSArray *_entries;
    NSArray *_shown;
    NSString *_failure;
    UISearchBar *_search;
    UIActivityIndicatorView *_spinner;
    void (^_handler)(NSString *);
    void (^_cancel)(void);
    BOOL _loading;
}
@end

@implementation ExteriaFilePicker

- (id)initWithDirectory:(NSString *)directory handler:(void (^)(NSString *))handler cancel:(void (^)(void))cancel {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _directory = [directory copy];
    _handler = [handler copy];
    _cancel = [cancel copy];
    self.title = directory ? ([directory isEqualToString:@"/"] ? @"/" : directory.lastPathComponent) : NSLocalizedString(@"attach.file.title", nil);
    return self;
}

- (void)dealloc {
    _search.delegate = nil;
    [_directory release]; [_entries release]; [_shown release]; [_failure release];
    [_search release]; [_spinner release]; [_handler release]; [_cancel release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleTable(self.tableView);
    else {
        self.tableView.backgroundColor = ExteriaColorScreen();
        self.tableView.separatorColor = ExteriaColorHairline();
    }
    self.tableView.rowHeight = 64;
    if (self.navigationController.viewControllers.count == 1) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"attach.cancel", nil)
                                                                                  style:UIBarButtonItemStyleBordered target:self action:@selector(leave)] autorelease];
    }
    if (_directory) {
        _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
        _search.placeholder = NSLocalizedString(@"attach.file.search", nil);
        _search.delegate = self;
        _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        if (ExteriaThemeIsClassic()) ExteriaClassicStyleSearchBar(_search);
        self.tableView.tableHeaderView = _search;
    }
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:_spinner] autorelease];
    [self loadDirectory];
}

- (void)loadDirectory {
    _loading = YES;
    [_spinner startAnimating];
    NSString *directory = [_directory copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSMutableArray *entries = [NSMutableArray array];
        NSError *error = nil;
        NSFileManager *files = [NSFileManager defaultManager];
        if (!directory) {
            NSArray *paths = [NSArray arrayWithObjects:@"/var/mobile/Media", [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], @"/var/mobile", @"/", nil];
            NSArray *titles = [NSArray arrayWithObjects:NSLocalizedString(@"attach.file.media", nil), NSLocalizedString(@"attach.file.app", nil),
                               NSLocalizedString(@"attach.file.mobile", nil), NSLocalizedString(@"attach.file.root", nil), nil];
            for (NSUInteger i = 0; i < paths.count; ++i) {
                NSString *path = [paths objectAtIndex:i];
                BOOL isDirectory = NO;
                if ([files fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
                    [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"path", [titles objectAtIndex:i], @"name", [NSNumber numberWithBool:YES], @"directory", nil]];
            }
        } else {
            NSArray *names = [files contentsOfDirectoryAtPath:directory error:&error];
            for (NSString *name in names) {
                NSString *path = [directory stringByAppendingPathComponent:name];
                struct stat info;
                if (stat(path.fileSystemRepresentation, &info) != 0 || (!S_ISDIR(info.st_mode) && !S_ISREG(info.st_mode))) continue;
                [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"path", name, @"name",
                                    [NSNumber numberWithBool:S_ISDIR(info.st_mode)], @"directory",
                                    [NSNumber numberWithLongLong:(long long)info.st_size], @"size", nil]];
            }
            [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                BOOL ad = [[a objectForKey:@"directory"] boolValue], bd = [[b objectForKey:@"directory"] boolValue];
                if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
                return [[a objectForKey:@"name"] compare:[b objectForKey:@"name"] options:NSCaseInsensitiveSearch | NSNumericSearch];
            }];
        }
        NSArray *result = [entries copy];
        NSString *failure = error ? [[error localizedDescription] copy] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            _loading = NO;
            [_spinner stopAnimating];
            [_entries release]; _entries = result;
            [_failure release]; _failure = failure;
            [self filterEntries];
        });
        [directory release];
        [pool drain];
    });
}

- (void)filterEntries {
    NSString *query = [_search.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *shown = [NSMutableArray array];
    for (NSDictionary *entry in _entries) {
        if (!query.length || [[entry objectForKey:@"name"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) [shown addObject:entry];
    }
    [_shown release]; _shown = [shown copy];
    UILabel *message = nil;
    if (!_loading && (_failure || !_shown.count)) {
        message = [[[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 90)] autorelease];
        message.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        message.backgroundColor = [UIColor clearColor]; message.textColor = ExteriaColorSecondary();
        message.textAlignment = ExteriaTextAlignmentCenter; message.numberOfLines = 0;
        message.text = _failure ? [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"attach.file.read.failed", nil), _failure] : NSLocalizedString(@"attach.file.empty", nil);
    }
    self.tableView.backgroundView = message;
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText { (void)searchBar; (void)searchText; [self filterEntries]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return ExteriaAllowsOrientation(orientation); }

- (void)leave {
    void (^cancel)(void) = [_cancel retain];
    [self dismissViewControllerAnimated:YES completion:^{ if (cancel) cancel(); [cancel release]; }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)_shown.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"entry";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    NSDictionary *entry = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    BOOL directory = [[entry objectForKey:@"directory"] boolValue];
    cell.textLabel.text = [entry objectForKey:@"name"];
    cell.detailTextLabel.text = !_directory ? [entry objectForKey:@"path"] : (directory ? NSLocalizedString(@"attach.file.folder", nil) : ExteriaFileSizeText([[entry objectForKey:@"size"] longLongValue]));
    cell.imageView.image = ExteriaSymbolImage(directory ? ExteriaSymbolSettingsFolders : ExteriaSymbolDocument, 28, ExteriaColorAccent());
    cell.accessoryType = directory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleCell(cell);
    else { cell.backgroundColor = ExteriaColorCard(); cell.textLabel.textColor = ExteriaColorTitle(); cell.detailTextLabel.textColor = ExteriaColorSecondary(); }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = [_shown objectAtIndex:(NSUInteger)indexPath.row];
    NSString *path = [entry objectForKey:@"path"];
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0 || (!S_ISDIR(info.st_mode) && !S_ISREG(info.st_mode)) || access(path.fileSystemRepresentation, R_OK) != 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"attach.file.unavailable", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show]; [alert release]; return;
    }
    if (S_ISDIR(info.st_mode)) {
        ExteriaFilePicker *inner = [[[ExteriaFilePicker alloc] initWithDirectory:path handler:_handler cancel:_cancel] autorelease];
        [self.navigationController pushViewController:inner animated:YES];
    } else if (S_ISREG(info.st_mode)) {
        void (^handler)(NSString *) = [_handler retain];
        [self dismissViewControllerAnimated:YES completion:^{ if (handler) handler(path); [handler release]; }];
    }
}

@end
