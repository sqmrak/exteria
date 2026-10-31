#include "exteria_plugin.h"
#include "test_util.h"

#define SRC(s) s, sizeof(s) - 1

static const exteria_plugin_message hello = { 7, -100123, 42, 0, "hello world", 11 };

static exteria_status run(exteria_plugin *p, const exteria_plugin_message *m, exteria_plugin_action *action,
                          char *out, size_t cap, size_t *len) {
    return exteria_plugin_on_message(p, m, action, out, cap, len);
}

static void loads_and_reads_manifest(void) {
    static const char script[] =
        "return { name = 'echo', version = '1', permissions = { 'messages.read', 'messages.modify' },\n"
        "  on_message = function(m) end }";
    exteria_plugin p;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK(strcmp(p.name, "echo") == 0);
    CHECK_EQ_INT(p.permissions, EXTERIA_PERM_MESSAGES_READ | EXTERIA_PERM_MESSAGES_MODIFY);
    exteria_plugin_close(&p);
    CHECK(p.lua == NULL);
}

static void rejects_bad_scripts(void) {
    static const struct { const char *src; exteria_status status; } cases[] = {
        { "return {", EXTERIA_E_MALFORMED },
        { "return 5", EXTERIA_E_MALFORMED },
        { "return { permissions = {}, on_message = function() end }", EXTERIA_E_MALFORMED },
        { "return { name = '', permissions = {}, on_message = function() end }", EXTERIA_E_MALFORMED },
        { "return { name = 'a\\nb', permissions = {}, on_message = function() end }", EXTERIA_E_MALFORMED },
        { "return { name = 'a', permissions = {} }", EXTERIA_E_MALFORMED },
        { "return { name = 'a', on_message = function() end }", EXTERIA_E_MALFORMED },
        { "return { name = 'a', permissions = { 'files.write' }, on_message = function() end }", EXTERIA_E_UNSUPPORTED },
        { "return { name = 'a', permissions = { 5 }, on_message = function() end }", EXTERIA_E_MALFORMED },
        { "return { name = 'a', permissions = { 'messages.read', 'messages.read', 'messages.read', 'messages.read',"
          " 'messages.read', 'messages.read', 'messages.read', 'messages.read', 'messages.read' },"
          " on_message = function() end }", EXTERIA_E_LIMIT },
        { "error('boom')", EXTERIA_E_STATE },
        { "return { name = 'a', permissions = {}, on_message = function() end }, nil, x.y.z", EXTERIA_E_STATE },
        { "\x1bLua", EXTERIA_E_MALFORMED }
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        exteria_plugin p;
        exteria_status status = exteria_plugin_load(&p, cases[i].src, strlen(cases[i].src));
        if (status != cases[i].status) fprintf(stderr, "case %zu: got %d\n", i, (int)status);
        CHECK_EQ_INT(status, cases[i].status);
        CHECK(p.lua == NULL);
        CHECK(p.error[0] != 0);
    }
    {
        exteria_plugin p;
        CHECK_EQ_INT(exteria_plugin_load(NULL, "x", 1), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_plugin_load(&p, NULL, 0), EXTERIA_E_ARG);
        CHECK_EQ_INT(exteria_plugin_load(&p, "", 0), EXTERIA_E_ARG);
    }
}

static void rejects_oversized_script(void) {
    static char big[EXTERIA_PLUGIN_SCRIPT_MAX + 1];
    exteria_plugin p;
    memset(big, ' ', sizeof big);
    CHECK_EQ_INT(exteria_plugin_load(&p, big, sizeof big), EXTERIA_E_LIMIT);
    CHECK(p.lua == NULL);
}

static void passes_hides_and_replaces(void) {
    static const char script[] =
        "return { name = 'filter', permissions = { 'messages.read', 'messages.modify' },\n"
        "  on_message = function(m)\n"
        "    if m.text:find('spam', 1, true) then return false end\n"
        "    if m.text == 'hello world' then return (m.text:gsub('world', 'there')) end\n"
        "    if m.text == 'same' then return m.text end\n"
        "  end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[64];
    size_t len;
    exteria_plugin_message m = hello;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_REPLACE);
    CHECK_EQ_INT(len, 11);
    CHECK(strcmp(out, "hello there") == 0);
    m.text = "buy spam now";
    m.text_len = 12;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_CANCEL);
    CHECK_EQ_INT(len, 0);
    m.text = "same";
    m.text_len = 4;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    m.text = "plain";
    m.text_len = 5;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&p);
}

