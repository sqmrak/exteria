#import <AVFoundation/AVFoundation.h>

/* AVAudioSession and AVAudioRecorder are looked up at run time */
/* the value of an AVFoundation string constant by its symbol name, for the AVAudioSession categories and the AVAudioRecorder
   setting keys */
NSString *ExteriaAudioConstant(const char *name);
AVAudioSession *ExteriaAudioSession(void);
Class ExteriaAudioRecorderClass(void);
NSString *ExteriaAudioCategoryPlayAndRecord(void);
NSString *ExteriaAudioCategoryPlayback(void);
/* the playback category, so a song or a video is heard with the silent switch on, and the session made active; NO when the system
   refuses, with the reason logged */
BOOL ExteriaAudioSessionBeginPlayback(void);
/* the record and play category with the voice chat mode, and the session made active, for a call; NO when the
   system refuses, with the reason logged */
BOOL ExteriaAudioSessionBeginCall(void);
void ExteriaAudioSessionEndCall(void);
/* sends the call's sound to the loudspeaker instead of the earpiece, or back */
void ExteriaAudioSessionSetSpeaker(BOOL speaker);
/* the playback category that mixes with what else is playing, and the session made active, for a sound nobody is
   meant to hear: it does not take the music of another app away */
BOOL ExteriaAudioSessionBeginMixedPlayback(void);
/* the record and play category with the default route, which is the earpiece of a phone, and the session made
   active: a voice message held to the ear */
BOOL ExteriaAudioSessionBeginEarpiece(void);
/* the record and play category and the session made active, for a voice message */
BOOL ExteriaAudioSessionBeginRecording(BOOL bluetooth);
/* whether this system can allow a Bluetooth microphone (ios 6 and later); the chat settings offer the choice only where it can */
BOOL ExteriaAudioSessionCanUseBluetoothMicrophone(void);
/* the category the session has now, nil without one */
NSString *ExteriaAudioSessionCategory(void);

typedef enum { ExteriaAudioRouteEarpiece, ExteriaAudioRouteSpeaker, ExteriaAudioRouteBluetooth, ExteriaAudioRouteWired } ExteriaAudioRoute;
/* whether a Bluetooth headset can carry the call now, with its name when the system tells it (ios 7 and later list the inputs; ios 6 shows the headset
   only once it is the route; ios 5 never) */
BOOL ExteriaAudioSessionBluetoothInputAvailable(NSString **name);
/* whether headphones or a headset with a cable are plugged in, with their name when the system tells it (ios 6 and later list them on the route, ios 5 only says that one is there) */
BOOL ExteriaAudioSessionWiredAvailable(NSString **name);
/* where the sound goes now; the earpiece when the system cannot say (ios 5) */
ExteriaAudioRoute ExteriaAudioSessionCurrentRoute(void);
/* moves a call to the earpiece, the loudspeaker or the headset: the microphone follows the output. NO when the system refuses, with the reason logged */
BOOL ExteriaAudioSessionSelectRoute(ExteriaAudioRoute route);
/* the name of the notification that says the route changed (ios 6 and later), nil before */
NSString *ExteriaAudioRouteChangeNotificationName(void);
