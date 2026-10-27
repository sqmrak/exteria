#import "exteria_profile_chat.h"

#import "exteria_chat_controller.h"

void ExteriaProfileShowChat(UIViewController *profile, ExteriaSession *session, ExteriaDialog *dialog, ExteriaAvatarCache *avatars,
                            ExteriaMediaCache *media, ExteriaStickerLibrary *stickers) {
    UINavigationController *navigation = profile.navigationController;
    NSArray *stack = navigation.viewControllers;
    NSUInteger at = [stack indexOfObject:profile];
    if (at != NSNotFound && at > 0) {
        UIViewController *below = [stack objectAtIndex:at - 1];
        if ([below isKindOfClass:[ExteriaChatController class]] && [(ExteriaChatController *)below showsDialog:dialog]) {
            [navigation popViewControllerAnimated:YES];
            return;
        }
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:session dialog:dialog avatars:avatars media:media stickers:stickers] autorelease];
    [navigation pushViewController:chat animated:YES];
}
