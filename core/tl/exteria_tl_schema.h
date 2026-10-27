#ifndef EXTERIA_TL_SCHEMA_H
#define EXTERIA_TL_SCHEMA_H

#include <stdint.h>


typedef enum exteria_tl_kind {
    EXTERIA_TL_K_INT,
    EXTERIA_TL_K_LONG,
    EXTERIA_TL_K_DOUBLE,
    EXTERIA_TL_K_INT128,
    EXTERIA_TL_K_INT256,
    EXTERIA_TL_K_STRING,
    EXTERIA_TL_K_BYTES,
    EXTERIA_TL_K_TRUE,
    EXTERIA_TL_K_FLAGS,
    EXTERIA_TL_K_OBJECT,
    EXTERIA_TL_K_VECTOR,
    EXTERIA_TL_K_GENERIC
} exteria_tl_kind;

typedef struct exteria_tl_type {
    uint8_t kind;
    uint8_t bare;
    uint16_t arg;
} exteria_tl_type;

#define EXTERIA_TL_NO_FLAGS 255

typedef struct exteria_tl_field {
    const char *name;
    uint16_t type;
    uint8_t flags_field;
    uint8_t flag_bit;
} exteria_tl_field;

typedef struct exteria_tl_ctor {
    uint32_t id;
    uint16_t result;
    uint16_t type_name;
    uint32_t first_field;
    uint8_t field_count;
    uint8_t is_function;
    const char *name;
} exteria_tl_ctor;

#define EXTERIA_TL_REF_ANY 0

extern const uint32_t exteria_tl_layer;
extern const char *const exteria_tl_type_names[];
extern const uint32_t exteria_tl_type_name_count;
extern const exteria_tl_type exteria_tl_types[];
extern const uint32_t exteria_tl_type_count;
extern const int32_t exteria_tl_bare_ctor[];
extern const exteria_tl_field exteria_tl_fields[];
extern const uint32_t exteria_tl_field_count;
extern const exteria_tl_ctor exteria_tl_ctors[];
extern const uint32_t exteria_tl_ctor_count;
extern const uint32_t exteria_tl_ctors_by_name[];

#endif
