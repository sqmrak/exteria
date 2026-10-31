#include "exteria_plugin.h"

#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

/* the plugin owns the whole lua state, so one limit covers script, tables and garbage alike */
#define PLUGIN_MEMORY_LIMIT (2u * 1024u * 1024u)
/* vm instructions per load or hook call, about 10 ms on an armv7 iphone 4 */
#define PLUGIN_INSTRUCTION_BUDGET 200000L
#define PLUGIN_HOOK_STEP 1000
#define PLUGIN_LOG_LINE_MAX 200
#define PLUGIN_LOG_LINES_PER_CALL 16

static exteria_plugin_log_fn g_log;

void exteria_plugin_set_log(exteria_plugin_log_fn fn) {
    g_log = fn;
}

typedef struct load_job {
    const char *script;
    size_t len;
    int syntax;
    exteria_status status;
} load_job;

typedef struct message_job {
    const char *hook;
    const exteria_plugin_message *in;
    const exteria_plugin_send *send;
    exteria_plugin_action action;
    char *out;
    size_t cap;
    size_t out_len;
    exteria_status status;
} message_job;

static void *plugin_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    exteria_plugin *p = ud;
    size_t old = ptr ? osize : 0;
    void *fresh;
    if (nsize == 0) {
        free(ptr);
        p->mem_used -= old;
        return NULL;
    }
    /* a failed grow must leave the old block valid, lua then runs a full collection and retries */
    if (nsize > old && nsize - old > p->mem_limit - p->mem_used) return NULL;
    fresh = realloc(ptr, nsize);
    if (!fresh) return NULL;
    p->mem_used = p->mem_used - old + nsize;
    return fresh;
}

static int plugin_panic(lua_State *L) {
    /* every call into the state is protected, so reaching this is a bug in the host */
    (void)L;
    abort();
}

/* an error raised here can be caught by pcall in the script, so after the budget is gone the hook fires on every
   instruction: each pcall that swallows the error is left again at its next instruction, up to the host */
static void budget_hook(lua_State *L, lua_Debug *ar) {
    void *ud;
    exteria_plugin *p;
    (void)ar;
    (void)lua_getallocf(L, &ud);
    p = ud;
    if (!p->exhausted) {
        p->budget -= PLUGIN_HOOK_STEP;
        if (p->budget > 0) return;
        p->exhausted = 1;
        lua_sethook(L, budget_hook, LUA_MASKCOUNT, 1);
    }
    luaL_error(L, "instruction budget exceeded");
}

static void arm(exteria_plugin *p) {
    p->budget = PLUGIN_INSTRUCTION_BUDGET;
    p->exhausted = 0;
    lua_sethook(p->lua, budget_hook, LUA_MASKCOUNT, PLUGIN_HOOK_STEP);
}

static void disarm(exteria_plugin *p) {
    lua_sethook(p->lua, NULL, 0, 0);
}

static void set_error(exteria_plugin *p, const char *text) {
    size_t n = text ? strlen(text) : 0;
    if (n >= sizeof p->error) n = sizeof p->error - 1;
    if (n) memcpy(p->error, text, n);
    p->error[n] = 0;
}

static exteria_status map_failure(exteria_plugin *p, int rc) {
    set_error(p, rc != LUA_OK && lua_type(p->lua, -1) == LUA_TSTRING ? lua_tostring(p->lua, -1) : "plugin failed");
    lua_pop(p->lua, 1);
    if (p->exhausted) return EXTERIA_E_TIMEOUT;
    if (rc == LUA_ERRMEM) return EXTERIA_E_NOMEM;
    if (rc == LUA_ERRSYNTAX) return EXTERIA_E_MALFORMED;
    return EXTERIA_E_STATE;
}

