#import "exteria_community_screen.h"

#import "exteria_classic_community_controller.h"
#import "exteria_community_controller.h"
#import "exteria_theme.h"

UIViewController *ExteriaCommunityScreen(ExteriaSession *session, ExteriaDialog *community, NSArray *known, ExteriaAvatarCache *avatars,
                                         ExteriaMediaCache *media, ExteriaStickerLibrary *stickers, void (^closeHandler)(void)) {
    if (ExteriaThemeIsClassic()) {
        ExteriaClassicCommunityController *screen = [[[ExteriaClassicCommunityController alloc] initWithSession:session community:community known:known
                                                                                                         avatars:avatars media:media stickers:stickers] autorelease];
        screen.hidesBottomBarWhenPushed = YES;
        screen.closeHandler = closeHandler;
        return screen;
    }
    ExteriaCommunityController *screen = [[[ExteriaCommunityController alloc] initWithSession:session community:community known:known
                                                                                      avatars:avatars media:media stickers:stickers] autorelease];
    screen.closeHandler = closeHandler;
    return screen;
}
