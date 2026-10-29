#import "exteria_chat_settings.h"
#import "exteria_proximity.h"
#import "exteria_music_player.h"

#include <unistd.h>

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "exteria_audio_session.h"
#import "exteria_now_playing.h"

#include <stdio.h>

#include "exteria_voice.h"
#include "exteria_flac.h"
#import "exteria_remote_file.h"

@interface ExteriaFlacJob : NSObject {
@public
    volatile int cancelled;
}
@end
@implementation ExteriaFlacJob
@end

static int ExteriaFlacCancelled(void *context) {
    return __sync_val_compare_and_swap(&((ExteriaFlacJob *)context)->cancelled, 0, 0);
}

NSString *const ExteriaMusicPlayerDidChangeNotification = @"ExteriaMusicPlayerDidChange";
NSString *const ExteriaMusicPlayerDidTickNotification = @"ExteriaMusicPlayerDidTick";

#define TICK_SECONDS 0.5
#define SPEED_KEY @"exteria.music.speed"
#define COVER_SIDE 300
/* an item that has not said ready or failed after this many ticks is given up on, so a stuck decoder does not spin forever */
#define READY_TICKS 30
/* back to the start of the song instead of the previous one when this far in */
#define RESTART_AFTER 3.0

/* the container AVPlayer sniffs by the file's extension on old systems, and the cache names files by key only */
static NSString *ExteriaAudioExtension(ExteriaMedia *track) {
    NSString *name = track.name.pathExtension.lowercaseString;
    if (name.length && name.length <= 5) return name;
    return @"mp3";
}

NSString *ExteriaTrackTitle(ExteriaMedia *track) {
    if (track.kind == EXTERIA_PREVIEW_VOICE) return NSLocalizedString(@"preview.voice", nil);
    if (track.title.length) return track.title;
    NSString *name = [track.name stringByDeletingPathExtension];
    return name.length ? name : NSLocalizedString(@"preview.audio", nil);
}

NSString *ExteriaTrackPerformer(ExteriaMedia *track) {
    return track.performer ? track.performer : @"";
}

NSString *ExteriaSpeedText(float speed) {
    return speed >= 1.9f ? @"2\u00d7" : (speed >= 1.4f ? @"1.5\u00d7" : @"1\u00d7");
}

NSString *ExteriaTrackLine(ExteriaMedia *track) {
    NSString *performer = ExteriaTrackPerformer(track);
    return performer.length ? [NSString stringWithFormat:@"%@ - %@", performer, ExteriaTrackTitle(track)] : ExteriaTrackTitle(track);
}

@interface ExteriaMusicPlayer () {
    ExteriaMedia *_track;
    NSArray *_queue;
    NSUInteger _index;
    ExteriaMediaCache *_media;
    ExteriaMusicState _state;
    float _loadProgress;
    AVPlayer *_player;
    AVPlayerItem *_item;
    ExteriaFlacJob *_flacJob;
    NSString *_flacDirectory;
    NSTimer *_timer;
    NSUInteger _token;
    NSUInteger _pathRequest;
    NSUInteger _waitTicks;
    BOOL _listening;
    /* AVPlayer keeps answering the old time until a seek has landed, which sent every slider back to where the song was for a moment; the target is
       the position while the seek runs, and a newer seek or a new player makes an older answer void */
    BOOL _seeking;
    NSTimeInterval _seekTarget;
    NSUInteger _seekGeneration;
    BOOL _pausedForRecording;
    /* the phone is watched for the ear while a voice message plays, and the sound follows it: earpiece near, loudspeaker away */
    BOOL _watchingProximity;
    UIImage *_cover;
    float _speed;
}
@end

@implementation ExteriaMusicPlayer

@synthesize track = _track;
@synthesize state = _state;
@synthesize loadProgress = _loadProgress;
@synthesize queue = _queue;
@synthesize media = _media;
@synthesize cover = _cover;
@synthesize speed = _speed;

