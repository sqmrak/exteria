#include "exteria_tl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <zlib.h>

#define TL_VECTOR_ID 0x1cb5c415u
#define TL_GZIP_ID 0x3072cfa1u

const exteria_tl_limits exteria_tl_default_limits = { 64u, 400000u, 16u * 1024u * 1024u, 0 };

static const exteria_tl_value tl_true_value = { EXTERIA_TL_V_TRUE, { 0 } };

static const exteria_tl_type *type_at(uint16_t ref) {
    return ref < exteria_tl_type_count ? &exteria_tl_types[ref] : NULL;
}

static int is_any_type(uint16_t type_name) {
    return type_name == exteria_tl_types[EXTERIA_TL_REF_ANY].arg;
}

const exteria_tl_ctor *exteria_tl_find_ctor(uint32_t id) {
    uint32_t lo = 0, hi = exteria_tl_ctor_count;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        uint32_t cur = exteria_tl_ctors[mid].id;
        if (cur == id) return &exteria_tl_ctors[mid];
        if (cur < id) lo = mid + 1;
        else hi = mid;
    }
    return NULL;
}

const exteria_tl_ctor *exteria_tl_find_ctor_by_name(const char *name) {
    uint32_t lo = 0, hi = exteria_tl_ctor_count;
    if (!name) return NULL;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        const exteria_tl_ctor *c = &exteria_tl_ctors[exteria_tl_ctors_by_name[mid]];
        int cmp = strcmp(c->name, name);
        if (cmp == 0) return c;
        if (cmp < 0) lo = mid + 1;
        else hi = mid;
    }
    return NULL;
}

const exteria_tl_field *exteria_tl_ctor_fields(const exteria_tl_ctor *ctor) {
    return &exteria_tl_fields[ctor->first_field];
}

int exteria_tl_field_index(const exteria_tl_ctor *ctor, const char *name) {
    const exteria_tl_field *f = exteria_tl_ctor_fields(ctor);
    unsigned i;
    if (!name) return -1;
    for (i = 0; i < ctor->field_count; ++i) {
        if (strcmp(f[i].name, name) == 0) return (int)i;
    }
    return -1;
}

const char *exteria_tl_result_type_name(const exteria_tl_ctor *ctor) {
    if (type_at(ctor->result)->kind != EXTERIA_TL_K_OBJECT) return NULL;
    return exteria_tl_type_names[ctor->type_name];
}

typedef struct dctx {
    exteria_arena *arena;
    exteria_tl_limits limits;
    uint32_t values;
    int in_gzip;
} dctx;

static exteria_tl_value *dnew(dctx *d, uint8_t kind) {
    exteria_tl_value *v;
    if (d->values >= d->limits.max_values) return NULL;
    v = (exteria_tl_value *)exteria_arena_alloc(d->arena, sizeof(*v));
    if (!v) return NULL;
    d->values++;
    v->kind = kind;
    return v;
}

static exteria_status read_string(exteria_reader *r, const uint8_t **data, uint32_t *len) {
    uint32_t n, total;
    uint8_t first = exteria_rd_u8(r);
    const uint8_t *p;
    if (r->status != EXTERIA_OK) return r->status;
    if (first < 254) {
        n = first;
        total = 1u + n;
    } else if (first == 254) {
        const uint8_t *b = exteria_rd_bytes(r, 3);
        if (!b) return r->status;
        n = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16);
        total = 4u + n;
    } else {
        return EXTERIA_E_MALFORMED;
    }
    p = exteria_rd_bytes(r, n);
    if (!p && n) return r->status;
    *data = p ? p : (const uint8_t *)"";
    *len = n;
    if (total % 4u) {
        if (!exteria_rd_bytes(r, 4u - total % 4u)) return r->status;
    }
    return EXTERIA_OK;
}

static exteria_status dec_type(dctx *d, exteria_reader *r, uint16_t ref, uint32_t depth, exteria_tl_value **out);

static exteria_status inflate_string(exteria_reader *r, exteria_writer *out) {
    const uint8_t *packed;
    uint32_t packed_len;
    uint8_t chunk[4096];
    z_stream zs;
    size_t mark = out->len;
    int zr;
    exteria_status s = read_string(r, &packed, &packed_len);
    if (s != EXTERIA_OK) return s;
    memset(&zs, 0, sizeof(zs));
    /* auto detection preserves the zlib framing accepted by the existing decoder */
    zr = inflateInit2(&zs, 15 + 32);
    if (zr != Z_OK) return zr == Z_MEM_ERROR ? EXTERIA_E_NOMEM : EXTERIA_E_MALFORMED;
    zs.next_in = (Bytef *)(uintptr_t)packed;
    zs.avail_in = packed_len;
    do {
        size_t got;
        zs.next_out = chunk;
        zs.avail_out = sizeof(chunk);
        zr = inflate(&zs, Z_NO_FLUSH);
        got = sizeof(chunk) - zs.avail_out;
        if (zr != Z_OK && zr != Z_STREAM_END) {
            s = zr == Z_MEM_ERROR ? EXTERIA_E_NOMEM : EXTERIA_E_MALFORMED;
            break;
        }
        s = exteria_wr_bytes(out, chunk, got);
        if (s != EXTERIA_OK) break;
        if (zr == Z_OK && zs.avail_in == 0 && zs.avail_out != 0) {
            s = EXTERIA_E_TRUNCATED;
            break;
        }
    } while (zr != Z_STREAM_END);
    /* a second stream or trailing data makes the packed body ambiguous */
    if (s == EXTERIA_OK && zs.avail_in != 0) s = EXTERIA_E_MALFORMED;
    inflateEnd(&zs);
    if (s != EXTERIA_OK) out->len = mark;
    return s;
}

