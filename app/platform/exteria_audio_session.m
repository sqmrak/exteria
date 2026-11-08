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

/* the record category of a call, with the Bluetooth option where the system has it: without it a headset never carries the microphone of a call (ios 6 and later) */
static BOOL ExteriaAudioSetCallCategory(AVAudioSession *audio, BOOL bluetooth, NSError **error) {
    NSString *category = ExteriaAudioCategoryPlayAndRecord();
    SEL withOptions = NSSelectorFromString(@"setCategory:withOptions:error:");
    if (!category) return NO;
    if ([audio respondsToSelector:withOptions]) {
        /* AVAudioSessionCategoryOptionAllowBluetooth is 4 */
        return ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))objc_msgSend)(audio, withOptions, category, bluetooth ? 4 : 0, error);
    }
    return [audio setCategory:category error:error];
}

static void ExteriaAudioSetVoiceChatMode(AVAudioSession *audio) {
    NSError *error = nil;
    /* the mode came with ios 5 and only tunes the microphone for speech; a call runs without it */
    NSString *mode = ExteriaAudioConstant("AVAudioSessionModeVoiceChat");
    if (mode && [audio respondsToSelector:@selector(setMode:error:)] && ![audio setMode:mode error:&error]) NSLog(@"exteria: voice chat mode refused: %@", error);
}

BOOL ExteriaAudioSessionBeginCall(void) {
    NSError *error = nil;
    AVAudioSession *audio = ExteriaAudioSession();
    if (!audio || !ExteriaAudioSetCallCategory(audio, YES, &error)) {
        NSLog(@"exteria: audio session refused the call: %@", error);
        return NO;
    }
    ExteriaAudioSetVoiceChatMode(audio);
    if (![audio setActive:YES error:&error]) {
        NSLog(@"exteria: audio session refused the call: %@", error);
        return NO;
    }
    return YES;
}

static BOOL ExteriaAudioPortIsBluetooth(NSString *type) {
    return type && ([type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortBluetoothHFP")] || [type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortBluetoothA2DP")] ||
                    [type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortBluetoothLE")]);
}

/* a cable: headphones, a headset with a microphone, or a usb sound card */
static BOOL ExteriaAudioPortIsWired(NSString *type) {
    return type && ([type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortHeadphones")] || [type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortHeadsetMic")] ||
                    [type isEqualToString:ExteriaAudioConstant("AVAudioSessionPortUSBAudio")]);
}

/* the input ports of ios 7 and later: the headset when a type matches, else the built in microphone */
static id ExteriaAudioInputPort(AVAudioSession *audio, BOOL bluetooth) {
    if (![audio respondsToSelector:NSSelectorFromString(@"availableInputs")]) return nil;
    NSString *builtIn = ExteriaAudioConstant("AVAudioSessionPortBuiltInMic");
    for (id port in [audio valueForKey:@"availableInputs"]) {
        NSString *type = [port valueForKey:@"portType"];
        if (bluetooth ? ExteriaAudioPortIsBluetooth(type) : [type isEqualToString:builtIn]) return port;
    }
    return nil;
}

BOOL ExteriaAudioSessionBluetoothInputAvailable(NSString **name) {
    AVAudioSession *audio = ExteriaAudioSession();
    if (name) *name = nil;
    if (!audio) return NO;
    id port = ExteriaAudioInputPort(audio, YES);
    if (port) {
        if (name) *name = [port valueForKey:@"portName"];
        return YES;
    }
    if (![audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) return NO;
    id route = [audio valueForKey:@"currentRoute"];
    for (id output in [route valueForKey:@"outputs"]) {
        if (ExteriaAudioPortIsBluetooth([output valueForKey:@"portType"])) {
            if (name) *name = [output valueForKey:@"portName"];
            return YES;
        }
    }
    return NO;
}

/* ios 5 has no route object: the route is a string such as "Headphone", "HeadsetInOut" or "HeadsetBT" */
static NSString *ExteriaAudioLegacyRouteName(void) {
    CFStringRef route = NULL;
    UInt32 size = sizeof(route);
    if (AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &size, &route) != noErr || !route) return nil;
    return [(NSString *)route autorelease];
}

