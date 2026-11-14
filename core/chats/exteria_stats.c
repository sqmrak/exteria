#include "exteria_stats.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exteria_store.h"
#include "exteria_tgc_json.h"
#include "exteria_tl_ids.h"

void exteria_chart_free(exteria_chart *chart) {
    uint32_t i;
    if (!chart) return;
    for (i = 0; i < EXTERIA_CHART_LINES_MAX; ++i) free(chart->lines[i].y);
    free(chart->x);
    free(chart);
}

/* the text of a string member, NULL when it is missing or something else */
static const char *member_text(const exteria_json *object, const char *key, size_t *len) {
    return exteria_json_string(exteria_json_get(object, key), len);
}

static int member_flag(const exteria_json *object, const char *key) {
    int value = 0;
    const exteria_json *node = exteria_json_get(object, key);
    return node && exteria_json_bool(node, &value) == EXTERIA_OK && value;
}

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* the server writes colors as #rrggbb; anything else keeps the neutral gray */
static uint32_t read_color(const exteria_json *colors, const char *id) {
    size_t len;
    const char *text = member_text(colors, id, &len);
    uint32_t value = 0;
    size_t i;
    if (!text || len != 7 || text[0] != '#') return 0x8e8e93u;
    for (i = 1; i < 7; ++i) {
        int digit = hex_digit(text[i]);
        if (digit < 0) return 0x8e8e93u;
        value = (value << 4) | (uint32_t)digit;
    }
    return value;
}

static int kind_of(const char *name) {
    if (!strcmp(name, "line")) return EXTERIA_CHART_LINE;
    if (!strcmp(name, "bar")) return EXTERIA_CHART_BAR;
    if (!strcmp(name, "area")) return EXTERIA_CHART_AREA;
    if (!strcmp(name, "step")) return EXTERIA_CHART_STEP;
    return 0;
}

/* the numbers of a column after its id, into a fresh array of exactly that many */
static exteria_status read_values(const exteria_json *column, uint32_t *count, int64_t **out) {
    size_t total = exteria_json_count(column);
    const exteria_json *item;
    int64_t *values;
    uint32_t n = 0;
    *out = NULL;
    if (total < 2) return EXTERIA_E_MALFORMED;
    if (total - 1 > EXTERIA_CHART_POINTS_MAX) return EXTERIA_E_LIMIT;
    values = calloc(total - 1, sizeof(*values));
    if (!values) return EXTERIA_E_NOMEM;
    for (item = exteria_json_next(exteria_json_first(column)); item; item = exteria_json_next(item)) {
        if (exteria_json_int(item, &values[n]) != EXTERIA_OK) {
            free(values);
            return EXTERIA_E_MALFORMED;
        }
        ++n;
    }
    *count = n;
    *out = values;
    return EXTERIA_OK;
}

