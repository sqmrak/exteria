#ifndef EXTERIA_SURFACE_H
#define EXTERIA_SURFACE_H

#include <stdint.h>

/* a native module that draws its own frames (a game, a decoder) publishes them here by name, and the view layer of the app shows
   them: python only says "show surface <name>", the pixels never pass through it */

/* gives the current frame: width, height and a pointer to width * height pixels of 32 bits, blue in the lowest byte, the top byte
   unused. 0 when there is no frame yet. the pointer stays valid until the module draws the next one */
typedef int (*exteria_surface_fn)(const uint32_t **pixels, int *width, int *height);

/* a surface that runs by itself: the view layer calls tick once per frame and feeds it keys, with no python in between */
typedef struct exteria_surface_ops {
    exteria_surface_fn frame;
    /* runs the module up to the next frame; 0 when it has ended */
    int (*tick)(void);
    /* a key goes down or up, in the numbering of the module; 0 when it is not accepted */
    int (*key)(int code, int pressed);
} exteria_surface_ops;

#define EXTERIA_SURFACES_MAX 8

/* EXTERIA_E_LIMIT when the table is full, EXTERIA_E_ARG for a name that is empty or too long; a name registered twice keeps its first */
int exteria_surface_register(const char *name, exteria_surface_fn fn);

/* the same with a tick and a key entry; the copy of ops is kept */
int exteria_surface_register_ops(const char *name, const exteria_surface_ops *ops);

/* 1 when the surface is running, 0 when it has ended or is unknown */
int exteria_surface_tick(const char *name);
int exteria_surface_key(const char *name, int code, int pressed);

/* 0 when the surface is unknown or has no frame */
int exteria_surface_get(const char *name, const uint32_t **pixels, int *width, int *height);

#endif
