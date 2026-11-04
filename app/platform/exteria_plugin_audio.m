#import "exteria_plugin_audio.h"

#import <objc/message.h>
#import "exteria_audio_session.h"
#import "exteria_plugins.h"

/* AVAudioPlayer is looked up by name: the arm64 slice links an sdk where it lives in AVFAudio, which ios 10 does not have */
static id g_player;

void ExteriaPluginAudioReset(void) {
    if (!g_player) return;
    ((void (*)(id, SEL))objc_msgSend)(g_player, @selector(stop));
    [g_player release];
    g_player = nil;
}

static exteria_status refuse(NSString **failure, NSString *text, exteria_status status) {
    if (failure) *failure = text;
    return status;
}

exteria_status ExteriaPluginAudioService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    if ([name isEqualToString:@"audio.open"]) {
        NSString *path = [request objectForKey:@"path"];
        if (![path isKindOfClass:[NSString class]] || !ExteriaPluginsPathInCache(path)) {
            return refuse(failure, @"a sound can only be played from the plugin files folder", EXTERIA_E_ARG);
        }
        ExteriaPluginAudioReset();
        Class playerClass = NSClassFromString(@"AVAudioPlayer");
        if (!playerClass) return refuse(failure, @"this system has no audio player", EXTERIA_E_UNSUPPORTED);
        NSError *error = nil;
        id player = [[playerClass alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
        if (!player) return refuse(failure, [NSString stringWithFormat:@"the sound would not open: %@", error.localizedDescription], EXTERIA_E_IO);
        if (!((BOOL (*)(id, SEL))objc_msgSend)(player, @selector(prepareToPlay))) {
            [player release];
            return refuse(failure, @"the sound would not prepare", EXTERIA_E_IO);
        }
        g_player = player;
        NSTimeInterval seconds = ((NSTimeInterval (*)(id, SEL))objc_msgSend)(player, @selector(duration));
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:(long long)(seconds * 1000.0)] forKey:@"duration_ms"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"audio.start"]) {
        if (!g_player) return refuse(failure, @"no sound is open", EXTERIA_E_STATE);
        /* the playback category, so the sound is heard with the silent switch on */
        if (!ExteriaAudioSessionBeginPlayback()) return refuse(failure, @"the audio session refused playback", EXTERIA_E_IO);
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(g_player, @selector(setCurrentTime:), 0);
        if (!((BOOL (*)(id, SEL))objc_msgSend)(g_player, @selector(play))) return refuse(failure, @"the sound would not play", EXTERIA_E_IO);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"audio.stop"]) {
        if (g_player) ((void (*)(id, SEL))objc_msgSend)(g_player, @selector(stop));
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"audio.release"]) {
        ExteriaPluginAudioReset();
        return EXTERIA_OK;
    }
    return EXTERIA_E_UNSUPPORTED;
}
