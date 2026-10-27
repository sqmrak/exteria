#include "exteria_folders.h"

static size_t peer_index(const exteria_peer_ref *peers, size_t count, const exteria_dialog_row *dialog) {
    if (!peers || count > EXTERIA_FOLDER_PEERS_MAX)
        return SIZE_MAX;
    for (size_t i = 0; i < count; ++i) {
        if ((peers[i].self && dialog->saved) || (!peers[i].self && peers[i].kind == dialog->peer_kind && peers[i].id == dialog->peer_id))
            return i;
    }
    return SIZE_MAX;
}

size_t exteria_folder_pin_index(const exteria_folder_rules *rules, const exteria_dialog_row *dialog) {
    if (!rules || !dialog)
        return SIZE_MAX;
    return peer_index(rules->pinned, rules->pinned_count, dialog);
}

int exteria_folder_contains(const exteria_folder_rules *rules, const exteria_dialog_row *dialog) {
    if (!rules || !dialog || dialog->folder || rules->included_count > EXTERIA_FOLDER_PEERS_MAX || rules->excluded_count > EXTERIA_FOLDER_PEERS_MAX ||
        rules->pinned_count > EXTERIA_FOLDER_PEERS_MAX || (rules->included_count && !rules->included) || (rules->excluded_count && !rules->excluded) ||
        (rules->pinned_count && !rules->pinned))
        return 0;
    if (peer_index(rules->excluded, rules->excluded_count, dialog) != SIZE_MAX)
        return 0;
    if (peer_index(rules->included, rules->included_count, dialog) != SIZE_MAX || exteria_folder_pin_index(rules, dialog) != SIZE_MAX)
        return 1;
    if ((rules->flags & EXTERIA_FOLDER_SKIP_ARCHIVED) && dialog->folder_id != 0)
        return 0;
    /* mentions keep a muted or otherwise read chat visible */
    if (!dialog->mentions) {
        if ((rules->flags & EXTERIA_FOLDER_SKIP_MUTED) && dialog->muted)
            return 0;
        if ((rules->flags & EXTERIA_FOLDER_SKIP_READ) && !dialog->unread_count && !dialog->unread_mark)
            return 0;
    }
    if (dialog->community)
        return (rules->flags & 31u) == 31u;
    switch (dialog->kind) {
    case EXTERIA_DIALOG_USER:
        return (rules->flags & (dialog->contact || dialog->saved ? EXTERIA_FOLDER_CONTACTS : EXTERIA_FOLDER_NON_CONTACTS)) != 0;
    case EXTERIA_DIALOG_BOT:
        return (rules->flags & EXTERIA_FOLDER_BOTS) != 0;
    case EXTERIA_DIALOG_GROUP:
        return (rules->flags & EXTERIA_FOLDER_GROUPS) != 0;
    case EXTERIA_DIALOG_CHANNEL:
        return (rules->flags & EXTERIA_FOLDER_CHANNELS) != 0;
    default:
        return 0;
    }
}
