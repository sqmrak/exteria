#ifndef EXTERIA_DOOM_H
#define EXTERIA_DOOM_H

#include <stdint.h>
#include "exteria_status.h"

/* doom on doomgeneric, one game for the life of the process (the engine keeps its state in globals). the screen is 320x200 */
#define EXTERIA_DOOM_WIDTH 320
#define EXTERIA_DOOM_HEIGHT 200

/* starts the game from the iwad at wad_path (shareware doom1.wad will do); savedir holds saves and the config. EXTERIA_E_IO when the
   wad cannot be read, EXTERIA_E_STATE when a game ran before in this process or the engine stopped itself, see exteria_doom_error */
exteria_status exteria_doom_start(const char *wad_path, const char *savedir);

/* runs the game up to the next frame. EXTERIA_E_EOF when the game has ended, by its menu or by an error of the engine */
exteria_status exteria_doom_tick(void);

/* a key of doomkeys.h (the arrows, ctrl, space, enter, escape and the letters in lower case) goes down or comes up; keys beyond a small
   queue are dropped. 0 when the key is not accepted */
int exteria_doom_key(int code, int pressed);

/* exteria_doom_tick as the surface layer wants it: 1 while the game runs, 0 when it has ended */
int exteria_doom_running(void);

/* the frame, in the shape of exteria_surface_fn */
int exteria_doom_frame(const uint32_t **pixels, int *width, int *height);

/* the last error text of the engine, empty when there is none */
const char *exteria_doom_error(void);

/* the PyInit function of the module _doom, which exposes the calls above to python; the app lists it in the config of core/pyhost.
   it also publishes the frame as the surface "doom" */
void *exteria_doom_module_init(void);

#endif
