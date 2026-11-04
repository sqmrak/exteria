#import "exteria_plugins.h"

#import <CommonCrypto/CommonDigest.h>
#import "exteria_message.h"
#import "exteria_plugin_ui.h"
#import "exteria_language.h"
#include "exteria_doom.h"
#include "exteria_pyhost.h"

NSString *const ExteriaPluginsDidChangeNotification = @"ExteriaPluginsDidChange";

static NSString *const ExteriaPluginsEnabledKey = @"exteria.plugins.enabled";
static NSString *const ExteriaPluginsSettingsKey = @"exteria.plugins.settings";
/* a folder of hundreds of files would stall the page, each one is parsed to read its name */
#define PLUGINS_LISTED_MAX 64
#define RESULTS_MAX 512
/* the exteraGram catalog has plugins of several hundred KiB */
#define PLUGIN_FILE_MAX (1024 * 1024)
#define SETTING_VALUE_MAX 16384
#define SETTINGS_PER_PLUGIN_MAX 256
#define TEXT_MAX 16384
/* importing the sdk from source on the first call takes seconds on an iphone 4, the hooks after it are bytecode in a loop */
#define LOAD_TIMEOUT_MS 20000
#define SCAN_TIMEOUT_MS 5000
#define HOOK_TIMEOUT_MS 400
/* a call queued with Handler may load a game or a large module: it gets time, the hooks above stay short */
#define QUEUED_TIMEOUT_MS 5000

@interface ExteriaPluginEntry ()
- (id)initWithFile:(NSString *)file;
@property (nonatomic, assign) int status;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL changed;
@property (nonatomic, copy) NSString *pluginId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *error;
@property (nonatomic, copy) NSString *fault;
@property (nonatomic, retain) NSDictionary *failure;
@property (nonatomic, retain) NSArray *permissions;
@property (nonatomic, assign) BOOL hasSettings;
@end

@implementation ExteriaPluginEntry
@synthesize file = _file, pluginId = _pluginId, name = _name, author = _author, version = _version, status = _status, error = _error,
            permissions = _permissions, enabled = _enabled, changed = _changed, fault = _fault, failure = _failure, hasSettings = _hasSettings;

- (id)initWithFile:(NSString *)file {
    self = [super init];
    if (self) _file = [file copy];
    return self;
}

- (void)dealloc {
    [_file release];
    [_pluginId release];
    [_name release];
    [_author release];
    [_version release];
    [_error release];
    [_fault release];
    [_failure release];
    [_permissions release];
    [super dealloc];
}
@end

/* a file found in the folder: what the sdk read from it, and the state of the plugin while it is on */
@interface ExteriaPluginSlot : NSObject {
@public
    ExteriaPluginEntry *entry;
    NSString *digest;
    NSString *path;
    /* the module is imported and on_plugin_load has run */
    BOOL loaded;
    /* on_plugin_load runs before loaded is set, and the services it calls must already answer */
    BOOL loading;
    BOOL sendHook;
    BOOL updateHook;
    /* a plugin hooks ChatMessageCell.setMessageContent: the messages on show are asked what they say */
    BOOL displayHook;
    int faults;
    NSMutableDictionary *menu;
    unsigned menuCounter;
}
@end

@implementation ExteriaPluginSlot
- (void)dealloc {
    [entry release];
    [digest release];
    [path release];
    [menu release];
    [super dealloc];
}
@end

static NSMutableArray *g_slots;
/* a result of the incoming hooks is kept per message text, since the chat is ordered again on every change; a new
   generation drops them all when a plugin is switched or a file changes */
static NSMutableDictionary *g_results;
static unsigned g_generation;
static BOOL g_started;
/* 0 not tried, 1 running, -1 did not start: the second try would fail the same way */
static int g_python;

static ExteriaPluginSlot *slot_for_file(NSString *file) {
    for (ExteriaPluginSlot *slot in g_slots) if ([slot->entry.file isEqualToString:file]) return slot;
    return nil;
}

static ExteriaPluginSlot *slot_for_id(NSString *pluginId) {
    for (ExteriaPluginSlot *slot in g_slots) if (slot->entry.pluginId && [slot->entry.pluginId isEqualToString:pluginId]) return slot;
    return nil;
}

#define LOG_FILE_MAX (256 * 1024)
#define LOG_FILE_KEEP (128 * 1024)

void ExteriaPluginsLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    va_end(arguments);
    NSLog(@"%@", line);
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString *path = [caches stringByAppendingPathComponent:@"exteria-plugins.log"];
    FILE *file = fopen([path fileSystemRepresentation], "a");
    if (!file) return;
    fprintf(file, "%.0f %s\n", [[NSDate date] timeIntervalSince1970], [line UTF8String]);
    long size = ftell(file);
    fclose(file);
    if (size <= LOG_FILE_MAX) return;
    /* over the cap: the newest half stays */
    NSData *all = [NSData dataWithContentsOfFile:path];
    if (all.length > LOG_FILE_KEEP) [[all subdataWithRange:NSMakeRange(all.length - LOG_FILE_KEEP, LOG_FILE_KEEP)] writeToFile:path atomically:YES];
}

NSString *ExteriaPluginsDirectory(void) {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *directory = [documents stringByAppendingPathComponent:@"Plugins"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        ExteriaPluginsLog(@"exteria: the plugins folder could not be made: %@", error);
    }
    return directory;
}

NSString *ExteriaPluginsCacheDirectory(void) {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString *directory = [caches stringByAppendingPathComponent:@"exteria-plugin-files"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        ExteriaPluginsLog(@"exteria: the plugin files folder could not be made: %@", error);
    }
    return directory;
}

BOOL ExteriaPluginsPathInCache(NSString *path) {
    /* symlinks resolved first: a link inside the folder must not lead out of it */
    NSString *root = [ExteriaPluginsCacheDirectory() stringByResolvingSymlinksInPath];
    return [[path stringByResolvingSymlinksInPath] hasPrefix:[root stringByAppendingString:@"/"]];
}

BOOL ExteriaPluginsAcceptsExtension(NSString *extension) {
    /* the scan matches lower case only, so does this */
    return [extension isEqualToString:@"plugin"] || [extension isEqualToString:@"py"] || [extension isEqualToString:@"elyx"];
}

static NSString *digest_of(NSData *data) {
    unsigned char sum[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, sum);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * sizeof(sum)];
    for (size_t i = 0; i < sizeof(sum); ++i) [hex appendFormat:@"%02x", sum[i]];
    return hex;
}