+ (ExteriaMusicPlayer *)sharedPlayer {
    static ExteriaMusicPlayer *player;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ player = [[ExteriaMusicPlayer alloc] init]; });
    return player;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    float saved = [[NSUserDefaults standardUserDefaults] floatForKey:SPEED_KEY];
    _speed = saved >= 1.9f ? 2.0f : (saved >= 1.4f ? 1.5f : 1.0f);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(enteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}

/* the speed rides on the player's rate, which a play call resets on some systems, so it is set after every play */
- (void)applyRate {
    if (_player && _state == ExteriaMusicStatePlaying) _player.rate = _speed;
}

- (void)cycleSpeed {
    _speed = _speed < 1.4f ? 1.5f : (_speed < 1.9f ? 2.0f : 1.0f);
    [[NSUserDefaults standardUserDefaults] setFloat:_speed forKey:SPEED_KEY];
    [self applyRate];
    [self changed];
}

#pragma mark state

/* the lock screen follows the song; the elapsed time is set here and advances by itself at the rate until the next change */
- (void)refreshNowPlaying {
    if (!_track || _state == ExteriaMusicStateIdle || _state == ExteriaMusicStateFailed) {
        ExteriaNowPlayingClear();
        return;
    }
    ExteriaNowPlayingShow(ExteriaTrackTitle(_track), ExteriaTrackPerformer(_track), _cover, self.position, self.duration,
                          _state == ExteriaMusicStatePlaying ? _speed : 0);
}

- (void)changed {
    [self refreshNowPlaying];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaMusicPlayerDidChangeNotification object:self];
}

- (void)setState:(ExteriaMusicState)state {
    _state = state;
    [self updateProximity];
    [self changed];
}

#pragma mark proximity

/* the sensor runs only while a voice message plays and the switch is on; a device without one (an iPad, an iPod) answers NO when it is asked to start */
- (void)updateProximity {
    BOOL want = _state == ExteriaMusicStatePlaying && _track.kind == EXTERIA_PREVIEW_VOICE && ExteriaChatRaiseToListen();
    if (want == _watchingProximity) return;
    if (want) {
        if (!ExteriaProximityStart()) return;
        _watchingProximity = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proximityChanged) name:ExteriaProximityDidChangeNotification object:nil];
        return;
    }
    _watchingProximity = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ExteriaProximityDidChangeNotification object:nil];
    ExteriaProximityStop();
    /* the next song takes the loudspeaker route itself when it starts; a message that was held to the ear has to be let go of by hand */
    if (_state == ExteriaMusicStatePaused) ExteriaAudioSessionBeginPlayback();
}

- (void)proximityChanged {
    if (!_watchingProximity || _state != ExteriaMusicStatePlaying) return;
    BOOL near = ExteriaProximityNear();
    BOOL routed = near ? ExteriaAudioSessionBeginEarpiece() : ExteriaAudioSessionBeginPlayback();
    /* a change of the category can stop the player; the message goes on from where it was */
    if (routed && _player.rate == 0) [_player play];
}

- (NSTimeInterval)position {
    if (!_player) return 0;
    if (_seeking) return _seekTarget;
    NSTimeInterval seconds = CMTimeGetSeconds(_player.currentTime);
    return seconds > 0 && seconds < 1e9 ? seconds : 0;
}

- (NSTimeInterval)duration {
    if (_item && _item.status == AVPlayerItemStatusReadyToPlay) {
        NSTimeInterval seconds = CMTimeGetSeconds(_item.duration);
        if (seconds > 0 && seconds < 1e9) return seconds;
    }
    return _track.duration;
}

- (BOOL)isCurrentTrack:(ExteriaMedia *)track {
    return _track && track && [_track.file.key isEqualToString:track.file.key];
}

#pragma mark audio session

- (void)observeInterruptions {
    if (_listening) return;
    NSString *name = ExteriaAudioConstant("AVAudioSessionInterruptionNotification");
    /* the notification came with ios 6; before it the song simply carries on after a call */
    if (!name) return;
    _listening = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interrupted:) name:name object:nil];
}

