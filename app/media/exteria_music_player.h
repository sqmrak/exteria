#import <Foundation/Foundation.h>

#import "exteria_media_cache.h"
#import "exteria_message.h"

/* what to call a song: its title tag, else its file name without the extension, else the word for audio; and its performer tag, empty
   when there is none */
NSString *ExteriaTrackTitle(ExteriaMedia *track);
NSString *ExteriaTrackPerformer(ExteriaMedia *track);
/* "1x", "1.5x" and "2x" */
NSString *ExteriaSpeedText(float speed);
/* "performer - Title", or the title alone */
NSString *ExteriaTrackLine(ExteriaMedia *track);

/* a link named for the format inside the temporary directory that points at the cached file, which the cache names
   by key only */
NSURL *ExteriaPlayableLink(NSString *path, NSString *extension, NSString *slot);

/* the same, named as the file was sent: a document that goes to another app or to the files of the person keeps its own name and extension, and two documents
   do not become file.pdf and file(1).pdf there */
NSURL *ExteriaNamedLink(NSString *path, NSString *name, NSString *slot);

/* posted on the main thread when the song, the state or the load progress changes, and each half second while a song plays */
extern NSString *const ExteriaMusicPlayerDidChangeNotification;
extern NSString *const ExteriaMusicPlayerDidTickNotification;

typedef enum {
    ExteriaMusicStateIdle,
    ExteriaMusicStateLoading,
    ExteriaMusicStatePlaying,
    ExteriaMusicStatePaused,
    ExteriaMusicStateFailed     /* the file did not arrive or this system cannot play its format */
} ExteriaMusicState;

/* the one song that plays on the device; there is a single audio output, so the profile's list, its mini player
   and the audio messages of a chat all drive this one object */
@interface ExteriaMusicPlayer : NSObject

+ (ExteriaMusicPlayer *)sharedPlayer;

@property (nonatomic, readonly) ExteriaMedia *track;
@property (nonatomic, readonly) ExteriaMusicState state;
/* the share of the file that has arrived while loading, 0 when the size is not known */
@property (nonatomic, readonly) float loadProgress;
/* seconds into the song, and its length (the tags' when the file does not say yet) */
@property (nonatomic, readonly) NSTimeInterval position;
@property (nonatomic, readonly) NSTimeInterval duration;
/* the songs next and previous go through; the current one is among them */
@property (nonatomic, readonly) NSArray *queue;
@property (nonatomic, readonly) ExteriaMediaCache *media;
/* the cover of the song once it has arrived, nil before and for songs without one */
@property (nonatomic, readonly) UIImage *cover;
/* 1, 1.5 or 2; it applies to songs and voice notes alike and is kept between runs */
@property (nonatomic, readonly) float speed;
/* the next of the three speeds after the current one */
- (void)cycleSpeed;

/* the order the songs of a queue go in and what happens at the end of one, as the player of exteraless has them; they apply to songs, a queue of voice notes always goes
   one after the other. both are kept between runs */
typedef enum {
    ExteriaMusicRepeatOff,      /* the queue ends after its last song */
    ExteriaMusicRepeatList,     /* after the last song the first one comes again */
    ExteriaMusicRepeatSong      /* the song that ends plays again */
} ExteriaMusicRepeat;
@property (nonatomic, readonly) BOOL shuffle;
@property (nonatomic, readonly) ExteriaMusicRepeat repeatMode;
- (void)toggleShuffle;
/* off, the list, the song, and off again */
- (void)cycleRepeat;

/* starts track, and queue (which should contain it) is what next and previous walk through; a queue without the
   track plays it alone */
- (void)playTrack:(ExteriaMedia *)track queue:(NSArray *)queue media:(ExteriaMediaCache *)media;
- (BOOL)isCurrentTrack:(ExteriaMedia *)track;
/* asked when a voice note ends, with that note: YES means the chat started something else after it (a video message), so the player stops and does not walk its
   own queue; NO leaves the next voice note to the player. set by the chat that started the note, nil for other owners of the player */
@property (nonatomic, copy) BOOL (^voiceEndHandler)(ExteriaMedia *track);
/* pauses a song that plays and does nothing for any other state, for a video that takes the speaker */
- (void)pause;
/* the pauses of the chat settings: a video or a video message that starts pauses the song when "pause music on
   media" is on */
- (void)pauseForMedia;
- (void)pauseForRecording;
- (void)resumeAfterRecording;
/* pauses a playing song and resumes a paused one; a failed one is tried again */
- (void)togglePause;
- (void)next;
- (void)previous;
- (void)playQueueTrackAtIndex:(NSUInteger)index;
/* the song and the queue are forgotten and the audio session is let go */
- (void)stop;
/* fraction of the song, 0 to 1 */
- (void)seekToFraction:(float)fraction;

@end
