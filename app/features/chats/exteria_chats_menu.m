#import "exteria_chats_menu.h"

#import "exteria_alert.h"
#import "exteria_alert_view.h"
#import "exteria_bookmarks_controller.h"
#import "exteria_chat_controller.h"
#import "exteria_dialog.h"
#import "exteria_more_settings_controller.h"
#import "exteria_person.h"
#import "exteria_popup_menu.h"
#import "exteria_proxy_settings.h"
#import "exteria_session_channels.h"
#import "exteria_symbol.h"
#import "exteria_theme.h"
#include "exteria_proxy.h"

@interface ExteriaChatsMenu () {
    ExteriaSession *_session;
    UIViewController *_host;
    ExteriaAvatarCache *_avatars;
    ExteriaMediaCache *_media;
    ExteriaStickerLibrary *_stickers;
    void (^_refresh)(void);
}
@end

@implementation ExteriaChatsMenu

- (id)initWithSession:(ExteriaSession *)session host:(UIViewController *)host avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers refresh:(void (^)(void))refresh {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _host = host;
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _refresh = [refresh copy];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_refresh release];
    [super dealloc];
}

- (void)showFailureText:(NSString *)text {
    ExteriaShowNotice(nil, text);
}

- (void)showInView:(UIView *)view anchor:(CGPoint)anchor {
    BOOL dark = ExteriaThemeIsDark();
    /* the list of proxies is one tap away only while one is on, which is when the connection may need it changed */
    exteria_proxy proxy;
    BOOL proxyEnabled = NO;
    exteria_status proxyStatus = ExteriaProxyRead(&proxy, &proxyEnabled);
    exteria_wipe(&proxy, sizeof(proxy));
    if (proxyStatus != EXTERIA_OK) NSLog(@"exteria: proxy settings unavailable: %s", exteria_status_name(proxyStatus));
    NSMutableArray *titles = [NSMutableArray arrayWithObjects:NSLocalizedString(dark ? @"menu.day" : @"menu.night", nil), NSLocalizedString(@"menu.group", nil),
                              NSLocalizedString(@"menu.channel", nil), NSLocalizedString(@"menu.saved", nil), NSLocalizedString(@"bookmarks.title", nil), nil];
    ExteriaSymbol symbols[] = {dark ? ExteriaSymbolSun : ExteriaSymbolMoon, ExteriaSymbolPerson, ExteriaSymbolMegaphone, ExteriaSymbolBookmark, ExteriaSymbolStar, ExteriaSymbolLock};
    NSUInteger proxyIndex = NSNotFound;
    if (proxyEnabled) {
        proxyIndex = titles.count;
        [titles addObject:NSLocalizedString(@"proxy.title", nil)];
    }
    /* the card's handler holds this object, which the screen that made it does not keep */
    [self retain];
    ExteriaPopupMenu *menu = [[[ExteriaPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        if (index == proxyIndex) [self openProxyList];
        else switch (index) {
        case 0: [self toggleDayNight]; break;
        case 1: [self askNameForMegagroup:YES]; break;
        case 2: [self askNameForMegagroup:NO]; break;
        case 3: [self openSavedMessages]; break;
        default: [self openBookmarks]; break;
        }
        [self autorelease];
    }] autorelease];
    [menu showInView:view anchor:anchor];
}

/* the proxies are kept on the More page of the settings, with the switch and the link prompt */
- (void)openProxyList {
    [_host.navigationController pushViewController:[[[ExteriaMoreSettingsController alloc] initWithSession:_session] autorelease] animated:YES];
}

- (void)openBookmarks {
    [_host.navigationController pushViewController:[[[ExteriaBookmarksController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease] animated:YES];
}

- (void)toggleDayNight {
    ExteriaThemeStoreDark(!ExteriaThemeIsDark());
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaThemeDidChangeNotification object:nil];
}

- (void)askNameForMegagroup:(BOOL)megagroup {
    Class alertClass = ExteriaAlertClass();
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(megagroup ? @"create.group.title" : @"create.channel.title", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"create.action", nil), nil];
    /* the plain text input style came with ios 5 */
    [alert setValue:[NSNumber numberWithInt:2] forKey:@"alertViewStyle"];
    [[alert textFieldAtIndex:0] setPlaceholder:NSLocalizedString(@"create.name", nil)];
    [alert setTag:megagroup ? 1 : 2];
    /* the alert keeps no reference to its delegate, so this object stays until its answer */
    [self retain];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self autorelease];
        return;
    }
    NSString *name = [[[alertView textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) {
        [self autorelease];
        return;
    }
    [_session createChannelTitled:name megagroup:alertView.tag == 1 completion:^(NSString *errorName) {
        if (errorName) [self showFailureText:[NSString stringWithFormat:NSLocalizedString(@"create.failed", nil), errorName]];
        else if (_refresh) _refresh();
        [self autorelease];
    }];
}

- (void)openSavedMessages {
    [self retain];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        ExteriaPerson *person = [items count] ? [items objectAtIndex:0] : nil;
        ExteriaDialog *saved = person ? [ExteriaDialog savedMessagesWithPerson:person] : nil;
        if (!saved) {
            [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"]];
            [self autorelease];
            return;
        }
        ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:saved avatars:_avatars media:_media stickers:_stickers] autorelease];
        chat.hidesBottomBarWhenPushed = YES;
        chat.closeHandler = ^{ if (_refresh) _refresh(); };
        [_host.navigationController pushViewController:chat animated:YES];
        [self autorelease];
    }];
}

@end
