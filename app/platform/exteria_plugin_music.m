#import "exteria_plugin_music.h"

#import "exteria_music_player.h"
#import "exteria_plugins.h"

/* a plugin that never gives a taken player back must not leave sounds playing: the oldest one is finished when there are this many */
#define GHOSTS_MAX 4

static NSMutableDictionary *g_ghosts;

static exteria_status refuse(NSString **failure, NSString *text, exteria_status status) {
    if (failure) *failure = text;
    return status;
}

void ExteriaPluginMusicReset(void) {
    for (ExteriaMusicGhost *ghost in g_ghosts.allValues) [ghost finish];
    [g_ghosts removeAllObjects];
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    if (player.volume != 1.0f) player.volume = 1.0f;
}

void ExteriaPluginMusicInstall(void) {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    player.startRoute = ^BOOL(NSUInteger index) {
        if (!ExteriaPluginsAreRunning()) return NO;
        id handled = ExteriaPluginsCallHost(@"music_play", [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:index]]);
        return [handled isKindOfClass:[NSNumber class]] && [handled boolValue];
    };
    player.pauseRoute = ^BOOL(void) {
        if (!ExteriaPluginsAreRunning()) return NO;
        id handled = ExteriaPluginsCallHost(@"music_pause", [NSArray array]);
        return [handled isKindOfClass:[NSNumber class]] && [handled boolValue];
    };
}

static NSDictionary *entry_of(ExteriaMusicPlayer *player, ExteriaMedia *track, NSUInteger queueIndex) {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    ExteriaRemoteFile *file = track.file;
    [entry setObject:file.key ? file.key : @"" forKey:@"key"];
    [entry setObject:track.kind == EXTERIA_PREVIEW_VOICE ? @"voice" : @"music" forKey:@"kind"];
    [entry setObject:track.title ? track.title : @"" forKey:@"title"];
    [entry setObject:track.performer ? track.performer : @"" forKey:@"performer"];
    [entry setObject:track.name ? track.name : @"" forKey:@"name"];
    [entry setObject:[NSNumber numberWithInt:track.duration] forKey:@"duration"];
    [entry setObject:[NSNumber numberWithLongLong:track.size] forKey:@"size"];
    if (queueIndex != NSNotFound) [entry setObject:[NSNumber numberWithUnsignedInteger:queueIndex] forKey:@"index"];
    /* only a file that has arrived whole has a place a plugin may name; a song that is not there yet is fetched when it starts */
    NSString *path = file && player.media ? [player.media cachedPathForFile:file size:track.size] : nil;
    if (path) [entry setObject:path forKey:@"path"];
    return entry;
}

static NSString *state_name(ExteriaMusicState state) {
    switch (state) {
    case ExteriaMusicStateIdle: return @"idle";
    case ExteriaMusicStateLoading: return @"loading";
    case ExteriaMusicStatePlaying: return @"playing";
    case ExteriaMusicStatePaused: return @"paused";
    case ExteriaMusicStateFailed: return @"failed";
    }
    return @"idle";
}

static NSNumber *milliseconds(NSTimeInterval seconds) {
    return [NSNumber numberWithLongLong:(long long)(seconds * 1000.0)];
}

static exteria_status player_service(NSDictionary *request, NSDictionary **reply, NSString **failure) {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    NSNumber *idValue = [request objectForKey:@"id"];
    NSString *op = [request objectForKey:@"op"];
    if (![idValue isKindOfClass:[NSNumber class]] || ![op isKindOfClass:[NSString class]]) return refuse(failure, @"a player and an operation are needed", EXTERIA_E_ARG);
    NSUInteger playback = [idValue unsignedIntegerValue];
    BOOL current = playback && playback == player.playbackId;
    ExteriaMusicGhost *ghost = current ? nil : [g_ghosts objectForKey:idValue];
    if (!current && !ghost) return refuse(failure, @"PLAYER_GONE", EXTERIA_E_NOTFOUND);
    if ([op isEqualToString:@"state"]) {
        BOOL playing = current ? player.state == ExteriaMusicStatePlaying && player.position >= 0 && player.playbackId == playback : ghost.playing;
        *reply = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:playing], @"playing",
                  milliseconds(current ? player.position : ghost.position), @"position_ms", milliseconds(current ? player.duration : ghost.duration), @"duration_ms",
                  [NSNumber numberWithFloat:player.speed], @"speed", nil];
        return EXTERIA_OK;
    }
    if ([op isEqualToString:@"volume"]) {
        NSNumber *value = [request objectForKey:@"value"];
        if (![value isKindOfClass:[NSNumber class]]) return refuse(failure, @"a volume is a number", EXTERIA_E_ARG);
        float volume = [value floatValue];
        if (current) player.volume = volume;
        else [ghost setVolume:volume];
        *reply = [NSDictionary dictionary];
        return EXTERIA_OK;
    }
    if ([op isEqualToString:@"release"]) {
        if (current) return refuse(failure, @"the song that plays is let go through cleanupPlayer", EXTERIA_E_STATE);
        [ghost finish];
        [g_ghosts removeObjectForKey:idValue];
        *reply = [NSDictionary dictionary];
        return EXTERIA_OK;
    }
    return refuse(failure, [NSString stringWithFormat:@"%@ is not an operation of a player", op], EXTERIA_E_UNSUPPORTED);
}

