#import <Foundation/Foundation.h>

#include "exteria_report.h"

#import "exteria_dialog.h"
#import "exteria_session.h"

@interface ExteriaSession (Report)

/* tells Telegram that the user, group or channel breaks its rules. comment may be nil, and the reason other needs
   one; the completion gets nil once the server took the report, and an error name otherwise (NOT_REPORTED when it
   answered false) */
- (void)reportDialog:(ExteriaDialog *)dialog reason:(exteria_report_reason)reason comment:(NSString *)comment completion:(void (^)(NSString *errorName))completion;

@end

/* one step of the dialogue of messages.report: the server either took the report, or lists what to choose from, or wants words */
typedef enum {
    ExteriaMessageReportDone = 1,
    ExteriaMessageReportChoose,
    ExteriaMessageReportComment
} ExteriaMessageReportKind;

@interface ExteriaMessageReportStep : NSObject {
    ExteriaMessageReportKind _kind;
    NSString *_title;
    NSArray *_options;
    NSArray *_tokens;
    NSData *_token;
    BOOL _commentOptional;
}
@property (nonatomic, readonly) ExteriaMessageReportKind kind;
@property (nonatomic, readonly, copy) NSString *title;
/* the words of each choice, and the token each one is sent back with, in the same order */
@property (nonatomic, readonly, retain) NSArray *options;
@property (nonatomic, readonly, retain) NSArray *tokens;
/* for the comment step: the token the words are sent with */
@property (nonatomic, readonly, retain) NSData *token;
@property (nonatomic, readonly) BOOL commentOptional;
+ (ExteriaMessageReportStep *)stepWithAnswer:(const exteria_message_report_answer *)answer;
@end

@interface ExteriaSession (MessageReport)

/* the first call has a nil token; the step comes back on the main thread, or an error name when the request failed
   or the answer was not one the dialogue knows */
- (void)reportMessageIds:(NSArray *)ids ofDialog:(ExteriaDialog *)dialog token:(NSData *)token comment:(NSString *)comment
              completion:(void (^)(ExteriaMessageReportStep *step, NSString *errorName))completion;

@end