/* the bytes of a plugin file, or nil with the status the page shows: too large, empty, or unreadable */
static NSData *read_plugin(NSString *path, int *status) {
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (!attributes) {
        ExteriaPluginsLog(@"exteria: the plugin %@ could not be read: %@", [path lastPathComponent], error);
        *status = EXTERIA_E_IO;
        return nil;
    }
    if ([attributes fileSize] > PLUGIN_FILE_MAX) {
        *status = EXTERIA_E_LIMIT;
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data) {
        ExteriaPluginsLog(@"exteria: the plugin %@ could not be read: %@", [path lastPathComponent], error);
        *status = EXTERIA_E_IO;
        return nil;
    }
    if (!data.length) {
        *status = EXTERIA_E_MALFORMED;
        return nil;
    }
    return data;
}

static NSDictionary *enabled_digests(void) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaPluginsEnabledKey];
    return stored ? stored : [NSDictionary dictionary];
}

static void store_enabled(NSString *file, NSString *digest) {
    NSMutableDictionary *all = [[enabled_digests() mutableCopy] autorelease];
    if (digest) [all setObject:digest forKey:file];
    else [all removeObjectForKey:file];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:ExteriaPluginsEnabledKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) ExteriaPluginsLog(@"exteria: the plugin switches were not saved");
}

static void changed(void) {
    ++g_generation;
    [g_results removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginsDidChangeNotification object:nil];
}

#pragma mark settings of the plugins

static NSMutableDictionary *settings_of(NSString *pluginId) {
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaPluginsSettingsKey];
    NSDictionary *mine = [all objectForKey:pluginId];
    return mine ? [[mine mutableCopy] autorelease] : [NSMutableDictionary dictionary];
}

static void store_settings(NSString *pluginId, NSDictionary *values) {
    NSMutableDictionary *all = [[[[NSUserDefaults standardUserDefaults] dictionaryForKey:ExteriaPluginsSettingsKey] mutableCopy] autorelease];
    if (!all) all = [NSMutableDictionary dictionary];
    if (values.count) [all setObject:values forKey:pluginId];
    else [all removeObjectForKey:pluginId];
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:ExteriaPluginsSettingsKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) ExteriaPluginsLog(@"exteria: the plugin settings were not saved");
}

#pragma mark python calls

static NSString *python_error_text(void);

static NSString *json_string(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    return data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

/* calls exteria_host.<function>(*arguments) and gives the decoded result, nil when it failed or returned null. *status
   says which; the text of a failure is in exteria_pyhost_error. NSJSONSerialization cannot hold a bare number or null at the top, so the
   result is read with fragments allowed where the sdk has them */
static id python_call(NSString *function, NSArray *arguments, uint32_t timeout, exteria_status *status) {
    exteria_status local = EXTERIA_OK;
    if (!status) status = &local;
    *status = EXTERIA_OK;
    if (g_python <= 0) {
        *status = EXTERIA_E_STATE;
        return nil;
    }
    NSString *encoded = json_string(arguments);
    if (!encoded) {
        *status = EXTERIA_E_MALFORMED;
        return nil;
    }
    char *reply = malloc(EXTERIA_PYHOST_REPLY_MAX + 1);
    if (!reply) {
        *status = EXTERIA_E_NOMEM;
        return nil;
    }
    size_t length = 0;
    *status = exteria_pyhost_call("exteria_host", [function UTF8String], [encoded UTF8String], timeout, reply, EXTERIA_PYHOST_REPLY_MAX, &length);
    id result = nil;
    if (*status == EXTERIA_OK && length) {
        NSData *data = [NSData dataWithBytesNoCopy:reply length:length freeWhenDone:NO];
        result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:NULL];
        if (result == [NSNull null]) result = nil;
    }
    free(reply);
    return result;
}

id ExteriaPluginsCallHost(NSString *function, NSArray *arguments) {
    if (![NSThread isMainThread]) {
        ExteriaPluginsLog(@"exteria: python call %@ from a background thread, skipped", function);
        return nil;
    }
    exteria_status status = EXTERIA_OK;
    id result = python_call(function, arguments, HOOK_TIMEOUT_MS, &status);
    if (status != EXTERIA_OK) ExteriaPluginsLog(@"exteria: %@ failed (%d): %@", function, (int)status, python_error_text());
    return result;
}

#pragma mark services for python

static exteria_status reply_json(id object, char *out, size_t cap, size_t *out_len) {
    NSString *text = json_string(object);
    const char *utf8 = [text UTF8String];
    size_t length = utf8 ? strlen(utf8) : 0;
    if (!utf8 || length > cap) return EXTERIA_E_LIMIT;
    memcpy(out, utf8, length);
    *out_len = length;
    return EXTERIA_OK;
}

static exteria_status reply_text(const char *text, exteria_status status, char *out, size_t cap, size_t *out_len) {
    size_t length = strlen(text);
    if (length > cap) length = cap;
    memcpy(out, text, length);
    *out_len = length;
    return status;
}

static exteria_status reply_value(id value, char *out, size_t cap, size_t *out_len) {
    return reply_json([NSDictionary dictionaryWithObject:value ? value : [NSNull null] forKey:@"value"], out, cap, out_len);
}

static BOOL granted(ExteriaPluginSlot *slot, NSString *permission) {
    /* the ui permission is always on, the rest are what the person saw when they turned the plugin on */
    if ([permission isEqualToString:@"ui"]) return YES;
    return [slot->entry.permissions containsObject:permission];
}

static void run_token_later(NSNumber *token, int64_t delay_ms) {
    dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, delay_ms * (int64_t)NSEC_PER_MSEC);
    dispatch_after(when, dispatch_get_main_queue(), ^{
        python_call(@"run_token", [NSArray arrayWithObject:token], QUEUED_TIMEOUT_MS, NULL);
    });
}

/* what python asks of the app: see python/shim/app/exteraless/plugins. every request names its plugin, and only a plugin
   that is loading or loaded is served */
