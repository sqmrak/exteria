#include <stdio.h>
#include <string.h>
#include "exteria_doom.h"
#include "test_util.h"

/* the engine keeps one game per process, so each case is a run of this program: "missing", "corrupt" or "play <wad>" */

static void missing_wad_is_an_error_and_can_be_retried(void) {
    CHECK_EQ_INT(exteria_doom_start("/nonexistent/doom1.wad", "/tmp"), EXTERIA_E_IO);
    CHECK(strstr(exteria_doom_error(), "/nonexistent/doom1.wad") != NULL);
    CHECK_EQ_INT(exteria_doom_start("/nonexistent/doom1.wad", "/tmp"), EXTERIA_E_IO);
    CHECK_EQ_INT(exteria_doom_start(NULL, "/tmp"), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_doom_tick(), EXTERIA_E_STATE);
}

static void a_corrupt_wad_stops_the_game_and_not_the_process(void) {
    const char *path = "/tmp/exteria-corrupt.wad";
    FILE *file = fopen(path, "wb");
    CHECK(file != NULL);
    if (!file) return;
    fwrite("IWAD\x01\0\0\0\xff\xff\xff\x7f", 1, 12, file);
    fclose(file);
    CHECK_EQ_INT(exteria_doom_start(path, "/tmp"), EXTERIA_E_STATE);
    CHECK(exteria_doom_error()[0] != 0);
    CHECK_EQ_INT(exteria_doom_tick(), EXTERIA_E_EOF);
    CHECK_EQ_INT(exteria_doom_start(path, "/tmp"), EXTERIA_E_STATE);
    CHECK_EQ_INT(exteria_doom_key(13, 1), 0);
    remove(path);
}

static unsigned long long checksum(const uint32_t *pixels, int count) {
    unsigned long long sum = 1469598103934665603ULL;
    for (int i = 0; i < count; ++i) sum = (sum ^ pixels[i]) * 1099511628211ULL;
    return sum;
}

static void the_game_runs_and_draws(const char *wad) {
    CHECK_EQ_INT(exteria_doom_start(wad, "/tmp"), EXTERIA_OK);
    const uint32_t *pixels = NULL;
    int width = 0, height = 0;
    unsigned long long seen[8];
    int sampled = 0;
    for (int tick = 0; tick < 400; ++tick) {
        CHECK_EQ_INT(exteria_doom_tick(), EXTERIA_OK);
        if (tick % 50 == 49 && sampled < 8) {
            CHECK(exteria_doom_frame(&pixels, &width, &height));
            CHECK_EQ_INT(width, EXTERIA_DOOM_WIDTH);
            CHECK_EQ_INT(height, EXTERIA_DOOM_HEIGHT);
            seen[sampled++] = checksum(pixels, width * height);
        }
    }
    int distinct = 0;
    for (int i = 0; i < sampled; ++i) {
        int fresh = 1;
        for (int j = 0; j < i; ++j) fresh = fresh && seen[i] != seen[j];
        distinct += fresh;
    }
    /* the title screen and the demo move, so frames differ */
    CHECK(distinct >= 2);
    int lit = 0;
    for (int i = 0; i < width * height; ++i) lit += (pixels[i] & 0xFFFFFF) != 0;
    CHECK(lit > width * height / 10);
    CHECK_EQ_INT(exteria_doom_key(13, 1), 1);
    CHECK_EQ_INT(exteria_doom_key(13, 0), 1);
    CHECK_EQ_INT(exteria_doom_key(0, 1), 0);
    for (int tick = 0; tick < 50; ++tick) CHECK_EQ_INT(exteria_doom_tick(), EXTERIA_OK);
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "missing") == 0) missing_wad_is_an_error_and_can_be_retried();
    else if (argc >= 2 && strcmp(argv[1], "corrupt") == 0) a_corrupt_wad_stops_the_game_and_not_the_process();
    else if (argc >= 3 && strcmp(argv[1], "play") == 0) the_game_runs_and_draws(argv[2]);
    else {
        fprintf(stderr, "usage: test_doom missing | corrupt | play <doom1.wad>\n");
        return 2;
    }
    if (g_failures) {
        fprintf(stderr, "test_doom %s: %d of %d checks failed\n", argv[1], g_failures, g_checks);
        return 1;
    }
    printf("test_doom %s: %d checks passed\n", argv[1], g_checks);
    return 0;
}
