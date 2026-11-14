#import "exteria_file_picker.h"
#import "exteria_alert_view.h"

#import <sys/stat.h>
#import <unistd.h>
#import <dirent.h>
#import <errno.h>
#import <string.h>

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
    NSArray *_extensions;
    NSString *_rootTitle;
    NSString *_searchPlaceholder;
    NSString *_emptyText;
    ExteriaSymbol _fileSymbol;
}
@end

@implementation ExteriaFilePicker

@synthesize extensions = _extensions, rootTitle = _rootTitle, searchPlaceholder = _searchPlaceholder, emptyText = _emptyText, fileSymbol = _fileSymbol;

- (id)initWithDirectory:(NSString *)directory handler:(void (^)(NSString *))handler cancel:(void (^)(void))cancel {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self) return nil;
    _directory = [directory copy];
    _handler = [handler copy];
    _cancel = [cancel copy];
    _fileSymbol = ExteriaSymbolDocument;
    self.title = directory ? ([directory isEqualToString:@"/"] ? @"/" : directory.lastPathComponent) : NSLocalizedString(@"attach.file.title", nil);
    return self;
}

- (void)dealloc {
    _search.delegate = nil;
    [_directory release]; [_entries release]; [_shown release]; [_failure release];
    [_search release]; [_spinner release]; [_handler release]; [_cancel release];
    [_extensions release]; [_rootTitle release]; [_searchPlaceholder release]; [_emptyText release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (ExteriaThemeIsClassic()) ExteriaClassicStyleTable(self.tableView);
    else {
        self.tableView.backgroundColor = ExteriaColorScreen();
        self.tableView.separatorColor = ExteriaColorHairline();
    }
    if (!_directory && _rootTitle.length) self.title = _rootTitle;
    self.tableView.rowHeight = 64;
    if (self.navigationController.viewControllers.count == 1) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"attach.cancel", nil)
                                                                                  style:UIBarButtonItemStyleBordered target:self action:@selector(leave)] autorelease];
    }
    if (_directory) {
        _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
        _search.placeholder = _searchPlaceholder.length ? _searchPlaceholder : NSLocalizedString(@"attach.file.search", nil);
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
    NSArray *extensions = [_extensions copy];
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
            /* the directory is read entry by entry: an entry the process may not stat, which the system keeps from a program outside the sandbox of its owner, is still a name in the
               folder, and leaving it out made folders that exist look missing. the kind comes from the directory record when stat will not say */
            DIR *handle = opendir(directory.fileSystemRepresentation);
            if (!handle) {
                error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithUTF8String:strerror(errno)] forKey:NSLocalizedDescriptionKey]];
            } else {
                struct dirent *record;
                while ((record = readdir(handle))) {
                    if (!strcmp(record->d_name, ".") || !strcmp(record->d_name, "..")) continue;
                    NSString *name = [NSString stringWithUTF8String:record->d_name];
                    if (!name) continue;
                    NSString *path = [directory stringByAppendingPathComponent:name];
                    struct stat info;
                    BOOL isDirectory, isFile;
                    long long size = 0;
                    if (stat(path.fileSystemRepresentation, &info) == 0) {
                        isDirectory = S_ISDIR(info.st_mode);
                        isFile = S_ISREG(info.st_mode);
                        size = (long long)info.st_size;
                    } else {
                        isDirectory = record->d_type == DT_DIR;
                        isFile = record->d_type == DT_REG;
                        struct stat link;
                        if (isFile && lstat(path.fileSystemRepresentation, &link) == 0) size = (long long)link.st_size;
                    }
                    if (!isDirectory && !isFile) continue;
                    if (extensions.count && isFile) {
                        BOOL wanted = NO;
                        for (NSString *extension in extensions) if ([[name pathExtension] caseInsensitiveCompare:extension] == NSOrderedSame) wanted = YES;
                        if (!wanted) continue;
                    }
                    [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:path, @"path", name, @"name",
                                        [NSNumber numberWithBool:isDirectory], @"directory", [NSNumber numberWithLongLong:size], @"size", nil]];
                }
                closedir(handle);
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
        [extensions release];
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
        message.text = _failure ? [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"attach.file.read.failed", nil), _failure] : (_emptyText.length ? _emptyText : NSLocalizedString(@"attach.file.empty", nil));
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
    cell.imageView.image = ExteriaSymbolImage(directory ? ExteriaSymbolSettingsFolders : _fileSymbol, 28, ExteriaColorAccent());
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
    BOOL listed = [[entry objectForKey:@"directory"] boolValue];
    /* a folder is opened and says itself why it cannot be read; the check here took away every folder that stat or access refused, though opendir may well read it */
    if (listed && (stat(path.fileSystemRepresentation, &info) != 0)) {
        info.st_mode = S_IFDIR;
    } else if (stat(path.fileSystemRepresentation, &info) != 0 || (!S_ISDIR(info.st_mode) && !S_ISREG(info.st_mode)) || (!S_ISDIR(info.st_mode) && access(path.fileSystemRepresentation, R_OK) != 0)) {
        UIAlertView *alert = [[ExteriaAlertClass() alloc] initWithTitle:nil message:NSLocalizedString(@"attach.file.unavailable", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
        [alert show]; [alert release]; return;
    }
    if (S_ISDIR(info.st_mode)) {
        ExteriaFilePicker *inner = [[[ExteriaFilePicker alloc] initWithDirectory:path handler:_handler cancel:_cancel] autorelease];
        inner.extensions = _extensions;
        inner.searchPlaceholder = _searchPlaceholder;
        inner.emptyText = _emptyText;
        inner.fileSymbol = _fileSymbol;
        [self.navigationController pushViewController:inner animated:YES];
    } else if (S_ISREG(info.st_mode)) {
        void (^handler)(NSString *) = [_handler retain];
        [self dismissViewControllerAnimated:YES completion:^{ if (handler) handler(path); [handler release]; }];
    }
}

@end
