#ifndef EXTERIA_TL_H
#define EXTERIA_TL_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_arena.h"
#include "exteria_bytes.h"
#include "exteria_status.h"
#include "exteria_tl_schema.h"

typedef enum exteria_tl_vkind {
    EXTERIA_TL_V_I32 = 1,
    EXTERIA_TL_V_I64,
    EXTERIA_TL_V_F64,
    EXTERIA_TL_V_BYTES,
    EXTERIA_TL_V_TRUE,
    EXTERIA_TL_V_OBJ,
    EXTERIA_TL_V_VEC
} exteria_tl_vkind;

typedef struct exteria_tl_value exteria_tl_value;

struct exteria_tl_value {
    uint8_t kind;
    union {
        int32_t i32;
        int64_t i64;
        double f64;
        struct {
            const uint8_t *data;
            uint32_t len;
        } bytes;
        struct {
            const exteria_tl_ctor *ctor;
            exteria_tl_value **fields;
        } obj;
        struct {
            uint32_t count;
            exteria_tl_value **items;
        } vec;
    } u;
};

typedef struct exteria_tl_limits {
    uint32_t max_depth;
    uint32_t max_values;
    uint32_t max_inflate;
    int borrow_bytes;      /* borrowed values alias the packet, so its storage must outlive the arena */
} exteria_tl_limits;

extern const exteria_tl_limits exteria_tl_default_limits;

typedef struct exteria_tl_error {
    const char *ctor;
    const char *field;
} exteria_tl_error;

const exteria_tl_ctor *exteria_tl_find_ctor(uint32_t id);
const exteria_tl_ctor *exteria_tl_find_ctor_by_name(const char *name);
const exteria_tl_field *exteria_tl_ctor_fields(const exteria_tl_ctor *ctor);
int exteria_tl_field_index(const exteria_tl_ctor *ctor, const char *name);
const char *exteria_tl_result_type_name(const exteria_tl_ctor *ctor);

exteria_status exteria_tl_decode(exteria_arena *arena, const exteria_tl_limits *limits, uint16_t type_ref,
                                 const uint8_t *data, size_t len, size_t *consumed, exteria_tl_value **out);
exteria_status exteria_tl_decode_all(exteria_arena *arena, const exteria_tl_limits *limits, uint16_t type_ref,
                                     const uint8_t *data, size_t len, exteria_tl_value **out);

/* mtproto must dispatch the unpacked rpc envelope before decoding its request-specific result */
exteria_status exteria_tl_unpack_gzip(const uint8_t *data, size_t len, exteria_writer *out);

exteria_status exteria_tl_encode(const exteria_tl_value *value, exteria_writer *w, exteria_tl_error *error);
exteria_status exteria_tl_result_ref(const exteria_tl_value *request, uint16_t *ref);

exteria_tl_value *exteria_tl_new_i32(exteria_arena *a, int32_t v);
exteria_tl_value *exteria_tl_new_i64(exteria_arena *a, int64_t v);
exteria_tl_value *exteria_tl_new_f64(exteria_arena *a, double v);
exteria_tl_value *exteria_tl_new_bytes(exteria_arena *a, const void *data, size_t len);
exteria_tl_value *exteria_tl_new_str(exteria_arena *a, const char *s);
exteria_tl_value *exteria_tl_new_vec(exteria_arena *a, uint32_t count);
exteria_tl_value *exteria_tl_new_obj(exteria_arena *a, const char *ctor_name);
exteria_tl_value *exteria_tl_new_obj_ctor(exteria_arena *a, const exteria_tl_ctor *ctor);
exteria_status exteria_tl_vec_set(exteria_tl_value *vec, uint32_t index, exteria_tl_value *item);

exteria_status exteria_tl_set(exteria_tl_value *obj, const char *field, exteria_tl_value *value);
exteria_status exteria_tl_set_i32(exteria_arena *a, exteria_tl_value *obj, const char *field, int32_t v);
exteria_status exteria_tl_set_i64(exteria_arena *a, exteria_tl_value *obj, const char *field, int64_t v);
exteria_status exteria_tl_set_f64(exteria_arena *a, exteria_tl_value *obj, const char *field, double v);
exteria_status exteria_tl_set_bytes(exteria_arena *a, exteria_tl_value *obj, const char *field, const void *data, size_t len);
exteria_status exteria_tl_set_str(exteria_arena *a, exteria_tl_value *obj, const char *field, const char *s);
exteria_status exteria_tl_set_flag(exteria_tl_value *obj, const char *field);
exteria_status exteria_tl_set_i64_vec(exteria_arena *a, exteria_tl_value *obj, const char *field, const int64_t *v, uint32_t count);
exteria_status exteria_tl_set_i32_vec(exteria_arena *a, exteria_tl_value *obj, const char *field, const int32_t *v, uint32_t count);

const exteria_tl_value *exteria_tl_get(const exteria_tl_value *obj, const char *field);
uint32_t exteria_tl_id(const exteria_tl_value *obj);
int exteria_tl_is(const exteria_tl_value *obj, uint32_t id);
int exteria_tl_has(const exteria_tl_value *obj, const char *field);
exteria_status exteria_tl_get_i32(const exteria_tl_value *obj, const char *field, int32_t *out);
exteria_status exteria_tl_get_i64(const exteria_tl_value *obj, const char *field, int64_t *out);
exteria_status exteria_tl_get_f64(const exteria_tl_value *obj, const char *field, double *out);
exteria_status exteria_tl_get_bytes(const exteria_tl_value *obj, const char *field, const uint8_t **data, size_t *len);
exteria_status exteria_tl_get_obj(const exteria_tl_value *obj, const char *field, const exteria_tl_value **out);
exteria_status exteria_tl_get_vec(const exteria_tl_value *obj, const char *field, const exteria_tl_value **out);

/* bounded byte output keeps file parts from filling diagnostic logs */
exteria_status exteria_tl_dump(const exteria_tl_value *value, exteria_writer *w);

#endif