static int valid_utf8(const unsigned char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        size_t extra;
        uint32_t cp;
        if (c < 0x80) { ++i; continue; }
        if (c >= 0xC2 && c <= 0xDF) { extra = 1; cp = c & 0x1Fu; }
        else if (c >= 0xE0 && c <= 0xEF) { extra = 2; cp = c & 0x0Fu; }
        else if (c >= 0xF0 && c <= 0xF4) { extra = 3; cp = c & 0x07u; }
        else return 0;
        if (n - i - 1 < extra) return 0;
        for (size_t k = 1; k <= extra; ++k) {
            if ((s[i + k] & 0xC0u) != 0x80u) return 0;
            cp = (cp << 6) | (s[i + k] & 0x3Fu);
        }
        if ((extra == 2 && cp < 0x800u) || (extra == 3 && cp < 0x10000u)) return 0;
        if (cp > 0x10FFFFu || (cp >= 0xD800u && cp <= 0xDFFFu)) return 0;
        i += extra + 1;
    }
    return 1;
}

static int control_free(const char *s, size_t n) {
    for (size_t i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)s[i];
        if (c < 0x20 || c == 0x7F) return 0;
    }
    return 1;
}

static uint32_t permission_bit(const char *name) {
    if (strcmp(name, "messages.read") == 0) return EXTERIA_PERM_MESSAGES_READ;
    if (strcmp(name, "messages.modify") == 0) return EXTERIA_PERM_MESSAGES_MODIFY;
    return 0;
}

static int sandbox_log(lua_State *L);

/* the sandbox is a plain table the chunk uses as _ENV. io, os, load, require, print, collectgarbage and the
   debug library are never opened, string.dump is removed, and chunks load as text only so no bytecode can run */
static void build_environment(lua_State *L) {
    static const char *const base_names[] = {
        "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type", "xpcall",
        "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen", NULL
    };
    static const struct { const char *name; lua_CFunction open; } libs[] = {
        { LUA_STRLIBNAME, luaopen_string }, { LUA_TABLIBNAME, luaopen_table },
        { LUA_MATHLIBNAME, luaopen_math }, { LUA_UTF8LIBNAME, luaopen_utf8 }
    };
    lua_newtable(L);
    luaL_requiref(L, LUA_GNAME, luaopen_base, 0);
    for (size_t i = 0; base_names[i]; ++i) {
        lua_getfield(L, -1, base_names[i]);
        lua_setfield(L, -3, base_names[i]);
    }
    lua_pop(L, 1);
    lua_pushcfunction(L, sandbox_log);
    lua_setfield(L, -2, "log");
    for (size_t i = 0; i < sizeof libs / sizeof libs[0]; ++i) {
        luaL_requiref(L, libs[i].name, libs[i].open, 0);
        if (i == 0) {
            lua_pushnil(L);
            lua_setfield(L, -2, "dump");
        }
        lua_setfield(L, -2, libs[i].name);
    }
}

static int sandbox_log(lua_State *L) {
    void *ud;
    exteria_plugin *p;
    size_t len;
    const char *line = luaL_tolstring(L, 1, &len);
    char clipped[PLUGIN_LOG_LINE_MAX + 1];
    (void)lua_getallocf(L, &ud);
    p = ud;
    if (++p->log_lines > PLUGIN_LOG_LINES_PER_CALL) return luaL_error(L, "too many log lines");
    if (len > PLUGIN_LOG_LINE_MAX) len = PLUGIN_LOG_LINE_MAX;
    memcpy(clipped, line, len);
    clipped[len] = 0;
    if (g_log) g_log(p->name[0] ? p->name : "?", clipped);
    return 0;
}

