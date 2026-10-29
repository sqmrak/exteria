#ifndef EXTERIA_BOTS_H
#define EXTERIA_BOTS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_markup.h"
#include "exteria_media.h"
#include "exteria_messages.h"
#include "exteria_people.h"
#include "exteria_tl.h"

/* a bot is a user: it is named in requests by an exteria_peer_ref of kind 1 with its access hash, a chat by the
   same */

/* a start parameter: up to 64 characters of A-Z a-z 0-9 _ - as the server takes them */
#define EXTERIA_START_PARAM_MAX 64
/* the shape of a public name, without the @ */
#define EXTERIA_USERNAME_LOOKUP_MAX 32

/* resolving a public name */
typedef struct exteria_resolved {
    exteria_dialog_row dialog;      /* the peer as a chat: kind, title, photo and access hash */
    uint8_t is_user;
    exteria_person_row person;      /* the user itself, with the flags of a bot */
} exteria_resolved;

/* contacts.resolveUsername; a name with a character outside A-Z a-z 0-9 _, or not 1 to 32 long, is EXTERIA_E_ARG */
exteria_status exteria_resolve_request(exteria_arena *arena, const char *username, exteria_tl_value **out);
/* the contacts.resolvedPeer answer */
exteria_status exteria_resolve_parse(const exteria_tl_value *answer, int64_t self_id, exteria_resolved *out);

/* an invite link to a private group or channel */
#define EXTERIA_INVITE_ABOUT_MAX 512
typedef struct exteria_invite {
    uint8_t member;                 /* the account is in the chat already (or may peek at it): dialog is set and about is not */
    exteria_dialog_row dialog;
    char title[EXTERIA_DIALOG_TITLE_MAX];
    char about[EXTERIA_INVITE_ABOUT_MAX];
    exteria_media_ref photo;
    int32_t participants;
    uint8_t broadcast;              /* a channel, not a group */
    uint8_t request_needed;         /* joining sends a request that an admin approves */
    uint8_t verified;
} exteria_invite;

/* messages.checkChatInvite and messages.importChatInvite; a hash outside A-Z a-z 0-9 _ - or longer than 128 is EXTERIA_E_ARG */
exteria_status exteria_invite_check_request(exteria_arena *arena, const char *hash, exteria_tl_value **out);
exteria_status exteria_invite_import_request(exteria_arena *arena, const char *hash, exteria_tl_value **out);
/* the ChatInvite answer */
exteria_status exteria_invite_parse(const exteria_tl_value *answer, int64_t self_id, exteria_invite *out);
/* the answer of the import: the chat the account joined, from the chats of the updates; a bot check that needs a web view is
   EXTERIA_E_UNSUPPORTED */
exteria_status exteria_invite_joined_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *out);

/* what a bot says about itself in the chat that has no messages yet, and its menu */
#define EXTERIA_BOT_COMMANDS_MAX 100
#define EXTERIA_BOT_COMMAND_MAX 40
#define EXTERIA_BOT_COMMAND_TEXT_MAX 132
#define EXTERIA_BOT_DESCRIPTION_MAX 2048
#define EXTERIA_BOT_MENU_TEXT_MAX 48
#define EXTERIA_BOT_URL_MAX 1024

typedef struct exteria_bot_command {
    char name[EXTERIA_BOT_COMMAND_MAX];     /* without the slash */
    char text[EXTERIA_BOT_COMMAND_TEXT_MAX];
} exteria_bot_command;

typedef enum exteria_bot_menu_kind {
    EXTERIA_BOT_MENU_DEFAULT = 0,
    EXTERIA_BOT_MENU_COMMANDS       /* the list of commands */
} exteria_bot_menu_kind;

typedef struct exteria_bot_info {
    uint8_t present;                /* the user carries bot info at all */
    char description[EXTERIA_BOT_DESCRIPTION_MAX];
    uint8_t has_picture;
    exteria_media_info picture;     /* the picture or animation shown above the description */
    uint8_t menu_kind;              /* exteria_bot_menu_kind */
    char privacy_url[EXTERIA_BOT_URL_MAX];
    uint16_t command_count;
    exteria_bot_command commands[EXTERIA_BOT_COMMANDS_MAX];
} exteria_bot_info;

/* the bot info of a users.userFull answer; a user that is not a bot leaves present zero. out is always initialised */
exteria_status exteria_bot_info_parse(const exteria_tl_value *answer, exteria_bot_info *out);

/* contacts.addContact for a user the person already knows or finds: it stores the name the person gives, which is
   the one shown instead of the name the user chose */
