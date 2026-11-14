#import "exteria_profile_chat.h"

#import "exteria_chat_controller.h"
#import "exteria_classic_topics_controller.h"
#import "exteria_forum_controller.h"
#import "exteria_topics_controller.h"
#import "exteria_topics_screen.h"

void ExteriaProfileShowChat(UIViewController *profile, ExteriaSession *session, ExteriaDialog *dialog, ExteriaAvatarCache *avatars,
                            ExteriaMediaCache *media, ExteriaStickerLibrary *stickers) {
    UINavigationController *navigation = profile.navigationController;
    NSArray *stack = navigation.viewControllers;
    NSUInteger at = [stack indexOfObject:profile];
    /* a forum is not one chat but its topics: the way into it is the list of topics, the one the profile was opened from when it is still below, or else a new one */
    BOOL forum = dialog.forum && !dialog.topicId;
    if (at != NSNotFound && at > 0) {
        UIViewController *below = [stack objectAtIndex:at - 1];
        if (forum && ([below isKindOfClass:[ExteriaForumController class]] || [below isKindOfClass:[ExteriaTopicsController class]] ||
                      [below isKindOfClass:[ExteriaClassicTopicsController class]]) && [(id)below showsForum:dialog]) {
            [navigation popViewControllerAnimated:YES];
            return;
        }
        if (!forum && [below isKindOfClass:[ExteriaChatController class]] && [(ExteriaChatController *)below showsDialog:dialog]) {
            [navigation popViewControllerAnimated:YES];
            return;
        }
    }
    if (forum) {
        [navigation pushViewController:ExteriaTopicsScreen(session, dialog, avatars, media, stickers, nil) animated:YES];
        return;
    }
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:session dialog:dialog avatars:avatars media:media stickers:stickers] autorelease];
    [navigation pushViewController:chat animated:YES];
}
