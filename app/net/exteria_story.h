#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_session.h"

#include "exteria_stories.h"

/* one story as the viewer draws it; built off the main thread */
@interface ExteriaStory : NSObject {
    exteria_story_row _row;
    NSString *_caption;
    ExteriaMedia *_media;
    ExteriaMedia *_music;
    ExteriaReaction *_reaction;
}
+ (ExteriaStory *)storyWithRow:(const exteria_story_row *)row;
@property (nonatomic, readonly) int32_t storyId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t expireDate;
@property (nonatomic, readonly) int32_t views;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL pinned;
@property (nonatomic, readonly) BOOL closeFriends;
@property (nonatomic, readonly, copy) NSString *caption;
/* a picture or a video; kind says which */
@property (nonatomic, readonly, retain) ExteriaMedia *media;
/* the track that plays with the story, nil when it has none */
@property (nonatomic, readonly, retain) ExteriaMedia *music;
/* "PERFORMER · TITLE" for the label of the track, whichever of the two the tags have */
@property (nonatomic, readonly) NSString *musicLine;
/* our reaction to it, nil when there is none */
@property (nonatomic, readonly, retain) ExteriaReaction *reaction;
@end

/* one ring of the strip: a poster and how much of their stories is unseen */
@interface ExteriaStoryPeer : NSObject {
    ExteriaDialog *_owner;
    int32_t _maxReadId;
    int32_t _count;
    int32_t _unread;
    int32_t _newestDate;
    int32_t _firstUnreadId;
    BOOL _closeFriends;
}
+ (ExteriaStoryPeer *)peerWithRow:(const exteria_story_peer *)row;
/* a poster whose stories are already in hand, with nothing unseen */
+ (ExteriaStoryPeer *)peerWithOwner:(ExteriaDialog *)owner count:(int32_t)count;
/* the poster in the form every chat screen uses, which also names them to requests */
@property (nonatomic, readonly, retain) ExteriaDialog *owner;
@property (nonatomic, readonly) int32_t maxReadId;
@property (nonatomic, readonly) int32_t count;
@property (nonatomic, readonly) int32_t unread;
@property (nonatomic, readonly) int32_t newestDate;
@property (nonatomic, readonly) int32_t firstUnreadId;
/* an unseen story is for close friends only, which turns the ring green */
@property (nonatomic, readonly) BOOL closeFriends;
@end

/* the answer of a story list: the poster with the current seen mark, and the stories oldest first */
typedef void (^ExteriaStoriesCompletion)(ExteriaStoryPeer *peer, NSArray *stories, NSString *errorName);

/* stories: the strip, one poster's stories, the seen mark, reactions and replies; implemented in
   exteria_session_stories.m */
@interface ExteriaSession (Stories)

/* ExteriaStoryPeer items, own stories first, then the unseen posters, then the seen ones */
- (void)loadStoryPeers:(ExteriaListCompletion)completion;
/* the live stories of one user or channel; a story the server sent only as a header is fetched in full first */
- (void)loadStoriesOfDialog:(ExteriaDialog *)dialog completion:(ExteriaStoriesCompletion)completion;
/* marks everything up to storyId seen, and counts the view; a failure only shows in the log, the next open says it again */
- (void)markStoriesSeenOfDialog:(ExteriaDialog *)dialog upTo:(int32_t)storyId;
/* a nil reaction takes ours back */
- (void)reactToStory:(int32_t)storyId ofDialog:(ExteriaDialog *)dialog reaction:(ExteriaReaction *)reaction
          completion:(void (^)(NSString *errorName))completion;
/* the text goes to the poster's chat as a reply to the story; randomId must differ for every message */
- (void)replyToStory:(int32_t)storyId ofDialog:(ExteriaDialog *)dialog text:(NSString *)text randomId:(long long)randomId
          completion:(void (^)(NSString *errorName))completion;

/* our own pinned stories, newest first, and one page of our archive of expired ones before beforeId (zero for the newest);
   ExteriaStory items, empty on the last page */
- (void)loadPinnedStories:(ExteriaListCompletion)completion;
- (void)loadStoryArchiveBefore:(int32_t)beforeId completion:(ExteriaListCompletion)completion;

@end