static void message_fields_reach_the_hook(void) {
    static const char script[] =
        "return { name = 'fields', permissions = { 'messages.read', 'messages.modify' },\n"
        "  on_message = function(m)\n"
        "    return m.id .. ':' .. m.chat .. ':' .. m.sender .. ':' .. tostring(m.outgoing) .. ':' .. m.text\n"
        "  end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[96];
    size_t len;
    exteria_plugin_message m = { 9, -1001234567890LL, 5000000000LL, 1, "a\xd0\xb1" "c", 4 };
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_REPLACE);
    CHECK(strcmp(out, "9:-1001234567890:5000000000:true:a\xd0\xb1" "c") == 0);
    exteria_plugin_close(&p);
}

static void text_needs_read_permission(void) {
    static const char script[] =
        "return { name = 'blind', permissions = { 'messages.modify' },\n"
        "  on_message = function(m) if m.text == nil and m.sender == 42 then return false end end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[16];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_CANCEL);
    exteria_plugin_close(&p);
}

static void modify_needs_permission(void) {
    static const char hide[] =
        "return { name = 'h', permissions = { 'messages.read' }, on_message = function(m) return false end }";
    static const char edit[] =
        "return { name = 'e', permissions = { 'messages.read' }, on_message = function(m) return 'x' end }";
    exteria_plugin p;
    exteria_plugin_action action = EXTERIA_PLUGIN_CANCEL;
    char out[16];
    size_t len = 99;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(hide)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    CHECK_EQ_INT(len, 0);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(edit)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&p);
}

static void bad_answers_keep_the_message(void) {
    static const char *const answers[] = {
        "true", "5", "{}", "''", "'\\xff'", "'\\xc0\\x80'", "'\\xed\\xa0\\x80'", "'\\xf4\\x90\\x80\\x80'", "'a\\xe2\\x82'"
    };
    for (size_t i = 0; i < sizeof answers / sizeof answers[0]; ++i) {
        char script[256];
        exteria_plugin p;
        exteria_plugin_action action = EXTERIA_PLUGIN_CANCEL;
        char out[16];
        size_t len;
        exteria_status status;
        snprintf(script, sizeof script,
                 "return { name = 'b', permissions = { 'messages.modify' }, on_message = function(m) return %s end }",
                 answers[i]);
        CHECK_EQ_INT(exteria_plugin_load(&p, script, strlen(script)), EXTERIA_OK);
        status = run(&p, &hello, &action, out, sizeof out, &len);
        if (status != EXTERIA_E_MALFORMED) fprintf(stderr, "answer %zu: got %d\n", i, (int)status);
        CHECK_EQ_INT(status, EXTERIA_E_MALFORMED);
        CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
        exteria_plugin_close(&p);
    }
}

static void output_buffer_is_bounded(void) {
    static const char script[] =
        "return { name = 'big', permissions = { 'messages.modify' },\n"
        "  on_message = function(m) return string.rep('a', 16) end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[16];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    /* 16 bytes need a 17 byte buffer for the terminator */
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_LIMIT);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&p);
}

static void input_is_bounded(void) {
    static const char script[] =
        "return { name = 'n', permissions = {}, on_message = function(m) end }";
    static char text[EXTERIA_PLUGIN_TEXT_MAX + 1];
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    exteria_plugin_message m = { 1, 2, 3, 0, text, EXTERIA_PLUGIN_TEXT_MAX };
    memset(text, 'a', sizeof text);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    m.text_len = sizeof text;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_E_LIMIT);
    m.text = NULL;
    m.text_len = 1;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_E_LIMIT);
    m.text_len = 0;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &m, &action, out, 0, &len), EXTERIA_E_ARG);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_STATE);
}

static void sandbox_hides_the_host(void) {
    static const char *const probes[] = {
        "io", "os", "debug", "package", "require", "load", "loadstring", "dofile", "loadfile", "print",
        "collectgarbage", "coroutine", "_G", "string.dump", "getmetatable('').__index.dump"
    };
    for (size_t i = 0; i < sizeof probes / sizeof probes[0]; ++i) {
        char script[256];
        exteria_plugin p;
        exteria_plugin_action action;
        char out[8];
        size_t len;
        snprintf(script, sizeof script,
                 "return { name = 's', permissions = { 'messages.modify' },"
                 " on_message = function(m) if %s ~= nil then return false end end }", probes[i]);
        CHECK_EQ_INT(exteria_plugin_load(&p, script, strlen(script)), EXTERIA_OK);
        CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
        if (action != EXTERIA_PLUGIN_PASS) fprintf(stderr, "sandbox leaks %s\n", probes[i]);
        CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
        exteria_plugin_close(&p);
    }
}

