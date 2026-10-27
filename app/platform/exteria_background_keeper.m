#import "exteria_background_keeper.h"

#import <objc/message.h>

#import "exteria_audio_session.h"
#import "exteria_voip_socket.h"

#define SAMPLE_RATE 8000
#define LOOP_SECONDS 1

/* the player is an id, so its BOOL returning methods are sent with their types, as the sdks of the two slices are not asked */
static BOOL ExteriaPlayerPlay(id player) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"play"));
}

static BOOL ExteriaPlayerPrepare(id player) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(player, NSSelectorFromString(@"prepareToPlay"));
}

/* a WAV of one second of 8 kHz mono 16 bit silence: the header is 44 bytes and every sample is zero */
static NSData *ExteriaSilence(void) {
    uint32_t bytes = SAMPLE_RATE * LOOP_SECONDS * 2;
    NSMutableData *wav = [NSMutableData dataWithLength:44 + bytes];
    uint8_t *p = wav.mutableBytes;
    uint32_t chunk = 36 + bytes, rate = SAMPLE_RATE, byteRate = SAMPLE_RATE * 2;
    uint16_t format = 1, channels = 1, align = 2, bits = 16;
    uint32_t sixteen = 16;
    memcpy(p, "RIFF", 4);
    memcpy(p + 4, &chunk, 4);
    memcpy(p + 8, "WAVEfmt ", 8);
    memcpy(p + 16, &sixteen, 4);
    memcpy(p + 20, &format, 2);
    memcpy(p + 22, &channels, 2);
    memcpy(p + 24, &rate, 4);
    memcpy(p + 28, &byteRate, 4);
    memcpy(p + 32, &align, 2);
    memcpy(p + 34, &bits, 2);
    memcpy(p + 36, "data", 4);
    memcpy(p + 40, &bytes, 4);
    return wav;
}

@interface ExteriaBackgroundKeeper () {
    /* an AVAudioPlayer; the class is looked up by name, since the arm64 slice's sdk keeps it in a framework ios 10 does not have */
    id _player;
    BOOL _listening;
}
@end

@implementation ExteriaBackgroundKeeper

+ (BOOL)needed {
    return !ExteriaVoipSocketSupported();
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player stop];
    [_player release];
    [super dealloc];
}

- (BOOL)running {
    return _player != nil && [_player isPlaying];
}

- (void)observeInterruptions {
    if (_listening) return;
    NSString *name = ExteriaAudioConstant("AVAudioSessionInterruptionNotification");
    if (!name) return;
    _listening = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interrupted:) name:name object:nil];
}

/* a call or an alarm took the session; when it gives it back the silence goes on, or the app would sleep with nothing to wake it */
- (void)interrupted:(NSNotification *)note {
    NSNumber *type = [note.userInfo objectForKey:@"AVAudioSessionInterruptionTypeKey"];
    if (!_player || type.integerValue != 0) return;
    if (!ExteriaAudioSessionBeginMixedPlayback()) return;
    if (!ExteriaPlayerPlay(_player)) NSLog(@"exteria: the background sound would not resume after an interruption");
}

- (BOOL)start {
    if (self.running) return YES;
    /* a call or a recording owns the session, and changing its category would cut it */
    NSString *category = ExteriaAudioSessionCategory();
    if (category && [category isEqualToString:ExteriaAudioCategoryPlayAndRecord()]) {
        NSLog(@"exteria: the background sound waits, a call or a recording has the audio session");
        return NO;
    }
    Class playerClass = NSClassFromString(@"AVAudioPlayer");
    if (!playerClass) {
        NSLog(@"exteria: this system has no audio player for the background sound");
        return NO;
    }
    if (!ExteriaAudioSessionBeginMixedPlayback()) return NO;
    NSError *error = nil;
    if (!_player) {
        _player = [[playerClass alloc] initWithData:ExteriaSilence() error:&error];
        if (!_player) {
            NSLog(@"exteria: the silence for the background sound did not load: %@", error);
            return NO;
        }
        [_player setNumberOfLoops:-1];
        ExteriaPlayerPrepare(_player);
    }
    [self observeInterruptions];
    if (!ExteriaPlayerPlay(_player)) {
        NSLog(@"exteria: the background sound would not start");
        return NO;
    }
    NSLog(@"exteria: the background sound plays");
    return YES;
}

- (void)stop {
    if (!_player) return;
    [_player stop];
    NSLog(@"exteria: the background sound stopped");
}

@end