BOOL ExteriaAudioSessionWiredAvailable(NSString **name) {
    AVAudioSession *audio = ExteriaAudioSession();
    if (name) *name = nil;
    if (!audio) return NO;
    if ([audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) {
        for (id output in [[audio valueForKey:@"currentRoute"] valueForKey:@"outputs"]) {
            if (ExteriaAudioPortIsWired([output valueForKey:@"portType"])) {
                if (name) *name = [output valueForKey:@"portName"];
                return YES;
            }
        }
        /* a headset also lists its microphone among the inputs, which ios 7 shows before it is the route */
        if ([audio respondsToSelector:NSSelectorFromString(@"availableInputs")]) {
            for (id port in [audio valueForKey:@"availableInputs"]) {
                if (ExteriaAudioPortIsWired([port valueForKey:@"portType"])) {
                    if (name) *name = [port valueForKey:@"portName"];
                    return YES;
                }
            }
        }
        return NO;
    }
    NSString *legacy = ExteriaAudioLegacyRouteName();
    return legacy && ([legacy rangeOfString:@"Headphone"].location != NSNotFound || ([legacy rangeOfString:@"Headset"].location != NSNotFound && [legacy rangeOfString:@"BT"].location == NSNotFound));
}

ExteriaAudioRoute ExteriaAudioSessionCurrentRoute(void) {
    AVAudioSession *audio = ExteriaAudioSession();
    if (!audio) return ExteriaAudioRouteEarpiece;
    if (![audio respondsToSelector:NSSelectorFromString(@"currentRoute")]) {
        NSString *legacy = ExteriaAudioLegacyRouteName();
        if (legacy && [legacy rangeOfString:@"BT"].location != NSNotFound) return ExteriaAudioRouteBluetooth;
        if (legacy && [legacy rangeOfString:@"Speaker"].location != NSNotFound) return ExteriaAudioRouteSpeaker;
        if (legacy && ([legacy rangeOfString:@"Headphone"].location != NSNotFound || [legacy rangeOfString:@"Headset"].location != NSNotFound)) return ExteriaAudioRouteWired;
        return ExteriaAudioRouteEarpiece;
    }
    NSString *speaker = ExteriaAudioConstant("AVAudioSessionPortBuiltInSpeaker");
    for (id output in [[audio valueForKey:@"currentRoute"] valueForKey:@"outputs"]) {
        NSString *type = [output valueForKey:@"portType"];
        if (ExteriaAudioPortIsBluetooth(type)) return ExteriaAudioRouteBluetooth;
        if (ExteriaAudioPortIsWired(type)) return ExteriaAudioRouteWired;
        if (speaker && [type isEqualToString:speaker]) return ExteriaAudioRouteSpeaker;
    }
    return ExteriaAudioRouteEarpiece;
}

BOOL ExteriaAudioSessionSelectRoute(ExteriaAudioRoute route) {
    AVAudioSession *audio = ExteriaAudioSession();
    NSError *error = nil;
    if (!audio) return NO;
    if (route == ExteriaAudioRouteSpeaker) {
        ExteriaAudioSessionSetSpeaker(YES);
        return YES;
    }
    BOOL bluetooth = route == ExteriaAudioRouteBluetooth;
    /* ios 6 has no preferred input: the headset is the route while the category allows it, and the earpiece once it does not; a category change drops the mode and the override, so both are set again */
    BOOL preferred = [audio respondsToSelector:NSSelectorFromString(@"setPreferredInput:error:")];
    if (!preferred || bluetooth) {
        if (!ExteriaAudioSetCallCategory(audio, bluetooth, &error)) {
            NSLog(@"exteria: audio session refused the call route: %@", error);
            return NO;
        }
        ExteriaAudioSetVoiceChatMode(audio);
        if (![audio setActive:YES error:&error]) {
            NSLog(@"exteria: audio session refused the call route: %@", error);
            return NO;
        }
    }
    ExteriaAudioSessionSetSpeaker(NO);
    if (preferred && route == ExteriaAudioRouteWired) {
        /* the cable wins over the built in output once nothing overrides it; the microphone of the headset follows when it has one, else the built in one stays */
        id headset = nil;
        for (id port in [audio valueForKey:@"availableInputs"]) {
            if (ExteriaAudioPortIsWired([port valueForKey:@"portType"])) { headset = port; break; }
        }
        if (headset && !((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(audio, NSSelectorFromString(@"setPreferredInput:error:"), headset, &error)) {
            NSLog(@"exteria: the headset input was refused: %@", error);
            return NO;
        }
        return YES;
    }
    if (preferred) {
        id port = ExteriaAudioInputPort(audio, bluetooth);
        if (!port && bluetooth) {
            NSLog(@"exteria: no bluetooth input to prefer");
            return NO;
        }
        if (!((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(audio, NSSelectorFromString(@"setPreferredInput:error:"), port, &error)) {
            NSLog(@"exteria: the preferred input was refused: %@", error);
            return NO;
        }
    }
    return YES;
}

NSString *ExteriaAudioRouteChangeNotificationName(void) {
    return ExteriaAudioConstant("AVAudioSessionRouteChangeNotification");
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
