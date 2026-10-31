#ifndef EXTERIA_PLUGIN_H
#define EXTERIA_PLUGIN_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

struct lua_State;

#define EXTERIA_PLUGIN_SCRIPT_MAX 65536u
#define EXTERIA_PLUGIN_TEXT_MAX 16384u
#define EXTERIA_PLUGIN_NAME_MAX 64u
#define EXTERIA_PLUGIN_PERMISSION_MAX 8u

/* bits of exteria_plugin.permissions, named in the "permissions" list of the plugin table */
enum {
    EXTERIA_PERM_MESSAGES_READ = 1,     /* "messages.read": the hook sees the text of a message */
    EXTERIA_PERM_MESSAGES_MODIFY = 2    /* "messages.modify": the hook may hide a message or replace its text */
};

/* bits of exteria_plugin.hooks, one for each function the plugin table carries */
enum {
    EXTERIA_HOOK_MESSAGE = 1,   /* on_message(m): a message of someone else on its way to the screen */
    EXTERIA_HOOK_SEND = 2,      /* on_send(m): a text of the person on its way to the server */
    EXTERIA_HOOK_EVENT = 4      /* on_event(name): "start", "stop", "pause" or "resume" */
};

typedef enum exteria_plugin_action {
    EXTERIA_PLUGIN_PASS = 0,
    EXTERIA_PLUGIN_CANCEL,
    EXTERIA_PLUGIN_REPLACE
} exteria_plugin_action;

typedef struct exteria_plugin_message {
    int64_t id;
    int64_t chat;
    int64_t sender;
    int outgoing;
    const char *text;       /* utf-8, not terminated */
    size_t text_len;
} exteria_plugin_message;

typedef struct exteria_plugin_send {
    int64_t chat;
    int32_t reply_to;
    const char *text;       /* utf-8, not terminated */
    size_t text_len;
} exteria_plugin_send;

/* receives the lines a plugin writes with log(text); the plugin name comes first. set it before the first load */
typedef void (*exteria_plugin_log_fn)(const char *plugin, const char *line);
void exteria_plugin_set_log(exteria_plugin_log_fn fn);

/* one loaded plugin. the allocator keeps the address of this struct, so it must not move after load */
typedef struct exteria_plugin {
    struct lua_State *lua;
    int table_ref;
    uint32_t permissions;
    uint32_t hooks;
    char name[EXTERIA_PLUGIN_NAME_MAX + 1];
    size_t mem_used;
    size_t mem_limit;
    long budget;
    int exhausted;
    int log_lines;
    char error[160];
} exteria_plugin;

/* runs the script once in a sandbox and checks the table it returns: a name, a list of permissions and at least one of
   on_message, on_send and on_event. a hook the table does not carry is skipped by the calls below. a failed load leaves the struct closed, with the reason in error.
   EXTERIA_E_MALFORMED: syntax error, bad table, missing field. EXTERIA_E_UNSUPPORTED: unknown permission.
   EXTERIA_E_TIMEOUT, EXTERIA_E_NOMEM: the script outran its instruction or memory budget */
exteria_status exteria_plugin_load(exteria_plugin *p, const char *script, size_t script_len);

/* calls on_message(msg). without messages.read the table has no text field. an answer of false hides the message
   and a string replaces its text, both need messages.modify and otherwise fail with EXTERIA_E_SECURITY and PASS.
   a replacement goes to out (terminated) and must be valid utf-8 that fits cap. on any failure action is PASS and the
   caller keeps the original message */
exteria_status exteria_plugin_on_message(exteria_plugin *p, const exteria_plugin_message *in,
                                        exteria_plugin_action *action, char *out, size_t cap, size_t *out_len);

/* calls on_send(m) with chat, reply_to and, with messages.read, text. the answer works as the one of on_message: nil
   leaves the text, false stops the send and a string replaces the text, both of them need messages.modify */
exteria_status exteria_plugin_on_send(exteria_plugin *p, const exteria_plugin_send *in,
                                     exteria_plugin_action *action, char *out, size_t cap, size_t *out_len);

/* calls on_event(name) for "start", "stop", "pause" or "resume", an answer is ignored. other names are EXTERIA_E_ARG */
exteria_status exteria_plugin_on_event(exteria_plugin *p, const char *name);

void exteria_plugin_close(exteria_plugin *p);

#endif