static int read_permissions(lua_State *L, int table, exteria_plugin *p, exteria_status *status) {
    lua_Integer count;
    lua_getfield(L, table, "permissions");
    if (lua_type(L, -1) != LUA_TTABLE) {
        *status = EXTERIA_E_MALFORMED;
        set_error(p, "permissions must be a list");
        return 0;
    }
    count = (lua_Integer)luaL_len(L, -1);
    if (count > (lua_Integer)EXTERIA_PLUGIN_PERMISSION_MAX) {
        *status = EXTERIA_E_LIMIT;
        set_error(p, "too many permissions");
        return 0;
    }
    for (lua_Integer i = 1; i <= count; ++i) {
        uint32_t bit = 0;
        if (lua_rawgeti(L, -1, i) == LUA_TSTRING) bit = permission_bit(lua_tostring(L, -1));
        if (!bit) {
            *status = lua_type(L, -1) == LUA_TSTRING ? EXTERIA_E_UNSUPPORTED : EXTERIA_E_MALFORMED;
            set_error(p, lua_type(L, -1) == LUA_TSTRING ? "unknown permission" : "permissions must be strings");
            return 0;
        }
        p->permissions |= bit;
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    return 1;
}

static int load_main(lua_State *L) {
    load_job *job = lua_touserdata(L, 1);
    void *ud;
    exteria_plugin *p;
    const char *name;
    size_t name_len;
    (void)lua_getallocf(L, &ud);
    p = ud;
    job->status = EXTERIA_E_MALFORMED;
    build_environment(L);
    if (luaL_loadbufferx(L, job->script, job->len, "=plugin", "t") != LUA_OK) {
        job->syntax = 1;
        return lua_error(L);
    }
    lua_pushvalue(L, -2);
    lua_setupvalue(L, -2, 1);
    lua_call(L, 0, 1);
    if (lua_type(L, -1) != LUA_TTABLE) {
        set_error(p, "the script must return a table");
        return 0;
    }
    lua_getfield(L, -1, "name");
    name = lua_type(L, -1) == LUA_TSTRING ? lua_tolstring(L, -1, &name_len) : NULL;
    if (!name || name_len == 0 || name_len > EXTERIA_PLUGIN_NAME_MAX || !control_free(name, name_len)) {
        set_error(p, "name must be 1 to 64 printable characters");
        return 0;
    }
    memcpy(p->name, name, name_len);
    p->name[name_len] = 0;
    lua_pop(L, 1);
    p->hooks = 0;
    {
        static const struct { const char *name; uint32_t bit; } hooks[] = {
            { "on_message", EXTERIA_HOOK_MESSAGE }, { "on_send", EXTERIA_HOOK_SEND }, { "on_event", EXTERIA_HOOK_EVENT }
        };
        for (size_t i = 0; i < sizeof hooks / sizeof hooks[0]; ++i) {
            int kind = lua_getfield(L, -1, hooks[i].name);
            if (kind != LUA_TNIL && kind != LUA_TFUNCTION) {
                set_error(p, "a hook must be a function");
                return 0;
            }
            if (kind == LUA_TFUNCTION) p->hooks |= hooks[i].bit;
            lua_pop(L, 1);
        }
        if (!p->hooks) {
            set_error(p, "the plugin has no hook");
            return 0;
        }
    }
    p->permissions = 0;
    if (!read_permissions(L, lua_gettop(L), p, &job->status)) return 0;
    p->table_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    job->status = EXTERIA_OK;
    return 0;
}

exteria_status exteria_plugin_load(exteria_plugin *p, const char *script, size_t script_len) {
    load_job job;
    int rc;
    if (!p) return EXTERIA_E_ARG;
    memset(p, 0, sizeof *p);
    p->table_ref = LUA_NOREF;
    if (!script || script_len == 0) return EXTERIA_E_ARG;
    if (script_len > EXTERIA_PLUGIN_SCRIPT_MAX) {
        set_error(p, "script is too large");
        return EXTERIA_E_LIMIT;
    }
    p->mem_limit = PLUGIN_MEMORY_LIMIT;
    p->lua = lua_newstate(plugin_alloc, p);
    if (!p->lua) {
        set_error(p, "out of memory");
        return EXTERIA_E_NOMEM;
    }
    lua_atpanic(p->lua, plugin_panic);
    job.script = script;
    job.len = script_len;
    job.syntax = 0;
    job.status = EXTERIA_E_STATE;
    arm(p);
    lua_pushcfunction(p->lua, load_main);
    lua_pushlightuserdata(p->lua, &job);
    rc = lua_pcall(p->lua, 1, 0, 0);
    disarm(p);
    if (rc != LUA_OK) job.status = map_failure(p, job.syntax ? LUA_ERRSYNTAX : rc);
    if (job.status != EXTERIA_OK) exteria_plugin_close(p);
    return job.status;
}

static void push_send(lua_State *L, const exteria_plugin *p, const exteria_plugin_send *in) {
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, (lua_Integer)in->chat);
    lua_setfield(L, -2, "chat");
    lua_pushinteger(L, (lua_Integer)in->reply_to);
    lua_setfield(L, -2, "reply_to");
    if (p->permissions & EXTERIA_PERM_MESSAGES_READ) {
        lua_pushlstring(L, in->text ? in->text : "", in->text_len);
        lua_setfield(L, -2, "text");
    }
}