static exteria_status plugin_service(void *ctx, const char *name_c, const char *payload, size_t payload_len,
                                     char *out, size_t cap, size_t *out_len) {
    (void)ctx;
    *out_len = 0;
    NSString *name = [NSString stringWithUTF8String:name_c];
    NSData *data = [NSData dataWithBytesNoCopy:(void *)payload length:payload_len freeWhenDone:NO];
    id parsed = payload_len ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : [NSDictionary dictionary];
    if (![parsed isKindOfClass:[NSDictionary class]]) return reply_text("the request is not a json object", EXTERIA_E_ARG, out, cap, out_len);
    NSDictionary *request = parsed;

    /* uikit is main thread only: python hands every call from a worker thread to the main one, so this is the second check */
    if (![NSThread isMainThread] && ![name isEqualToString:@"ui.run"]) {
        return reply_text("the app is served on its main thread only", EXTERIA_E_STATE, out, cap, out_len);
    }
    if ([name hasPrefix:@"ui."] || [name hasPrefix:@"sensor."] || [name hasPrefix:@"theme."] || [name hasPrefix:@"app."] || [name hasPrefix:@"chat."] || [name hasPrefix:@"sheet."] || [name hasPrefix:@"audio."]) {
        NSDictionary *answer = nil;
        NSString *failure = nil;
        exteria_status result = ExteriaPluginUIService(name, request, &answer, &failure);
        /* a name the view layer does not own, such as ui.run, is answered below */
        if (result != EXTERIA_E_UNSUPPORTED || failure) {
            if (result != EXTERIA_OK) return reply_text([failure ? failure : name UTF8String], result, out, cap, out_len);
            return reply_json(answer, out, cap, out_len);
        }
    }
    /* a queued call names no plugin: the token belongs to python */
    if ([name isEqualToString:@"ui.run"]) {
        NSNumber *token = [request objectForKey:@"token"];
        int64_t delay = [[request objectForKey:@"delay"] longLongValue];
        if (![token isKindOfClass:[NSNumber class]] || delay < 0 || delay > 60000) return reply_text("bad ui request", EXTERIA_E_ARG, out, cap, out_len);
        run_token_later(token, delay);
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"plugins.dir"]) return reply_value(ExteriaPluginsDirectory(), out, cap, out_len);
    if ([name isEqualToString:@"files.cache"]) return reply_value(ExteriaPluginsCacheDirectory(), out, cap, out_len);
    if ([name isEqualToString:@"permission.unsafe"]) return reply_value([NSNumber numberWithBool:NO], out, cap, out_len);

    NSString *pluginId = [request objectForKey:@"plugin"];
    ExteriaPluginSlot *slot = [pluginId isKindOfClass:[NSString class]] ? slot_for_id(pluginId) : nil;
    if (!slot || !(slot->loaded || slot->loading)) return reply_text("no such plugin is running", EXTERIA_E_NOTFOUND, out, cap, out_len);

    if ([name isEqualToString:@"log"]) {
        ExteriaPluginsLog(@"exteria: plugin %@: %@", pluginId, [request objectForKey:@"message"]);
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"permission.has"]) {
        return reply_value([NSNumber numberWithBool:granted(slot, [request objectForKey:@"permission"])], out, cap, out_len);
    }
    if ([name isEqualToString:@"permission.check"]) {
        NSString *permission = [request objectForKey:@"permission"];
        BOOL allowed = granted(slot, permission);
        if (!allowed) ExteriaPluginsLog(@"exteria: plugin %@ was refused %@ for %@", pluginId, permission, [request objectForKey:@"what"]);
        return reply_value([NSNumber numberWithBool:allowed], out, cap, out_len);
    }
    if ([name isEqualToString:@"settings.get"]) {
        return reply_value([settings_of(pluginId) objectForKey:[request objectForKey:@"key"]], out, cap, out_len);
    }
    if ([name isEqualToString:@"settings.set"]) {
        NSString *key = [request objectForKey:@"key"];
        NSString *value = [request objectForKey:@"value"];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) return reply_text("key and value are strings", EXTERIA_E_ARG, out, cap, out_len);
        if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > SETTING_VALUE_MAX) return reply_text("the value is too large", EXTERIA_E_LIMIT, out, cap, out_len);
        NSMutableDictionary *values = settings_of(pluginId);
        if (!([values objectForKey:key] || values.count < SETTINGS_PER_PLUGIN_MAX)) return reply_text("too many settings", EXTERIA_E_LIMIT, out, cap, out_len);
        [values setObject:value forKey:key];
        store_settings(pluginId, values);
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"settings.export"]) {
        NSMutableDictionary *decoded = [NSMutableDictionary dictionary];
        NSDictionary *values = settings_of(pluginId);
        for (NSString *key in values) {
            id one = [NSJSONSerialization JSONObjectWithData:[[values objectForKey:key] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:NULL];
            if (one) [decoded setObject:one forKey:key];
        }
        return reply_value(json_string(decoded), out, cap, out_len);
    }
    if ([name isEqualToString:@"settings.import"] || [name isEqualToString:@"settings.replace"]) {
        NSString *text = [request objectForKey:@"value"];
        id incoming = [text isKindOfClass:[NSString class]] ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        if (![incoming isKindOfClass:[NSDictionary class]] || [incoming count] > SETTINGS_PER_PLUGIN_MAX) return reply_text("not a settings object", EXTERIA_E_ARG, out, cap, out_len);
        NSMutableDictionary *values = [name isEqualToString:@"settings.import"] ? settings_of(pluginId) : [NSMutableDictionary dictionary];
        for (NSString *key in incoming) {
            NSString *one = json_string([NSArray arrayWithObject:[incoming objectForKey:key]]);
            /* the value is stored as json of itself, so the array wrapper is cut off */
            if (one.length < 2) continue;
            one = [one substringWithRange:NSMakeRange(1, one.length - 2)];
            if ([one lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > SETTING_VALUE_MAX) return reply_text("a value is too large", EXTERIA_E_LIMIT, out, cap, out_len);
            [values setObject:one forKey:key];
        }
        store_settings(pluginId, values);
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"settings.reload"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginsDidChangeNotification object:nil];
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"hook.send.add"]) {
        slot->sendHook = YES;
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"hook.send.remove"]) {
        slot->sendHook = NO;
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"hook.display.add"] || [name isEqualToString:@"hook.display.remove"]) {
        slot->displayHook = [name isEqualToString:@"hook.display.add"];
        g_generation++;
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"hook.request.add"] || [name isEqualToString:@"hook.request.remove"]) {
        /* the tl requests of the core do not pass through python, so a request hook is accepted and never called */
        ExteriaPluginsLog(@"exteria: plugin %@ asked for a request hook, which this app does not call", pluginId);
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    if ([name isEqualToString:@"menu.add"]) {
        NSDictionary *item = [request objectForKey:@"item"];
        if (![item isKindOfClass:[NSDictionary class]]) return reply_text("no menu item", EXTERIA_E_ARG, out, cap, out_len);
        if (!slot->menu) slot->menu = [[NSMutableDictionary alloc] init];
        NSString *itemId = [item objectForKey:@"item_id"];
        if (![itemId isKindOfClass:[NSString class]]) itemId = [NSString stringWithFormat:@"%@.%u", pluginId, ++slot->menuCounter];
        [slot->menu setObject:item forKey:itemId];
        ExteriaPluginsLog(@"exteria: plugin %@ added the menu item %@ (%@)", pluginId, itemId, [item objectForKey:@"menu_type"]);
        return reply_value(itemId, out, cap, out_len);
    }
    if ([name isEqualToString:@"menu.remove"]) {
        [slot->menu removeObjectForKey:[request objectForKey:@"id"]];
        return reply_json([NSDictionary dictionary], out, cap, out_len);
    }
    return reply_text(name_c, EXTERIA_E_UNSUPPORTED, out, cap, out_len);
}