exteria_status exteria_chart_parse(const char *json, size_t len, exteria_chart **out) {
    exteria_json_doc *doc = NULL;
    const exteria_json *root, *columns, *types, *names, *colors, *column;
    exteria_chart *chart;
    exteria_status status;
    uint32_t line_points[EXTERIA_CHART_LINES_MAX];
    uint32_t i;
    char x_id[32] = "x";
    if (out) *out = NULL;
    if (!json || !out || !len) return EXTERIA_E_ARG;
    status = exteria_json_parse(json, len, &doc);
    if (status != EXTERIA_OK) return status == EXTERIA_E_LIMIT ? EXTERIA_E_LIMIT : EXTERIA_E_MALFORMED;
    root = exteria_json_root(doc);
    columns = exteria_json_get(root, "columns");
    types = exteria_json_get(root, "types");
    names = exteria_json_get(root, "names");
    colors = exteria_json_get(root, "colors");
    if (exteria_json_kind(columns) != EXTERIA_JSON_ARRAY || exteria_json_kind(types) != EXTERIA_JSON_OBJECT) {
        exteria_json_free(doc);
        return EXTERIA_E_MALFORMED;
    }
    chart = calloc(1, sizeof(*chart));
    if (!chart) {
        exteria_json_free(doc);
        return EXTERIA_E_NOMEM;
    }
    /* the type "x" marks the column of the time axis, whatever id it has */
    for (column = exteria_json_first(types); column; column = exteria_json_next(column)) {
        const char *kind = exteria_json_string(column, NULL), *key = exteria_json_key(column);
        if (kind && key && !strcmp(kind, "x") && strlen(key) < sizeof(x_id)) {
            strcpy(x_id, key);
            break;
        }
    }
    status = EXTERIA_OK;
    for (column = exteria_json_first(columns); column && status == EXTERIA_OK; column = exteria_json_next(column)) {
        const char *id, *name, *kind_text;
        size_t name_len;
        uint32_t n = 0;
        int64_t *values = NULL;
        int kind;
        if (exteria_json_kind(column) != EXTERIA_JSON_ARRAY) { status = EXTERIA_E_MALFORMED; break; }
        id = exteria_json_string(exteria_json_first(column), NULL);
        if (!id) { status = EXTERIA_E_MALFORMED; break; }
        status = read_values(column, &n, &values);
        if (status != EXTERIA_OK) break;
        if (!strcmp(id, x_id)) {
            if (chart->x) status = EXTERIA_E_MALFORMED;
            else { chart->x = values; chart->points = n; values = NULL; }
            free(values);
            continue;
        }
        kind_text = member_text(types, id, NULL);
        kind = kind_text ? kind_of(kind_text) : 0;
        if (!kind || chart->line_count >= EXTERIA_CHART_LINES_MAX) {
            free(values);
            status = kind ? EXTERIA_E_LIMIT : EXTERIA_E_MALFORMED;
            break;
        }
        line_points[chart->line_count] = n;
        chart->lines[chart->line_count].y = values;
        chart->lines[chart->line_count].kind = (uint8_t)kind;
        chart->lines[chart->line_count].color = read_color(colors, id);
        name = member_text(names, id, &name_len);
        snprintf(chart->lines[chart->line_count].name, sizeof(chart->lines[0].name), "%s", name && name_len ? name : id);
        ++chart->line_count;
    }
    if (status == EXTERIA_OK && (!chart->x || !chart->line_count)) status = EXTERIA_E_MALFORMED;
    /* a series that is shorter or longer than the time axis would be read past its end */
    for (i = 0; status == EXTERIA_OK && i < chart->line_count; ++i) {
        if (line_points[i] != chart->points) status = EXTERIA_E_MALFORMED;
    }
    if (status == EXTERIA_OK) {
        chart->stacked = member_flag(root, "stacked") ? 1 : 0;
        chart->percentage = member_flag(root, "percentage") ? 1 : 0;
    }
    exteria_json_free(doc);
    if (status != EXTERIA_OK) {
        exteria_chart_free(chart);
        return status;
    }
    *out = chart;
    return EXTERIA_OK;
}

void exteria_stats_graph_free(exteria_stats_graph *graph) {
    if (!graph) return;
    exteria_chart_free(graph->chart);
    memset(graph, 0, sizeof(*graph));
}

static exteria_status copy_text(const exteria_tl_value *value, const char *field, char *out, size_t capacity) {
    const uint8_t *data;
    size_t len;
    if (exteria_tl_get_bytes(value, field, &data, &len) != EXTERIA_OK || !data || len >= capacity || memchr(data, 0, len)) return EXTERIA_E_MALFORMED;
    memcpy(out, data, len);
    out[len] = 0;
    return EXTERIA_OK;
}

exteria_status exteria_stats_graph_read(const exteria_tl_value *value, exteria_stats_graph *out) {
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (exteria_tl_is(value, EXTERIA_TL_ID_statsGraphAsync)) {
        if (copy_text(value, "token", out->token, sizeof(out->token)) != EXTERIA_OK || !out->token[0]) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        out->kind = EXTERIA_GRAPH_ASYNC;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(value, EXTERIA_TL_ID_statsGraphError)) {
        if (copy_text(value, "error", out->error, sizeof(out->error)) != EXTERIA_OK) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        out->kind = EXTERIA_GRAPH_ERROR;
        return EXTERIA_OK;
    }
    if (exteria_tl_is(value, EXTERIA_TL_ID_statsGraph)) {
        const exteria_tl_value *json = exteria_tl_get(value, "json");
        const uint8_t *data;
        size_t len;
        exteria_status status;
        if (!exteria_tl_is(json, EXTERIA_TL_ID_dataJSON) || exteria_tl_get_bytes(json, "data", &data, &len) != EXTERIA_OK || !data) return EXTERIA_E_MALFORMED;
        if (exteria_tl_has(value, "zoom_token") && copy_text(value, "zoom_token", out->zoom_token, sizeof(out->zoom_token)) != EXTERIA_OK) {
            memset(out, 0, sizeof(*out));
            return EXTERIA_E_MALFORMED;
        }
        status = exteria_chart_parse((const char *)data, len, &out->chart);
        if (status != EXTERIA_OK) {
            memset(out, 0, sizeof(*out));
            return status;
        }
        out->kind = EXTERIA_GRAPH_JSON;
        return EXTERIA_OK;
    }
    return EXTERIA_E_MALFORMED;
}