exteria_status exteria_tl_unpack_gzip(const uint8_t *data, size_t len, exteria_writer *out) {
    exteria_reader r;
    size_t mark;
    exteria_status s;
    if (!data || !out) return EXTERIA_E_ARG;
    if (len < 4) return EXTERIA_E_TRUNCATED;
    exteria_reader_init(&r, data, len);
    if (exteria_rd_u32le(&r) != TL_GZIP_ID) return EXTERIA_E_MALFORMED;
    mark = out->len;
    s = inflate_string(&r, out);
    if (s == EXTERIA_OK && exteria_reader_left(&r) != 0) s = EXTERIA_E_MALFORMED;
    if (s != EXTERIA_OK) out->len = mark;
    return s;
}

static exteria_status dec_gzip(dctx *d, exteria_reader *r, uint16_t ref, uint32_t depth, exteria_tl_value **out) {
    exteria_writer plain;
    exteria_reader inner;
    dctx sub;
    uint8_t *kept;
    size_t len;
    exteria_status s;
    if (d->in_gzip) return EXTERIA_E_MALFORMED;
    exteria_writer_init(&plain, d->limits.max_inflate);
    s = inflate_string(r, &plain);
    if (s != EXTERIA_OK) {
        exteria_writer_free(&plain);
        return s;
    }
    len = plain.len;
    kept = (uint8_t *)exteria_arena_copy(d->arena, plain.data, len);
    exteria_writer_free(&plain);
    if (!kept) return EXTERIA_E_LIMIT;
    exteria_reader_init(&inner, kept, len);
    sub = *d;
    sub.in_gzip = 1;
    s = dec_type(&sub, &inner, ref, depth, out);
    d->values = sub.values;
    if (s != EXTERIA_OK) return s == EXTERIA_E_TRUNCATED ? EXTERIA_E_MALFORMED : s;
    if (exteria_reader_left(&inner) != 0) return EXTERIA_E_MALFORMED;
    return EXTERIA_OK;
}

static exteria_status dec_fields(dctx *d, exteria_reader *r, const exteria_tl_ctor *ctor, uint32_t depth,
                                 exteria_tl_value **out) {
    exteria_tl_value *v = dnew(d, EXTERIA_TL_V_OBJ);
    const exteria_tl_field *f = exteria_tl_ctor_fields(ctor);
    unsigned i;
    if (!v) return EXTERIA_E_LIMIT;
    v->u.obj.ctor = ctor;
    v->u.obj.fields = NULL;
    if (ctor->field_count) {
        v->u.obj.fields = (exteria_tl_value **)exteria_arena_alloc(d->arena, sizeof(exteria_tl_value *) * ctor->field_count);
        if (!v->u.obj.fields) return EXTERIA_E_LIMIT;
    }
    for (i = 0; i < ctor->field_count; ++i) {
        const exteria_tl_type *t = type_at(f[i].type);
        exteria_status s;
        if (f[i].flags_field != EXTERIA_TL_NO_FLAGS) {
            const exteria_tl_value *fv = v->u.obj.fields[f[i].flags_field];
            if (!fv || !((uint32_t)fv->u.i32 & (1u << f[i].flag_bit))) continue;
            if (t->kind == EXTERIA_TL_K_TRUE) {
                v->u.obj.fields[i] = (exteria_tl_value *)(uintptr_t)&tl_true_value;
                continue;
            }
        }
        s = dec_type(d, r, f[i].type, depth + 1, &v->u.obj.fields[i]);
        if (s != EXTERIA_OK) return s;
    }
    *out = v;
    return EXTERIA_OK;
}

