#ifndef EXTERIA_RICH_H
#define EXTERIA_RICH_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_media.h"
#include "exteria_messages.h"
#include "exteria_status.h"
#include "exteria_tl.h"

/* a richMessage (an article a bot or a Premium account sends) read into a flat, bounded list of blocks the app lays out top to bottom. a document past the
   bounds keeps what fit and says so in truncated */
#define EXTERIA_RICH_BLOCKS_MAX 512
#define EXTERIA_RICH_TEXT_MAX (64 * 1024)
#define EXTERIA_RICH_ENTITIES_MAX 2048
#define EXTERIA_RICH_URLS_MAX (16 * 1024)
#define EXTERIA_RICH_MEDIA_MAX 32
#define EXTERIA_RICH_TABLE_COLUMNS_MAX 16
#define EXTERIA_RICH_LABEL_MAX 16

typedef enum exteria_rich_kind {
    EXTERIA_RICH_PARAGRAPH = 1,
    EXTERIA_RICH_HEADING,      /* level 1 (title) to 6 */
    EXTERIA_RICH_SUBTITLE,     /* a subtitle or a kicker: smaller, in the secondary color */
    EXTERIA_RICH_PREFORMATTED, /* code or a formula source, in a fixed font */
    EXTERIA_RICH_FOOTER,       /* a footer or the author line */
    EXTERIA_RICH_CAPTION,      /* the caption of the media, table or quote before it */
    EXTERIA_RICH_PULLQUOTE,
    EXTERIA_RICH_LIST_ITEM,    /* label holds the bullet, the number or the box */
    EXTERIA_RICH_DIVIDER,
    EXTERIA_RICH_MEDIA,        /* media indexes media: a photo, a video, or a map point with its zoom in level */
    EXTERIA_RICH_TABLE,        /* rows and columns of the cells that follow it; text is the title */
    EXTERIA_RICH_CELL,         /* row, column, colspan and rowspan inside the table before it */
    EXTERIA_RICH_DETAILS       /* the summary of a details block; its blocks follow one level deeper, and EXTERIA_RICH_OPEN says the author shows them at first */
} exteria_rich_kind;

enum {
    /* a list item */
    EXTERIA_RICH_CHECKBOX = 1,
    EXTERIA_RICH_CHECKED = 2,
    /* a details block */
    EXTERIA_RICH_OPEN = 1,
    /* a table */
    EXTERIA_RICH_BORDERED = 1,
    EXTERIA_RICH_STRIPED = 2,
    /* a cell */
    EXTERIA_RICH_HEADER_CELL = 1,
    EXTERIA_RICH_ALIGN_CENTER = 2,
    EXTERIA_RICH_ALIGN_RIGHT = 4
};

typedef struct exteria_rich_block {
    uint8_t kind;               /* exteria_rich_kind */
    uint8_t level;              /* the level of a heading, the zoom of a map */
    uint8_t indent;             /* how deep in lists and details the block stands */
    uint8_t quote;              /* how many quotes hold it; the app draws a bar for each */
    uint8_t flags;
    uint16_t row;               /* a cell's row, or the rows of a table */
    uint16_t column;            /* a cell's first column, or the columns of a table */
    uint16_t colspan;           /* a cell's columns, at least 1 */
    uint16_t rowspan;           /* a cell's rows, at least 1; the cells of the rows below skip the columns it covers */
    uint16_t media;             /* index into exteria_rich_doc.media */
    uint32_t text_offset;       /* UTF-8 bytes into exteria_rich_doc.text */
    uint32_t text_length;
    uint16_t entity_start;      /* the entities of the block text, offsets in UTF-16 units from its start */
    uint16_t entity_count;
    char label[EXTERIA_RICH_LABEL_MAX];
} exteria_rich_block;

typedef struct exteria_rich_doc {
    uint8_t rtl;
    uint8_t truncated;
    uint16_t block_count;
    uint16_t entity_count;
    uint16_t media_count;
    uint32_t text_length;
    uint32_t urls_length;
    exteria_rich_block blocks[EXTERIA_RICH_BLOCKS_MAX];
    exteria_entity entities[EXTERIA_RICH_ENTITIES_MAX]; /* url_offset points into urls */
    exteria_media_info media[EXTERIA_RICH_MEDIA_MAX];
    char text[EXTERIA_RICH_TEXT_MAX];
    char urls[EXTERIA_RICH_URLS_MAX];
} exteria_rich_doc;

/* reads the rich_message of a message; EXTERIA_E_NOTFOUND when the message has none, EXTERIA_E_MALFORMED when it has no block to show */
exteria_status exteria_rich_read(const exteria_tl_value *message, exteria_rich_doc *out);

#endif