static void push_message(lua_State *L, const exteria_plugin *p, const exteria_plugin_message *in) {
    lua_createtable(L, 0, 5);
    lua_pushinteger(L, (lua_Integer)in->id);
    lua_setfield(L, -2, "id");
    lua_pushinteger(L, (lua_Integer)in->chat);
    lua_setfield(L, -2, "chat");
    lua_pushinteger(L, (lua_Integer)in->sender);
    lua_setfield(L, -2, "sender");
    lua_pushboolean(L, in->outgoing != 0);
    lua_setfield(L, -2, "outgoing");
    if (p->permissions & EXTERIA_PERM_MESSAGES_READ) {
        lua_pushlstring(L, in->text ? in->text : "", in->text_len);
        lua_setfield(L, -2, "text");
    }
}

static int message_main(lua_State *L) {
    message_job *job = lua_touserdata(L, 1);
    void *ud;
    exteria_plugin *p;
    int kind;
    (void)lua_getallocf(L, &ud);
    p = ud;
    job->status = EXTERIA_E_MALFORMED;
    lua_rawgeti(L, LUA_REGISTRYINDEX, p->table_ref);
    lua_getfield(L, -1, job->hook);
    if (job->send) push_send(L, p, job->send);
    else push_message(L, p, job->in);
    lua_call(L, 1, 1);
    kind = lua_type(L, -1);
    if (kind == LUA_TNIL) {
        job->status = EXTERIA_OK;
        return 0;
    }
    if (kind != LUA_TBOOLEAN && kind != LUA_TSTRING) {
        set_error(p, "on_message must return nil, false or a string");
        return 0;
    }
    if (kind == LUA_TBOOLEAN && lua_toboolean(L, -1)) {
        set_error(p, "on_message returned true");
        return 0;
    }
    if (!(p->permissions & EXTERIA_PERM_MESSAGES_MODIFY)) {
        set_error(p, "messages.modify is not granted");
        job->status = EXTERIA_E_SECURITY;
        return 0;
    }
    if (kind == LUA_TBOOLEAN) {
        job->action = EXTERIA_PLUGIN_CANCEL;
        job->status = EXTERIA_OK;
        return 0;
    }
    {
        size_t len;
        const char *text = lua_tolstring(L, -1, &len);
        if (len == 0 || !valid_utf8((const unsigned char *)text, len)) {
            set_error(p, "the replacement must be non-empty utf-8");
            return 0;
        }
        if (len > EXTERIA_PLUGIN_TEXT_MAX || len >= job->cap) {
            set_error(p, "the replacement is too long");
            job->status = EXTERIA_E_LIMIT;
            return 0;
        }
        /* an unchanged text is not an edit */
        const char *before = job->send ? job->send->text : job->in->text;
        size_t before_len = job->send ? job->send->text_len : job->in->text_len;
        if (len == before_len && before && memcmp(text, before, len) == 0) {
            job->status = EXTERIA_OK;
            return 0;
        }
        memcpy(job->out, text, len);
        job->out[len] = 0;
        job->out_len = len;
        job->action = EXTERIA_PLUGIN_REPLACE;
        job->status = EXTERIA_OK;
    }
    return 0;
}

