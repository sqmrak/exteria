#ifndef EXTERIA_TGC_JSON_H
#define EXTERIA_TGC_JSON_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the JSON the tgcalls signaling speaks, read and written with hard bounds; the text comes from the other phone,
   so the depth, the number of values and the size of the text are all capped, and every string is checked to be
   UTF-8 */

#define EXTERIA_JSON_MAX_DEPTH 12
#define EXTERIA_JSON_MAX_TEXT (64u * 1024u)
#define EXTERIA_JSON_MAX_NODES 4096u

typedef enum exteria_json_type {
    EXTERIA_JSON_NULL,
    EXTERIA_JSON_BOOL,
    EXTERIA_JSON_NUMBER,
    EXTERIA_JSON_STRING,
    EXTERIA_JSON_ARRAY,
    EXTERIA_JSON_OBJECT
} exteria_json_type;

typedef struct exteria_json exteria_json;
typedef struct exteria_json_doc exteria_json_doc;

/* parses a whole document, which must be one value and nothing after it but white space */
exteria_status exteria_json_parse(const char *text, size_t len, exteria_json_doc **out);
void exteria_json_free(exteria_json_doc *doc);
const exteria_json *exteria_json_root(const exteria_json_doc *doc);

exteria_json_type exteria_json_kind(const exteria_json *node);

/* the last member of an object with that key, or NULL; also NULL when node is not an object */
const exteria_json *exteria_json_get(const exteria_json *object, const char *key);

/* array elements and object members in document order: first and next are NULL at the end, and for a node that holds none */
const exteria_json *exteria_json_first(const exteria_json *node);
const exteria_json *exteria_json_next(const exteria_json *node);
size_t exteria_json_count(const exteria_json *node);
/* the key of an object member, NULL for anything else */
const char *exteria_json_key(const exteria_json *node);

/* the string value, NUL terminated, with its length in bytes; NULL when node is not a string */
const char *exteria_json_string(const exteria_json *node, size_t *len);
/* an integral number that fits int64; EXTERIA_E_MALFORMED for a fraction, an exponent form or a value out of range, and for a
   node that is no number */
exteria_status exteria_json_int(const exteria_json *node, int64_t *out);
exteria_status exteria_json_bool(const exteria_json *node, int *out);

/* writing: values go to a buffer the caller owns, commas and the colons come by themselves; a failed step (a
   buffer too small, a misplaced call, a nesting too deep) sticks, and finish reports it */
typedef struct exteria_json_out {
    char *buf;
    size_t cap;
    size_t len;
    exteria_status status;
    int depth;
    uint8_t member_count[EXTERIA_JSON_MAX_DEPTH];
    uint8_t is_object[EXTERIA_JSON_MAX_DEPTH];
    uint8_t key_pending;
} exteria_json_out;

void exteria_json_out_init(exteria_json_out *out, char *buf, size_t cap);
void exteria_json_out_object(exteria_json_out *out);
void exteria_json_out_array(exteria_json_out *out);
void exteria_json_out_end(exteria_json_out *out);
/* the key of the next object member; the value follows in the next call */
void exteria_json_out_key(exteria_json_out *out, const char *key);
void exteria_json_out_string(exteria_json_out *out, const char *value);
void exteria_json_out_int(exteria_json_out *out, int64_t value);
void exteria_json_out_bool(exteria_json_out *out, int value);
/* EXTERIA_OK with the length (the text is NUL terminated) once exactly one value is complete */
exteria_status exteria_json_out_finish(exteria_json_out *out, size_t *len);

#endif
