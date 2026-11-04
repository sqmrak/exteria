#ifndef EXTERIA_DOOM_EXIT_H
#define EXTERIA_DOOM_EXIT_H

/* the engine sources are built with -Dexit=exteria_doom_exit: its quit and its fatal errors leave the game, not the app */
void exteria_doom_exit(int code) __attribute__((noreturn));

#endif
