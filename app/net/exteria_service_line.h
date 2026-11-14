#import <Foundation/Foundation.h>

#include "exteria_messages.h"

/* the wording of a service message, for the pill in a chat and the line in the chat list. who acts and whom is
   acted on, either may be nil when the name is not known */
NSString *ExteriaServiceLine(exteria_service_kind kind, NSString *who, NSString *whom, NSString *text, int32_t value, BOOL actorIsTarget);

/* the value of a community line (EXTERIA_SERVICE_COMMUNITY) as the caller completes it: the core gives the first two bits, the caller knows the chat and
   who is reading. the text of the line is the title of the community, nil or empty when it is not known */
enum {
    ExteriaCommunityRemoved = 1,
    ExteriaCommunityUnknownActor = 2,
    ExteriaCommunityChannel = 4,
    ExteriaCommunityBot = 8,
    ExteriaCommunityByMe = 16
};