static exteria_status dec_bytes_value(dctx *d, exteria_reader *r, size_t fixed, exteria_tl_value **out) {
    const uint8_t *p;
    uint32_t n;
    exteria_tl_value *v;
    exteria_status s;
    if (fixed) {
        p = exteria_rd_bytes(r, fixed);
        if (!p) return r->status;
        n = (uint32_t)fixed;
    } else {
        s = read_string(r, &p, &n);
        if (s != EXTERIA_OK) return s;
    }
    v = dnew(d, EXTERIA_TL_V_BYTES);
    if (!v) return EXTERIA_E_LIMIT;
    if (d->limits.borrow_bytes && !d->in_gzip) {
        v->u.bytes.data = p;
    } else {
        uint8_t *copy = (uint8_t *)exteria_arena_alloc(d->arena, (size_t)n + 1);
        if (!copy) return EXTERIA_E_LIMIT;
        if (n) memcpy(copy, p, n);
        v->u.bytes.data = copy;
    }
    v->u.bytes.len = n;
    *out = v;
    return EXTERIA_OK;
}

static exteria_status dec_object(dctx *d, exteria_reader *r, const exteria_tl_type *t, uint32_t depth,
                                 exteria_tl_value **out) {
    const exteria_tl_ctor *ctor;
    int any = is_any_type(t->arg);
    if (t->bare) {
        int32_t ci = exteria_tl_bare_ctor[t->arg];
        if (ci < 0) return EXTERIA_E_UNSUPPORTED;
        ctor = &exteria_tl_ctors[ci];
    } else {
        uint32_t id = exteria_rd_u32le(r);
        if (r->status != EXTERIA_OK) return r->status;
        if (id == TL_GZIP_ID) return dec_gzip(d, r, (uint16_t)(t - exteria_tl_types), depth, out);
        ctor = exteria_tl_find_ctor(id);
        if (!ctor) return EXTERIA_E_UNSUPPORTED;
        if (!any && (ctor->is_function || ctor->type_name != t->arg)) return EXTERIA_E_MALFORMED;
    }
    return dec_fields(d, r, ctor, depth, out);
}

static exteria_status dec_type(dctx *d, exteria_reader *r, uint16_t ref, uint32_t depth, exteria_tl_value **out) {
    const exteria_tl_type *t = type_at(ref);
    exteria_tl_value *v;
    if (!t) return EXTERIA_E_ARG;
    if (depth > d->limits.max_depth) return EXTERIA_E_LIMIT;
    switch (t->kind) {
    case EXTERIA_TL_K_INT:
    case EXTERIA_TL_K_FLAGS: {
        uint32_t x = exteria_rd_u32le(r);
        if (r->status != EXTERIA_OK) return r->status;
        v = dnew(d, EXTERIA_TL_V_I32);
        if (!v) return EXTERIA_E_LIMIT;
        v->u.i32 = (int32_t)x;
        *out = v;
        return EXTERIA_OK;
    }
    case EXTERIA_TL_K_LONG: {
        uint64_t x = exteria_rd_u64le(r);
        if (r->status != EXTERIA_OK) return r->status;
        v = dnew(d, EXTERIA_TL_V_I64);
        if (!v) return EXTERIA_E_LIMIT;
        v->u.i64 = (int64_t)x;
        *out = v;
        return EXTERIA_OK;
    }
    case EXTERIA_TL_K_DOUBLE: {
        uint64_t x = exteria_rd_u64le(r);
        double f;
        if (r->status != EXTERIA_OK) return r->status;
        v = dnew(d, EXTERIA_TL_V_F64);
        if (!v) return EXTERIA_E_LIMIT;
        memcpy(&f, &x, sizeof(f));
        v->u.f64 = f;
        *out = v;
        return EXTERIA_OK;
    }
    case EXTERIA_TL_K_INT128:
        return dec_bytes_value(d, r, 16, out);
    case EXTERIA_TL_K_INT256:
        return dec_bytes_value(d, r, 32, out);
    case EXTERIA_TL_K_STRING:
    case EXTERIA_TL_K_BYTES:
        return dec_bytes_value(d, r, 0, out);
    case EXTERIA_TL_K_TRUE:
        *out = (exteria_tl_value *)(uintptr_t)&tl_true_value;
        return EXTERIA_OK;
    case EXTERIA_TL_K_OBJECT:
        return dec_object(d, r, t, depth, out);
    case EXTERIA_TL_K_GENERIC:
        return dec_object(d, r, &exteria_tl_types[EXTERIA_TL_REF_ANY], depth, out);
    case EXTERIA_TL_K_VECTOR: {
        uint32_t count, i;
        if (!t->bare) {
            uint32_t id = exteria_rd_u32le(r);
            if (r->status != EXTERIA_OK) return r->status;
            if (id == TL_GZIP_ID) return dec_gzip(d, r, ref, depth, out);
            if (id != TL_VECTOR_ID) return EXTERIA_E_MALFORMED;
        }
        count = exteria_rd_u32le(r);
        if (r->status != EXTERIA_OK) return r->status;
        /* every element takes at least four bytes, this bounds the allocation by the input */
        if (count > exteria_reader_left(r) / 4u) return EXTERIA_E_MALFORMED;
        v = dnew(d, EXTERIA_TL_V_VEC);
        if (!v) return EXTERIA_E_LIMIT;
        v->u.vec.count = count;
        v->u.vec.items = NULL;
        if (count) {
            v->u.vec.items = (exteria_tl_value **)exteria_arena_alloc(d->arena, sizeof(exteria_tl_value *) * count);
            if (!v->u.vec.items) return EXTERIA_E_LIMIT;
        }
        for (i = 0; i < count; ++i) {
            exteria_status s = dec_type(d, r, t->arg, depth + 1, &v->u.vec.items[i]);
            if (s != EXTERIA_OK) return s;
        }
        *out = v;
        return EXTERIA_OK;
    }
    }
    return EXTERIA_E_UNSUPPORTED;
}