/* a voice message stops when the app goes away, if the person asked for that; a song keeps playing, since it is what the background audio is for */
- (void)enteredBackground:(NSNotification *)note {
    (void)note;
    if (_track.kind == EXTERIA_PREVIEW_VOICE && ExteriaChatFlagGet(ExteriaChatFlagPauseVoiceOnMinimize)) [self pause];
}

- (void)interrupted:(NSNotification *)note {
    NSNumber *type = [note.userInfo objectForKey:@"AVAudioSessionInterruptionTypeKey"];
    if (type.integerValue == 1 && _state == ExteriaMusicStatePlaying) [self pause];
}

- (BOOL)takeAudioSession {
    if (!ExteriaAudioSessionBeginPlayback()) return NO;
    [self observeInterruptions];
    ExteriaRemoteControlsStart(self, @selector(remotePlay:), @selector(remotePause:), @selector(remoteToggle:), @selector(remoteNext:), @selector(remotePrevious:));
    return YES;
}

/* the lock screen's buttons; zero is "handled" for the command center */
- (NSInteger)remotePlay:(id)event {
    (void)event;
    if (_state == ExteriaMusicStatePaused) [self togglePause];
    return 0;
}

- (NSInteger)remotePause:(id)event {
    (void)event;
    [self pause];
    return 0;
}

- (NSInteger)remoteToggle:(id)event {
    (void)event;
    [self togglePause];
    return 0;
}

- (NSInteger)remoteNext:(id)event {
    (void)event;
    [self next];
    return 0;
}

- (NSInteger)remotePrevious:(id)event {
    (void)event;
    [self previous];
    return 0;
}

#pragma mark playing

- (void)stopTimer {
    [_timer invalidate];
    _timer = nil;
}

- (void)releasePlayer {
    if (_flacJob) {
        __sync_lock_test_and_set(&_flacJob->cancelled, 1);
        [_flacJob release];
        _flacJob = nil;
    }
    [self stopTimer];
    if (_item) [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [_player pause];
    [_player release];
    _player = nil;
    [_item release];
    _item = nil;
    if (_flacDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:_flacDirectory error:NULL];
        [_flacDirectory release];
        _flacDirectory = nil;
    }
    ++_seekGeneration;
    _seeking = NO;
}

- (void)fail:(NSString *)reason {
    NSLog(@"exteria: song %@ does not play: %@", _track.file.key, reason);
    [self releasePlayer];
    [self setState:ExteriaMusicStateFailed];
}

/* the link under the name given, in a folder that is emptied first */
static NSURL *ExteriaLinkNamed(NSString *path, NSString *aliasName, NSString *slot) {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"exteria-" stringByAppendingString:slot]];
    [files removeItemAtPath:directory error:NULL];
    NSError *error = nil;
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: cannot make %@: %@", directory, error);
        return nil;
    }
    NSString *alias = [directory stringByAppendingPathComponent:aliasName];
    /* a hard link is the cached file itself, so the player never follows a link out of the temporary folder into the cache; the symbolic link stays for
       a volume that refuses the hard link */
    if (link(path.fileSystemRepresentation, alias.fileSystemRepresentation) == 0) return [NSURL fileURLWithPath:alias];
    if (![files createSymbolicLinkAtPath:alias withDestinationPath:path error:&error]) {
        NSLog(@"exteria: cannot link %@: %@", path, error);
        return nil;
    }
    return [NSURL fileURLWithPath:alias];
}

NSURL *ExteriaPlayableLink(NSString *path, NSString *extension, NSString *slot) {
    return ExteriaLinkNamed(path, [@"file." stringByAppendingString:extension], slot);
}

/* an inch short of what a file system takes: names are cut in the middle of the stem, never in the extension, since the extension tells the type */
#define LINK_NAME_BYTES_MAX 120

