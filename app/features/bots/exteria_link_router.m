#import "exteria_platform.h"
#import "exteria_link_router.h"
#import "exteria_group_call_engine.h"

#import <QuartzCore/QuartzCore.h>

#import "exteria_alert.h"
#import "exteria_article_controller.h"
#import "exteria_chat_controller.h"
#import "exteria_session_channels.h"
#import "exteria_dialog_picker_controller.h"
#import "exteria_gift_screen.h"
#import "exteria_theme.h"
#import "exteria_proxy_settings.h"
#import "exteria_user_profile_controller.h"

#include "exteria_links.h"
#include "exteria_bytes.h"

/* the schemes an address in a message or a button may hand to the system; javascript:, file: and the rest are not links to follow */
static BOOL ExteriaSystemSchemeAllowed(NSString *scheme) {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"http"] || [lower isEqualToString:@"https"] || [lower isEqualToString:@"mailto"] || [lower isEqualToString:@"tel"];
}

@interface ExteriaBusyView : UIView {
    UIActivityIndicatorView *_spinner;
}
+ (void)showFor:(NSUInteger)token;
+ (void)hideFor:(NSUInteger)token;
@end

static ExteriaBusyView *sBusy = nil;
static NSUInteger sBusyToken = 0;

@implementation ExteriaBusyView

- (id)init {
    self = [super initWithFrame:CGRectMake(0, 0, 80, 80)];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.layer.cornerRadius = 12;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.center = CGPointMake(40, 40);
    [self addSubview:_spinner];
    [_spinner startAnimating];
    return self;
}

- (void)dealloc {
    [_spinner release];
    [super dealloc];
}

+ (void)showFor:(NSUInteger)token {
    UIView *window = ExteriaOverlayHost();
    if (!window) return;
    sBusyToken = token;
    if (!sBusy) sBusy = [[ExteriaBusyView alloc] init];
    sBusy.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    sBusy.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [window addSubview:sBusy];
}

/* only the call that put the spinner up takes it down, so a late answer of an earlier tap does not hide the spinner of a later one */
+ (void)hideFor:(NSUInteger)token {
    if (token != sBusyToken) return;
    [sBusy removeFromSuperview];
}

@end

@implementation ExteriaLinkRouter

@synthesize anchor = _anchor;
@synthesize session = _session;

- (id)initWithSession:(ExteriaSession *)session avatars:(ExteriaAvatarCache *)avatars media:(ExteriaMediaCache *)media
             stickers:(ExteriaStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [super dealloc];
}

