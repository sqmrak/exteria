#import <Foundation/Foundation.h>

#import "exteria_status.h"

/* what a plugin that works on the music player asks of the app (python/shim/org/telegram/messenger/music.py stands the android MediaController and the
   players of ExoPlayer over it). the music player stays the owner of the songs: a plugin starts and pauses them, reads where they are, sets the volume of the
   player of a song and takes that player out to fade it while the next song starts. services, main thread only:


   music.state              the playback, the position, the queue, the song that plays
   music.entry (position | index)   one song of the queue, by its place in the order they are played or by queue index
   music.peek               the song a manual next would start
   music.start (index)      starts the song at a queue index, without asking the plugin again
   music.pause              pauses a playing song, without asking the plugin again
   music.cleanup            lets the player of the current song go
   music.detach             takes the player of the current song out to fade it; it keeps its playback number
   music.play_docs (docs, index)   plays songs that python names by their documents (see ExteriaPluginSongOfJSON) as the queue, starting at index
   music.player (id, op)    op volume (value 0 to 1), release or state, for the current playback or a player that was taken out


   a song that starts or a song that is paused asks the plugins first (exteria_host.music_play, music_pause), so a hook on playMessage or pauseMessage runs
   before the music player acts, as the hook runs before the android one does */
exteria_status ExteriaPluginMusicService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);

@class ExteriaMediaCache;
/* the cache the songs of a plugin are fetched with, the one of the main screen */
void ExteriaPluginMusicSetMedia(ExteriaMediaCache *media);
/* the main screen that goes lets its cache go, unless a newer screen has set its own */
void ExteriaPluginMusicForgetMedia(ExteriaMediaCache *media);

/* puts the routes on the music player; they cost nothing while no plugin runs */
void ExteriaPluginMusicInstall(void);

/* finishes the players that were taken out and sets the volume back to full, for when the plugins stop */
void ExteriaPluginMusicReset(void);
