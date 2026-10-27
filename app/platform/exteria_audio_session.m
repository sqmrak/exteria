#import <AudioToolbox/AudioToolbox.h>
#import "exteria_audio_session.h"

#include <dlfcn.h>
#import <objc/message.h>

NSString *ExteriaAudioConstant(const char *name) {
    NSString **value = (NSString **)dlsym(RTLD_DEFAULT, name);
    return value ? *value : nil;
}

AVAudioSession *ExteriaAudioSession(void) {
    return [NSClassFromString(@"AVAudioSession") sharedInstance];
}

Class ExteriaAudioRecorderClass(void) {
    return NSClassFromString(@"AVAudioRecorder");
}

NSString *ExteriaAudioCategoryPlayAndRecord(void) {
    return ExteriaAudioConstant("AVAudioSessionCategoryPlayAndRecord");
}

BOOL ExteriaAudioSessionBeginPlayback(void) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *category = ExteriaAudioCategoryPlayback();
    if (!audio || !category || ![audio setCategory:category error:&error] || ![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused playback: %@", error);
        return NO;
    }
    return YES;
}

BOOL ExteriaAudioSessionBeginEarpiece(void) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *category = ExteriaAudioCategoryPlayAndRecord();
    if (!audio || !category || ![audio setCategory:category error:&error] || ![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused the earpiece route: %@", error);
        return NO;
    }
    /* the record category may keep an earlier override to the loudspeaker */
    ExteriaAudioSessionSetSpeaker(NO);
    return YES;
}

BOOL ExteriaAudioSessionCanUseBluetoothMicrophone(void) {
    return [ExteriaAudioSession() respondsToSelector:NSSelectorFromString(@"setCategory:withOptions:error:")];
}

BOOL ExteriaAudioSessionBeginRecording(BOOL bluetooth) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *category = ExteriaAudioCategoryPlayAndRecord();
    if (!audio || !category) return NO;
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    BOOL set;
    if (bluetooth && [audio respondsToSelector:withOptions]) {
        /* AVAudioSessionCategoryOptionAllowBluetooth is 4 */
        set = ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, 4, &error);
    } else {
        set = [audio setCategory:category error:&error];
    }
    if (!set || ![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused the recording: %@", error);
        return NO;
    }
    return YES;
}

BOOL ExteriaAudioSessionBeginMixedPlayback(void) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *category = ExteriaAudioCategoryPlayback();
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    if (!audio || !category || ![audio respondsToSelector:withOptions]) return NO;
    /* AVAudioSessionCategoryOptionMixWithOthers is 1 */
    BOOL set = ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, 1, &error);
    if (!set || ![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused mixed playback: %@", error);
        return NO;
    }
    return YES;
}

NSString *ExteriaAudioSessionCategory(void) {
    return [ExteriaAudioSession() category];
}

NSString *ExteriaAudioCategoryPlayback(void) {
    return ExteriaAudioConstant("AVAudioSessionCategoryPlayback");
}

BOOL ExteriaAudioSessionBeginCall(void) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    NSString *category = ExteriaAudioCategoryPlayAndRecord();
    if (!audio || !category || ![audio setCategory:category error:&error]) {
        NSLog(@"exteria: audio session refused the call: %@", error);
        return NO;
    }
    /* the mode came with ios 5 and only tunes the microphone for speech; a call runs without it */
    NSString *mode = ExteriaAudioConstant("AVAudioSessionModeVoiceChat");
    if (mode && [audio respondsToSelector:@selector(setMode:error:)] && ![audio setMode:mode error:&error]) NSLog(@"exteria: voice chat mode refused: %@", error);
    if (![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused the call: %@", error);
        return NO;
    }
    return YES;
}

void ExteriaAudioSessionEndCall(void) {
    ExteriaAudioSessionSetSpeaker(NO);
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    if (audio && ![audio setActive:NO error:&error]) NSLog(@"exteria: audio session would not close after the call: %@", error);
}

void ExteriaAudioSessionSetSpeaker(BOOL speaker) {
    AVAudioSession *audio = ExteriaAudioSession();
    NSError *error = nil;
    if (!audio) return;
    /* 'spkr' is AVAudioSessionPortOverrideSpeaker; the method is ios 6, ios 5 has only the c property */
    SEL override = NSSelectorFromString(@"overrideOutputAudioPort:error:");
    if ([audio respondsToSelector:override]) {
        NSMethodSignature *signature = [audio methodSignatureForSelector:override];
        NSInvocation *call = [NSInvocation invocationWithMethodSignature:signature];
        NSUInteger port = speaker ? 'spkr' : 0;
        NSError **errorOut = &error;
        [call setTarget:audio];
        [call setSelector:override];
        [call setArgument:&port atIndex:2];
        [call setArgument:&errorOut atIndex:3];
        [call invoke];
        if (error) NSLog(@"exteria: the loudspeaker route was refused: %@", error);
        return;
    }
    UInt32 route = speaker ? kAudioSessionOverrideAudioRoute_Speaker : kAudioSessionOverrideAudioRoute_None;
    OSStatus status = AudioSessionSetProperty(kAudioSessionProperty_OverrideAudioRoute, sizeof(route), &route);
    if (status != 0) NSLog(@"exteria: the loudspeaker route was refused: %d", (int)status);
}