#define EXTERIA_CONTACT_NAME_MAX 64
exteria_status exteria_contact_edit_request(exteria_arena *arena, const exteria_peer_ref *user, const char *first, const char *last, const char *phone,
                                            exteria_tl_value **out);
/* contacts.importContacts for one phone number: the way to add someone who is not known yet */
exteria_status exteria_contact_import_request(exteria_arena *arena, const char *phone, const char *first, const char *last, exteria_tl_value **out);
/* how many of the numbers the server found an account for in a contacts.importedContacts answer; anything else is EXTERIA_E_MALFORMED */
exteria_status exteria_contact_import_parse(const exteria_tl_value *answer, size_t *imported);
/* messages.startBot: the first message of a chat with a bot. random_id is not zero */
exteria_status exteria_start_bot_request(exteria_arena *arena, const exteria_peer_ref *bot, const exteria_peer_ref *peer,
                                         int64_t random_id, const char *param, exteria_tl_value **out);

/* the press of a callback button */
#define EXTERIA_CALLBACK_TEXT_MAX 1024
#define EXTERIA_CALLBACK_URL_MAX 1024

typedef struct exteria_callback_answer {
    uint8_t alert;                  /* shown as a dialog instead of a short note */
    uint8_t has_url;
    uint8_t native_ui;
    int32_t cache_time;
    char message[EXTERIA_CALLBACK_TEXT_MAX];
    char url[EXTERIA_CALLBACK_URL_MAX];
} exteria_callback_answer;

/* messages.getBotCallbackAnswer for the button with data (at most 64 bytes) on a message */
exteria_status exteria_callback_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, const uint8_t *data,
                                        size_t data_len, int game, exteria_tl_value *password, exteria_tl_value **out);
exteria_status exteria_callback_parse(const exteria_tl_value *answer, exteria_callback_answer *out);

/* the inputCheckPasswordSRP for a password, from the account.password answer of account.getPassword;
   EXTERIA_E_UNSUPPORTED when the account has no password or uses a scheme this client cannot compute */
exteria_status exteria_password_input(exteria_arena *arena, const exteria_tl_value *account_password, const char *password,
                                      exteria_tl_value **out);
exteria_status exteria_password_request(exteria_arena *arena, exteria_tl_value **out);

/* inline mode: @bot query in any chat */
#define EXTERIA_INLINE_ID_MAX 72
#define EXTERIA_INLINE_TITLE_MAX 100
#define EXTERIA_INLINE_TEXT_MAX 200
#define EXTERIA_INLINE_OFFSET_MAX 80
#define EXTERIA_INLINE_RESULTS_MAX 50
#define EXTERIA_INLINE_QUERY_MAX 256
#define EXTERIA_WEB_URL_MAX 512

typedef enum exteria_inline_kind {
    EXTERIA_INLINE_OTHER = 0,
    EXTERIA_INLINE_ARTICLE,
    EXTERIA_INLINE_PHOTO,
    EXTERIA_INLINE_GIF,
    EXTERIA_INLINE_VIDEO,
    EXTERIA_INLINE_AUDIO,
    EXTERIA_INLINE_VOICE,
    EXTERIA_INLINE_FILE,
    EXTERIA_INLINE_STICKER,
    EXTERIA_INLINE_LOCATION,
    EXTERIA_INLINE_CONTACT,
    EXTERIA_INLINE_GAME
} exteria_inline_kind;

/* a picture a bot hosts itself: fetched by address, through the servers when the bot asked for a proxy */
typedef struct exteria_web_ref {
    uint8_t present;
    uint8_t proxied;                /* upload.getWebFile with the access hash, otherwise a plain GET of url */
    int64_t access_hash;
    int32_t size;
    char url[EXTERIA_WEB_URL_MAX];
    char mime[EXTERIA_MEDIA_MIME_MAX];
} exteria_web_ref;

typedef struct exteria_inline_result {
    uint8_t kind;                   /* exteria_inline_kind */
    char id[EXTERIA_INLINE_ID_MAX];
    char title[EXTERIA_INLINE_TITLE_MAX];
    char description[EXTERIA_INLINE_TEXT_MAX];
    exteria_media_info media;       /* the photo or document the server holds; kind text without one */
    exteria_web_ref thumb;          /* the picture the bot hosts */
    int32_t width;
    int32_t height;
    int32_t duration;
} exteria_inline_result;

typedef struct exteria_inline_page {
    int64_t query_id;
    uint8_t gallery;                /* the results are pictures, shown as a grid */
    int32_t cache_time;
    char next_offset[EXTERIA_INLINE_OFFSET_MAX];    /* empty on the last page */
    char switch_text[EXTERIA_BOT_MENU_TEXT_MAX];    /* a button that opens the chat with the bot */
    char switch_param[EXTERIA_START_PARAM_MAX + 1];
} exteria_inline_page;