+ (NSString *)textForError:(NSString *)errorName {
    if ([errorName isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([errorName isEqualToString:@"USERNAME_NOT_FOUND"]) return NSLocalizedString(@"bots.error.username", nil);
    if ([errorName isEqualToString:@"BOT_RESPONSE_TIMEOUT"]) return NSLocalizedString(@"bots.error.timeout", nil);
    if ([errorName isEqualToString:@"PASSWORD_HASH_INVALID"]) return NSLocalizedString(@"bots.error.password", nil);
    if ([errorName isEqualToString:@"BOT_APP_INVALID"] || [errorName isEqualToString:@"BOT_INVALID"]) return NSLocalizedString(@"bots.error.app", nil);
    if ([errorName isEqualToString:@"BOT_DOMAIN_INVALID"] || [errorName isEqualToString:@"URL_INVALID"]) return NSLocalizedString(@"bots.error.domain", nil);
    if ([errorName isEqualToString:@"STARS_UNSUPPORTED"] || [errorName isEqualToString:@"BOT_PRECHECKOUT_FAILED"]) return NSLocalizedString(@"gifts.error.unsupported", nil);
    if ([errorName isEqualToString:@"BALANCE_TOO_LOW"] || [errorName isEqualToString:@"BALANCE_LOW"]) return NSLocalizedString(@"gifts.error.balance", nil);
    if ([errorName isEqualToString:@"INVITE_HASH_EXPIRED"] || [errorName isEqualToString:@"INVITE_HASH_INVALID"] || [errorName isEqualToString:@"INVITE_HASH_EMPTY"]) return NSLocalizedString(@"invite.error.expired", nil);
    if ([errorName isEqualToString:@"INVITE_REQUEST_SENT"]) return NSLocalizedString(@"invite.error.sent", nil);
    if ([errorName isEqualToString:@"USER_ALREADY_PARTICIPANT"]) return NSLocalizedString(@"invite.error.member", nil);
    if ([errorName isEqualToString:@"USERS_TOO_MUCH"] || [errorName isEqualToString:@"CHANNELS_TOO_MUCH"]) return NSLocalizedString(@"invite.error.full", nil);
    if ([errorName isEqualToString:@"JOIN_WEBVIEW"]) return NSLocalizedString(@"invite.error.webview", nil);
    if ([errorName isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    if ([errorName isEqualToString:@"CHANNEL_PRIVATE"] || [errorName isEqualToString:@"CHANNEL_INVALID"]) return NSLocalizedString(@"link.error.private", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"bots.error.unknown", nil), errorName ? errorName : @"?"];
}

- (NSUInteger)beginBusy {
    ++_token;
    [ExteriaBusyView showFor:_token];
    return _token;
}

- (void)endBusy:(NSUInteger)token {
    [ExteriaBusyView hideFor:token];
}

- (void)showNote:(NSString *)text {
    if (!text.length) return;
    UIView *window = ExteriaOverlayHost();
    if (!window) return;
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    label.textColor = [UIColor whiteColor];
    label.font = ExteriaFontMedium(15);
    label.textAlignment = ExteriaTextAlignmentCenter;
    label.numberOfLines = 3;
    label.text = text;
    label.layer.cornerRadius = 10;
    label.clipsToBounds = YES;
    CGFloat width = MIN(window.bounds.size.width - 48, 340);
    CGSize fit = [label sizeThatFits:CGSizeMake(width - 24, 200)];
    label.frame = CGRectMake(0, 0, MIN(width, fit.width + 28), fit.height + 18);
    label.center = CGPointMake(CGRectGetMidX(window.bounds), window.bounds.size.height - 110 - label.frame.size.height / 2);
    label.alpha = 0;
    [window addSubview:label];
    [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL done) {
        (void)done;
        [UIView animateWithDuration:0.3 delay:2.2 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL finished) {
            (void)finished;
            [label removeFromSuperview];
        }];
    }];
}

NSString *const ExteriaOpenLinkNotification = @"ExteriaOpenLink";

BOOL ExteriaIsTelegramLink(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    if ([scheme isEqualToString:@"tg"]) return YES;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    NSString *host = [url.host lowercaseString];
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    return [host isEqualToString:@"t.me"] || [host isEqualToString:@"telegram.me"] || [host isEqualToString:@"telegram.dog"];
}

- (UINavigationController *)navigation {
    return _anchor.navigationController;
}

- (void)openExternal:(NSString *)url {
    NSURL *target = [NSURL URLWithString:url];
    if (!target || !ExteriaSystemSchemeAllowed(target.scheme)) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    if (![[UIApplication sharedApplication] openURL:target]) [self showNote:NSLocalizedString(@"bots.error.link", nil)];
}

#pragma mark links

- (void)openLink:(NSString *)url {
    if (!url.length) return;
    NSURL *articleURL = [NSURL URLWithString:url];
    if (ExteriaIsArticleURL(articleURL)) {
        ExteriaPresentArticle(articleURL, _anchor);
        return;
    }
    static NSString *const mentionPrefix = @"exteria-mention:";
    if ([url hasPrefix:mentionPrefix]) {
        [self openMention:[url substringFromIndex:mentionPrefix.length]];
        return;
    }
    exteria_tg_link link;
    if (exteria_tg_link_parse(url.UTF8String, &link) != EXTERIA_OK) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    switch (link.kind) {
    case EXTERIA_LINK_OTHER:
        [self openExternal:url];
        return;
    case EXTERIA_LINK_INVOICE: {
        [self payInvoiceOfSlug:[NSString stringWithUTF8String:link.slug] completion:nil];
        return;
    }
    case EXTERIA_LINK_INVITE:
        [self openInviteOfHash:[NSString stringWithUTF8String:link.slug]];
        return;
    case EXTERIA_LINK_PROXY:
    case EXTERIA_LINK_SOCKS: {
        exteria_proxy proxy;
        exteria_status status = exteria_proxy_from_link(&link, &proxy);
        if (status != EXTERIA_OK) {
            exteria_wipe(&proxy, sizeof(proxy));
            exteria_wipe(&link, sizeof(link));
            ExteriaShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(@"proxy.invalid", nil));
            return;
        }
        NSString *description = [NSString stringWithFormat:NSLocalizedString(@"proxy.confirm", nil),
            proxy.kind == EXTERIA_PROXY_SOCKS5 ? @"SOCKS5" : @"MTProto", proxy.server, (unsigned)proxy.port];
        exteria_wipe(&proxy, sizeof(proxy));
        exteria_wipe(&link, sizeof(link));
        ExteriaConfirm(NSLocalizedString(@"proxy.title", nil), description, NSLocalizedString(@"proxy.enable", nil), ^{
            exteria_status saved = ExteriaProxyStoreLink(url);
            if (saved != EXTERIA_OK) ExteriaShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(@"proxy.savefailed", nil));
        });
        return;
    }
    case EXTERIA_LINK_CALL:
        /* a conference call is end-to-end encrypted with a protocol this app does not have, so its link is told apart from a person's */
        ExteriaShowNotice(NSLocalizedString(@"group.title", nil), NSLocalizedString(@"group.notice.unsupported", nil));
        return;
    case EXTERIA_LINK_PRIVATE_POST: {
        long long channelId = link.channel_id;
        int32_t messageId = link.message_id;
        NSUInteger token = [self beginBusy];
        [self retain];
        [_session loadChannelDialogWithId:channelId completion:^(ExteriaDialog *dialog, NSString *errorName) {
            [self endBusy:token];
            [self autorelease];
            if (!dialog) {
                [self showNote:[ExteriaLinkRouter textForError:errorName]];
                return;
            }
            [self openDialog:dialog person:nil draft:nil startParam:nil messageId:messageId];
        }];
        return;
    }
    case EXTERIA_LINK_PEER:
        break;
    }
    NSString *name = [NSString stringWithUTF8String:link.username];
    NSString *start = link.has_start && link.start[0] ? [NSString stringWithUTF8String:link.start] : nil;
    int32_t messageId = link.message_id;
    BOOL wantsVoiceChat = link.has_voice_chat != 0;
    NSString *voiceHash = link.voice_chat[0] ? [NSString stringWithUTF8String:link.voice_chat] : nil;
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session resolveUsername:name completion:^(ExteriaDialog *resolved, ExteriaPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!resolved) {
            [self showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        [self openDialog:resolved person:person draft:nil startParam:person.bot ? start : nil messageId:messageId];
        /* ?videochat= names the voice chat of a group or channel: the chat opens behind it, and the call joins with the invite hash of the link */
        if (wantsVoiceChat && (resolved.peerKind == 2 || resolved.peerKind == 3)) [_session.groupCalls joinVoiceChatOfDialog:resolved inviteHash:voiceHash];
    }];
}