NSURL *ExteriaNamedLink(NSString *path, NSString *name, NSString *slot) {
    NSString *clean = [[name lastPathComponent] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    clean = [[clean componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@""];
    /* a name that begins with dots would be hidden, and one that is only dots is a directory entry */
    while ([clean hasPrefix:@"."]) clean = [clean substringFromIndex:1];
    if (!clean.length) clean = @"file";
    NSString *extension = [clean pathExtension];
    NSString *stem = [clean stringByDeletingPathExtension];
    while ([stem lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + (extension.length ? extension.length + 1 : 0) > LINK_NAME_BYTES_MAX && stem.length > 1) {
        stem = [stem substringToIndex:stem.length - 1];
    }
    return ExteriaLinkNamed(path, extension.length ? [stem stringByAppendingPathExtension:extension] : stem, slot);
}

/* a voice note is Ogg Opus, which no system here plays; the decoder writes the samples as they come, so the
   recording is never held as samples */
typedef struct {
    FILE *file;
    size_t samples;
} ExteriaWavTarget;

static int ExteriaWavWrite(void *ctx, const int16_t *samples, size_t count) {
    ExteriaWavTarget *target = ctx;
    if (fwrite(samples, sizeof(int16_t), count, target->file) != count) return 1;
    target->samples += count;
    return 0;
}

/* writes the WAV and returns its path, nil on failure with the reason in error */
static NSString *ExteriaDecodeVoice(NSString *path, NSString **error) {
    NSError *readError = nil;
    NSData *ogg = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&readError];
    if (!ogg) {
        *error = [readError description];
        return nil;
    }
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"exteria-voice"];
    NSFileManager *files = [NSFileManager defaultManager];
    [files removeItemAtPath:directory error:NULL];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&readError]) {
        *error = [readError description];
        return nil;
    }
    NSString *wav = [directory stringByAppendingPathComponent:@"note.wav"];
    FILE *file = fopen(wav.fileSystemRepresentation, "wb");
    if (!file) {
        *error = @"cannot create the wav file";
        return nil;
    }
    uint8_t header[44];
    ExteriaWavTarget target = {file, 0};
    memset(header, 0, sizeof(header));
    BOOL written = fwrite(header, 1, sizeof(header), file) == sizeof(header);
    exteria_status status = written ? exteria_voice_decode(ogg.bytes, ogg.length, ExteriaWavWrite, &target, &target.samples) : EXTERIA_E_IO;
    if (status == EXTERIA_OK) {
        exteria_wav_header(EXTERIA_VOICE_RATE, target.samples, header);
        written = fseek(file, 0, SEEK_SET) == 0 && fwrite(header, 1, sizeof(header), file) == sizeof(header);
    }
    BOOL closed = fclose(file) == 0;
    if (status != EXTERIA_OK || !written || !closed) {
        *error = [NSString stringWithFormat:@"decode: %s", exteria_status_name(status)];
        [files removeItemAtPath:directory error:NULL];
        return nil;
    }
    return wav;
}

- (void)playItemAtURL:(NSURL *)url {
    if (!url || ![self takeAudioSession]) {
        [self fail:@"the file cannot be opened"];
        return;
    }
    [self releasePlayer];
    _item = [[AVPlayerItem playerItemWithURL:url] retain];
    _player = [[AVPlayer playerWithPlayerItem:_item] retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    _waitTicks = 0;
    [self setState:ExteriaMusicStatePlaying];
    [self startPlayer];
}

/* pitch stays put at 1.5 and 2 times, where the system has the setting (ios 7 on); the key is set by name so older sdks build */
- (void)startPlayer {
    if ([_item respondsToSelector:NSSelectorFromString(@"setAudioTimePitchAlgorithm:")]) {
        NSString *algorithm = ExteriaAudioConstant("AVAudioTimePitchAlgorithmTimeDomain");
        if (algorithm) [_item setValue:algorithm forKey:@"audioTimePitchAlgorithm"];
    }
    [_player play];
    [self applyRate];
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:TICK_SECONDS target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}

static BOOL ExteriaIsOgg(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:4];
    [handle closeFile];
    return head.length == 4 && !memcmp(head.bytes, "OggS", 4);
}

static BOOL ExteriaIsFlac(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:4];
    [handle closeFile];
    return head.length == 4 && !memcmp(head.bytes, "fLaC", 4);
}

