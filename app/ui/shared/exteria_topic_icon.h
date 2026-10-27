#import <UIKit/UIKit.h>

#import "exteria_dialog.h"

/* the side in points of the picture ExteriaTopicIconImage gives */
#define EXTERIA_TOPIC_ICON_SIDE 34.0

/* the icon of a forum topic: its custom emoji once the picture is in memory, otherwise a hash in the topic's color */
UIImage *ExteriaTopicIconImage(ExteriaDialog *topic);
