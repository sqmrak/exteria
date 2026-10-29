#ifndef EXTERIA_LINKS_H
#define EXTERIA_LINKS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

#define EXTERIA_LINK_URL_MAX 2048
#define EXTERIA_LINK_NAME_MAX 33
#define EXTERIA_LINK_PARAM_MAX 65
#define EXTERIA_LINK_SLUG_MAX 129
#define EXTERIA_LINK_SERVER_MAX 256
#define EXTERIA_LINK_SECRET_MAX 275
#define EXTERIA_LINK_CREDENTIAL_MAX 65

typedef enum exteria_link_kind {
    EXTERIA_LINK_OTHER = 0,     /* not a telegram link this client acts on: open it as an ordinary address */
    EXTERIA_LINK_PEER,          /* a user, bot, group or channel by its name, with what the link asks of it */
    EXTERIA_LINK_INVOICE,       /* an invoice by its slug */
    EXTERIA_LINK_PROXY,         /* an MTProto proxy: server, port and secret */
    EXTERIA_LINK_SOCKS,         /* a SOCKS5 proxy: server and port, with a user and a password or without */
    EXTERIA_LINK_INVITE,        /* an invite to a private group or channel: the hash is in slug */
    EXTERIA_LINK_CALL,          /* t.me/call/<slug>: a conference call by its slug */
    EXTERIA_LINK_PRIVATE_POST   /* t.me/c/<channel>/<post> or tg://privatepost: a message of a channel or group by its number, for members */
} exteria_link_kind;

typedef struct exteria_tg_link {
    exteria_link_kind kind;
    char username[EXTERIA_LINK_NAME_MAX];
    uint8_t has_start;              /* ?start= was given, also when it is empty */
    char start[EXTERIA_LINK_PARAM_MAX];
    char app_name[EXTERIA_LINK_NAME_MAX];   /* t.me/bot/app: the short name of one of the bot's apps */
    uint8_t has_start_app;          /* ?startapp=, which opens the bot's main app when no app name is given */
    char start_app[EXTERIA_LINK_PARAM_MAX];
    int32_t message_id;             /* t.me/name/123, zero without one */
    int64_t channel_id;             /* the number of the channel or group of a private post link, as it stands in the link (without the -100) */
    /* ?videochat= or ?voicechat= on a name: the voice chat of that group or channel, joined with this invite hash (empty when the parameter has no value) */
    uint8_t has_voice_chat;
    char voice_chat[EXTERIA_LINK_PARAM_MAX];
    char slug[EXTERIA_LINK_SLUG_MAX];
    /* the proxy links: the secret stays as typed in the link (hex or base64url), for exteria_proxy_secret_decode */
    char proxy_server[EXTERIA_LINK_SERVER_MAX];
    uint16_t proxy_port;
    char proxy_secret[EXTERIA_LINK_SECRET_MAX];
    char proxy_user[EXTERIA_LINK_CREDENTIAL_MAX];
    char proxy_password[EXTERIA_LINK_CREDENTIAL_MAX];
} exteria_tg_link;

/* reads tg:// links and the t.me, telegram.me and telegram.dog forms of them; anything else is kind other with
   EXTERIA_OK */
exteria_status exteria_tg_link_parse(const char *url, exteria_tg_link *out);

/* the name of a mention ("@name" or "name") when it has the shape of a public name; EXTERIA_E_MALFORMED otherwise */
exteria_status exteria_mention_name(const char *text, char *out, size_t cap);

/* a bot command as it stands in a message: "/start", "/start@helper_bot". command gets the part before the @ with
   the slash, bot the name after it (empty without one) */
exteria_status exteria_bot_command_split(const char *text, char *command, size_t command_cap, char *bot, size_t bot_cap);

#endif
