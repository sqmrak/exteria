#import <Foundation/Foundation.h>

#import "exteria_bot_markup.h"
#import "exteria_dialog.h"
#import "exteria_message.h"
#import "exteria_person.h"

#include "exteria_bots.h"

/* what a bot says about itself, built off the main thread */
@interface ExteriaBotCommand : NSObject {
    NSString *_name;
    NSString *_text;
}
/* without the slash */
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *text;
@end

@interface ExteriaBotInfo : NSObject {
    NSString *_botDescription;
    ExteriaMedia *_picture;
    NSArray *_commands;
    exteria_bot_menu_kind _menuKind;
    NSString *_privacyUrl;
}
+ (ExteriaBotInfo *)infoWithRow:(const exteria_bot_info *)row;
/* the text shown in the empty chat of the bot, empty when it has none */
@property (nonatomic, readonly, copy) NSString *botDescription;
/* the picture or animation above it; nil without one */
@property (nonatomic, readonly, retain) ExteriaMedia *picture;
/* ExteriaBotCommand items */
@property (nonatomic, readonly, retain) NSArray *commands;
@property (nonatomic, readonly) exteria_bot_menu_kind menuKind;
@property (nonatomic, readonly, copy) NSString *privacyUrl;
@end

/* the answer to the press of a callback button */
@interface ExteriaCallbackAnswer : NSObject {
    BOOL _alert;
    NSString *_message;
    NSString *_url;
}
+ (ExteriaCallbackAnswer *)answerWithRow:(const exteria_callback_answer *)row;
@property (nonatomic, readonly) BOOL alert;
@property (nonatomic, readonly, copy) NSString *message;
/* an address to open (a game page), nil when there is none */
@property (nonatomic, readonly, copy) NSString *url;
@end

/* where the picture of a result lives when the bot hosts it */
@interface ExteriaWebFile : NSObject {
    NSString *_url;
    BOOL _proxied;
    long long _accessHash;
}
/* nil when the ref carries no picture */
+ (ExteriaWebFile *)fileWithRef:(const exteria_web_ref *)ref;
@property (nonatomic, readonly, copy) NSString *url;
/* fetched through the servers with the access hash, otherwise by the address itself */
@property (nonatomic, readonly) BOOL proxied;
@property (nonatomic, readonly) long long accessHash;
@end

@interface ExteriaInlineResult : NSObject {
    exteria_inline_kind _kind;
    NSString *_resultId;
    NSString *_title;
    NSString *_subtitle;
    ExteriaMedia *_media;
    ExteriaWebFile *_thumb;
    int32_t _width;
    int32_t _height;
    int32_t _duration;
}
+ (ExteriaInlineResult *)resultWithRow:(const exteria_inline_result *)row;
@property (nonatomic, readonly) exteria_inline_kind kind;
@property (nonatomic, readonly, copy) NSString *resultId;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *subtitle;
/* the photo or document the server holds, nil for a result the bot hosts */
@property (nonatomic, readonly, retain) ExteriaMedia *media;
@property (nonatomic, readonly, retain) ExteriaWebFile *thumb;
@property (nonatomic, readonly) int32_t width;
@property (nonatomic, readonly) int32_t height;
@property (nonatomic, readonly) int32_t duration;
@end

@interface ExteriaInlinePage : NSObject {
    long long _queryId;
    BOOL _gallery;
    NSString *_nextOffset;
    NSString *_switchText;
    NSString *_switchParam;
    NSArray *_results;
}
+ (ExteriaInlinePage *)pageWithRow:(const exteria_inline_page *)row results:(NSArray *)results;
@property (nonatomic, readonly) long long queryId;
@property (nonatomic, readonly) BOOL gallery;
@property (nonatomic, readonly, copy) NSString *nextOffset;
/* a button that opens the chat with the bot; empty text when there is none */
@property (nonatomic, readonly, copy) NSString *switchText;
@property (nonatomic, readonly, copy) NSString *switchParam;
@property (nonatomic, readonly, retain) NSArray *results;
@end

/* a request to sign in on a site */
@interface ExteriaUrlAuth : NSObject {
    exteria_url_auth_kind _kind;
    BOOL _requestWrite;
    BOOL _requestPhone;
    NSString *_botName;
    NSString *_domain;
    NSString *_url;
    NSArray *_codes;
}
+ (ExteriaUrlAuth *)authWithRow:(const exteria_url_auth *)row;
@property (nonatomic, readonly) exteria_url_auth_kind kind;
@property (nonatomic, readonly) BOOL requestWrite;
@property (nonatomic, readonly) BOOL requestPhone;
@property (nonatomic, readonly, copy) NSString *botName;
@property (nonatomic, readonly, copy) NSString *domain;
@property (nonatomic, readonly, copy) NSString *url;
/* the NSString codes the person must pick from, empty when no code is asked */
@property (nonatomic, readonly, retain) NSArray *codes;
@end

/* an invoice in stars, asked of the server and waiting for the person's yes */
@interface ExteriaStarsInvoice : NSObject {
@public
    /* a message of the chat carries it, otherwise the slug of the link does */
    exteria_peer_ref peer;
    int32_t messageId;
    NSString *slug;
    long long formId;
    long long botId;
    long long stars;
    NSString *title;
    NSString *invoiceDescription;
}
@end
