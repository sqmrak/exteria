#ifndef EXTERIA_SEND_AS_H
#define EXTERIA_SEND_AS_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_dialogs.h"
#include "exteria_messages.h"
#include "exteria_tl.h"

/* the server lists at most this many; a longer list is cut here */
#define EXTERIA_SEND_AS_MAX 50

/* channels.getSendAs: who the account may write as in a group or channel (itself, its channels, an anonymous admin
   identity); the peer must be a channel with its hash, or a basic group */
exteria_status exteria_send_as_request(exteria_arena *arena, const exteria_peer_ref *peer, exteria_tl_value **out);

/* the channels.sendAsPeers answer as one dialog row per identity, in the server's order (the account itself comes
   first there) */
exteria_status exteria_send_as_parse(const exteria_tl_value *answer, int64_t self_id, exteria_dialog_row *rows, uint8_t *premium_required, size_t cap,
                                     size_t *count);

/* sets send_as of a send request (text, media, sticker, location, contact) to this identity, which must be a user
   with its hash or a channel with its hash */
exteria_status exteria_set_send_as(exteria_arena *arena, exteria_tl_value *request, const exteria_peer_ref *send_as);

/* messages.saveDefaultSendAs: the identity the account writes as in that chat from now on, on every device */
exteria_status exteria_save_default_send_as_request(exteria_arena *arena, const exteria_peer_ref *peer, const exteria_peer_ref *send_as,
                                                    exteria_tl_value **out);

#endif