static void state_does_not_leak_between_plugins(void) {
    static const char a[] =
        "counter = 0\n"
        "return { name = 'a', permissions = {}, on_message = function(m) counter = counter + 1 end }";
    static const char b[] =
        "return { name = 'b', permissions = { 'messages.modify' }, on_message = function(m) if counter ~= nil then return false end end }";
    exteria_plugin pa, pb;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&pa, SRC(a)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_plugin_load(&pb, SRC(b)), EXTERIA_OK);
    CHECK_EQ_INT(run(&pa, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(run(&pb, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&pa);
    exteria_plugin_close(&pb);
}

static void runtime_error_keeps_the_message(void) {
    static const char script[] =
        "return { name = 'err', permissions = {}, on_message = function(m) if m.id == 7 then error('bad') end end }";
    exteria_plugin p;
    exteria_plugin_action action = EXTERIA_PLUGIN_CANCEL;
    char out[8];
    size_t len;
    exteria_plugin_message other = hello;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_STATE);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    CHECK(strstr(p.error, "bad") != NULL);
    /* the plugin stays usable after a failed call */
    other.id = 8;
    CHECK_EQ_INT(run(&p, &other, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(p.error[0], 0);
    exteria_plugin_close(&p);
}

static void endless_loops_time_out(void) {
    static const char at_load[] = "while true do end";
    static const char in_hook[] =
        "return { name = 'spin', permissions = {}, on_message = function(m) while true do end end }";
    static const char shielded[] =
        "return { name = 'pc', permissions = {}, on_message = function(m)\n"
        "  while true do pcall(function() while true do end end) end end }";
    static const char nested[] =
        "return { name = 'pc2', permissions = {}, on_message = function(m)\n"
        "  local function f() return pcall(f) end\n"
        "  while true do f() end end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(at_load)), EXTERIA_E_TIMEOUT);
    CHECK(p.lua == NULL);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(in_hook)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_TIMEOUT);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(shielded)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_TIMEOUT);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(nested)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_TIMEOUT);
    exteria_plugin_close(&p);
}

static void budget_resets_every_call(void) {
    static const char script[] =
        "return { name = 'work', permissions = {}, on_message = function(m)\n"
        "  local n = 0 for i = 1, 20000 do n = n + i end end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    for (int i = 0; i < 20; ++i) CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
    exteria_plugin_close(&p);
}

static void memory_is_capped(void) {
    static const char at_load[] = "local s = 'x' for i = 1, 40 do s = s .. s end";
    static const char in_hook[] =
        "return { name = 'mem', permissions = {}, on_message = function(m) return string.rep('x', 1e9) end }";
    static const char grows[] =
        "return { name = 'mem2', permissions = {}, on_message = function(m)\n"
        "  local s = 'x' while true do s = s .. s end end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(at_load)), EXTERIA_E_NOMEM);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(in_hook)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_NOMEM);
    CHECK(p.mem_used <= p.mem_limit);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(grows)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_E_NOMEM);
    CHECK(p.mem_used <= p.mem_limit);
    exteria_plugin_close(&p);
}

static void pattern_backtracking_is_bounded(void) {
    static const char script[] =
        "return { name = 'pat', permissions = { 'messages.read' }, on_message = function(m)\n"
        "  return m.text:find('.-.-.-.-.-.-x') end }";
    static char text[EXTERIA_PLUGIN_TEXT_MAX];
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    exteria_plugin_message m = { 1, 2, 3, 0, text, sizeof text };
    memset(text, 'a', sizeof text);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_E_STATE);
    CHECK(strstr(p.error, "pattern too complex") != NULL);
    exteria_plugin_close(&p);
}

static char logged[8][256];
static int logged_count;

static void capture_log(const char *plugin, const char *line) {
    if (logged_count < 8) snprintf(logged[logged_count], sizeof logged[0], "%s|%s", plugin, line);
    ++logged_count;
}

