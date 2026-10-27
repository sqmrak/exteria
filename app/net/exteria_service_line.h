#import <Foundation/Foundation.h>

#include "exteria_messages.h"

/* the wording of a service message, for the pill in a chat and the line in the chat list. who acts and whom is
   acted on, either may be nil when the name is not known */
NSString *ExteriaServiceLine(exteria_service_kind kind, NSString *who, NSString *whom, NSString *text, int32_t value, BOOL actorIsTarget);
