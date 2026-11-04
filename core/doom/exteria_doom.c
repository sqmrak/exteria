/* doomgeneric.h declares its platform functions without prototypes, as upstream ships it */
#pragma GCC diagnostic ignored "-Wstrict-prototypes"
#pragma GCC diagnostic ignored "-Wmissing-prototypes"

#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include "exteria_doom.h"
#include "exteria_doom_exit.h"
#include "../../third_party/doomgeneric/doomgeneric.h"

#define KEY_QUEUE 64
#define ERROR_MAX 256

static jmp_buf g_leave;
static int g_inside;
static int g_started;
static int g_dead;
static int g_frame_ready;
static char g_error[ERROR_MAX];
static struct { unsigned char pressed; unsigned char key; } g_keys[KEY_QUEUE];
static unsigned g_key_read, g_key_write;
static struct timeval g_origin;

/* the engine's way out: back to the call that entered it, since the stack above is the engine's own */
void exteria_doom_exit(int code) {
    if (code != 0 && !g_error[0]) snprintf(g_error, sizeof g_error, "the engine stopped with code %d", code);
    g_dead = 1;
    if (g_inside) longjmp(g_leave, 1);
    /* not inside a call of ours: nothing to go back to */
    _exit(code);
}

void exteria_doom_report(const char *message);

void exteria_doom_report(const char *message) {
    snprintf(g_error, sizeof g_error, "%s", message);
}

void DG_Init(void) {
    gettimeofday(&g_origin, NULL);
}

void DG_DrawFrame(void) {
    g_frame_ready = 1;
}

void DG_SleepMs(uint32_t ms) {
    /* the engine waits for the next tic here; the caller is the main thread of the app, which must not be held for long */
    usleep((ms > 2 ? 2 : ms) * 1000);
}

uint32_t DG_GetTicksMs(void) {
    struct timeval now;
    gettimeofday(&now, NULL);
    return (uint32_t)((now.tv_sec - g_origin.tv_sec) * 1000 + (now.tv_usec - g_origin.tv_usec) / 1000);
}

int DG_GetKey(int *pressed, unsigned char *key) {
    if (g_key_read == g_key_write) return 0;
    *pressed = g_keys[g_key_read % KEY_QUEUE].pressed;
    *key = g_keys[g_key_read % KEY_QUEUE].key;
    ++g_key_read;
    return 1;
}

void DG_SetWindowTitle(const char *title) {
    (void)title;
}

exteria_status exteria_doom_start(const char *wad_path, const char *savedir) {
    if (!wad_path || !wad_path[0] || !savedir) return EXTERIA_E_ARG;
    if (g_started) return EXTERIA_E_STATE;
    g_error[0] = 0;
    /* a wad that is missing is not a game that ran: the caller may copy it in and start again */
    FILE *file = fopen(wad_path, "rb");
    if (!file) {
        snprintf(g_error, sizeof g_error, "cannot read %s", wad_path);
        return EXTERIA_E_IO;
    }
    fclose(file);
    g_started = 1;
    /* the engine keeps pointers into its argument vector for the whole game */
    static char wad[1024], save[1024];
    snprintf(wad, sizeof wad, "%s", wad_path);
    snprintf(save, sizeof save, "%s", savedir);
    static char arg0[] = "doom", arg1[] = "-iwad", arg3[] = "-savedir", arg5[] = "-nosound", arg6[] = "-nomusic", arg7[] = "-nomouse";
    static char *argv[] = { arg0, arg1, wad, arg3, save, arg5, arg6, arg7, NULL };
    g_inside = 1;
    if (setjmp(g_leave) == 0) {
        doomgeneric_Create(8, argv);
        g_inside = 0;
        return EXTERIA_OK;
    }
    g_inside = 0;
    return EXTERIA_E_STATE;
}

exteria_status exteria_doom_tick(void) {
    if (!g_started) return EXTERIA_E_STATE;
    if (g_dead) return EXTERIA_E_EOF;
    g_inside = 1;
    if (setjmp(g_leave) == 0) {
        doomgeneric_Tick();
        g_inside = 0;
        return EXTERIA_OK;
    }
    g_inside = 0;
    return EXTERIA_E_EOF;
}

int exteria_doom_running(void) {
    return exteria_doom_tick() == EXTERIA_OK;
}

int exteria_doom_key(int code, int pressed) {
    if (code <= 0 || code > 255 || g_dead) return 0;
    if (g_key_write - g_key_read >= KEY_QUEUE) return 0;
    g_keys[g_key_write % KEY_QUEUE].pressed = pressed ? 1 : 0;
    g_keys[g_key_write % KEY_QUEUE].key = (unsigned char)code;
    ++g_key_write;
    return 1;
}

int exteria_doom_frame(const uint32_t **pixels, int *width, int *height) {
    if (!g_frame_ready || !DG_ScreenBuffer) return 0;
    *pixels = DG_ScreenBuffer;
    *width = EXTERIA_DOOM_WIDTH;
    *height = EXTERIA_DOOM_HEIGHT;
    return 1;
}

const char *exteria_doom_error(void) {
    return g_error;
}
