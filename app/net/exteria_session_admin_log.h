#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_session.h"

#include "exteria_admin_log.h"

/* one action of the recent actions of a group or channel; built off the main thread */
@interface ExteriaAdminEvent : NSObject {
    long long _eventId;
    int32_t _date;
    exteria_admin_event_kind _kind;
    BOOL _flag;
    BOOL _hasMedia;
    BOOL _hasTarget;
    int32_t _messageId;
    int32_t _number;
    NSString *_actorName;
    NSString *_actorUsername;
    NSString *_targetName;
    NSString *_beforeText;
    NSString *_afterText;
}
@property (nonatomic, readonly) long long eventId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) exteria_admin_event_kind kind;
/* the new value of a switch */
@property (nonatomic, readonly) BOOL flag;
@property (nonatomic, readonly) BOOL hasMedia;
@property (nonatomic, readonly) BOOL hasTarget;
@property (nonatomic, readonly) int32_t messageId;
/* seconds of a slow mode or of an auto-delete period, zero for off */
@property (nonatomic, readonly) int32_t number;
@property (nonatomic, readonly, copy) NSString *actorName;
@property (nonatomic, readonly, copy) NSString *actorUsername;
@property (nonatomic, readonly, copy) NSString *targetName;
@property (nonatomic, readonly, copy) NSString *beforeText;
@property (nonatomic, readonly, copy) NSString *afterText;
@end

/* channels.getAdminLog; implemented in exteria_session_admin_log.m */
@interface ExteriaSession (AdminLog)

/* one page of the events of a channel or supergroup, newest first, below the id of the last event already shown (zero for the first page), filtered by the
   text of the query when it has any. the completion runs on the main thread; events is nil with an error name when the page did not load, and a page shorter
   than EXTERIA_ADMIN_LOG_PAGE is the last one */
- (void)loadAdminLogOfDialog:(ExteriaDialog *)dialog query:(NSString *)query beforeId:(long long)maxId
                  completion:(void (^)(NSArray *events, NSString *errorName))completion;

@end
