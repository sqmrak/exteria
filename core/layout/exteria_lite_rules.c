#include "exteria_lite_rules.h"

#define LOW_PRESET (EXTERIA_LITE_EMOJI_CHAT_PREMIUM | EXTERIA_LITE_EMOJI_KEYBOARD_PREMIUM | EXTERIA_LITE_EMOJI_REACTIONS_PREMIUM | EXTERIA_LITE_AUTOPLAY_GIFS | \
                    EXTERIA_LITE_CHAT_THANOS | EXTERIA_LITE_PARTICLES)
#define MEDIUM_PRESET (EXTERIA_LITE_STICKERS_KEYBOARD | EXTERIA_LITE_STICKERS_CHAT | EXTERIA_LITE_EMOJI_KEYBOARD_PREMIUM | EXTERIA_LITE_EMOJI_REACTIONS_PREMIUM | \
                       EXTERIA_LITE_EMOJI_CHAT_PREMIUM | EXTERIA_LITE_EMOJI_CHAT_NOT_PREMIUM | EXTERIA_LITE_CHAT_FORUM_TWOCOLUMN | EXTERIA_LITE_CALLS | \
                       EXTERIA_LITE_AUTOPLAY_VIDEOS | EXTERIA_LITE_AUTOPLAY_GIFS | EXTERIA_LITE_CHAT_THANOS | EXTERIA_LITE_PARTICLES)
#define HIGH_PRESET (EXTERIA_LITE_STICKERS_KEYBOARD | EXTERIA_LITE_STICKERS_CHAT | EXTERIA_LITE_EMOJI_KEYBOARD_PREMIUM | EXTERIA_LITE_EMOJI_REACTIONS_PREMIUM | \
                     EXTERIA_LITE_EMOJI_CHAT_PREMIUM | EXTERIA_LITE_EMOJI_CHAT_NOT_PREMIUM | EXTERIA_LITE_EMOJI_REACTIONS_NOT_PREMIUM | \
                     EXTERIA_LITE_EMOJI_KEYBOARD_NOT_PREMIUM | EXTERIA_LITE_CHAT_BACKGROUND | EXTERIA_LITE_CHAT_FORUM_TWOCOLUMN | EXTERIA_LITE_CHAT_SPOILER | \
                     EXTERIA_LITE_CHAT_BLUR | EXTERIA_LITE_CHAT_SCALE | EXTERIA_LITE_CHAT_THANOS | EXTERIA_LITE_CALLS | EXTERIA_LITE_AUTOPLAY_VIDEOS | \
                     EXTERIA_LITE_AUTOPLAY_GIFS | EXTERIA_LITE_PARTICLES)

uint32_t exteria_lite_default_value(exteria_lite_class device_class) {
    switch (device_class) {
    case EXTERIA_LITE_CLASS_LOW: return LOW_PRESET;
    case EXTERIA_LITE_CLASS_AVERAGE: return MEDIUM_PRESET;
    default: return HIGH_PRESET;
    }
}

exteria_lite_class exteria_lite_measure_class(uint64_t memory_bytes, unsigned cores) {
    if (cores <= 1 || memory_bytes <= 512ull * 1024 * 1024) return EXTERIA_LITE_CLASS_LOW;
    if (memory_bytes <= 1024ull * 1024 * 1024) return EXTERIA_LITE_CLASS_AVERAGE;
    return EXTERIA_LITE_CLASS_HIGH;
}

uint32_t exteria_lite_for_account(uint32_t flag, int premium) {
    static const uint32_t pairs[][2] = {
        {EXTERIA_LITE_EMOJI_KEYBOARD_PREMIUM, EXTERIA_LITE_EMOJI_KEYBOARD_NOT_PREMIUM},
        {EXTERIA_LITE_EMOJI_REACTIONS_PREMIUM, EXTERIA_LITE_EMOJI_REACTIONS_NOT_PREMIUM},
        {EXTERIA_LITE_EMOJI_CHAT_PREMIUM, EXTERIA_LITE_EMOJI_CHAT_NOT_PREMIUM}
    };
    unsigned i;
    for (i = 0; i < sizeof(pairs) / sizeof(pairs[0]); ++i) {
        uint32_t both = pairs[i][0] | pairs[i][1];
        if (flag & both) flag = (flag & ~both) | (premium ? pairs[i][0] : pairs[i][1]);
    }
    return flag;
}

int exteria_lite_enabled(uint32_t value, int power_saver_applied, uint32_t flag, int premium) {
    if (power_saver_applied) return 0;
    return (value & exteria_lite_for_account(flag, premium)) != 0;
}

uint32_t exteria_lite_with(uint32_t value, uint32_t flag, int on) {
    return on ? (value | flag) : (value & ~flag);
}

int exteria_lite_power_saver_applied(int level, int battery_percent) {
    return level > 0 && battery_percent >= 0 && battery_percent <= level;
}

int exteria_lite_clamp_level(int level) {
    return level < 0 ? 0 : (level > 100 ? 100 : level);
}

uint32_t exteria_power_notice_update(exteria_power_notice_state *state, int battery_percent, int saver) {
    uint32_t events = 0;
    int low;
    if (!state) return 0;
    if (battery_percent >= 0 && battery_percent <= 100) {
        low = battery_percent <= 20;
        if (low && !state->low) events |= EXTERIA_POWER_NOTICE_LOW;
        state->low = low;
    }
    saver = saver != 0;
    if (saver && !state->saver) events |= EXTERIA_POWER_NOTICE_SAVER;
    state->saver = saver;
    return events;
}