exteria_status exteria_tl_decode(exteria_arena *arena, const exteria_tl_limits *limits, uint16_t type_ref,
                                 const uint8_t *data, size_t len, size_t *consumed, exteria_tl_value **out) {
    dctx d;
    exteria_reader r;
    exteria_status s;
    if (out) *out = NULL;
    if (consumed) *consumed = 0;
    if (!arena || !out || (len && !data)) return EXTERIA_E_ARG;
    d.arena = arena;
    d.limits = limits ? *limits : exteria_tl_default_limits;
    d.values = 0;
    d.in_gzip = 0;
    exteria_reader_init(&r, data, len);
    s = dec_type(&d, &r, type_ref, 0, out);
    if (s != EXTERIA_OK) {
        *out = NULL;
        return s;
    }
    if (consumed) *consumed = r.pos;
    return EXTERIA_OK;
}

exteria_status exteria_tl_decode_all(exteria_arena *arena, const exteria_tl_limits *limits, uint16_t type_ref,
                                     const uint8_t *data, size_t len, exteria_tl_value **out) {
    size_t used = 0;
    exteria_status s = exteria_tl_decode(arena, limits, type_ref, data, len, &used, out);
    if (s != EXTERIA_OK) return s;
    if (used != len) {
        *out = NULL;
        return EXTERIA_E_MALFORMED;
    }
    return EXTERIA_OK;
}

#define ENC_MAX_DEPTH 96u

static exteria_status write_string(exteria_writer *w, const uint8_t *data, size_t len) {
    static const uint8_t zeros[4] = { 0, 0, 0, 0 };
    size_t total;
    exteria_status s;
    if (len >= 0x1000000u) return EXTERIA_E_LIMIT;
    if (len < 254) {
        s = exteria_wr_u8(w, (uint8_t)len);
        total = 1 + len;
    } else {
        uint8_t h[4];
        h[0] = 254;
        h[1] = (uint8_t)len;
        h[2] = (uint8_t)(len >> 8);
        h[3] = (uint8_t)(len >> 16);
        s = exteria_wr_bytes(w, h, 4);
        total = 4 + len;
    }
    if (s != EXTERIA_OK) return s;
    s = exteria_wr_bytes(w, data, len);
    if (s != EXTERIA_OK) return s;
    if (total % 4) return exteria_wr_bytes(w, zeros, 4 - total % 4);
    return EXTERIA_OK;
}

static exteria_status fail_at(exteria_tl_error *err, const exteria_tl_ctor *ctor, const char *field,
                              exteria_status s) {
    if (err) {
        err->ctor = ctor ? ctor->name : NULL;
        err->field = field;
    }
    return s;
}

static exteria_status enc_type(exteria_writer *w, const exteria_tl_value *v, uint16_t ref, uint32_t depth,
                               const exteria_tl_ctor *owner, const char *field, exteria_tl_error *err);

static exteria_status enc_object(exteria_writer *w, const exteria_tl_value *v, int boxed, uint32_t depth,
                                 exteria_tl_error *err) {
    const exteria_tl_ctor *ctor = v->u.obj.ctor;
    const exteria_tl_field *f = exteria_tl_ctor_fields(ctor);
    unsigned i, j;
    exteria_status s;
    if (depth > ENC_MAX_DEPTH) return fail_at(err, ctor, NULL, EXTERIA_E_LIMIT);
    if (boxed) {
        s = exteria_wr_u32le(w, ctor->id);
        if (s != EXTERIA_OK) return s;
    }
    for (i = 0; i < ctor->field_count; ++i) {
        const exteria_tl_type *t = type_at(f[i].type);
        const exteria_tl_value *fv = v->u.obj.fields[i];
        if (t->kind == EXTERIA_TL_K_FLAGS) {
            uint32_t word = 0;
            for (j = 0; j < ctor->field_count; ++j) {
                if (f[j].flags_field == i && v->u.obj.fields[j]) word |= 1u << f[j].flag_bit;
            }
            s = exteria_wr_u32le(w, word);
            if (s != EXTERIA_OK) return s;
            continue;
        }
        if (!fv) {
            if (f[i].flags_field != EXTERIA_TL_NO_FLAGS || t->kind == EXTERIA_TL_K_TRUE) continue;
            return fail_at(err, ctor, f[i].name, EXTERIA_E_ARG);
        }
        if (t->kind == EXTERIA_TL_K_TRUE) continue;
        s = enc_type(w, fv, f[i].type, depth + 1, ctor, f[i].name, err);
        if (s != EXTERIA_OK) return s;
    }
    return EXTERIA_OK;
}

