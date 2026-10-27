#import "exteria_profile_feed.h"

#import "exteria_gift_folders.h"
#import "exteria_gift_tiles.h"
#import "exteria_story.h"

@interface ExteriaProfileFeed () {
    ExteriaSession *_session;
    ExteriaDialog *_owner;
    NSMutableArray *_items;
    NSMutableArray *_tiles;
    NSString *_nextOffset;
    NSString *_errorName;
    BOOL _loading;
    BOOL _loaded;
    BOOL _finished;
    NSUInteger _generation;
    int32_t _folderId;
}
@end

@implementation ExteriaProfileFeed

@synthesize kind = _kind;
@synthesize items = _items;
@synthesize tiles = _tiles;
@synthesize loading = _loading;
@synthesize loaded = _loaded;
@synthesize finished = _finished;
@synthesize errorName = _errorName;
@synthesize folderId = _folderId;

- (id)initWithSession:(ExteriaSession *)session kind:(ExteriaProfileFeedKind)kind owner:(ExteriaDialog *)owner {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _kind = kind;
    _owner = [owner retain];
    _items = [[NSMutableArray alloc] init];
    _tiles = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc {
    /* a page still on its way finds the generation changed and drops its answer */
    ++_generation;
    [_session release];
    [_owner release];
    [_items release];
    [_tiles release];
    [_nextOffset release];
    [_errorName release];
    [super dealloc];
}

- (void)reload:(void (^)(void))changed {
    ++_generation;
    _loading = NO;
    _finished = NO;
    [_nextOffset release];
    _nextOffset = nil;
    [self loadPageReplacing:YES changed:changed];
}

- (void)loadMore:(void (^)(void))changed {
    if (_loading || _finished || !_loaded) return;
    [self loadPageReplacing:NO changed:changed];
}

- (void)take:(NSArray *)page replacing:(BOOL)replacing {
    if (replacing) {
        [_items removeAllObjects];
        [_tiles removeAllObjects];
    }
    for (id item in page) {
        [_items addObject:item];
        if (_kind == ExteriaFeedGifts) [_tiles addObject:ExteriaTileForSavedGift(item, _owner.saved)];
        else [_tiles addObject:ExteriaTileForStory(item)];
    }
}

- (void)loadPageReplacing:(BOOL)replacing changed:(void (^)(void))changed {
    _loading = YES;
    NSUInteger generation = _generation;
    void (^notify)(void) = [changed copy];
    [self retain];
    void (^storyPage)(NSArray *, NSString *) = ^(NSArray *stories, NSString *errorName) {
        [self autorelease];
        if (generation != _generation) { [notify release]; return; }
        _loading = NO;
        [_errorName release];
        _errorName = [errorName copy];
        if (stories) {
            _loaded = YES;
            [self take:stories replacing:replacing];
            /* the pinned list comes whole, the archive ends on an empty page */
            _finished = _kind == ExteriaFeedPinnedStories || stories.count == 0;
        }
        if (notify) notify();
        [notify release];
    };
    void (^storyPageCopy)(NSArray *, NSString *) = [storyPage copy];
    if (_kind == ExteriaFeedPinnedStories) {
        [_session loadPinnedStories:storyPageCopy];
    } else if (_kind == ExteriaFeedArchivedStories) {
        int32_t before = replacing ? 0 : [(ExteriaStory *)[_items lastObject] storyId];
        [_session loadStoryArchiveBefore:before completion:storyPageCopy];
    } else {
        [_session loadSavedGiftsOfDialog:_owner folder:_folderId offset:replacing ? nil : _nextOffset completion:^(NSArray *gifts, NSInteger total, NSString *next, NSString *errorName) {
            (void)total;
            [self autorelease];
            if (generation != _generation) { [notify release]; return; }
            _loading = NO;
            [_errorName release];
            _errorName = [errorName copy];
            if (gifts) {
                _loaded = YES;
                [self take:gifts replacing:replacing];
                [_nextOffset release];
                _nextOffset = [next copy];
                _finished = next == nil;
            }
            if (notify) notify();
            [notify release];
        }];
    }
    [storyPageCopy release];
}

@end
