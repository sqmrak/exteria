#include "exteria_markup.h"

#include <math.h>
#include <string.h>

#include "exteria_tl_ids.h"

static int is_vec(const exteria_tl_value *v) {
    return v && v->kind == EXTERIA_TL_V_VEC;
}

/* a string cut at a character boundary so a long label never ends in half a sequence */
static void copy_cut(char *dst, size_t cap, const uint8_t *data, size_t len) {
    if (len >= cap) {
        len = cap - 1;
        while (len > 0 && (data[len] & 0xC0u) == 0x80u) --len;
    }
    memcpy(dst, data, len);
    dst[len] = 0;
}

static void copy_field(char *dst, size_t cap, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    dst[0] = 0;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return;
    copy_cut(dst, cap, data, len);
}

/* stores a string in the pool; false when it does not fit whole, since a cut address would open the wrong page */
static int pool_put(exteria_markup *m, exteria_markup_button *b, const uint8_t *data, size_t len) {
    if (m->pool_len + len + 1 > sizeof(m->pool) || len > 0xffffu) return 0;
    memcpy(m->pool + m->pool_len, data, len);
    m->pool[m->pool_len + len] = 0;
    b->arg_offset = m->pool_len;
    b->arg_length = (uint16_t)len;
    m->pool_len = (uint16_t)(m->pool_len + len + 1);
    return 1;
}

static int pool_field(exteria_markup *m, exteria_markup_button *b, const exteria_tl_value *object, const char *field) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(object, field, &data, &len) != EXTERIA_OK) return 0;
    return pool_put(m, b, data, len);
}

static uint8_t want_of(const exteria_tl_value *object, const char *field) {
    const exteria_tl_value *v = exteria_tl_get(object, field);
    if (exteria_tl_is(v, EXTERIA_TL_ID_boolTrue)) return EXTERIA_WANT_YES;
    if (v && v->kind == EXTERIA_TL_V_OBJ) return EXTERIA_WANT_NO;
    return EXTERIA_WANT_ANY;
}

static void read_peer_type(const exteria_tl_value *type, exteria_markup_button *b) {
    if (exteria_tl_is(type, EXTERIA_TL_ID_requestPeerTypeUser)) {
        b->choice = EXTERIA_CHOICE_USER;
        b->want_bot = want_of(type, "bot");
        b->want_premium = want_of(type, "premium");
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_requestPeerTypeChat)) {
        b->choice = EXTERIA_CHOICE_GROUP;
        b->want_creator = exteria_tl_has(type, "creator") ? EXTERIA_WANT_YES : EXTERIA_WANT_ANY;
        b->want_username = want_of(type, "has_username");
        b->want_forum = want_of(type, "forum");
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_requestPeerTypeBroadcast)) {
        b->choice = EXTERIA_CHOICE_CHANNEL;
        b->want_creator = exteria_tl_has(type, "creator") ? EXTERIA_WANT_YES : EXTERIA_WANT_ANY;
        b->want_username = want_of(type, "has_username");
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_requestPeerTypeCreateBot)) {
        b->choice = EXTERIA_CHOICE_CREATE_BOT;
    } else {
        b->kind = EXTERIA_BUTTON_DISABLED;
    }
}

/* the part of a button that its type constructor decides, for a reply keyboard */
static void read_keyboard_type(exteria_markup_button *b, const exteria_tl_value *type) {
    b->kind = EXTERIA_BUTTON_DISABLED;
    if (exteria_tl_is(type, EXTERIA_TL_ID_buttonTypeDefault)) {
        b->kind = EXTERIA_BUTTON_TEXT;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_buttonTypeRequestPhone)) {
        b->kind = EXTERIA_BUTTON_REQUEST_PHONE;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_buttonTypeRequestGeoLocation)) {
        b->kind = EXTERIA_BUTTON_REQUEST_GEO;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_buttonTypeRequestPoll)) {
        b->kind = EXTERIA_BUTTON_REQUEST_POLL;
        b->quiz = want_of(type, "quiz");
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_buttonTypeRequestPeer)) {
        b->kind = EXTERIA_BUTTON_REQUEST_PEER;
        b->max_quantity = 1;
        if (exteria_tl_get_i32(type, "button_id", &b->button_id) != EXTERIA_OK) {
            b->kind = EXTERIA_BUTTON_DISABLED;
            return;
        }
        {
            int32_t quantity = 1;
            exteria_tl_get_i32(type, "max_quantity", &quantity);
            b->max_quantity = (uint8_t)(quantity < 1 ? 1 : quantity > 10 ? 10 : quantity);
        }
        read_peer_type(exteria_tl_get(type, "peer_type"), b);
    }
}