/* t.me/+hash: the chat opens when the account is in it already, and otherwise the person sees what it is and decides to join */
- (void)openInviteOfHash:(NSString *)hash {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session checkInviteHash:hash completion:^(ExteriaDialog *member, NSString *title, NSString *about, NSInteger participants, BOOL broadcast, BOOL requestNeeded, NSString *errorName) {
        [self endBusy:token];
        if (errorName) {
            [self showNote:[ExteriaLinkRouter textForError:errorName]];
            [self autorelease];
            return;
        }
        if (member) {
            [self openDialog:member person:nil draft:nil startParam:nil messageId:0];
            [self autorelease];
            return;
        }
        NSString *kind = NSLocalizedString(broadcast ? @"invite.channel" : @"invite.group", nil);
        NSMutableString *message = [NSMutableString stringWithFormat:NSLocalizedString(@"invite.members", nil), kind, (long)participants];
        if (about.length) [message appendFormat:@"\n\n%@", about];
        if (requestNeeded) [message appendFormat:@"\n\n%@", NSLocalizedString(@"invite.request", nil)];
        ExteriaConfirm(title, message, NSLocalizedString(requestNeeded ? @"invite.send" : @"invite.join", nil), ^{
            [self joinInviteOfHash:hash];
        });
        [self autorelease];
    }];
}

