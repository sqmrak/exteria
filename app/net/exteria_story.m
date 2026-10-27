#import "exteria_story.h"

/* strings arrive as UTF-8 cut by the core, but a server can still send invalid bytes */
static NSString *ExteriaUtf8(const char *bytes) {
    NSString *text = [NSString stringWithUTF8String:bytes];
    return text ? text : @"";
}

@implementation ExteriaStory

@synthesize caption = _caption;
@synthesize media = _media;
@synthesize reaction = _reaction;

+ (ExteriaStory *)storyWithRow:(const exteria_story_row *)row {
    ExteriaStory *story = [[[ExteriaStory alloc] init] autorelease];
    story->_row = *row;
    story->_caption = [ExteriaUtf8(row->caption) copy];
    story->_media = [[ExteriaMedia mediaWithInfo:&row->media] retain];
    if (row->music.ref.source != EXTERIA_MEDIA_SOURCE_NONE) story->_music = [[ExteriaMedia mediaWithInfo:&row->music] retain];
    if (row->reacted) story->_reaction = [[ExteriaReaction reactionWithRow:&row->reaction] retain];
    return story;
}

- (void)dealloc {
    [_caption release];
    [_media release];
    [_music release];
    [_reaction release];
    [super dealloc];
}

- (NSString *)musicLine {
    if (!_music) return nil;
    NSString *performer = _music.performer, *title = _music.title;
    NSString *line = performer.length && title.length ? [NSString stringWithFormat:@"%@ \u00B7 %@", performer, title] : (title.length ? title : performer);
    return [line uppercaseString];
}

- (int32_t)storyId { return _row.id; }
- (int32_t)date { return _row.date; }
- (int32_t)expireDate { return _row.expire_date; }
- (int32_t)views { return _row.views; }
- (BOOL)outgoing { return _row.out; }
- (BOOL)pinned { return _row.pinned; }
- (BOOL)closeFriends { return _row.close_friends; }

@end

@implementation ExteriaStoryPeer

@synthesize owner = _owner;
@synthesize maxReadId = _maxReadId;
@synthesize count = _count;
@synthesize unread = _unread;
@synthesize newestDate = _newestDate;
@synthesize firstUnreadId = _firstUnreadId;
@synthesize closeFriends = _closeFriends;

+ (ExteriaStoryPeer *)peerWithRow:(const exteria_story_peer *)row {
    ExteriaStoryPeer *peer = [[[ExteriaStoryPeer alloc] init] autorelease];
    peer->_owner = [[ExteriaDialog alloc] initWithRow:&row->owner];
    peer->_maxReadId = row->max_read_id;
    peer->_count = row->count;
    peer->_unread = row->unread;
    peer->_newestDate = row->newest_date;
    peer->_firstUnreadId = row->first_unread_id;
    peer->_closeFriends = row->close_friends != 0;
    return peer;
}

+ (ExteriaStoryPeer *)peerWithOwner:(ExteriaDialog *)owner count:(int32_t)count {
    ExteriaStoryPeer *peer = [[[ExteriaStoryPeer alloc] init] autorelease];
    peer->_owner = [owner retain];
    peer->_count = count;
    return peer;
}

- (void)dealloc {
    [_owner release];
    [super dealloc];
}

@end