static int value_fits(const exteria_tl_type *t, const exteria_tl_value *v) {
    switch (t->kind) {
    case EXTERIA_TL_K_INT:
    case EXTERIA_TL_K_FLAGS: return v->kind == EXTERIA_TL_V_I32;
    case EXTERIA_TL_K_LONG: return v->kind == EXTERIA_TL_V_I64;
    case EXTERIA_TL_K_DOUBLE: return v->kind == EXTERIA_TL_V_F64;
    case EXTERIA_TL_K_INT128: return v->kind == EXTERIA_TL_V_BYTES && v->u.bytes.len == 16;
    case EXTERIA_TL_K_INT256: return v->kind == EXTERIA_TL_V_BYTES && v->u.bytes.len == 32;
    case EXTERIA_TL_K_STRING:
    case EXTERIA_TL_K_BYTES: return v->kind == EXTERIA_TL_V_BYTES;
    case EXTERIA_TL_K_TRUE: return v->kind == EXTERIA_TL_V_TRUE;
    case EXTERIA_TL_K_OBJECT:
        if (v->kind != EXTERIA_TL_V_OBJ) return 0;
        if (is_any_type(t->arg)) return 1;
        return !v->u.obj.ctor->is_function && v->u.obj.ctor->type_name == t->arg;
    case EXTERIA_TL_K_VECTOR: return v->kind == EXTERIA_TL_V_VEC;
    case EXTERIA_TL_K_GENERIC: return v->kind == EXTERIA_TL_V_OBJ;
    }
    return 0;
}

static exteria_status enc_type(exteria_writer *w, const exteria_tl_value *v, uint16_t ref, uint32_t depth,
                               const exteria_tl_ctor *owner, const char *field, exteria_tl_error *err) {
    const exteria_tl_type *t = type_at(ref);
    exteria_status s;
    if (!t) return fail_at(err, owner, field, EXTERIA_E_ARG);
    if (depth > ENC_MAX_DEPTH) return fail_at(err, owner, field, EXTERIA_E_LIMIT);
    if (!value_fits(t, v)) return fail_at(err, owner, field, EXTERIA_E_ARG);
    switch (t->kind) {
    case EXTERIA_TL_K_INT:
    case EXTERIA_TL_K_FLAGS:
        return exteria_wr_u32le(w, (uint32_t)v->u.i32);
    case EXTERIA_TL_K_LONG:
        return exteria_wr_u64le(w, (uint64_t)v->u.i64);
    case EXTERIA_TL_K_DOUBLE: {
        uint64_t x;
        memcpy(&x, &v->u.f64, sizeof(x));
        return exteria_wr_u64le(w, x);
    }
    case EXTERIA_TL_K_INT128:
    case EXTERIA_TL_K_INT256:
        return exteria_wr_bytes(w, v->u.bytes.data, v->u.bytes.len);
    case EXTERIA_TL_K_STRING:
    case EXTERIA_TL_K_BYTES:
        return write_string(w, v->u.bytes.data, v->u.bytes.len);
    case EXTERIA_TL_K_TRUE:
        return EXTERIA_OK;
    case EXTERIA_TL_K_OBJECT:
        return enc_object(w, v, !t->bare, depth, err);
    case EXTERIA_TL_K_GENERIC:
        return enc_object(w, v, 1, depth, err);
    case EXTERIA_TL_K_VECTOR: {
        uint32_t i;
        if (!t->bare) {
            s = exteria_wr_u32le(w, TL_VECTOR_ID);
            if (s != EXTERIA_OK) return s;
        }
        s = exteria_wr_u32le(w, v->u.vec.count);
        if (s != EXTERIA_OK) return s;
        for (i = 0; i < v->u.vec.count; ++i) {
            if (!v->u.vec.items[i]) return fail_at(err, owner, field, EXTERIA_E_ARG);
            s = enc_type(w, v->u.vec.items[i], t->arg, depth + 1, owner, field, err);
            if (s != EXTERIA_OK) return s;
        }
        return EXTERIA_OK;
    }
    }
    return EXTERIA_E_UNSUPPORTED;
}

exteria_status exteria_tl_encode(const exteria_tl_value *value, exteria_writer *w, exteria_tl_error *error) {
    size_t mark;
    exteria_status s;
    if (error) {
        error->ctor = NULL;
        error->field = NULL;
    }
    if (!value || !w || value->kind != EXTERIA_TL_V_OBJ) return EXTERIA_E_ARG;
    mark = w->len;
    s = enc_object(w, value, 1, 0, error);
    /* a failed encode must not corrupt earlier requests in the writer */
    if (s != EXTERIA_OK && w->len > mark) w->len = mark;
    return s;
}