- (void)joinInviteOfHash:(NSString *)hash {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session joinInviteHash:hash completion:^(ExteriaDialog *dialog, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!dialog) {
            [self showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        [self openDialog:dialog person:nil draft:nil startParam:nil messageId:0];
    }];
}

/* a @name in a message: a person opens their profile, a group or channel opens its chat */
- (void)openMention:(NSString *)name {
    char buffer[EXTERIA_LINK_NAME_MAX];
    if (exteria_mention_name(name.UTF8String, buffer, sizeof(buffer)) != EXTERIA_OK) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session resolveUsername:name completion:^(ExteriaDialog *resolved, ExteriaPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!resolved) {
            [self showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        UINavigationController *navigation = [self navigation];
        if (!person || !navigation) {
            [self openDialog:resolved person:person draft:nil startParam:nil messageId:0];
            return;
        }
        /* a user the server names without an access hash (the account itself) has no dialog made from the person, and a profile built on nil has no peer to ask for */
        ExteriaDialog *peer = [ExteriaDialog dialogWithPerson:person];
        ExteriaUserProfileController *profile = [[[ExteriaUserProfileController alloc] initWithSession:_session dialog:peer ? peer : resolved avatars:_avatars
                                                                                                  media:_media stickers:_stickers] autorelease];
        [navigation pushViewController:profile animated:YES];
    }];
}

#pragma mark screens

