#ifndef EXTERIA_FOLDERS_H
#define EXTERIA_FOLDERS_H

#include "exteria_dialogs.h"
#include "exteria_messages.h"

#define EXTERIA_FOLDERS_MAX 100
#define EXTERIA_FOLDER_PEERS_MAX 1000

/* these bits describe rules, not the flags of a serialized DialogFilter */
enum {
    EXTERIA_FOLDER_CONTACTS = 1,
    EXTERIA_FOLDER_NON_CONTACTS = 2,
    EXTERIA_FOLDER_GROUPS = 4,
    EXTERIA_FOLDER_CHANNELS = 8,
    EXTERIA_FOLDER_BOTS = 16,
    EXTERIA_FOLDER_SKIP_MUTED = 32,
    EXTERIA_FOLDER_SKIP_READ = 64,
    EXTERIA_FOLDER_SKIP_ARCHIVED = 128
};

typedef struct exteria_folder_rules {
    uint32_t flags;
    const exteria_peer_ref *included;
    size_t included_count;
    const exteria_peer_ref *excluded;
    size_t excluded_count;
    const exteria_peer_ref *pinned;
    size_t pinned_count;
} exteria_folder_rules;

int exteria_folder_contains(const exteria_folder_rules *rules, const exteria_dialog_row *dialog);
int exteria_folder_scans_dialogs(uint32_t flags, int archived);
/* SIZE_MAX means that this chat is not pinned in the folder */
size_t exteria_folder_pin_index(const exteria_folder_rules *rules, const exteria_dialog_row *dialog);

/* preserve an emoji outside an edit, moving its UTF-16 offset when the edit comes first */
int exteria_folder_shift_emoji(size_t *offset, size_t length, size_t start, size_t removed, size_t inserted);
exteria_status exteria_folder_title_build(exteria_arena *arena, const char *text, const exteria_send_entity *entities,
                                          size_t count, exteria_tl_value **out);

#endif
