#ifndef EXTERIA_TEXT_CLASS_H
#define EXTERIA_TEXT_CLASS_H

#include <stddef.h>
#include <stdint.h>

/* what the text layer has to do with one character before it asks a font for its glyph */
typedef enum {
    EXTERIA_CP_CHECK = 0,   /* ask the fonts, a missing glyph needs a fallback font */
    EXTERIA_CP_PLAIN,       /* every font the app draws with has it, or it draws nothing (controls, spaces, the object marker) */
    EXTERIA_CP_ATTACH       /* has no shape of its own and goes with the font of the character before it (joiners, selectors) */
} exteria_cp_class;

/* the class of one code point; anything above 0x10FFFF is plain, as it cannot be drawn */
exteria_cp_class exteria_cp_class_of(uint32_t cp);

/* reads the code point at units[index] from UTF-16 text of len units and returns how many units it takes, 1 or 2;
   a surrogate without its partner is returned alone as that unit, so malformed text still moves forward. index
   must be below len */
size_t exteria_utf16_next(const uint16_t *units, size_t len, size_t index, uint32_t *cp);

#endif
