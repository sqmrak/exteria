#import <Foundation/Foundation.h>

#import "exteria_status.h"

/* audio.open (path) gives {duration_ms} for a file inside the plugin files folder and holds it ready, audio.start plays it from the
   start, audio.stop stops it and audio.release lets it go. one sound at a time: opening another one releases the first. main thread only */
exteria_status ExteriaPluginAudioService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);

/* stops and releases the sound, for when the plugins stop */
void ExteriaPluginAudioReset(void);
