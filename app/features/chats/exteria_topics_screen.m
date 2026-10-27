#import "exteria_topics_screen.h"

#import "exteria_classic_topics_controller.h"
#import "exteria_theme.h"
#import "exteria_topics_controller.h"

UIViewController *ExteriaTopicsScreen(ExteriaSession *session, ExteriaDialog *forum, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                      ExteriaStickerLibrary *stickers, void (^closeHandler)(void)) {
    if (ExteriaThemeIsClassic()) {
        ExteriaClassicTopicsController *topics = [[[ExteriaClassicTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                                   media:media stickers:stickers] autorelease];
        topics.hidesBottomBarWhenPushed = YES;
        topics.closeHandler = closeHandler;
        return topics;
    }
    ExteriaTopicsController *topics = [[[ExteriaTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                   media:media stickers:stickers] autorelease];
    topics.closeHandler = closeHandler;
    return topics;
}