#pragma mark the interpreter

static BOOL ensure_python(void) {
    if (g_python) return g_python > 0;
    NSString *root = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"python"];
    NSString *stdlib = [root stringByAppendingPathComponent:@"stdlib"];
    NSString *shim = [root stringByAppendingPathComponent:@"shim"];
    NSString *sdk = [root stringByAppendingPathComponent:@"sdk"];
    exteria_pyhost_config config;
    memset(&config, 0, sizeof(config));
    config.stdlib = [stdlib fileSystemRepresentation];
    config.paths[0] = [shim fileSystemRepresentation];
    config.paths[1] = [sdk fileSystemRepresentation];
    config.service = plugin_service;
    /* native code a plugin can import: the game */
    config.modules[0].name = "_doom";
    config.modules[0].init = exteria_doom_module_init;
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    exteria_status status = exteria_pyhost_init(&config);
    if (status != EXTERIA_OK) {
        ExteriaPluginsLog(@"exteria: python did not start (%d): %s", (int)status, exteria_pyhost_error());
        g_python = -1;
        return NO;
    }
    g_python = 1;
    ExteriaPluginsLog(@"exteria: python started in %.0f ms", ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
    return YES;
}

static NSString *python_error_text(void) {
    const char *text = exteria_pyhost_error();
    return [NSString stringWithUTF8String:text[0] ? text : "plugin failed"];
}

#pragma mark loading

static void unload_slot(ExteriaPluginSlot *slot) {
    if (!slot->loaded) return;
    exteria_status status = EXTERIA_OK;
    python_call(@"unload", [NSArray arrayWithObject:slot->entry.pluginId], HOOK_TIMEOUT_MS, &status);
    if (status != EXTERIA_OK) ExteriaPluginsLog(@"exteria: plugin %@ did not unload cleanly: %@", slot->entry.file, python_error_text());
    slot->loaded = NO;
    slot->sendHook = NO;
    slot->updateHook = NO;
    slot->displayHook = NO;
    slot->entry.hasSettings = NO;
    [slot->menu removeAllObjects];
    BOOL any = NO;
    for (ExteriaPluginSlot *other in g_slots) any = any || other->loaded;
    if (!any) ExteriaPluginUIReset();
}

/* imports the plugin. YES when it runs; else the failure is on the entry and the plugin is off */
static BOOL load_slot(ExteriaPluginSlot *slot) {
    if (slot->loaded) return YES;
    NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
    slot->loading = YES;
    exteria_status status = EXTERIA_OK;
    NSDictionary *result = python_call(@"load", [NSArray arrayWithObjects:slot->path, slot->entry.pluginId, nil], LOAD_TIMEOUT_MS, &status);
    slot->loading = NO;
    if (status != EXTERIA_OK || ![result isKindOfClass:[NSDictionary class]] || ![[result objectForKey:@"ok"] boolValue]) {
        NSString *why = status != EXTERIA_OK ? python_error_text() : [result objectForKey:@"error"];
        ExteriaPluginsLog(@"exteria: plugin %@ did not load: %@", slot->entry.file, why);
        slot->entry.fault = [why isKindOfClass:[NSString class]] ? why : @"plugin failed";
        id explained = [result isKindOfClass:[NSDictionary class]] ? [result objectForKey:@"why"] : nil;
        slot->entry.failure = [explained isKindOfClass:[NSDictionary class]] ? explained : [NSDictionary dictionaryWithObjectsAndKeys:@"other", @"kind", slot->entry.fault, @"detail", nil];
        /* the sdk drops a plugin whose on_plugin_load raised, so there is nothing to unload here */
        slot->sendHook = NO;
        slot->updateHook = NO;
        slot->displayHook = NO;
        [slot->menu removeAllObjects];
        return NO;
    }
    slot->entry.failure = nil;
    NSDictionary *handles = [result objectForKey:@"handles"];
    slot->updateHook = [[handles objectForKey:@"update"] boolValue];
    slot->entry.hasSettings = [[result objectForKey:@"has_settings"] boolValue];
    slot->loaded = YES;
    ExteriaPluginsLog(@"exteria: plugin %@ loaded in %.0f ms", slot->entry.file, ([NSDate timeIntervalSinceReferenceDate] - began) * 1000);
    return YES;
}