- (void)beginPlaybackAtPath:(NSString *)path {
    if (ExteriaIsFlac(path) || [[_track.name.pathExtension lowercaseString] isEqualToString:@"flac"]) {
        static dispatch_queue_t queue;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ queue = dispatch_queue_create("exteria.flac.decode", DISPATCH_QUEUE_SERIAL); });
        NSUInteger token = _token;
        ExteriaFlacJob *job = [[ExteriaFlacJob alloc] init];
        _flacJob = job;
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"exteria-flac-%lu", (unsigned long)token]];
        dispatch_async(queue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSFileManager *files = [NSFileManager defaultManager];
            NSError *error = nil;
            [files removeItemAtPath:directory error:NULL];
            BOOL made = [files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
            NSString *wav = [directory stringByAppendingPathComponent:@"music.wav"];
            exteria_status status = made ? exteria_flac_to_wav(path.fileSystemRepresentation, wav.fileSystemRepresentation, ExteriaFlacCancelled, job) : EXTERIA_E_IO;
            if (!made) NSLog(@"exteria: cannot create FLAC playback directory: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token != _token || _flacJob != job) {
                    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
                    return;
                }
                [_flacJob release];
                _flacJob = nil;
                if (status != EXTERIA_OK) {
                    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
                    [self fail:[NSString stringWithFormat:@"FLAC decode: %s", exteria_status_name(status)]];
                    return;
                }
                [self playItemAtURL:[NSURL fileURLWithPath:wav]];
                if (_state == ExteriaMusicStatePlaying) _flacDirectory = [directory copy];
                else [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
            });
            [pool drain];
        });
        return;
    }
    if (ExteriaIsOgg(path)) {
        static dispatch_queue_t queue;
        if (!queue) queue = dispatch_queue_create("exteria.voice.decode", DISPATCH_QUEUE_SERIAL);
        NSUInteger token = _token;
        dispatch_async(queue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSString *reason = nil;
            NSString *wav = ExteriaDecodeVoice(path, &reason);
            reason = [[reason copy] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token != _token) return;
                if (!wav) [self fail:reason];
                else [self playItemAtURL:[NSURL fileURLWithPath:wav]];
            });
            [pool drain];
        });
        return;
    }
    [self playItemAtURL:ExteriaPlayableLink(path, ExteriaAudioExtension(_track), @"music")];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    if (!_item) return;
    if (_item.status == AVPlayerItemStatusFailed) {
        [self fail:[_item.error description]];
        return;
    }
    if (_item.status == AVPlayerItemStatusUnknown && ++_waitTicks > READY_TICKS) {
        [self fail:@"the file never became ready"];
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaMusicPlayerDidTickNotification object:self];
}

- (void)itemEnded:(NSNotification *)note {
    (void)note;
    /* a voice message that ends leaves the next one of the chat unplayed, if the person asked for that */
    BOOL voice = _track.kind == EXTERIA_PREVIEW_VOICE;
    if (_index + 1 < _queue.count && !(voice && ExteriaChatFlagGet(ExteriaChatFlagNoAutoNextVoice))) [self next];
    else [self stop];
}

- (void)startCurrent {
    ++_token;
    [self releasePlayer];
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    ExteriaMedia *track = [_queue objectAtIndex:_index];
    [_track release];
    _track = [track retain];
    _loadProgress = 0;
    [_cover release];
    _cover = nil;
    ExteriaRemoteFile *file = track.file;
    if (!file) {
        [self fail:@"nothing to fetch"];
        return;
    }
    [self setState:ExteriaMusicStateLoading];
    NSUInteger token = _token;
    [_media loadCoverForTrack:track maxSide:COVER_SIDE completion:^(UIImage *image) {
        if (token != _token || !image) return;
        _cover = [image retain];
        [self changed];
    }];
    _pathRequest = [_media loadPathForFile:file size:track.size progress:^(float fraction) {
        if (token != _token) return;
        _loadProgress = fraction;
        /* download progress does not change the lock screen's playback data */
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaMusicPlayerDidChangeNotification object:self];
    } completion:^(NSString *path) {
        if (token != _token) return;
        _pathRequest = 0;
        if (!path) {
            [self fail:@"the file did not arrive"];
            return;
        }
        [self beginPlaybackAtPath:path];
    }];
}

