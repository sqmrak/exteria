#ifndef EXTERIA_MARKUP_H
#define EXTERIA_MARKUP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_tl.h"
#include "exteria_welcome.h"

/* the server takes 100 buttons in a keyboard; a bigger one is cut there so a hostile answer cannot grow the rows */
#define EXTERIA_MARKUP_ROWS_MAX 40
#define EXTERIA_MARKUP_ROW_MAX 12
#define EXTERIA_MARKUP_BUTTONS_MAX 100
#define EXTERIA_MARKUP_TEXT_MAX 96
#define EXTERIA_MARKUP_DATA_MAX 64
#define EXTERIA_MARKUP_POOL_MAX 8192
#define EXTERIA_MARKUP_PLACEHOLDER_MAX 96

typedef enum exteria_markup_kind {
    EXTERIA_MARKUP_NONE = 0,
    EXTERIA_MARKUP_INLINE,          /* buttons under the message */
    EXTERIA_MARKUP_KEYBOARD,        /* replaces the keyboard of the chat */
    EXTERIA_MARKUP_HIDE,            /* takes a reply keyboard away */
    EXTERIA_MARKUP_FORCE_REPLY      /* asks for an answer to the message */
} exteria_markup_kind;

typedef enum exteria_button_kind {
    EXTERIA_BUTTON_TEXT = 1,        /* a reply keyboard button: sends its own text */
    EXTERIA_BUTTON_URL,
    EXTERIA_BUTTON_CALLBACK,
    EXTERIA_BUTTON_URL_AUTH,        /* a link that signs the person in on the bot's site */
    EXTERIA_BUTTON_SWITCH_INLINE,
    EXTERIA_BUTTON_GAME,
    EXTERIA_BUTTON_BUY,
    EXTERIA_BUTTON_COPY,
    EXTERIA_BUTTON_USER_PROFILE,
    EXTERIA_BUTTON_REQUEST_PHONE,
    EXTERIA_BUTTON_REQUEST_GEO,
    EXTERIA_BUTTON_REQUEST_POLL,
    EXTERIA_BUTTON_REQUEST_PEER,
    EXTERIA_BUTTON_DISABLED         /* a kind this client does not know (a web app button among them), or one that does not fit; shown, never acted on */
} exteria_button_kind;

typedef enum exteria_button_style {
    EXTERIA_BUTTON_STYLE_PLAIN = 0,
    EXTERIA_BUTTON_STYLE_PRIMARY,
    EXTERIA_BUTTON_STYLE_DANGER,
    EXTERIA_BUTTON_STYLE_SUCCESS
} exteria_button_style;

/* what kind of chat a request peer button asks the person to choose */
typedef enum exteria_peer_choice {
    EXTERIA_CHOICE_USER = 1,
    EXTERIA_CHOICE_GROUP,
    EXTERIA_CHOICE_CHANNEL,
    EXTERIA_CHOICE_CREATE_BOT       /* a new bot, which this client cannot make */
} exteria_peer_choice;

/* a condition of a request peer button: the chat may be anything, must have the property, or must not */
enum { EXTERIA_WANT_ANY = 0, EXTERIA_WANT_YES = 1, EXTERIA_WANT_NO = 2 };

typedef struct exteria_markup_button {
    uint8_t kind;               /* exteria_button_kind */
    uint8_t style;              /* exteria_button_style */
    uint8_t password;           /* callback: the server wants the 2fa password with the press */
    uint8_t same_peer;          /* switch inline: only in the chat the message is in */
    uint8_t quiz;               /* request poll: EXTERIA_WANT_YES for a quiz only, EXTERIA_WANT_NO for a plain poll only */
    uint8_t data_len;           /* callback payload bytes in data */
    uint8_t choice;             /* request peer: exteria_peer_choice */
    uint8_t want_bot;           /* request peer, users: bots only or people only */
    uint8_t want_premium;
    uint8_t want_username;      /* request peer, chats and channels */
    uint8_t want_forum;
    uint8_t want_creator;       /* request peer: chats the person owns */
    uint8_t max_quantity;       /* request peer: how many the person may pick, at least 1 */
    int32_t button_id;          /* url auth and request peer: names the button to the server */
    int64_t user_id;            /* user profile */
    int64_t icon;               /* the custom emoji that decorates the button, zero for none */
    uint16_t arg_offset;        /* into the pool: the address, the inline query, the text to copy */
    uint16_t arg_length;
    char text[EXTERIA_MARKUP_TEXT_MAX];
    uint8_t data[EXTERIA_MARKUP_DATA_MAX];
} exteria_markup_button;

typedef struct exteria_markup {
    uint8_t kind;               /* exteria_markup_kind */
    uint8_t resize;             /* keyboard: only as tall as its rows need */
    uint8_t single_use;         /* keyboard: goes away after one press */
    uint8_t persistent;         /* keyboard: stays open when the person types */
    uint8_t selective;          /* meant for some of the people in the chat only */
    uint8_t row_count;
    uint8_t row_size[EXTERIA_MARKUP_ROWS_MAX];
    uint16_t button_count;
    uint16_t pool_len;
    char placeholder[EXTERIA_MARKUP_PLACEHOLDER_MAX];
    exteria_markup_button buttons[EXTERIA_MARKUP_BUTTONS_MAX];
    char pool[EXTERIA_MARKUP_POOL_MAX];
} exteria_markup;

/* a ReplyMarkup, or NULL for a message that has none. out is always initialised and left as kind none when there
   is nothing to show */
exteria_status exteria_markup_read(const exteria_tl_value *markup, exteria_markup *out);

/* the text of a button argument (address, query, text to copy), terminated; an empty string for a button that has none */
const char *exteria_markup_arg(const exteria_markup *markup, const exteria_markup_button *button);

/* the frames of the buttons in reading order for a width */
exteria_status exteria_markup_layout(const uint8_t *row_size, size_t row_count, double width, double row_height, double gap,
                                     exteria_rect *frames, size_t cap, double *height);

#endif
