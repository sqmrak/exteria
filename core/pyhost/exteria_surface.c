#include <string.h>
#include "exteria_status.h"
#include "exteria_surface.h"

#define NAME_MAX_LEN 31

static struct {
    char name[NAME_MAX_LEN + 1];
    exteria_surface_ops ops;
} g_surfaces[EXTERIA_SURFACES_MAX];
static int g_count;

int exteria_surface_register_ops(const char *name, const exteria_surface_ops *ops) {
    if (!name || !name[0] || !ops || !ops->frame || strlen(name) > NAME_MAX_LEN) return EXTERIA_E_ARG;
    for (int i = 0; i < g_count; ++i) {
        if (strcmp(g_surfaces[i].name, name) == 0) return EXTERIA_OK;
    }
    if (g_count == EXTERIA_SURFACES_MAX) return EXTERIA_E_LIMIT;
    strcpy(g_surfaces[g_count].name, name);
    g_surfaces[g_count].ops = *ops;
    ++g_count;
    return EXTERIA_OK;
}

int exteria_surface_register(const char *name, exteria_surface_fn fn) {
    exteria_surface_ops ops;
    memset(&ops, 0, sizeof ops);
    ops.frame = fn;
    return exteria_surface_register_ops(name, &ops);
}

static const exteria_surface_ops *find(const char *name) {
    if (!name) return NULL;
    for (int i = 0; i < g_count; ++i) {
        if (strcmp(g_surfaces[i].name, name) == 0) return &g_surfaces[i].ops;
    }
    return NULL;
}

int exteria_surface_tick(const char *name) {
    const exteria_surface_ops *ops = find(name);
    return ops && ops->tick ? ops->tick() : 0;
}

int exteria_surface_key(const char *name, int code, int pressed) {
    const exteria_surface_ops *ops = find(name);
    return ops && ops->key ? ops->key(code, pressed) : 0;
}

int exteria_surface_get(const char *name, const uint32_t **pixels, int *width, int *height) {
    const exteria_surface_ops *ops = find(name);
    if (!ops || !pixels || !width || !height) return 0;
    return ops->frame(pixels, width, height);
}
