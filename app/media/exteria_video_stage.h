#import <Foundation/Foundation.h>

/* videos come from Telegram as fragmented mp4, which the player of an old system shows black, without a length, or with a seek that starts over. The plain form of the file,
   made by core/media/exteria_fmp4.c, plays on every system the app runs on, and is what the player, the system library and the share sheet are given */

/* writes the plain form of the file at source to destination and returns YES; NO when the file is not fragmented or the form could not be made (the reason is in the log),
   and then nothing is left at destination */
BOOL ExteriaWritePlainVideo(NSString *source, NSString *destination);

/* the video under a new name: the plain form of a fragmented file, else a hard link to the cached file, which costs no copy */
BOOL ExteriaStageVideo(NSString *source, NSString *destination, NSError **error);

/* the same off the main thread, one run at a time, since the work reads and writes the whole file; completion runs on the main thread */
void ExteriaStageVideoAsync(NSString *source, NSString *destination, void (^completion)(BOOL staged, NSError *error));

/* the queue those runs go through, for work that has to wait its turn behind them */
dispatch_queue_t ExteriaVideoStageQueue(void);