/* messages.getInlineBotResults; offset is "" for the first page */
exteria_status exteria_inline_query_request(exteria_arena *arena, const exteria_peer_ref *bot, const exteria_peer_ref *peer,
                                            const char *query, const char *offset, exteria_tl_value **out);
/* a messages.botResults answer into page and at most cap results; a result this client cannot show is skipped */
exteria_status exteria_inline_results_parse(const exteria_tl_value *answer, exteria_inline_page *page, exteria_inline_result *rows,
                                            size_t cap, size_t *count);
/* messages.sendInlineBotResult of the result with id from the page with query_id */
exteria_status exteria_inline_send_request(exteria_arena *arena, const exteria_peer_ref *peer, int64_t random_id, int64_t query_id,
                                           const char *result_id, exteria_tl_value **out);

/* users.getUsers for a user named by a message that mentions them, which is how a button or a text mention gives the access hash that
   opening their profile needs. peer and msg_id name the message */
exteria_status exteria_user_from_message_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int64_t user_id, exteria_tl_value **out);
/* the user with user_id in the answer to it; EXTERIA_E_NOTFOUND when the answer does not carry that user */
exteria_status exteria_user_from_message_parse(const exteria_tl_value *answer, int64_t user_id, exteria_person_row *out);

/* a link in a message or a button that asks to sign the person in on the bot's site */
#define EXTERIA_URL_AUTH_CODES_MAX 8
#define EXTERIA_URL_AUTH_NAME_MAX 96

typedef enum exteria_url_auth_kind {
    EXTERIA_URL_AUTH_OPEN = 0,      /* nothing to ask: open the address as it is */
    EXTERIA_URL_AUTH_ASK,           /* the person decides whether to sign in */
    EXTERIA_URL_AUTH_DONE           /* signed in; url is the address to open */
} exteria_url_auth_kind;

typedef struct exteria_url_auth {
    uint8_t kind;                   /* exteria_url_auth_kind */
    uint8_t request_write;          /* the site asks to message the person */
    uint8_t request_phone;          /* the site asks for the phone number */
    uint8_t code_count;             /* the person must pick the code the site shows from these */
    char bot[EXTERIA_URL_AUTH_NAME_MAX];
    char domain[EXTERIA_URL_AUTH_NAME_MAX];
    char url[EXTERIA_BOT_URL_MAX];
    char codes[EXTERIA_URL_AUTH_CODES_MAX][16];
} exteria_url_auth;

/* messages.requestUrlAuth for a button (peer, msg_id, button_id) or, with peer NULL, for a bare address */
exteria_status exteria_url_auth_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                        const char *url, exteria_tl_value **out);
exteria_status exteria_url_auth_parse(const exteria_tl_value *answer, exteria_url_auth *out);
/* messages.acceptUrlAuth; code is the chosen one of the codes, or NULL */
exteria_status exteria_url_auth_accept_request(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                               const char *url, int write_allowed, int share_phone, const char *code, exteria_tl_value **out);

/* an invoice paid in stars */
typedef struct exteria_stars_form {
    int64_t form_id;
    int64_t bot_id;
    int64_t stars;
    char title[EXTERIA_INLINE_TITLE_MAX];
    char description[EXTERIA_INLINE_TEXT_MAX * 2];
} exteria_stars_form;

/* inputInvoiceMessage for the invoice of a message, and inputInvoiceSlug for one a link names by its slug (letters, digits, _ and -) */
exteria_status exteria_invoice_message_input(exteria_arena *arena, const exteria_peer_ref *peer, int32_t msg_id, exteria_tl_value **out);
exteria_status exteria_invoice_slug_input(exteria_arena *arena, const char *slug, exteria_tl_value **out);
/* a payments.paymentFormStars answer */
exteria_status exteria_stars_form_parse(const exteria_tl_value *answer, exteria_stars_form *out);

/* answers a bot's keyboard */
/* messages.sendMedia with the person's own number, for a button that asks for it */
exteria_status exteria_send_contact_request(exteria_arena *arena, const exteria_peer_ref *peer, const char *phone, const char *first_name,
                                            const char *last_name, int64_t random_id, exteria_tl_value **out);
/* messages.sendBotRequestedPeer: the chats the person picked for a request peer button of the message msg_id */
exteria_status exteria_requested_peers_request(exteria_arena *arena, const exteria_peer_ref *bot_chat, int32_t msg_id, int32_t button_id,
                                               const exteria_peer_ref *peers, size_t count, exteria_tl_value **out);

#endif