exteria_status exteria_channel_stats_read(const exteria_tl_value *answer, int32_t *stats_dc, int *can_view) {
    const exteria_tl_value *full;
    if (!stats_dc || !can_view) return EXTERIA_E_ARG;
    *stats_dc = 0;
    *can_view = 0;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_messages_chatFull)) return EXTERIA_E_MALFORMED;
    full = exteria_tl_get(answer, "full_chat");
    if (!exteria_tl_is(full, EXTERIA_TL_ID_channelFull)) return EXTERIA_E_MALFORMED;
    *can_view = exteria_tl_has(full, "can_view_stats") ? 1 : 0;
    if (exteria_tl_has(full, "stats_dc")) {
        if (exteria_tl_get_i32(full, "stats_dc", stats_dc) != EXTERIA_OK || *stats_dc <= 0) {
            *stats_dc = 0;
            *can_view = 0;
            return EXTERIA_E_MALFORMED;
        }
    }
    return EXTERIA_OK;
}

static exteria_status input_channel(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out) {
    exteria_tl_value *channel;
    exteria_status status;
    if (!peer || peer->kind != 3 || peer->id <= 0) return EXTERIA_E_ARG;
    channel = exteria_tl_new_obj(arena, "inputChannel");
    if (!channel) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_i64(arena, channel, "channel_id", peer->id);
    if (status == EXTERIA_OK) status = exteria_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
    if (status == EXTERIA_OK) *out = channel;
    return status;
}

exteria_status exteria_message_stats_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t message_id, exteria_tl_value **out) {
    exteria_tl_value *request, *input = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0) return EXTERIA_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "stats.getMessageStats");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_message_stats_read(const exteria_tl_value *answer, exteria_stats_graph *views, exteria_stats_graph *reactions) {
    exteria_status status;
    if (!views || !reactions) return EXTERIA_E_ARG;
    memset(views, 0, sizeof(*views));
    memset(reactions, 0, sizeof(*reactions));
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stats_messageStats)) return EXTERIA_E_MALFORMED;
    status = exteria_stats_graph_read(exteria_tl_get(answer, "views_graph"), views);
    if (status != EXTERIA_OK) return status;
    status = exteria_stats_graph_read(exteria_tl_get(answer, "reactions_by_emotion_graph"), reactions);
    if (status != EXTERIA_OK) exteria_stats_graph_free(views);
    return status;
}

exteria_status exteria_async_graph_request(exteria_arena *arena, const char *token, int with_x, int64_t x, exteria_tl_value **out) {
    exteria_tl_value *request;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || !token || !token[0] || strlen(token) >= EXTERIA_STATS_TOKEN_MAX) return EXTERIA_E_ARG;
    request = exteria_tl_new_obj(arena, "stats.loadAsyncGraph");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set_str(arena, request, "token", token);
    if (status == EXTERIA_OK && with_x) status = exteria_tl_set_i64(arena, request, "x", x);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_async_graph_read(const exteria_tl_value *answer, exteria_stats_graph *out) {
    return exteria_stats_graph_read(answer, out);
}