exteria_status ExteriaPluginMusicService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure) {
    ExteriaMusicPlayer *player = [ExteriaMusicPlayer sharedPlayer];
    NSUInteger count = player.queue.count;
    if ([name isEqualToString:@"music.state"]) {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        [state setObject:[NSNumber numberWithUnsignedInteger:player.playbackId] forKey:@"id"];
        [state setObject:state_name(player.state) forKey:@"state"];
        [state setObject:milliseconds(player.position) forKey:@"position_ms"];
        [state setObject:milliseconds(player.duration) forKey:@"duration_ms"];
        [state setObject:[NSNumber numberWithFloat:player.speed] forKey:@"speed"];
        [state setObject:[NSNumber numberWithBool:player.shuffle] forKey:@"shuffle"];
        [state setObject:[NSNumber numberWithInt:(int)player.repeatMode] forKey:@"repeat"];
        [state setObject:[NSNumber numberWithUnsignedInteger:count] forKey:@"count"];
        NSUInteger at = [player playPositionOfCurrent];
        if (at != NSNotFound) [state setObject:[NSNumber numberWithUnsignedInteger:at] forKey:@"position"];
        if (player.track) {
            NSUInteger index = [player.queue indexOfObjectIdenticalTo:player.track];
            [state setObject:entry_of(player, player.track, index) forKey:@"track"];
        }
        *reply = state;
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.entry"]) {
        NSNumber *index = [request objectForKey:@"index"];
        NSNumber *position = [request objectForKey:@"position"];
        NSUInteger at = NSNotFound;
        if ([index isKindOfClass:[NSNumber class]]) at = [index unsignedIntegerValue];
        else if ([position isKindOfClass:[NSNumber class]]) at = [player queueIndexAtPlayPosition:[position unsignedIntegerValue]];
        if (at == NSNotFound || at >= count) return refuse(failure, @"the queue has no such song", EXTERIA_E_NOTFOUND);
        *reply = entry_of(player, [player.queue objectAtIndex:at], at);
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.peek"]) {
        NSUInteger at = [player nextQueueIndex];
        *reply = at == NSNotFound || at >= count ? [NSDictionary dictionary] : [NSDictionary dictionaryWithObject:entry_of(player, [player.queue objectAtIndex:at], at) forKey:@"entry"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.start"]) {
        NSNumber *index = [request objectForKey:@"index"];
        if (![index isKindOfClass:[NSNumber class]] || [index unsignedIntegerValue] >= count) return refuse(failure, @"the queue has no such song", EXTERIA_E_NOTFOUND);
        [player startQueueIndex:[index unsignedIntegerValue]];
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:player.playbackId] forKey:@"id"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.pause"]) {
        BOOL was = player.state == ExteriaMusicStatePlaying;
        [player pauseWithoutRoute];
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:was] forKey:@"paused"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.cleanup"]) {
        [player releaseCurrentPlayer];
        *reply = [NSDictionary dictionary];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.detach"]) {
        ExteriaMusicGhost *ghost = [player detachPlayback];
        if (ghost) {
            if (!g_ghosts) g_ghosts = [[NSMutableDictionary alloc] init];
            while (g_ghosts.count >= GHOSTS_MAX) {
                NSNumber *oldest = [[[g_ghosts allKeys] sortedArrayUsingSelector:@selector(compare:)] objectAtIndex:0];
                [[g_ghosts objectForKey:oldest] finish];
                [g_ghosts removeObjectForKey:oldest];
            }
            [g_ghosts setObject:ghost forKey:[NSNumber numberWithUnsignedInteger:ghost.playbackId]];
        }
        *reply = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:ghost != nil] forKey:@"detached"];
        return EXTERIA_OK;
    }
    if ([name isEqualToString:@"music.player"]) return player_service(request, reply, failure);
    return EXTERIA_E_UNSUPPORTED;
}