#pragma mark control

- (void)playQueueTrackAtIndex:(NSUInteger)index {
    if (index >= _queue.count) return;
    if (index == _index && _state != ExteriaMusicStateFailed) { [self togglePause]; return; }
    _index = index;
    [self startCurrent];
}

- (void)playTrack:(ExteriaMedia *)track queue:(NSArray *)queue media:(ExteriaMediaCache *)media {
    if (!track || !media) return;
    ExteriaMediaCache *nextMedia = [media retain];
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    [_media release];
    _media = nextMedia;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < queue.count; ++i) {
        if ([(ExteriaMedia *)[queue objectAtIndex:i] file] && [[[queue objectAtIndex:i] file].key isEqualToString:track.file.key]) { index = i; break; }
    }
    [_queue release];
    if (index == NSNotFound) {
        _queue = [[NSArray arrayWithObject:track] retain];
        _index = 0;
    } else {
        _queue = [queue copy];
        _index = index;
    }
    [self startCurrent];
}

- (void)pause {
    if (_state != ExteriaMusicStatePlaying) return;
    [_player pause];
    [self stopTimer];
    [self setState:ExteriaMusicStatePaused];
}

- (void)pauseForMedia {
    if (ExteriaChatPauseMusicOnMedia()) [self pause];
}

- (void)pauseForRecording {
    if (!ExteriaChatPauseMusicOnRecord() || _state != ExteriaMusicStatePlaying) return;
    [self pause];
    _pausedForRecording = YES;
}

- (void)resumeAfterRecording {
    if (!_pausedForRecording) return;
    _pausedForRecording = NO;
    if (_state == ExteriaMusicStatePaused) [self togglePause];
}

- (void)togglePause {
    switch (_state) {
    case ExteriaMusicStatePlaying:
        [self pause];
        break;
    case ExteriaMusicStatePaused:
        if (![self takeAudioSession]) {
            [self fail:@"the audio session was refused"];
            return;
        }
        _state = ExteriaMusicStatePlaying;
        [self startPlayer];
        [self changed];
        break;
    case ExteriaMusicStateFailed:
        if (_queue.count) [self startCurrent];
        break;
    case ExteriaMusicStateLoading:
    case ExteriaMusicStateIdle:
        break;
    }
}

- (void)next {
    if (_index + 1 >= _queue.count) return;
    ++_index;
    [self startCurrent];
}

- (void)previous {
    if (!_queue.count) return;
    if (self.position > RESTART_AFTER || _index == 0) {
        [self seekToFraction:0];
        return;
    }
    --_index;
    [self startCurrent];
}

- (void)seekToFraction:(float)fraction {
    NSTimeInterval length = self.duration;
    if (!_player || length <= 0) return;
    fraction = fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction);
    NSUInteger generation = ++_seekGeneration;
    _seeking = YES;
    _seekTarget = length * fraction;
    [_player seekToTime:CMTimeMakeWithSeconds(_seekTarget, 600) completionHandler:^(BOOL finished) {
        (void)finished;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != _seekGeneration) return;
            _seeking = NO;
            [self refreshNowPlaying];
            [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaMusicPlayerDidTickNotification object:self];
        });
    }];
    [self refreshNowPlaying];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaMusicPlayerDidTickNotification object:self];
}

- (void)stop {
    ++_token;
    [self releasePlayer];
    [_media cancelPathRequest:_pathRequest];
    _pathRequest = 0;
    [_track release];
    _track = nil;
    [_queue release];
    _queue = nil;
    _index = 0;
    _loadProgress = 0;
    [_cover release];
    _cover = nil;
    ExteriaRemoteControlsStop(self);
    [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"exteria-music"] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"exteria-voice"] error:NULL];
    [ExteriaAudioSession() setActive:NO error:NULL];
    [self setState:ExteriaMusicStateIdle];
}

@end