exteria_status exteria_public_forwards_request(exteria_arena *arena, const exteria_peer_ref *channel, int32_t message_id,
                                               const char *offset, exteria_tl_value **out) {
    exteria_tl_value *request, *input = NULL;
    exteria_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0 || (offset && strlen(offset) >= EXTERIA_STATS_OFFSET_MAX)) return EXTERIA_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != EXTERIA_OK) return status;
    request = exteria_tl_new_obj(arena, "stats.getMessagePublicForwards");
    if (!request) return EXTERIA_E_NOMEM;
    status = exteria_tl_set(request, "channel", input);
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == EXTERIA_OK) status = exteria_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == EXTERIA_OK) status = exteria_tl_set_i32(arena, request, "limit", EXTERIA_PUBLIC_FORWARDS_PAGE);
    if (status == EXTERIA_OK) *out = request;
    return status;
}

exteria_status exteria_public_forwards_parse(const exteria_tl_value *answer, exteria_public_forward *rows, size_t capacity, size_t *count,
                                             int32_t *total, char *next, size_t next_capacity) {
    const exteria_tl_value *items;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (total) *total = 0;
    if (next && next_capacity) next[0] = 0;
    if (!rows || !capacity || !count || !total || !next || !next_capacity) return EXTERIA_E_ARG;
    if (!exteria_tl_is(answer, EXTERIA_TL_ID_stats_publicForwards) || exteria_tl_get_vec(answer, "forwards", &items) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    if (items->u.vec.count > capacity || items->u.vec.count > EXTERIA_PUBLIC_FORWARDS_PAGE) return EXTERIA_E_LIMIT;
    if (exteria_tl_has(answer, "next_offset") &&
        (copy_text(answer, "next_offset", next, next_capacity) != EXTERIA_OK || strlen(next) >= EXTERIA_STATS_OFFSET_MAX)) {
        next[0] = 0;
        return EXTERIA_E_MALFORMED;
    }
    for (i = 0; i < items->u.vec.count; ++i) {
        const exteria_tl_value *item = items->u.vec.items[i], *inner;
        exteria_public_forward row;
        exteria_peer peer;
        memset(&row, 0, sizeof(row));
        if (exteria_tl_is(item, EXTERIA_TL_ID_publicForwardMessage)) {
            inner = exteria_tl_get(item, "message");
            /* a deleted or inaccessible message arrives empty; there is nothing to show of it */
            if (!exteria_tl_is(inner, EXTERIA_TL_ID_message)) continue;
            if (exteria_peer_from_tl(exteria_tl_get(inner, "peer_id"), &peer) != EXTERIA_OK || peer.id <= 0 ||
                exteria_tl_get_i32(inner, "id", &row.item_id) != EXTERIA_OK || row.item_id <= 0 ||
                exteria_tl_get_i32(inner, "date", &row.date) != EXTERIA_OK || row.date < 0) {
                next[0] = 0;
                return EXTERIA_E_MALFORMED;
            }
            if (exteria_tl_has(inner, "views") && (exteria_tl_get_i32(inner, "views", &row.views) != EXTERIA_OK || row.views < 0)) {
                next[0] = 0;
                return EXTERIA_E_MALFORMED;
            }
        } else if (exteria_tl_is(item, EXTERIA_TL_ID_publicForwardStory)) {
            inner = exteria_tl_get(item, "story");
            if (!exteria_tl_is(inner, EXTERIA_TL_ID_storyItem)) continue;
            if (exteria_peer_from_tl(exteria_tl_get(item, "peer"), &peer) != EXTERIA_OK || peer.id <= 0 ||
                exteria_tl_get_i32(inner, "id", &row.item_id) != EXTERIA_OK || row.item_id <= 0 ||
                exteria_tl_get_i32(inner, "date", &row.date) != EXTERIA_OK || row.date < 0) {
                next[0] = 0;
                return EXTERIA_E_MALFORMED;
            }
            row.story = 1;
            if (exteria_tl_has(inner, "views")) {
                const exteria_tl_value *views = exteria_tl_get(inner, "views");
                if (exteria_tl_has(views, "views_count") && (exteria_tl_get_i32(views, "views_count", &row.views) != EXTERIA_OK || row.views < 0)) {
                    next[0] = 0;
                    return EXTERIA_E_MALFORMED;
                }
            }
        } else {
            continue;
        }
        row.peer_kind = peer.kind;
        row.peer_id = peer.id;
        rows[n++] = row;
    }
    *count = n;
    if (exteria_tl_get_i32(answer, "count", total) != EXTERIA_OK || *total < (int32_t)n) *total = (int32_t)n;
    return EXTERIA_OK;
}