static exteria_status run_text_hook(exteria_plugin *p, uint32_t bit, const char *hook, message_job *job,
                                   exteria_plugin_action *action, char *out, size_t cap, size_t *out_len) {
    int rc;
    if (action) *action = EXTERIA_PLUGIN_PASS;
    if (out_len) *out_len = 0;
    if (out && cap) out[0] = 0;
    if (!p || !action || !out || cap == 0 || !out_len) return EXTERIA_E_ARG;
    if (!p->lua) return EXTERIA_E_STATE;
    /* a plugin without this hook leaves the message alone */
    if (!(p->hooks & bit)) return EXTERIA_OK;
    job->hook = hook;
    job->action = EXTERIA_PLUGIN_PASS;
    job->out = out;
    job->cap = cap;
    job->out_len = 0;
    job->status = EXTERIA_E_STATE;
    p->error[0] = 0;
    p->log_lines = 0;
    arm(p);
    lua_pushcfunction(p->lua, message_main);
    lua_pushlightuserdata(p->lua, job);
    rc = lua_pcall(p->lua, 1, 0, 0);
    disarm(p);
    if (rc != LUA_OK) {
        job->status = map_failure(p, rc);
        job->action = EXTERIA_PLUGIN_PASS;
    }
    if (job->status != EXTERIA_OK) {
        out[0] = 0;
        return job->status;
    }
    *action = job->action;
    *out_len = job->out_len;
    return EXTERIA_OK;
}

exteria_status exteria_plugin_on_message(exteria_plugin *p, const exteria_plugin_message *in,
                                        exteria_plugin_action *action, char *out, size_t cap, size_t *out_len) {
    message_job job;
    memset(&job, 0, sizeof job);
    if (action) *action = EXTERIA_PLUGIN_PASS;
    if (out_len) *out_len = 0;
    if (out && cap) out[0] = 0;
    if (!in) return EXTERIA_E_ARG;
    if (in->text_len > EXTERIA_PLUGIN_TEXT_MAX || (in->text_len && !in->text)) return EXTERIA_E_LIMIT;
    job.in = in;
    return run_text_hook(p, EXTERIA_HOOK_MESSAGE, "on_message", &job, action, out, cap, out_len);
}

exteria_status exteria_plugin_on_send(exteria_plugin *p, const exteria_plugin_send *in,
                                     exteria_plugin_action *action, char *out, size_t cap, size_t *out_len) {
    message_job job;
    memset(&job, 0, sizeof job);
    if (action) *action = EXTERIA_PLUGIN_PASS;
    if (out_len) *out_len = 0;
    if (out && cap) out[0] = 0;
    if (!in) return EXTERIA_E_ARG;
    if (in->text_len > EXTERIA_PLUGIN_TEXT_MAX || (in->text_len && !in->text)) return EXTERIA_E_LIMIT;
    job.send = in;
    return run_text_hook(p, EXTERIA_HOOK_SEND, "on_send", &job, action, out, cap, out_len);
}

static int event_main(lua_State *L) {
    const char *name = lua_touserdata(L, 1);
    void *ud;
    exteria_plugin *p;
    (void)lua_getallocf(L, &ud);
    p = ud;
    lua_rawgeti(L, LUA_REGISTRYINDEX, p->table_ref);
    lua_getfield(L, -1, "on_event");
    lua_pushstring(L, name);
    lua_call(L, 1, 0);
    return 0;
}

exteria_status exteria_plugin_on_event(exteria_plugin *p, const char *name) {
    int rc;
    if (!p || !name) return EXTERIA_E_ARG;
    if (strcmp(name, "start") && strcmp(name, "stop") && strcmp(name, "pause") && strcmp(name, "resume")) return EXTERIA_E_ARG;
    if (!p->lua) return EXTERIA_E_STATE;
    if (!(p->hooks & EXTERIA_HOOK_EVENT)) return EXTERIA_OK;
    p->error[0] = 0;
    p->log_lines = 0;
    arm(p);
    lua_pushcfunction(p->lua, event_main);
    lua_pushlightuserdata(p->lua, (void *)name);
    rc = lua_pcall(p->lua, 1, 0, 0);
    disarm(p);
    return rc == LUA_OK ? EXTERIA_OK : map_failure(p, rc);
}

void exteria_plugin_close(exteria_plugin *p) {
    if (!p) return;
    if (p->lua) lua_close(p->lua);
    p->lua = NULL;
    p->table_ref = LUA_NOREF;
    p->permissions = 0;
    p->hooks = 0;
    p->name[0] = 0;
}
