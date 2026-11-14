#ifndef EXTERIA_THEME_LINK_H
#define EXTERIA_THEME_LINK_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_media.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* what a t.me/addtheme link names: account.getTheme on a slug, and the theme that comes back with its .tgios-theme file, or with colors only */

#define EXTERIA_THEME_SLUG_MAX 128
#define EXTERIA_THEME_TITLE_MAX 128

typedef struct exteria_theme_link_info {
    char title[EXTERIA_THEME_TITLE_MAX];
    /* the theme file of the ios format; has_file is zero for a theme that only carries accent colors (settings), which this client cannot apply */
    int has_file;
    exteria_media_info file;
    /* the first of the theme's settings: the base look (dark for the night and tinted bases) and the accent as 0xRRGGBB; has_colors is zero for a theme that has none */
    int has_colors;
    int dark;
    uint32_t accent;
} exteria_theme_link_info;

/* account.getTheme in the "ios" format for a slug (letters, digits, dash and underscore, 1 to 128); anything else is EXTERIA_E_ARG */
exteria_status exteria_theme_link_request(exteria_arena *arena, const char *slug, exteria_tl_value **out);

/* a Theme. a missing slug or title, or a document that is not a fetchable file, is EXTERIA_E_MALFORMED, with out zeroed; a long title is cut at a
   character boundary */
exteria_status exteria_theme_link_parse(const exteria_tl_value *answer, exteria_theme_link_info *out);

#endif