static void read_inline_type(exteria_markup *m, exteria_markup_button *b, const exteria_tl_value *type) {
    b->kind = EXTERIA_BUTTON_DISABLED;
    if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeUrl)) {
        b->kind = EXTERIA_BUTTON_URL;
        if (!pool_field(m, b, type, "url")) b->kind = EXTERIA_BUTTON_DISABLED;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeCallback)) {
        const uint8_t *data;
        size_t len;
        if (exteria_tl_get_bytes(type, "data", &data, &len) != EXTERIA_OK || len > EXTERIA_MARKUP_DATA_MAX) return;
        b->kind = EXTERIA_BUTTON_CALLBACK;
        b->password = exteria_tl_has(type, "requires_password") ? 1 : 0;
        b->data_len = (uint8_t)len;
        if (len) memcpy(b->data, data, len);
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeUrlAuth)) {
        b->kind = EXTERIA_BUTTON_URL_AUTH;
        if (exteria_tl_get_i32(type, "button_id", &b->button_id) != EXTERIA_OK || !pool_field(m, b, type, "url"))
            b->kind = EXTERIA_BUTTON_DISABLED;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeSwitchInline)) {
        b->kind = EXTERIA_BUTTON_SWITCH_INLINE;
        b->same_peer = exteria_tl_has(type, "same_peer") ? 1 : 0;
        if (!pool_field(m, b, type, "query")) b->kind = EXTERIA_BUTTON_DISABLED;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeGame)) {
        b->kind = EXTERIA_BUTTON_GAME;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeBuy)) {
        b->kind = EXTERIA_BUTTON_BUY;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeCopy)) {
        b->kind = EXTERIA_BUTTON_COPY;
        if (!pool_field(m, b, type, "copy_text")) b->kind = EXTERIA_BUTTON_DISABLED;
    } else if (exteria_tl_is(type, EXTERIA_TL_ID_inlineButtonTypeUserProfile)) {
        b->kind = EXTERIA_BUTTON_USER_PROFILE;
        if (exteria_tl_get_i64(type, "user_id", &b->user_id) != EXTERIA_OK || b->user_id <= 0) b->kind = EXTERIA_BUTTON_DISABLED;
    }
}

static void read_style(const exteria_tl_value *button, exteria_markup_button *b) {
    const exteria_tl_value *style = exteria_tl_get(button, "style");
    if (!exteria_tl_is(style, EXTERIA_TL_ID_keyboardButtonStyle)) return;
    if (exteria_tl_has(style, "bg_danger")) b->style = EXTERIA_BUTTON_STYLE_DANGER;
    else if (exteria_tl_has(style, "bg_success")) b->style = EXTERIA_BUTTON_STYLE_SUCCESS;
    else if (exteria_tl_has(style, "bg_primary")) b->style = EXTERIA_BUTTON_STYLE_PRIMARY;
    exteria_tl_get_i64(style, "icon", &b->icon);
}

static void read_rows(exteria_markup *m, const exteria_tl_value *rows, int inline_buttons) {
    uint32_t r, i;
    if (!is_vec(rows)) return;
    for (r = 0; r < rows->u.vec.count && m->row_count < EXTERIA_MARKUP_ROWS_MAX; ++r) {
        const exteria_tl_value *buttons = exteria_tl_get(rows->u.vec.items[r], "buttons");
        uint8_t in_row = 0;
        if (!is_vec(buttons)) continue;
        for (i = 0; i < buttons->u.vec.count && in_row < EXTERIA_MARKUP_ROW_MAX && m->button_count < EXTERIA_MARKUP_BUTTONS_MAX; ++i) {
            const exteria_tl_value *button = buttons->u.vec.items[i];
            exteria_markup_button *b = &m->buttons[m->button_count];
            const exteria_tl_value *type;
            if (!exteria_tl_is(button, inline_buttons ? EXTERIA_TL_ID_keyboardInlineButton : EXTERIA_TL_ID_keyboardButton)) continue;
            memset(b, 0, sizeof(*b));
            copy_field(b->text, sizeof(b->text), button, "text");
            read_style(button, b);
            type = exteria_tl_get(button, "type");
            if (inline_buttons) read_inline_type(m, b, type);
            else read_keyboard_type(b, type);
            ++m->button_count;
            ++in_row;
        }
        if (in_row) m->row_size[m->row_count++] = in_row;
    }
}