static ExteriaPluginSlot *make_slot(NSString *file, NSString *path) {
    ExteriaPluginSlot *slot = [[[ExteriaPluginSlot alloc] init] autorelease];
    slot->entry = [[ExteriaPluginEntry alloc] initWithFile:file];
    slot->path = [path copy];
    int status = EXTERIA_OK;
    NSData *script = read_plugin(path, &status);
    if (!script) {
        slot->entry.status = status;
        return slot;
    }
    slot->digest = [digest_of(script) retain];
    if (!ensure_python()) {
        slot->entry.status = EXTERIA_E_IO;
        slot->entry.error = @"the python runtime did not start";
        return slot;
    }
    exteria_status call_status = EXTERIA_OK;
    /* the first call imports the whole sdk from bytecode, which an iphone 4 needs seconds for */
    static BOOL warm;
    NSDictionary *meta = python_call(@"metadata", [NSArray arrayWithObject:path], warm ? SCAN_TIMEOUT_MS : LOAD_TIMEOUT_MS, &call_status);
    if (call_status == EXTERIA_OK) warm = YES;
    if (call_status != EXTERIA_OK || ![meta isKindOfClass:[NSDictionary class]]) {
        slot->entry.status = call_status == EXTERIA_E_TIMEOUT ? EXTERIA_E_TIMEOUT : EXTERIA_E_STATE;
        slot->entry.error = python_error_text();
        ExteriaPluginsLog(@"exteria: the metadata of %@ could not be read (%d): %@", file, (int)call_status, slot->entry.error);
        return slot;
    }
    if (![[meta objectForKey:@"ok"] boolValue]) {
        slot->entry.status = EXTERIA_E_MALFORMED;
        id why = [meta objectForKey:@"error"];
        slot->entry.error = [why isKindOfClass:[NSString class]] ? why : nil;
        ExteriaPluginsLog(@"exteria: %@ was refused: %@", file, slot->entry.error);
        return slot;
    }
    NSDictionary *fields = [meta objectForKey:@"meta"];
    id value;
    slot->entry.pluginId = [(value = [fields objectForKey:@"id"]) isKindOfClass:[NSString class]] ? value : nil;
    slot->entry.name = [(value = [fields objectForKey:@"name"]) isKindOfClass:[NSString class]] ? value : file;
    slot->entry.author = [(value = [fields objectForKey:@"author"]) isKindOfClass:[NSString class]] ? value : nil;
    slot->entry.version = [(value = [fields objectForKey:@"version"]) isKindOfClass:[NSString class]] ? value : nil;
    if (!slot->entry.pluginId) {
        slot->entry.status = EXTERIA_E_MALFORMED;
        return slot;
    }
    NSMutableArray *permissions = [NSMutableArray array];
    id declared = [fields objectForKey:@"permissions"];
    if ([declared isKindOfClass:[NSArray class]]) {
        for (id one in declared) if ([one isKindOfClass:[NSString class]] && ![permissions containsObject:one]) [permissions addObject:one];
    }
    NSDictionary *needed = python_call(@"capabilities", [NSArray arrayWithObject:path], SCAN_TIMEOUT_MS, NULL);
    if ([needed isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in [[needed allKeys] sortedArrayUsingSelector:@selector(compare:)]) if (![permissions containsObject:key]) [permissions addObject:key];
    }
    slot->entry.permissions = permissions;
    return slot;
}

static void rescan(void) {
    if (!g_slots) g_slots = [[NSMutableArray alloc] init];
    NSString *directory = ExteriaPluginsDirectory();
    NSError *error = nil;
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:&error] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (!names) ExteriaPluginsLog(@"exteria: the plugins folder could not be listed: %@", error);
    NSMutableArray *fresh = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    BOOL differs = NO;
    for (NSString *file in names) {
        if (!ExteriaPluginsAcceptsExtension([file pathExtension])) continue;
        if (fresh.count == PLUGINS_LISTED_MAX) break;
        NSString *path = [directory stringByAppendingPathComponent:file];
        ExteriaPluginSlot *old = slot_for_file(file);
        int status = EXTERIA_OK;
        NSData *script = old && old->digest ? read_plugin(path, &status) : nil;
        /* an unchanged file keeps its running plugin and its fault count */
        if (old && old->digest && script && [digest_of(script) isEqualToString:old->digest]) {
            [fresh addObject:old];
            if (old->entry.pluginId) [ids addObject:old->entry.pluginId];
            continue;
        }
        /* a changed file that was running is stopped before the new one is read, they share an id */
        if (old) unload_slot(old);
        ExteriaPluginSlot *slot = make_slot(file, path);
        if (slot->entry.pluginId) {
            if ([ids containsObject:slot->entry.pluginId]) {
                slot->entry.status = EXTERIA_E_STATE;
                slot->entry.error = @"another file in the folder has the same __id__";
            } else {
                [ids addObject:slot->entry.pluginId];
            }
        }
        if (slot->entry.status == EXTERIA_OK && slot->digest) {
            NSString *approved = [enabled_digests() objectForKey:file];
            if ([approved isEqualToString:slot->digest]) {
                slot->entry.enabled = YES;
                if (g_started && !load_slot(slot)) {
                    slot->entry.enabled = NO;
                    store_enabled(file, nil);
                }
            } else {
                slot->entry.changed = approved != nil;
            }
        }
        [fresh addObject:slot];
        /* a file that stays unreadable or refused is the same entry as before */
        if (!old || old->digest || slot->digest) differs = YES;
    }
    for (ExteriaPluginSlot *gone in g_slots) if (![fresh containsObject:gone]) unload_slot(gone);
    if (fresh.count != g_slots.count) differs = YES;
    [g_slots setArray:fresh];
    if (differs) changed();
}

NSArray *ExteriaPluginsList(void) {
    rescan();
    NSMutableArray *entries = [NSMutableArray array];
    for (ExteriaPluginSlot *slot in g_slots) [entries addObject:slot->entry];
    return entries;
}

/* the folder is read at launch only when the person has turned something on, so a phone without plugins never starts python */
void ExteriaPluginsStart(void) {
    if (g_started) return;
    g_started = YES;
    /* a library such as zwylib keeps texts in the language of the app and learns of a change through LocaleController.applyLanguage; python is not started for it */
    [[NSNotificationCenter defaultCenter] addObserverForName:ExteriaLanguageDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        (void)note;
        for (ExteriaPluginSlot *slot in g_slots) {
            if (slot->loaded) {
                ExteriaPluginsCallHost(@"language_changed", [NSArray array]);
                return;
            }
        }
    }];
    if (!g_results) g_results = [[NSMutableDictionary alloc] init];
    if (!enabled_digests().count) {
        if (!g_slots) g_slots = [[NSMutableArray alloc] init];
        return;
    }
    /* g_started is set, so the scan loads the plugins that are on */
    rescan();
    ExteriaPluginsEvent("start");
}

void ExteriaPluginsSetEnabled(NSString *file, BOOL enabled) {
    ExteriaPluginSlot *slot = slot_for_file(file);
    if (!slot || slot->entry.status != EXTERIA_OK || !slot->digest) return;
    if (enabled) {
        /* the file may have changed since the page listed it: the digest the person saw is the one that is approved */
        int status = EXTERIA_OK;
        NSData *script = read_plugin(slot->path, &status);
        if (!script || ![digest_of(script) isEqualToString:slot->digest]) {
            rescan();
            return;
        }
        slot->entry.enabled = YES;
        slot->entry.changed = NO;
        slot->entry.fault = nil;
        slot->faults = 0;
        if (!load_slot(slot)) {
            slot->entry.enabled = NO;
            changed();
            return;
        }
        store_enabled(file, slot->digest);
    } else {
        unload_slot(slot);
        slot->entry.enabled = NO;
        store_enabled(file, nil);
    }
    changed();
}

