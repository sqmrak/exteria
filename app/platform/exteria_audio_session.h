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