exteria_status exteria_markup_read(const exteria_tl_value *markup, exteria_markup *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!markup) return EXTERIA_OK;
    if (markup->kind != EXTERIA_TL_V_OBJ) return EXTERIA_E_MALFORMED;
    if (exteria_tl_is(markup, EXTERIA_TL_ID_replyKeyboardHide)) {
        out->kind = EXTERIA_MARKUP_HIDE;
        out->selective = exteria_tl_has(markup, "selective") ? 1 : 0;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(markup, EXTERIA_TL_ID_replyKeyboardForceReply)) {
        out->kind = EXTERIA_MARKUP_FORCE_REPLY;
        out->single_use = exteria_tl_has(markup, "single_use") ? 1 : 0;
        out->selective = exteria_tl_has(markup, "selective") ? 1 : 0;
        copy_field(out->placeholder, sizeof(out->placeholder), markup, "placeholder");
        return EXTERIA_OK;
    }
    if (exteria_tl_is(markup, EXTERIA_TL_ID_replyKeyboardMarkup)) {
        out->kind = EXTERIA_MARKUP_KEYBOARD;
        out->resize = exteria_tl_has(markup, "resize") ? 1 : 0;
        out->single_use = exteria_tl_has(markup, "single_use") ? 1 : 0;
        out->selective = exteria_tl_has(markup, "selective") ? 1 : 0;
        out->persistent = exteria_tl_has(markup, "persistent") ? 1 : 0;
        copy_field(out->placeholder, sizeof(out->placeholder), markup, "placeholder");
        read_rows(out, exteria_tl_get(markup, "rows"), 0);
        if (!out->button_count) out->kind = EXTERIA_MARKUP_NONE;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(markup, EXTERIA_TL_ID_replyInlineMarkup)) {
        out->kind = EXTERIA_MARKUP_INLINE;
        read_rows(out, exteria_tl_get(markup, "rows"), 1);
        if (!out->button_count) out->kind = EXTERIA_MARKUP_NONE;
        return EXTERIA_OK;
    }
    return EXTERIA_E_UNSUPPORTED;
}

const char *exteria_markup_arg(const exteria_markup *markup, const exteria_markup_button *button) {
    if (!markup || !button || button->arg_length == 0) return "";
    return markup->pool + button->arg_offset;
}

static double round_half_up(double v) {
    return floor(v + 0.5);
}

exteria_status exteria_markup_layout(const uint8_t *row_size, size_t row_count, double width, double row_height, double gap,
                                     exteria_rect *frames, size_t cap, double *height) {
    size_t at = 0, r, total = 0;
    if (height) *height = 0;
    if (!frames || !height || (row_count && !row_size) || !(width > 0) || !(row_height > 0) || gap < 0) return EXTERIA_E_ARG;
    for (r = 0; r < row_count; ++r) {
        if (row_size[r] == 0) return EXTERIA_E_MALFORMED;
        total += row_size[r];
    }
    if (cap < total) return EXTERIA_E_ARG;
    for (r = 0; r < row_count; ++r) {
        unsigned n = row_size[r], k;
        double y = (double)r * (row_height + gap);
        double unit = (width - gap * (double)(n - 1)) / (double)n;
        if (!(unit > 0)) return EXTERIA_E_LIMIT;
        for (k = 0; k < n; ++k) {
            double left = round_half_up((double)k * (unit + gap));
            double right = round_half_up((double)k * (unit + gap) + unit);
            frames[at].x = left;
            frames[at].y = y;
            frames[at].width = right - left;
            frames[at].height = row_height;
            ++at;
        }
    }
    if (row_count) *height = (double)row_count * row_height + (double)(row_count - 1) * gap;
    return EXTERIA_OK;
}