static void switch_off_for_faults(ExteriaPluginSlot *slot) {
    ExteriaPluginsLog(@"exteria: plugin %@ failed %d calls in a row and is switched off: %@", slot->entry.file, slot->faults, slot->entry.fault);
    unload_slot(slot);
    slot->entry.enabled = NO;
    store_enabled(slot->entry.file, nil);
    changed();
}

/* counts the outcome of one hook call. the failure stays on the entry, and the third in a row switches the plugin off */
static void note_outcome(ExteriaPluginSlot *slot, exteria_status status) {
    if (status == EXTERIA_OK) {
        slot->faults = 0;
        return;
    }
    NSString *why = python_error_text();
    ExteriaPluginsLog(@"exteria: plugin %@ failed (%d): %@", slot->entry.file, (int)status, why);
    /* a refused permission is the plugin asking for more than it was given, not a broken plugin */
    if (status == EXTERIA_E_SECURITY) return;
    slot->entry.fault = why;
    if (++slot->faults >= EXTERIA_PLUGIN_FAULTS_MAX) switch_off_for_faults(slot);
}

static BOOL on_main_thread(const char *what) {
    if ([NSThread isMainThread]) return YES;
    ExteriaPluginsLog(@"exteria: plugin hook %s called off the main thread, skipped", what);
    return NO;
}

void ExteriaPluginsEvent(const char *name) {
    if (!g_started || !on_main_thread("on_app_event")) return;
    NSString *event = [@"app_" stringByAppendingString:[NSString stringWithUTF8String:name]];
    for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
        if (!slot->loaded) continue;
        exteria_status status = EXTERIA_OK;
        python_call(@"app_event", [NSArray arrayWithObjects:slot->entry.pluginId, event, nil], HOOK_TIMEOUT_MS, &status);
        note_outcome(slot, status);
    }
}

/* a text that does not fit bypasses the plugins, a plugin cannot see half of a message */
static BOOL fits(NSString *text) {
    return [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= TEXT_MAX;
}

static NSString *strategy_of(NSDictionary *result) {
    id strategy = [result isKindOfClass:[NSDictionary class]] ? [result objectForKey:@"strategy"] : nil;
    return [strategy isKindOfClass:[NSString class]] ? strategy : @"DEFAULT";
}

/* the plugins hear a message the way the android app tells them: didReceiveNewMessages. a message is new when it is above the newest
   one announced for its chat and was sent in the last two minutes, so the history a chat shows on opening is not news */
static NSMutableDictionary *g_newest;

static void announce(long long chat, int32_t messageId, NSString *text, BOOL outgoing) {
    BOOL listening = NO;
    for (ExteriaPluginSlot *slot in g_slots) listening = listening || slot->loaded;
    if (!listening) return;
    NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:messageId], @"id", text ? text : @"", @"text", [NSNumber numberWithBool:outgoing], @"out", nil];
    ExteriaPluginsCallHost(@"new_messages", [NSArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithLongLong:chat], [NSArray arrayWithObject:item], nil]);
}

static void announce_incoming(ExteriaMessage *message, long long chat, NSString *text) {
    if (!g_newest) g_newest = [[NSMutableDictionary alloc] init];
    NSNumber *key = [NSNumber numberWithLongLong:chat];
    int32_t newest = [[g_newest objectForKey:key] intValue];
    if (message.messageId <= newest) return;
    [g_newest setObject:[NSNumber numberWithInt:message.messageId] forKey:key];
    if ((int32_t)[[NSDate date] timeIntervalSince1970] - message.date > 120) return;
    announce(chat, message.messageId, text, NO);
}

BOOL ExteriaPluginsHidesMessage(ExteriaMessage *message, long long chat) {
    if (!g_started || !g_slots.count || message.service || message.outgoing || message.messageId <= 0) return NO;
    if (!on_main_thread("on_update_hook")) return NO;
    NSString *source = message.sourceText;
    if (!source) source = @"";
    NSString *key = [NSString stringWithFormat:@"%lld:%d:%lu:%lu:%u", chat, (int)message.messageId, (unsigned long)source.length, (unsigned long)source.hash, g_generation];
    id cached = [g_results objectForKey:key];
    if (cached) {
        if ([cached isKindOfClass:[NSString class]]) [message showPluginText:cached];
        else if (cached == [NSNull null]) [message restoreSourceText];
        return [cached isKindOfClass:[NSNumber class]];
    }
    NSString *current = source;
    BOOL hidden = NO;
    announce_incoming(message, chat, source);
    if (fits(current)) {
        for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
            if (!slot->loaded || !slot->updateHook) continue;
            /* the shape of TLRPC.TL_updateNewMessage as the plugins of exteraGram read it */
            NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:(int)message.messageId], @"id",
                [NSNumber numberWithLongLong:chat], @"peer_id",
                [NSNumber numberWithLongLong:message.senderKey], @"from_id",
                [NSNumber numberWithBool:NO], @"out",
                current, @"message", nil];
            NSDictionary *update = [NSDictionary dictionaryWithObject:item forKey:@"message"];
            exteria_status status = EXTERIA_OK;
            NSDictionary *result = python_call(@"update_hook", [NSArray arrayWithObjects:slot->entry.pluginId, [NSNumber numberWithInt:0], @"TL_updateNewMessage", update, nil], HOOK_TIMEOUT_MS, &status);
            note_outcome(slot, status);
            if (status != EXTERIA_OK) continue;
            NSString *strategy = strategy_of(result);
            if ([strategy isEqualToString:@"CANCEL"]) {
                hidden = YES;
                break;
            }
            if ([strategy isEqualToString:@"MODIFY"] || [strategy isEqualToString:@"MODIFY_FINAL"]) {
                id changed_update = [result objectForKey:@"update"];
                id changed_item = [changed_update isKindOfClass:[NSDictionary class]] ? [changed_update objectForKey:@"message"] : nil;
                id next = [changed_item isKindOfClass:[NSDictionary class]] ? [changed_item objectForKey:@"message"] : nil;
                if ([next isKindOfClass:[NSString class]] && fits(next)) current = next;
                if ([strategy isEqualToString:@"MODIFY_FINAL"]) break;
            }
        }
    }
    if (g_results.count >= RESULTS_MAX) [g_results removeAllObjects];
    if (hidden) {
        [g_results setObject:[NSNumber numberWithBool:YES] forKey:key];
        return YES;
    }
    if (![current isEqualToString:source]) {
        [message showPluginText:current];
        [g_results setObject:current forKey:key];
    } else {
        [message restoreSourceText];
        [g_results setObject:[NSNull null] forKey:key];
    }
    return NO;
}

