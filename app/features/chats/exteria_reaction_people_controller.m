#import "exteria_reaction_people_controller.h"

#import "exteria_session_actions.h"
#import "exteria_person.h"
#import "exteria_time.h"
#import "exteria_weak_reference.h"

#define REACTORS_MAX 500

@interface ExteriaReactionPeopleController () {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    int32_t _messageId;
    NSMutableArray *_reactors;
    NSMutableDictionary *_people;
    NSMutableSet *_offsets;
    NSString *_next;
    NSString *_error;
    BOOL _started;
    BOOL _loading;
    BOOL _limited;
    ExteriaWeakReference *_weak;
}
@end

@implementation ExteriaReactionPeopleController

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog messageId:(int32_t)messageId {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _messageId = messageId;
    _reactors = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _offsets = [[NSMutableSet alloc] init];
    _weak = [[ExteriaWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chat.reactors.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_reactors release];
    [_people release];
    [_offsets release];
    [_next release];
    [_error release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadNext];
}

- (void)themeDidChange { [self rebuild]; }

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in _reactors) {
        NSNumber *key = [entry objectForKey:@"peer"];
        ExteriaPerson *person = [_people objectForKey:key];
        NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", key];
        int32_t date = [[entry objectForKey:@"date"] intValue];
        NSString *time = date > 0 ? ExteriaMediaTimeText(date) : NSLocalizedString(@"chat.reactors.time.unknown", nil);
        ExteriaReaction *reaction = [entry objectForKey:@"reaction"];
        [rows addObject:[ExteriaSettingsRow rowWithTitle:name subtitle:time value:reaction.displayText tap:nil]];
    }
    ExteriaWeakReference *weak = _weak;
    if (_loading) [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.loading", nil) value:nil tap:nil]];
    else if (_error) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.retry", nil) subtitle:_error value:nil tap:^{
            [(ExteriaReactionPeopleController *)weak.target loadNext];
        }]];
    } else if (_next && _reactors.count < REACTORS_MAX) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"group.tab.more", nil) value:nil tap:^{
            [(ExteriaReactionPeopleController *)weak.target loadNext];
        }]];
    } else if (_started && !_reactors.count) {
        [rows addObject:[ExteriaSettingsRow rowWithTitle:NSLocalizedString(@"chat.reactors.empty", nil) value:nil tap:nil]];
    }
    NSString *footer = _limited ? NSLocalizedString(@"chat.reactors.limit", nil) : nil;
    self.sections = [NSArray arrayWithObject:[ExteriaSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
    [self reloadSettings];
}

- (void)loadNext {
    if (_loading || (_started && !_next && !_error) || _reactors.count >= REACTORS_MAX) return;
    NSString *cursor = [[_next copy] autorelease];
    _loading = YES;
    [_error release]; _error = nil;
    [self rebuild];
    ExteriaWeakReference *weak = _weak;
    [_session loadReactorsOfMessageId:_messageId ofDialog:_dialog offset:cursor completion:^(NSArray *items, NSDictionary *people, NSString *next, NSString *errorName) {
        ExteriaReactionPeopleController *page = weak.target;
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
            NSUInteger room = REACTORS_MAX - page->_reactors.count;
            NSUInteger take = MIN(room, items.count);
            if (take) [page->_reactors addObjectsFromArray:[items subarrayWithRange:NSMakeRange(0, take)]];
            page->_limited = take < items.count || (next && page->_reactors.count >= REACTORS_MAX);
            [page->_next release];
            page->_next = [next copy];
        }
        [page rebuild];
    }];
}
@end