exteria_status exteria_tl_result_ref(const exteria_tl_value *request, uint16_t *ref) {
    unsigned guard;
    if (!request || !ref || request->kind != EXTERIA_TL_V_OBJ) return EXTERIA_E_ARG;
    for (guard = 0; guard < 16; ++guard) {
        const exteria_tl_ctor *ctor = request->u.obj.ctor;
        const exteria_tl_field *f = exteria_tl_ctor_fields(ctor);
        unsigned i;
        const exteria_tl_value *inner = NULL;
        if (!ctor->is_function) return EXTERIA_E_ARG;
        if (type_at(ctor->result)->kind != EXTERIA_TL_K_GENERIC) {
            *ref = ctor->result;
            return EXTERIA_OK;
        }
        for (i = 0; i < ctor->field_count; ++i) {
            if (type_at(f[i].type)->kind == EXTERIA_TL_K_GENERIC) inner = request->u.obj.fields[i];
        }
        if (!inner || inner->kind != EXTERIA_TL_V_OBJ) return EXTERIA_E_ARG;
        request = inner;
    }
    return EXTERIA_E_LIMIT;
}

static exteria_tl_value *new_value(exteria_arena *a, uint8_t kind) {
    exteria_tl_value *v = (exteria_tl_value *)exteria_arena_alloc(a, sizeof(*v));
    if (v) v->kind = kind;
    return v;
}

exteria_tl_value *exteria_tl_new_i32(exteria_arena *a, int32_t x) {
    exteria_tl_value *v = new_value(a, EXTERIA_TL_V_I32);
    if (v) v->u.i32 = x;
    return v;
}

exteria_tl_value *exteria_tl_new_i64(exteria_arena *a, int64_t x) {
    exteria_tl_value *v = new_value(a, EXTERIA_TL_V_I64);
    if (v) v->u.i64 = x;
    return v;
}

exteria_tl_value *exteria_tl_new_f64(exteria_arena *a, double x) {
    exteria_tl_value *v = new_value(a, EXTERIA_TL_V_F64);
    if (v) v->u.f64 = x;
    return v;
}

exteria_tl_value *exteria_tl_new_bytes(exteria_arena *a, const void *data, size_t len) {
    exteria_tl_value *v;
    uint8_t *copy;
    if (len > 0x7fffffffu || (len && !data)) return NULL;
    v = new_value(a, EXTERIA_TL_V_BYTES);
    copy = (uint8_t *)exteria_arena_alloc(a, len + 1);
    if (!v || !copy) return NULL;
    if (len) memcpy(copy, data, len);
    v->u.bytes.data = copy;
    v->u.bytes.len = (uint32_t)len;
    return v;
}

exteria_tl_value *exteria_tl_new_str(exteria_arena *a, const char *s) {
    if (!s) return NULL;
    return exteria_tl_new_bytes(a, s, strlen(s));
}

exteria_tl_value *exteria_tl_new_vec(exteria_arena *a, uint32_t count) {
    exteria_tl_value *v = new_value(a, EXTERIA_TL_V_VEC);
    if (!v) return NULL;
    v->u.vec.count = count;
    v->u.vec.items = NULL;
    if (count) {
        if (count > 0x10000000u) return NULL;
        v->u.vec.items = (exteria_tl_value **)exteria_arena_alloc(a, sizeof(exteria_tl_value *) * count);
        if (!v->u.vec.items) return NULL;
    }
    return v;
}

exteria_tl_value *exteria_tl_new_obj_ctor(exteria_arena *a, const exteria_tl_ctor *ctor) {
    exteria_tl_value *v;
    if (!ctor) return NULL;
    v = new_value(a, EXTERIA_TL_V_OBJ);
    if (!v) return NULL;
    v->u.obj.ctor = ctor;
    v->u.obj.fields = NULL;
    if (ctor->field_count) {
        v->u.obj.fields = (exteria_tl_value **)exteria_arena_alloc(a, sizeof(exteria_tl_value *) * ctor->field_count);
        if (!v->u.obj.fields) return NULL;
    }
    return v;
}

exteria_tl_value *exteria_tl_new_obj(exteria_arena *a, const char *ctor_name) {
    return exteria_tl_new_obj_ctor(a, exteria_tl_find_ctor_by_name(ctor_name));
}

exteria_status exteria_tl_vec_set(exteria_tl_value *vec, uint32_t index, exteria_tl_value *item) {
    if (!vec || vec->kind != EXTERIA_TL_V_VEC || !item || index >= vec->u.vec.count) return EXTERIA_E_ARG;
    vec->u.vec.items[index] = item;
    return EXTERIA_OK;
}