BOOL ExteriaPluginsStopsSend(NSString **text, long long chat, int replyTo, NSString *replyText, NSString **quote, int32_t *quoteOffset) {
    if (!g_started || !g_slots.count || !text || !*text || !on_main_thread("on_send_message_hook")) return NO;
    NSString *current = *text;
    if (!fits(current)) return NO;
    NSString *currentQuote = quote ? *quote : nil;
    int32_t currentOffset = quoteOffset ? *quoteOffset : -1;
    for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
        if (!slot->loaded || !slot->sendHook) continue;
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            current, @"message",
            [NSNumber numberWithLongLong:chat], @"peer",
            [NSNumber numberWithInt:replyTo], @"replyToMsg", nil];
        /* the words of the answered message and of the quote the reply carries, which the plugins of exteraGram read as replyToMsg.messageText and replyQuote */
        if (replyTo > 0 && replyText.length && fits(replyText)) [params setObject:replyText forKey:@"replyText"];
        if (currentQuote.length && fits(currentQuote)) {
            [params setObject:currentQuote forKey:@"quote"];
            [params setObject:[NSNumber numberWithInt:currentOffset] forKey:@"quoteOffset"];
        }
        exteria_status status = EXTERIA_OK;
        NSDictionary *result = python_call(@"send_message_hook", [NSArray arrayWithObjects:slot->entry.pluginId, [NSNumber numberWithInt:0], params, nil], HOOK_TIMEOUT_MS, &status);
        note_outcome(slot, status);
        if (status != EXTERIA_OK) continue;
        NSString *strategy = strategy_of(result);
        if ([strategy isEqualToString:@"CANCEL"]) return YES;
        if ([strategy isEqualToString:@"MODIFY"] || [strategy isEqualToString:@"MODIFY_FINAL"]) {
            id changed_params = [result objectForKey:@"params"];
            id next = [changed_params isKindOfClass:[NSDictionary class]] ? [changed_params objectForKey:@"message"] : nil;
            if ([next isKindOfClass:[NSString class]] && [next length] && fits(next)) current = next;
            id changed_quote = [changed_params isKindOfClass:[NSDictionary class]] ? [changed_params objectForKey:@"replyQuote"] : nil;
            if ([changed_quote isKindOfClass:[NSDictionary class]]) {
                id words = [changed_quote objectForKey:@"text"];
                id offset = [changed_quote objectForKey:@"offset"];
                if ([words isKindOfClass:[NSString class]] && [words length] && fits(words)) {
                    currentQuote = words;
                    currentOffset = [offset isKindOfClass:[NSNumber class]] ? (int32_t)[offset intValue] : 0;
                }
            } else if (changed_quote == [NSNull null]) {
                currentQuote = nil;
                currentOffset = -1;
            }
            if ([strategy isEqualToString:@"MODIFY_FINAL"]) break;
        }
    }
    *text = current;
    if (quote) *quote = currentQuote;
    if (quoteOffset) *quoteOffset = currentOffset;
    announce(chat, 0, current, YES);
    return NO;
}

/* what the display hooks last made of a message: chat:id to the words before and the words shown, so a message is put back when the plugin stops changing it, and a
   message that was edited on the server in between is left alone */
static NSMutableDictionary *g_rewritten;

void ExteriaPluginsRewriteMessages(NSArray *messages, long long chat) {
    if (!g_started || !g_slots.count || !on_main_thread("display hook")) return;
    BOOL hooked = NO;
    for (ExteriaPluginSlot *slot in g_slots) hooked = hooked || (slot->loaded && slot->displayHook);
    if (!g_rewritten) g_rewritten = [[NSMutableDictionary alloc] init];
    if (!hooked && !g_rewritten.count) return;
    NSMutableArray *items = [NSMutableArray array];
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (ExteriaMessage *message in messages) {
        if (message.messageId <= 0 || message.service) continue;
        NSString *key = [NSString stringWithFormat:@"%lld:%d", chat, (int)message.messageId];
        NSArray *before = [g_rewritten objectForKey:key];
        if (before && [message.text isEqualToString:[before objectAtIndex:1]]) {
            [message showPluginText:[before objectAtIndex:0]];
        }
        [g_rewritten removeObjectForKey:key];
        if (!hooked) continue;
        NSString *text = message.text ? message.text : @"";
        if (!fits(text)) continue;
        [byKey setObject:message forKey:[NSNumber numberWithInt:(int)message.messageId]];
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:(int)message.messageId], @"id", text, @"text", [NSNumber numberWithBool:message.outgoing], @"out", nil]];
    }
    if (!items.count) return;
    NSDictionary *changed = ExteriaPluginsCallHost(@"display_messages", [NSArray arrayWithObjects:[NSNumber numberWithLongLong:chat], items, nil]);
    if (![changed isKindOfClass:[NSDictionary class]]) return;
    for (NSString *idText in changed) {
        ExteriaMessage *message = [byKey objectForKey:[NSNumber numberWithInt:[idText intValue]]];
        id words = [changed objectForKey:idText];
        if (!message || ![words isKindOfClass:[NSString class]] || ![words length] || !fits(words)) continue;
        NSString *before = message.text ? message.text : @"";
        [message showPluginText:words];
        if (g_rewritten.count >= RESULTS_MAX) [g_rewritten removeAllObjects];
        [g_rewritten setObject:[NSArray arrayWithObjects:before, words, nil] forKey:[NSString stringWithFormat:@"%lld:%d", chat, (int)message.messageId]];
    }
}

