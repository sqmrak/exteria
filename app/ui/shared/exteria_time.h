#import <Foundation/Foundation.h>

#include "exteria_time_zone.h"

extern NSString *const ExteriaTimeDidChangeNotification;

/* display preferences never change message timestamps or the device clock */
int32_t ExteriaTimeZoneChoice(void);
void ExteriaTimeZoneSetChoice(int32_t minutes);
NSString *ExteriaTimeZoneChoiceText(void);
NSString *ExteriaTimeZoneOffsetText(int32_t minutes);
NSCalendar *ExteriaDisplayCalendar(void);

/* the time of a message the way chat lists show it: the clock today, the weekday within the last week, the short
   date before that */
NSString *ExteriaListTimeText(int32_t unixDate);

/* the date a run of messages is filed under in a chat: Today, Yesterday, the weekday within the week, else the date */
NSString *ExteriaDayText(int32_t unixDate);

/* "last seen" lines for the contact list */
NSString *ExteriaLastSeenText(int presence, int32_t seen);

/* the fullscreen media header includes both its day and local clock */
NSString *ExteriaMediaTimeText(int32_t unixDate);

/* the time of day alone, in the short form of the system's language, such as the clock under a bubble */
NSString *ExteriaClockText(int32_t unixDate);