static void send_hook_hides_and_replaces(void) {
    static const char script[] =
        "return { name = 'outbox', permissions = { 'messages.read', 'messages.modify' },\n"
        "  on_send = function(m)\n"
        "    if m.text == 'secret' then return false end\n"
        "    if m.text == 'hi' then return 'hi, ' .. m.chat .. ' ' .. m.reply_to end\n"
        "  end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[64];
    size_t len;
    exteria_plugin_send m = { -42, 7, "hi", 2 };
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(p.hooks, EXTERIA_HOOK_SEND);
    CHECK_EQ_INT(exteria_plugin_on_send(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_REPLACE);
    CHECK(strcmp(out, "hi, -42 7") == 0);
    m.text = "secret";
    m.text_len = 6;
    CHECK_EQ_INT(exteria_plugin_on_send(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_CANCEL);
    m.text = "other";
    m.text_len = 5;
    CHECK_EQ_INT(exteria_plugin_on_send(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    /* the incoming hook is absent, so a message passes untouched */
    CHECK_EQ_INT(run(&p, &hello, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    CHECK_EQ_INT(exteria_plugin_on_send(&p, NULL, &action, out, sizeof out, &len), EXTERIA_E_ARG);
    exteria_plugin_close(&p);
}

static void send_hook_needs_permissions(void) {
    static const char blind[] =
        "return { name = 'b', permissions = { 'messages.modify' }, on_send = function(m) if m.text == nil then return 'x' end end }";
    static const char readonly[] =
        "return { name = 'r', permissions = { 'messages.read' }, on_send = function(m) return false end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[16];
    size_t len;
    exteria_plugin_send m = { 1, 0, "hi", 2 };
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(blind)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_plugin_on_send(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_REPLACE);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(readonly)), EXTERIA_OK);
    CHECK_EQ_INT(exteria_plugin_on_send(&p, &m, &action, out, sizeof out, &len), EXTERIA_E_SECURITY);
    CHECK_EQ_INT(action, EXTERIA_PLUGIN_PASS);
    exteria_plugin_close(&p);
}

static void events_reach_the_plugin(void) {
    static const char script[] =
        "local seen = 0\n"
        "return { name = 'life', permissions = {}, on_event = function(name)\n"
        "  seen = seen + 1 log(name .. seen) if name == 'stop' then error('late') end end }";
    exteria_plugin p;
    logged_count = 0;
    exteria_plugin_set_log(capture_log);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    CHECK_EQ_INT(p.hooks, EXTERIA_HOOK_EVENT);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, "start"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, "pause"), EXTERIA_OK);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, "stop"), EXTERIA_E_STATE);
    CHECK(strstr(p.error, "late") != NULL);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, "bogus"), EXTERIA_E_ARG);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, NULL), EXTERIA_E_ARG);
    CHECK_EQ_INT(logged_count, 3);
    CHECK(strcmp(logged[0], "life|start1") == 0);
    CHECK(strcmp(logged[1], "life|pause2") == 0);
    CHECK(strcmp(logged[2], "life|stop3") == 0);
    exteria_plugin_close(&p);
    CHECK_EQ_INT(exteria_plugin_on_event(&p, "start"), EXTERIA_E_STATE);
    exteria_plugin_set_log(NULL);
}

static void log_is_bounded(void) {
    static const char script[] =
        "return { name = 'chatty', permissions = {}, on_message = function(m)\n"
        "  if m.id == 1 then log(string.rep('x', 500)) end\n"
        "  if m.id == 2 then for i = 1, 17 do log(i) end end end }";
    exteria_plugin p;
    exteria_plugin_action action;
    char out[8];
    size_t len;
    exteria_plugin_message m = hello;
    logged_count = 0;
    exteria_plugin_set_log(capture_log);
    CHECK_EQ_INT(exteria_plugin_load(&p, SRC(script)), EXTERIA_OK);
    m.id = 1;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    CHECK_EQ_INT(logged_count, 1);
    CHECK_EQ_INT(strlen(logged[0]), strlen("chatty|") + 200);
    logged_count = 0;
    m.id = 2;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_E_STATE);
    CHECK_EQ_INT(logged_count, 16);
    CHECK(strstr(p.error, "too many log lines") != NULL);
    /* the count starts over with every call */
    m.id = 1;
    CHECK_EQ_INT(run(&p, &m, &action, out, sizeof out, &len), EXTERIA_OK);
    exteria_plugin_close(&p);
    exteria_plugin_set_log(NULL);
}

static void hooks_must_be_functions(void) {
    static const char *const scripts[] = {
        "return { name = 'a', permissions = {}, on_send = 5 }",
        "return { name = 'a', permissions = {}, on_event = 'x', on_message = function() end }",
        "return { name = 'a', permissions = {} }"
    };
    for (size_t i = 0; i < sizeof scripts / sizeof scripts[0]; ++i) {
        exteria_plugin p;
        CHECK_EQ_INT(exteria_plugin_load(&p, scripts[i], strlen(scripts[i])), EXTERIA_E_MALFORMED);
        CHECK(p.lua == NULL);
    }
}

int main(void) {
    loads_and_reads_manifest();
    rejects_bad_scripts();
    rejects_oversized_script();
    passes_hides_and_replaces();
    message_fields_reach_the_hook();
    text_needs_read_permission();
    modify_needs_permission();
    bad_answers_keep_the_message();
    output_buffer_is_bounded();
    input_is_bounded();
    sandbox_hides_the_host();
    state_does_not_leak_between_plugins();
    runtime_error_keeps_the_message();
    endless_loops_time_out();
    budget_resets_every_call();
    memory_is_capped();
    pattern_backtracking_is_bounded();
    send_hook_hides_and_replaces();
    send_hook_needs_permissions();
    events_reach_the_plugin();
    log_is_bounded();
    hooks_must_be_functions();
    return test_finish("test_plugin");
}