exteria_status exteria_tl_set(exteria_tl_value *obj, const char *field, exteria_tl_value *value) {
    const exteria_tl_field *f;
    int idx;
    if (!obj || obj->kind != EXTERIA_TL_V_OBJ || !value) return EXTERIA_E_ARG;
    idx = exteria_tl_field_index(obj->u.obj.ctor, field);
    if (idx < 0) return EXTERIA_E_NOTFOUND;
    f = &exteria_tl_ctor_fields(obj->u.obj.ctor)[idx];
    if (type_at(f->type)->kind == EXTERIA_TL_K_FLAGS) return EXTERIA_E_ARG;
    if (!value_fits(type_at(f->type), value)) return EXTERIA_E_ARG;
    obj->u.obj.fields[idx] = value;
    return EXTERIA_OK;
}

exteria_status exteria_tl_set_i32(exteria_arena *a, exteria_tl_value *obj, const char *field, int32_t x) {
    exteria_tl_value *v = exteria_tl_new_i32(a, x);
    return v ? exteria_tl_set(obj, field, v) : EXTERIA_E_NOMEM;
}

exteria_status exteria_tl_set_i64(exteria_arena *a, exteria_tl_value *obj, const char *field, int64_t x) {
    exteria_tl_value *v = exteria_tl_new_i64(a, x);
    return v ? exteria_tl_set(obj, field, v) : EXTERIA_E_NOMEM;
}

exteria_status exteria_tl_set_f64(exteria_arena *a, exteria_tl_value *obj, const char *field, double x) {
    exteria_tl_value *v = exteria_tl_new_f64(a, x);
    return v ? exteria_tl_set(obj, field, v) : EXTERIA_E_NOMEM;
}

exteria_status exteria_tl_set_bytes(exteria_arena *a, exteria_tl_value *obj, const char *field, const void *data, size_t len) {
    exteria_tl_value *v = exteria_tl_new_bytes(a, data, len);
    return v ? exteria_tl_set(obj, field, v) : EXTERIA_E_NOMEM;
}

exteria_status exteria_tl_set_str(exteria_arena *a, exteria_tl_value *obj, const char *field, const char *s) {
    exteria_tl_value *v = exteria_tl_new_str(a, s);
    return v ? exteria_tl_set(obj, field, v) : EXTERIA_E_NOMEM;
}

exteria_status exteria_tl_set_flag(exteria_tl_value *obj, const char *field) {
    return exteria_tl_set(obj, field, (exteria_tl_value *)(uintptr_t)&tl_true_value);
}

exteria_status exteria_tl_set_i64_vec(exteria_arena *a, exteria_tl_value *obj, const char *field, const int64_t *x, uint32_t count) {
    exteria_tl_value *vec = exteria_tl_new_vec(a, count);
    uint32_t i;
    if (!vec) return EXTERIA_E_NOMEM;
    for (i = 0; i < count; ++i) {
        exteria_tl_value *item = exteria_tl_new_i64(a, x[i]);
        if (!item) return EXTERIA_E_NOMEM;
        vec->u.vec.items[i] = item;
    }
    return exteria_tl_set(obj, field, vec);
}

exteria_status exteria_tl_set_i32_vec(exteria_arena *a, exteria_tl_value *obj, const char *field, const int32_t *x, uint32_t count) {
    exteria_tl_value *vec = exteria_tl_new_vec(a, count);
    uint32_t i;
    if (!vec) return EXTERIA_E_NOMEM;
    for (i = 0; i < count; ++i) {
        exteria_tl_value *item = exteria_tl_new_i32(a, x[i]);
        if (!item) return EXTERIA_E_NOMEM;
        vec->u.vec.items[i] = item;
    }
    return exteria_tl_set(obj, field, vec);
}

const exteria_tl_value *exteria_tl_get(const exteria_tl_value *obj, const char *field) {
    int idx;
    if (!obj || obj->kind != EXTERIA_TL_V_OBJ) return NULL;
    idx = exteria_tl_field_index(obj->u.obj.ctor, field);
    if (idx < 0) return NULL;
    return obj->u.obj.fields[idx];
}

uint32_t exteria_tl_id(const exteria_tl_value *obj) {
    return obj && obj->kind == EXTERIA_TL_V_OBJ ? obj->u.obj.ctor->id : 0;
}

int exteria_tl_is(const exteria_tl_value *obj, uint32_t id) {
    return exteria_tl_id(obj) == id;
}

int exteria_tl_has(const exteria_tl_value *obj, const char *field) {
    return exteria_tl_get(obj, field) != NULL;
}

static exteria_status get_kind(const exteria_tl_value *obj, const char *field, uint8_t kind, const exteria_tl_value **out) {
    const exteria_tl_value *v = exteria_tl_get(obj, field);
    if (!v) return EXTERIA_E_NOTFOUND;
    if (v->kind != kind) return EXTERIA_E_MALFORMED;
    *out = v;
    return EXTERIA_OK;
}