NSArray *ExteriaPluginsSettingsItems(NSString *pluginId) {
    ExteriaPluginSlot *slot = slot_for_id(pluginId);
    if (!slot || !slot->loaded || !on_main_thread("create_settings")) return nil;
    exteria_status status = EXTERIA_OK;
    id items = python_call(@"settings", [NSArray arrayWithObject:pluginId], QUEUED_TIMEOUT_MS, &status);
    note_outcome(slot, status);
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

void ExteriaPluginsSettingClick(NSString *pluginId, NSString *callbackId) {
    ExteriaPluginSlot *slot = slot_for_id(pluginId);
    if (!slot || !slot->loaded || !on_main_thread("on_click")) return;
    exteria_status status = EXTERIA_OK;
    python_call(@"setting_click", [NSArray arrayWithObjects:pluginId, callbackId, nil], QUEUED_TIMEOUT_MS, &status);
    note_outcome(slot, status);
}

void ExteriaPluginsSettingChanged(NSString *pluginId, NSString *key, id value) {
    ExteriaPluginSlot *slot = slot_for_id(pluginId);
    if (!slot || !slot->loaded || !on_main_thread("on_change")) return;
    /* the sdk takes the value as the json of itself; a top level json value is wrapped in a list to be written */
    NSString *wrapped = json_string([NSArray arrayWithObject:value ? value : [NSNull null]]);
    NSString *encoded = wrapped.length > 2 ? [wrapped substringWithRange:NSMakeRange(1, wrapped.length - 2)] : @"null";
    exteria_status status = EXTERIA_OK;
    python_call(@"setting_changed", [NSArray arrayWithObjects:pluginId, key, encoded, nil], QUEUED_TIMEOUT_MS, &status);
    note_outcome(slot, status);
}

NSArray *ExteriaPluginsActions(void) {
    NSMutableArray *actions = [NSMutableArray array];
    for (ExteriaPluginSlot *slot in g_slots) {
        if (!slot->loaded) continue;
        for (NSString *itemId in [[slot->menu allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *item = [slot->menu objectForKey:itemId];
            NSString *type = [item objectForKey:@"menu_type"];
            NSString *text = [item objectForKey:@"text"];
            /* the menus of a message or of a profile belong to those screens, which have no plugin items. the menu of actions on a chat has no place of its own, so its items are here too */
            if (![text isKindOfClass:[NSString class]] || !([type isEqualToString:@"MAIN_MENU"] || [type isEqualToString:@"DRAWER_MENU"] || [type isEqualToString:@"CHAT_ACTION_MENU"])) continue;
            [actions addObject:[NSDictionary dictionaryWithObjectsAndKeys:slot->entry.name ? slot->entry.name : slot->entry.file, @"plugin",
                                slot->entry.pluginId, @"pluginId", itemId, @"item", text, @"text", nil]];
        }
    }
    ExteriaPluginsLog(@"exteria: the plugins page lists %lu actions of %lu plugins", (unsigned long)actions.count, (unsigned long)g_slots.count);
    return actions;
}

NSArray *ExteriaPluginsMessageMenuItems(void) {
    NSMutableArray *found = [NSMutableArray array];
    for (ExteriaPluginSlot *slot in g_slots) {
        if (!slot->loaded) continue;
        for (NSString *itemId in [[slot->menu allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSDictionary *item = [slot->menu objectForKey:itemId];
            id text = [item objectForKey:@"text"];
            if (![text isKindOfClass:[NSString class]] || ![[item objectForKey:@"menu_type"] isEqual:@"MESSAGE_CONTEXT_MENU"]) continue;
            [found addObject:[NSDictionary dictionaryWithObjectsAndKeys:slot->entry.pluginId, @"pluginId", itemId, @"item", text, @"text",
                              [NSNumber numberWithInt:[[item objectForKey:@"priority"] intValue]], @"priority", nil]];
        }
    }
    /* a stable sort: equal priorities keep the order of plugins and ids */
    return [found sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
        return [[b objectForKey:@"priority"] compare:[a objectForKey:@"priority"]];
    }];
}

void ExteriaPluginsRunMessageAction(NSString *pluginId, NSString *itemId, NSDictionary *message) {
    ExteriaPluginSlot *slot = slot_for_id(pluginId);
    if (!slot || !slot->loaded || ![slot->menu objectForKey:itemId] || !on_main_thread("menu_click")) return;
    exteria_status status = EXTERIA_OK;
    python_call(@"menu_click", [NSArray arrayWithObjects:pluginId, itemId, [NSDictionary dictionaryWithObject:message forKey:@"message"], nil], QUEUED_TIMEOUT_MS, &status);
    note_outcome(slot, status);
}

void ExteriaPluginsRunAction(NSString *pluginId, NSString *itemId) {
    ExteriaPluginSlot *slot = slot_for_id(pluginId);
    if (!slot || !slot->loaded || ![slot->menu objectForKey:itemId] || !on_main_thread("menu_click")) return;
    exteria_status status = EXTERIA_OK;
    python_call(@"menu_click", [NSArray arrayWithObjects:pluginId, itemId, [NSDictionary dictionary], nil], QUEUED_TIMEOUT_MS, &status);
    note_outcome(slot, status);
}

NSString *ExteriaPluginsImport(NSString *path, NSString *name, NSString **installed) {
    if (installed) *installed = nil;
    NSString *given = name.length ? [name lastPathComponent] : [path lastPathComponent];
    NSString *extension = [[given pathExtension] lowercaseString];
    if ([given hasPrefix:@"."] || !ExteriaPluginsAcceptsExtension(extension) || ![[given stringByDeletingPathExtension] length]) {
        return NSLocalizedString(@"plugins.import.notplugin", nil);
    }
    /* the folder scan matches the lower case extension only */
    NSString *file = [[given stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
    int status = EXTERIA_OK;
    NSData *script = read_plugin(path, &status);
    if (!script) {
        if (status == EXTERIA_E_LIMIT) return NSLocalizedString(@"plugins.import.large", nil);
        if (status == EXTERIA_E_MALFORMED) return NSLocalizedString(@"plugins.err.script", nil);
        return NSLocalizedString(@"plugins.err.unreadable", nil);
    }
    NSString *directory = ExteriaPluginsDirectory();
    NSString *target = [directory stringByAppendingPathComponent:file];
    NSFileManager *files = [NSFileManager defaultManager];
    if (![files fileExistsAtPath:target]) {
        NSUInteger present = 0;
        for (NSString *entry in [files contentsOfDirectoryAtPath:directory error:NULL]) if (ExteriaPluginsAcceptsExtension([entry pathExtension])) ++present;
        if (present >= PLUGINS_LISTED_MAX) return NSLocalizedString(@"plugins.import.full", nil);
    }
    NSError *error = nil;
    if (![script writeToFile:target options:NSDataWritingAtomic error:&error]) {
        ExteriaPluginsLog(@"exteria: the plugin %@ could not be written to the plugins folder: %@", file, error);
        return NSLocalizedString(@"plugins.import.failed", nil);
    }
    rescan();
    if (installed) *installed = file;
    return nil;
}
