#import <Foundation/Foundation.h>

#import "exteria_session.h"
#import "exteria_photo.h"

#include "exteria_call_log.h"

/* one line of the call log: a call with a person, when it was, how long it lasted and how it ended */
@interface ExteriaCallLogEntry : NSObject {
    exteria_call_log_row _row;
    NSString *_name;
    NSString *_initials;
    ExteriaPhoto *_photo;
}
- (id)initWithRow:(const exteria_call_log_row *)row;
@property (nonatomic, readonly) int32_t messageId;
@property (nonatomic, readonly) int32_t date;
/* seconds talked, zero for a call that did not connect */
@property (nonatomic, readonly) int32_t duration;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL video;
/* an incoming call nobody answered, or one the other side did not pick up */
@property (nonatomic, readonly) BOOL missed;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) long long userId;
@property (nonatomic, readonly) BOOL deleted;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *initials;
@property (nonatomic, readonly, retain) ExteriaPhoto *photo;
/* "Исходящий, 1:05", "Пропущенный", and so on: the line under the name */
- (NSString *)summaryText;
/* the chat with the person, for a call back or a message; nil when the server gave no access hash */
- (ExteriaDialog *)dialog;
@end

@interface ExteriaSession (CallLog)
/* ExteriaCallLogEntry items, newest first; the completion runs on the main thread */
- (void)loadCallLog:(ExteriaListCompletion)completion;
@end
