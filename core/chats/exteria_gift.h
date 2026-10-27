#ifndef EXTERIA_GIFT_H
#define EXTERIA_GIFT_H

#include <stdint.h>

#include "exteria_media.h"
#include "exteria_tl.h"

#define EXTERIA_GIFT_TITLE_MAX 64
#define EXTERIA_GIFT_SLUG_MAX 64
#define EXTERIA_GIFT_ATTR_MAX 48

/* a StarGift of either kind: a catalog gift sold for stars, or a unique one that was upgraded and has a number,
   a model, a pattern and a backdrop */
typedef struct exteria_gift {
    int64_t id;
    int64_t catalog_id;         /* the id of the catalog gift a unique one came from, id otherwise */
    uint8_t unique;
    uint8_t limited;
    uint8_t sold_out;
    uint8_t birthday;
    uint8_t require_premium;
    uint8_t auction;            /* sold by bidding, which this client does not do */
    uint8_t has_backdrop;
    int64_t stars;              /* price of a catalog gift */
    int64_t convert_stars;      /* what the receiver gets when turning it into stars */
    int64_t upgrade_stars;      /* price of the upgrade to a unique gift, zero when it cannot be upgraded */
    int32_t remains;            /* a limited gift: left to sell; a unique one: the copies made so far */
    int32_t total;
    int32_t num;                /* the number of a unique gift */
    uint32_t backdrop_center;   /* 0xRRGGBB */
    uint32_t backdrop_edge;
    uint32_t backdrop_text;
    uint32_t backdrop_pattern;  /* the color the pattern symbols are drawn in */
    int32_t model_permille;     /* how rare each attribute is, in thousandths; zero when the server named a rank or nothing */
    int32_t pattern_permille;
    int32_t backdrop_permille;
    int64_t owner_id;           /* the user a unique gift belongs to, zero when unknown */
    exteria_media_info sticker; /* the animated picture; the model of a unique gift */
    exteria_media_info pattern_sticker; /* the symbol repeated over the backdrop of a unique gift */
    char title[EXTERIA_GIFT_TITLE_MAX];
    char slug[EXTERIA_GIFT_SLUG_MAX];
    char model[EXTERIA_GIFT_ATTR_MAX];
    char pattern[EXTERIA_GIFT_ATTR_MAX];
    char backdrop[EXTERIA_GIFT_ATTR_MAX];
    char owner_name[EXTERIA_GIFT_TITLE_MAX];
} exteria_gift;

/* reads a starGift or starGiftUnique; a gift without an id, a price, or (unique) a title is EXTERIA_E_MALFORMED;
   its picture may be missing, then sticker has no source. out is always initialised */
exteria_status exteria_gift_read(const exteria_tl_value *gift, exteria_gift *out);

#endif
