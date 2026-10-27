#import <Foundation/Foundation.h>

#include "exteria_poll.h"  /* the core struct */

/* one answer of a poll */
@interface ExteriaPollAnswer : NSObject {
    NSString *_text;
    NSData *_option;
    int32_t _voters;
    BOOL _chosen;
    BOOL _correct;
}
@property (nonatomic, readonly, copy) NSString *text;
/* the token the server names the answer by, which a vote sends back */
@property (nonatomic, readonly, retain) NSData *option;
@property (nonatomic, readonly) int32_t voters;
@property (nonatomic, readonly) BOOL chosen;
@property (nonatomic, readonly) BOOL correct;
@end

/* the poll of a message: what the server said and, for a poll with several answers, the ones picked here and not sent yet */
@interface ExteriaPoll : NSObject {
    NSString *_question;
    NSArray *_answers;
    long long _pollId;
    BOOL _closed;
    BOOL _publicVoters;
    BOOL _multiple;
    BOOL _quiz;
    BOOL _revotingDisabled;
    BOOL _hideResults;
    BOOL _hasCounts;
    int32_t _totalVoters;
    NSArray *_recentVoters;
    NSMutableIndexSet *_picked;
}
+ (ExteriaPoll *)pollWithRow:(const exteria_poll *)row;
@property (nonatomic, readonly, copy) NSString *question;
@property (nonatomic, readonly, retain) NSArray *answers;
@property (nonatomic, readonly) long long pollId;
@property (nonatomic, readonly) BOOL closed;
@property (nonatomic, readonly) BOOL publicVoters;
@property (nonatomic, readonly) BOOL multiple;
@property (nonatomic, readonly) BOOL quiz;
@property (nonatomic, readonly) BOOL revotingDisabled;
@property (nonatomic, readonly) BOOL hideResults;
@property (nonatomic, readonly) int32_t totalVoters;
/* the user ids (NSNumber) of the last few who voted in a public poll, the newest first */
@property (nonatomic, readonly, retain) NSArray *recentVoters;
/* this account has voted */
@property (nonatomic, readonly) BOOL voted;
/* the counts are known, so bars can be drawn */
@property (nonatomic, readonly) BOOL hasCounts;
/* the answers picked on this phone and not sent: only a poll with several answers keeps any */
@property (nonatomic, readonly, retain) NSIndexSet *picked;
- (void)togglePicked:(NSUInteger)index;
- (void)clearPicked;
/* the picks of the older copy of this poll carry over to the newer, when it is the same poll that has not been voted in meanwhile */
- (void)inheritPickedFrom:(ExteriaPoll *)older;
/* a string that differs when what the poll shows differs */
- (NSString *)stateKey;
/* whether the bars and percentages show: after a vote, after the poll closed */
- (BOOL)showsResultsEarly:(BOOL)early;
@end
