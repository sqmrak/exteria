#import <UIKit/UIKit.h>

#import "exteria_dialog.h"

/* the side in points of the picture ExteriaTopicIconImage gives */
#define EXTERIA_TOPIC_ICON_SIDE 48.0

/* the icon of a forum topic: its custom emoji once the picture is in memory, otherwise a hash in the topic's color */
UIImage *ExteriaTopicIconImage(ExteriaDialog *topic);

/* the same for an icon named by its parts, as the chat list names the topic of the last message of a forum */
UIImage *ExteriaTopicIconImageOf(long long emoji, int32_t rgb);