- (void)openDialog:(ExteriaDialog *)dialog person:(ExteriaPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam {
    [self openDialog:dialog person:person draft:draft startParam:startParam messageId:0];
}

- (void)openDialog:(ExteriaDialog *)dialog person:(ExteriaPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam messageId:(int32_t)messageId {
    (void)person;
    UINavigationController *navigation = [self navigation];
    if (!navigation) return;
    ExteriaChatController *chat = [[[ExteriaChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media
                                                                          stickers:_stickers] autorelease];
    chat.draftText = draft;
    chat.startParam = startParam;
    chat.startMessageId = messageId;
    [navigation pushViewController:chat animated:YES];
}

- (void)openProfileOfUser:(long long)userId inMessage:(int32_t)messageId dialog:(ExteriaDialog *)dialog {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadUser:userId ofMessage:messageId inDialog:dialog completion:^(ExteriaPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        ExteriaDialog *chat = person ? [ExteriaDialog dialogWithPerson:person] : nil;
        UINavigationController *navigation = [self navigation];
        if (!chat || !navigation) {
            if (!person) [self showNote:[ExteriaLinkRouter textForError:errorName]];
            return;
        }
        ExteriaUserProfileController *profile = [[[ExteriaUserProfileController alloc] initWithSession:_session dialog:chat avatars:_avatars media:_media
                                                                                               stickers:_stickers] autorelease];
        [navigation pushViewController:profile animated:YES];
    }];
}

- (void)pickDialogsWithFilter:(BOOL (^)(ExteriaDialog *))filter limit:(NSUInteger)limit completion:(void (^)(NSArray *))completion {
    UINavigationController *navigation = [self navigation];
    if (!navigation) return;
    void (^done)(NSArray *) = [completion copy];
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"bots.pick.title", nil);
    picker.filter = filter;
    picker.limit = limit;
    picker.pickHandler = ^(NSArray *dialogs) {
        done(dialogs);
        [done release];
    };
    [navigation pushViewController:picker animated:YES];
}

- (void)pickDialogWithTypes:(uint8_t)types completion:(void (^)(ExteriaDialog *))completion {
    UINavigationController *navigation = [self navigation];
    if (!navigation) return;
    void (^done)(ExteriaDialog *) = [completion copy];
    ExteriaDialogPickerController *picker = [[[ExteriaDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"bots.pick.title", nil);
    picker.filter = ^BOOL(ExteriaDialog *dialog) {
        if (!types) return YES;
        switch (dialog.kind) {
        case EXTERIA_DIALOG_USER: return (types & 1u) != 0;
        case EXTERIA_DIALOG_BOT: return (types & 2u) != 0;
        case EXTERIA_DIALOG_GROUP: return (types & 4u) != 0;
        case EXTERIA_DIALOG_CHANNEL: return (types & 8u) != 0;
        }
        return NO;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        done([dialogs lastObject]);
        [done release];
    };
    [navigation pushViewController:picker animated:YES];
}

#pragma mark invoices

- (void)confirmInvoice:(ExteriaStarsInvoice *)invoice completion:(void (^)(NSString *))completion {
    NSString *message = invoice->invoiceDescription.length
        ? [NSString stringWithFormat:@"%@\n\n%@", invoice->invoiceDescription, ExteriaStarsText(invoice->stars)]
        : ExteriaStarsText(invoice->stars);
    void (^done)(NSString *) = [completion copy];
    ExteriaShowAlert(invoice->title.length ? invoice->title : NSLocalizedString(@"bots.invoice.title", nil), message,
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil),
                      [NSString stringWithFormat:NSLocalizedString(@"bots.invoice.pay", nil), ExteriaStarsText(invoice->stars)], nil],
                     0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index != 1) {
            if (done) done(@"cancelled");
            [done release];
            return;
        }
        NSUInteger token = [self beginBusy];
        [self retain];
        [_session payStarsInvoice:invoice completion:^(NSString *errorName) {
            [self endBusy:token];
            [self autorelease];
            if (errorName) [self showNote:[ExteriaLinkRouter textForError:errorName]];
            if (done) done(errorName ? @"failed" : @"paid");
            [done release];
        }];
    });
}

- (void)handleInvoice:(ExteriaStarsInvoice *)invoice error:(NSString *)errorName token:(NSUInteger)token completion:(void (^)(NSString *))done {
    [self endBusy:token];
    if (!invoice) {
        [self showNote:[ExteriaLinkRouter textForError:errorName]];
        if (done) done(@"failed");
        [done release];
        return;
    }
    [self confirmInvoice:invoice completion:done];
    [done release];
}

- (void)payInvoiceOfSlug:(NSString *)slug completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadStarsInvoiceOfSlug:slug completion:^(ExteriaStarsInvoice *invoice, NSString *errorName) {
        [self autorelease];
        [self handleInvoice:invoice error:errorName token:token completion:[done retain]];
        [done release];
    }];
}

- (void)payInvoiceOfMessage:(int32_t)messageId inDialog:(ExteriaDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadStarsInvoiceOfMessage:messageId inDialog:dialog completion:^(ExteriaStarsInvoice *invoice, NSString *errorName) {
        [self autorelease];
        [self handleInvoice:invoice error:errorName token:token completion:[done retain]];
        [done release];
    }];
}

@end
