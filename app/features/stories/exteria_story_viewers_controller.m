#import "exteria_story_viewers_controller.h"

#import "exteria_person.h"
#import "exteria_theme.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"
#import "exteria_story.h"

/* the list stops here, as the one of the people who reacted does */
#define VIEWERS_MAX 1000

@interface ExteriaStoryViewersController () {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    int32_t _storyId;
    int32_t _views;
    NSMutableArray *_viewers;
    NSMutableDictionary *_people;
    NSMutableSet *_offsets;
    NSString *_next;
    NSString *_error;
    BOOL _started;
    BOOL _loading;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaStoryViewersController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog storyId:(int32_t)storyId views:(int32_t)views {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _storyId = storyId;
    _views = views;
    _viewers = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _offsets = [[NSMutableSet alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"story.viewers.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_viewers release];
    [_people release];
    [_offsets release];
    [_next release];
    [_error release];
    [super dealloc];
}

- (UINavigationController *)presentableNavigation {
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
    navigation.navigationBarHidden = !ExteriaThemeIsClassic();
    if (ExteriaThemeIsClassic()) {
        self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"story.close", nil)
            style:UIBarButtonItemStyleDone target:self action:@selector(closeViewers)] autorelease];
    }
    return navigation;
}

- (void)closeViewers {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

/* the arrow of the page is the way out of a page that stands first in its own navigation */
- (void)goBack {
    if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self closeViewers];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadNext];
}

- (void)themeDidChange { [self rebuild]; }

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in _viewers) {
        NSNumber *key = [entry objectForKey:@"peer"];
        ExteriaPerson *person = [_people objectForKey:key];
        NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", key];
        int32_t date = [[entry objectForKey:@"date"] intValue];
        NSString *time = date > 0 ? ExteriaMediaTimeText(date) : nil;
        [rows addObject:[ExteriaSettingsRow rowWithTitle:name subtitle:time value:nil tap:nil]];
    }
    ExteriaWeakReference *weak = _weak;
    if (_loading) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.loading", nil) value:nil tap:nil]];
    } else if (_error) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.retry", nil) subtitle:_error value:nil tap:^{
            [(ExteriaStoryViewersController *)weak.target loadNext];
        }]];
    } else if (_next && _viewers.count < VIEWERS_MAX) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"group.tab.more", nil) value:nil tap:^{
            [(ExteriaStoryViewersController *)weak.target loadNext];
        }]];
    } else if (_started && !_viewers.count) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"story.viewers.empty", nil) value:nil tap:nil]];
    }
    /* the count the server gave says how many looked, also when the list shows fewer, since people who hid their views or left are not all named */
    NSString *footer = _views > 0 ? [NSString stringWithFormat:NSLocalizedString(@"story.views", nil), (int)_views] : nil;
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}

- (void)loadNext {
    if (_loading || (_started && !_next && !_error) || _viewers.count >= VIEWERS_MAX) return;
    NSString *cursor = [[_next copy] autorelease];
    _loading = YES;
    [_error release]; _error = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadViewersOfStory:_storyId ofDialog:_dialog offset:cursor completion:^(NSArray *items, NSDictionary *people, NSString *next, int32_t total, NSString *errorName) {
        ExteriaStoryViewersController *page = weak.target;
        if (!page) return;
        page->_loading = NO;
        page->_started = YES;
        if (errorName) {
            page->_error = [[NSString stringWithFormat:NSLocalizedString(@"chat.reactors.error", nil), errorName] copy];
        } else if (next && ([page->_offsets containsObject:next] || (cursor && [next isEqualToString:cursor]))) {
            page->_error = [NSLocalizedString(@"chat.reactors.badpage", nil) copy];
        } else {
            if (cursor) [page->_offsets addObject:cursor];
            [page->_people addEntriesFromDictionary:people];
            [page->_viewers addObjectsFromArray:items];
            if (total > 0) page->_views = total;
            [page->_next release];
            page->_next = [next copy];
        }
        [page rebuild];
    }];
}

@end
