#import <UIKit/UIKit.h>
#import "exteria_session.h"
#import "exteria_avatar_cache.h"
#import "exteria_media_cache.h"

typedef enum {
    ExteriaChatPeekOpen,
    ExteriaChatPeekPin,
    ExteriaChatPeekMute,
    ExteriaChatPeekArchive,
    ExteriaChatPeekSelect
} ExteriaChatPeekAction;

void ExteriaShowChatPeek(UIView *host, CGRect source, ExteriaDialog *dialog, ExteriaSession *session,
                         ExteriaAvatarCache *avatars, ExteriaMediaCache *media, BOOL canSelect,
                         void (^handler)(ExteriaChatPeekAction action));
