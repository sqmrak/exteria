#import <Foundation/Foundation.h>

/* the words of a voice note written by the AI provider of the translator, for an account that Telegram will not transcribe: the note is decoded to a WAV and sent to the
   chat completions API of the provider as an audio part, with the key, the model and the address that are set for the translator */
@interface ExteriaVoiceTranscriber : NSObject

/* a provider that takes audio is chosen and has a key and a model; the Vertex one speaks another protocol and is not served */
+ (BOOL)isConfigured;
/* oggPath is the voice note as Telegram sent it. completion gets the text, or nil and the reason; it runs on the main thread and not after cancel */
+ (ExteriaVoiceTranscriber *)transcribeVoiceAtPath:(NSString *)oggPath completion:(void (^)(NSString *text, NSString *failure))completion;
- (void)cancel;

@end
