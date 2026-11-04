#import "exteria_topics_screen.h"

#import "exteria_classic_topics_controller.h"
#import "exteria_forum_controller.h"
#import "exteria_platform.h"
#import "exteria_theme.h"
#import "exteria_topics_controller.h"

UIViewController *ExteriaTopicsScreenWithChats(ExteriaSession *session, ExteriaDialog *forum, NSArray *dialogs, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                               ExteriaStickerLibrary *stickers, void (^archiveHandler)(void), void (^closeHandler)(void)) {
    if (ExteriaThemeIsClassic()) {
        ExteriaClassicTopicsController *topics = [[[ExteriaClassicTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                                   media:media stickers:stickers] autorelease];
        topics.hidesBottomBarWhenPushed = YES;
        topics.closeHandler = closeHandler;
        return topics;
    }
    /* the saved messages list the chats their messages came from, which the plain list of the topics already shows */
    if (!ExteriaIsPad() && !forum.saved) {
        ExteriaForumController *screen = [[[ExteriaForumController alloc] initWithSession:session forum:forum dialogs:dialogs avatars:avatars
                                                                                    media:media stickers:stickers] autorelease];
        screen.archiveHandler = archiveHandler;
        screen.closeHandler = closeHandler;
        return screen;
    }
    ExteriaTopicsController *topics = [[[ExteriaTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                   media:media stickers:stickers] autorelease];
    topics.closeHandler = closeHandler;
    return topics;
}

UIViewController *ExteriaTopicsScreen(ExteriaSession *session, ExteriaDialog *forum, ExteriaAvatarCache *avatars, ExteriaMediaCache *media,
                                      ExteriaStickerLibrary *stickers, void (^closeHandler)(void)) {
    return ExteriaTopicsScreenWithChats(session, forum, nil, avatars, media, stickers, nil, closeHandler);
}