exteria_status exteria_tl_get_i32(const exteria_tl_value *obj, const char *field, int32_t *out) {
    const exteria_tl_value *v;
    exteria_status s = get_kind(obj, field, EXTERIA_TL_V_I32, &v);
    if (s == EXTERIA_OK) *out = v->u.i32;
    return s;
}

exteria_status exteria_tl_get_i64(const exteria_tl_value *obj, const char *field, int64_t *out) {
    const exteria_tl_value *v;
    exteria_status s = get_kind(obj, field, EXTERIA_TL_V_I64, &v);
    if (s == EXTERIA_OK) *out = v->u.i64;
    return s;
}

exteria_status exteria_tl_get_f64(const exteria_tl_value *obj, const char *field, double *out) {
    const exteria_tl_value *v;
    exteria_status s = get_kind(obj, field, EXTERIA_TL_V_F64, &v);
    if (s == EXTERIA_OK) *out = v->u.f64;
    return s;
}

exteria_status exteria_tl_get_bytes(const exteria_tl_value *obj, const char *field, const uint8_t **data, size_t *len) {
    const exteria_tl_value *v;
    exteria_status s = get_kind(obj, field, EXTERIA_TL_V_BYTES, &v);
    if (s == EXTERIA_OK) {
        *data = v->u.bytes.data;
        *len = v->u.bytes.len;
    }
    return s;
}

exteria_status exteria_tl_get_obj(const exteria_tl_value *obj, const char *field, const exteria_tl_value **out) {
    return get_kind(obj, field, EXTERIA_TL_V_OBJ, out);
}

exteria_status exteria_tl_get_vec(const exteria_tl_value *obj, const char *field, const exteria_tl_value **out) {
    return get_kind(obj, field, EXTERIA_TL_V_VEC, out);
}

static exteria_status put(exteria_writer *w, const char *s) {
    return exteria_wr_bytes(w, s, strlen(s));
}

static exteria_status dump_value(const exteria_tl_value *v, exteria_writer *w, uint32_t depth) {
    char tmp[48];
    exteria_status s;
    uint32_t i;
    if (depth > ENC_MAX_DEPTH) return put(w, "...");
    if (!v) return put(w, "null");
    switch (v->kind) {
    case EXTERIA_TL_V_I32:
        snprintf(tmp, sizeof(tmp), "%d", (int)v->u.i32);
        return put(w, tmp);
    case EXTERIA_TL_V_I64:
        snprintf(tmp, sizeof(tmp), "%lld", (long long)v->u.i64);
        return put(w, tmp);
    case EXTERIA_TL_V_F64:
        snprintf(tmp, sizeof(tmp), "%g", v->u.f64);
        return put(w, tmp);
    case EXTERIA_TL_V_TRUE:
        return put(w, "true");
    case EXTERIA_TL_V_BYTES: {
        uint32_t n = v->u.bytes.len < 32 ? v->u.bytes.len : 32;
        s = put(w, "x'");
        for (i = 0; i < n && s == EXTERIA_OK; ++i) {
            snprintf(tmp, sizeof(tmp), "%02x", v->u.bytes.data[i]);
            s = put(w, tmp);
        }
        if (s == EXTERIA_OK && n < v->u.bytes.len) s = put(w, "...");
        if (s == EXTERIA_OK) s = put(w, "'");
        return s;
    }
    case EXTERIA_TL_V_VEC:
        s = put(w, "[");
        for (i = 0; i < v->u.vec.count && s == EXTERIA_OK; ++i) {
            if (i) s = put(w, ", ");
            if (s == EXTERIA_OK) s = dump_value(v->u.vec.items[i], w, depth + 1);
        }
        if (s == EXTERIA_OK) s = put(w, "]");
        return s;
    case EXTERIA_TL_V_OBJ: {
        const exteria_tl_ctor *c = v->u.obj.ctor;
        const exteria_tl_field *f = exteria_tl_ctor_fields(c);
        unsigned first = 1;
        s = put(w, c->name);
        if (s == EXTERIA_OK) s = put(w, "(");
        for (i = 0; i < c->field_count && s == EXTERIA_OK; ++i) {
            if (!v->u.obj.fields[i]) continue;
            if (!first) s = put(w, ", ");
            first = 0;
            if (s == EXTERIA_OK) s = put(w, f[i].name);
            if (s == EXTERIA_OK) s = put(w, "=");
            if (s == EXTERIA_OK) s = dump_value(v->u.obj.fields[i], w, depth + 1);
        }
        if (s == EXTERIA_OK) s = put(w, ")");
        return s;
    }
    }
    return EXTERIA_E_ARG;
}

exteria_status exteria_tl_dump(const exteria_tl_value *value, exteria_writer *w) {
    return dump_value(value, w, 0);
}
