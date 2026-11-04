#import "exteria_quick_actions.h"
#import <objc/message.h>
#import "exteria_session.h"

#define QUICK_ACTION_COUNT 4
/* UIApplicationShortcutIconTypeMessage, a constant that the sdk of the armv7 slice does not name */
#define QUICK_ACTION_ICON_MESSAGE 17

static NSString *const ExteriaQuickActionChatType = @"com.sqmrak.exteria.chat";

void ExteriaQuickActionsUpdate(NSArray *dialogs) {
    UIApplication *application = [UIApplication sharedApplication];
    Class itemClass = NSClassFromString(@"UIApplicationShortcutItem");
    Class iconClass = NSClassFromString(@"UIApplicationShortcutIcon");
    if (!itemClass || !iconClass || ![application respondsToSelector:NSSelectorFromString(@"setShortcutItems:")]) return;
    NSMutableArray *items = [NSMutableArray array];
    id icon = ((id (*)(id, SEL, NSInteger))objc_msgSend)(iconClass, NSSelectorFromString(@"iconWithType:"), QUICK_ACTION_ICON_MESSAGE);
    for (ExteriaDialog *dialog in dialogs) {
        if (items.count >= QUICK_ACTION_COUNT) break;
        if (dialog.folder || dialog.community || dialog.topicId > 0 || dialog.title.length == 0) continue;
        if (dialog.peerKind == 3 && dialog.left) continue;
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:dialog.peerKind], @"kind",
                                                                         [NSNumber numberWithLongLong:dialog.peerId], @"peer", nil];
        id item = ((id (*)(id, SEL, NSString *, NSString *, NSString *, id, NSDictionary *))objc_msgSend)([itemClass alloc],
            NSSelectorFromString(@"initWithType:localizedTitle:localizedSubtitle:icon:userInfo:"), ExteriaQuickActionChatType, dialog.title, nil, icon, info);
        if (!item) continue;
        [items addObject:item];
        [item release];
    }
    ((void (*)(id, SEL, NSArray *))objc_msgSend)(application, NSSelectorFromString(@"setShortcutItems:"), items);
}

NSDictionary *ExteriaQuickActionChatInfo(id item) {
    if (!item || ![item respondsToSelector:NSSelectorFromString(@"type")]) return nil;
    if (![[item valueForKey:@"type"] isEqual:ExteriaQuickActionChatType]) return nil;
    NSDictionary *info = [item valueForKey:@"userInfo"];
    return [info isKindOfClass:[NSDictionary class]] ? info : nil;
}
