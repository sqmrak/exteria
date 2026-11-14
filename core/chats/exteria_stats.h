#ifndef EXTERIA_STATS_H
#define EXTERIA_STATS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_messages.h"
#include "exteria_tl.h"

/* the statistics of one channel post: two graphs and the public channels that forwarded it. The graphs come as JSON
   text from the server (its own chart format), so every size below is a hard cap on what a hostile or broken answer
   can make the app allocate */

#define EXTERIA_CHART_POINTS_MAX 1024
#define EXTERIA_CHART_LINES_MAX 16
#define EXTERIA_CHART_NAME_MAX 64
#define EXTERIA_STATS_TOKEN_MAX 256
#define EXTERIA_STATS_ERROR_MAX 160
#define EXTERIA_PUBLIC_FORWARDS_PAGE 30
#define EXTERIA_STATS_OFFSET_MAX 256

typedef enum exteria_chart_kind {
    EXTERIA_CHART_LINE = 1,
    EXTERIA_CHART_BAR,
    EXTERIA_CHART_AREA,
    EXTERIA_CHART_STEP
} exteria_chart_kind;

typedef struct exteria_chart_line {
    char name[EXTERIA_CHART_NAME_MAX];
    uint32_t color;         /* 0xRRGGBB */
    uint8_t kind;           /* exteria_chart_kind */
    int64_t *y;             /* chart.points values */
} exteria_chart_line;

/* one chart: x holds unix milliseconds, each line one value per x */
typedef struct exteria_chart {
    uint32_t points;
    uint32_t line_count;
    int64_t *x;
    exteria_chart_line lines[EXTERIA_CHART_LINES_MAX];
    uint8_t stacked;        /* the lines add up to the height of the bar */
    uint8_t percentage;     /* the lines are shares of a whole */
} exteria_chart;

/* parses the JSON a statsGraph carries; EXTERIA_E_MALFORMED for a document that is not a chart this reader knows, EXTERIA_E_LIMIT for one
   past the caps above. *out is NULL unless the answer is EXTERIA_OK, and then it is owned by the caller */
exteria_status exteria_chart_parse(const char *json, size_t len, exteria_chart **out);
void exteria_chart_free(exteria_chart *chart);

typedef enum exteria_graph_kind {
    EXTERIA_GRAPH_NONE = 0,
    EXTERIA_GRAPH_JSON,     /* chart is set; zoom_token, when not empty, loads the same range at a finer step */
    EXTERIA_GRAPH_ASYNC,    /* token loads the graph with stats.loadAsyncGraph */
    EXTERIA_GRAPH_ERROR     /* the server says why it has no graph */
} exteria_graph_kind;

typedef struct exteria_stats_graph {
    exteria_graph_kind kind;
    exteria_chart *chart;
    char token[EXTERIA_STATS_TOKEN_MAX];
    char zoom_token[EXTERIA_STATS_TOKEN_MAX];
    char error[EXTERIA_STATS_ERROR_MAX];
} exteria_stats_graph;

void exteria_stats_graph_free(exteria_stats_graph *graph);
/* one StatsGraph object; out is always initialised */
exteria_status exteria_stats_graph_read(const exteria_tl_value *value, exteria_stats_graph *out);

/* channels.getFullChannel's answer: the data center that keeps the statistics (zero when the answer names none) and whether the
   account may read them */
exteria_status exteria_channel_stats_read(const exteria_tl_value *answer, int32_t *stats_dc, int *can_view);

/* stats.getMessageStats for a post of a channel; peer must be a channel with its access hash */
exteria_status exteria_message_stats_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t message_id, exteria_tl_value **out);
/* a stats.messageStats: the graph of views and shares, and the graph of reactions by emotion */
exteria_status exteria_message_stats_read(const exteria_tl_value *answer, exteria_stats_graph *views, exteria_stats_graph *reactions);
/* stats.loadAsyncGraph; with_x asks for the finer step around the x (milliseconds) of a zoom token */
exteria_status exteria_async_graph_request(exteria_arena *arena, const char *token, int with_x, int64_t x, exteria_tl_value **out);
/* the StatsGraph of the answer; EXTERIA_E_MALFORMED for anything else */
exteria_status exteria_async_graph_read(const exteria_tl_value *answer, exteria_stats_graph *out);

typedef struct exteria_public_forward {
    uint8_t story;          /* a story of the channel, not a post */
    int32_t peer_kind;      /* where it was forwarded to, as exteria_peer */
    int64_t peer_id;
    int32_t item_id;        /* the message or story id there */
    int32_t date;           /* unix seconds */
    int32_t views;          /* zero when the server counts none */
} exteria_public_forward;

exteria_status exteria_public_forwards_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t message_id,
                                               const char *offset, exteria_tl_value **out);
/* the rows of a stats.publicForwards page, at most capacity of them; total is its count field (at least the rows), next the offset of the
   following page, empty at the end. an entry that is neither a message nor a story is skipped */
exteria_status exteria_public_forwards_parse(const exteria_tl_value *answer, exteria_public_forward *rows, size_t capacity, size_t *count,
                                             int32_t *total, char *next, size_t next_capacity);

#endif
