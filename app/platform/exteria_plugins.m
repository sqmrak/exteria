#import "exteria_plugins.h"

#import <CommonCrypto/CommonDigest.h>
#import "exteria_message.h"
#include "exteria_plugin.h"

NSString *const ExteriaPluginsDidChangeNotification = @"ExteriaPluginsDidChange";

static NSString *const ExteriaPluginsEnabledKey = @"exteria.plugins.enabled";
/* a folder of hundreds of scripts would stall the page, each one is parsed to read its name */
#define PLUGINS_LISTED_MAX 64
#define RESULTS_MAX 512

@interface ExteriaPluginEntry ()
- (id)initWithFile:(NSString *)file;
@property (nonatomic, assign) int status;
@property (nonatomic, assign) unsigned permissions;
@property (nonatomic, assign) unsigned hooks;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL changed;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fault;
@end

@implementation ExteriaPluginEntry
@synthesize file = _file, name = _name, status = _status, permissions = _permissions, hooks = _hooks, enabled = _enabled, changed = _changed, fault = _fault;

- (id)initWithFile:(NSString *)file {
    self = [super init];
    if (self) _file = [file copy];
    return self;
}

- (void)dealloc {
    [_file release];
    [_name release];
    [_fault release];
    [super dealloc];
}
@end

/* a script found in the folder: what the host read from it, and the open host while the plugin is on */
@interface ExteriaPluginSlot : NSObject {
@public
    ExteriaPluginEntry *entry;
    NSString *digest;
    exteria_plugin *host;
    int faults;
}
@end

@implementation ExteriaPluginSlot
- (void)closeHost {
    if (!host) return;
    exteria_plugin_close(host);
    free(host);
    host = NULL;
}
- (void)dealloc {
    [self closeHost];
    [entry release];
    [digest release];
    [super dealloc];
}
@end

static NSMutableArray *g_slots;
/* a result of the incoming hooks is kept per message text, since the chat is ordered again on every change; a new
   generation drops them all when a plugin is switched or a file changes */
static NSMutableDictionary *g_results;
static unsigned g_generation;
static BOOL g_started;

static void plugin_log(const char *plugin, const char *line) {
    NSLog(@"exteria: plugin %s: %s", plugin, line);
}

NSString *ExteriaPluginsDirectory(void) {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *directory = [documents stringByAppendingPathComponent:@"Plugins"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: the plugins folder could not be made: %@", error);
    }
    return directory;
}

static NSString *digest_of(NSData *data) {
    unsigned char sum[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, sum);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * sizeof(sum)];
    for (size_t i = 0; i < sizeof(sum); ++i) [hex appendFormat:@"%02x", sum[i]];
    return hex;
}

/* the bytes of a script, or nil with the status the page shows: too large, empty, or unreadable */
static NSData *read_script(NSString *path, int *status) {
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (!attributes) {
        NSLog(@"exteria: the plugin %@ could not be read: %@", [path lastPathComponent], error);
        *status = EXTERIA_E_IO;
        return nil;
    }
    if ([attributes fileSize] > EXTERIA_PLUGIN_SCRIPT_MAX) {
        *status = EXTERIA_E_LIMIT;
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    if (!data) {
        NSLog(@"exteria: the plugin %@ could not be read: %@", [path lastPathComponent], error);
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
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"exteria: the plugin switches were not saved");
}

static void changed(void) {
    ++g_generation;
    [g_results removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaPluginsDidChangeNotification object:nil];
}

/* runs the script into a fresh host. the host stays open when the caller keeps it, else it is closed after the manifest is read */
static exteria_status open_host(NSData *script, exteria_plugin **out) {
    exteria_plugin *host = calloc(1, sizeof(*host));
    if (!host) return EXTERIA_E_NOMEM;
    exteria_status status = exteria_plugin_load(host, (const char *)script.bytes, script.length);
    if (status != EXTERIA_OK) NSLog(@"exteria: a plugin was refused (%d): %s", (int)status, host->error);
    *out = host;
    return status;
}

static ExteriaPluginSlot *slot_for_file(NSString *file) {
    for (ExteriaPluginSlot *slot in g_slots) if ([slot->entry.file isEqualToString:file]) return slot;
    return nil;
}

static ExteriaPluginSlot *make_slot(NSString *file, NSString *path) {
    ExteriaPluginSlot *slot = [[[ExteriaPluginSlot alloc] init] autorelease];
    slot->entry = [[ExteriaPluginEntry alloc] initWithFile:file];
    int status = EXTERIA_OK;
    NSData *script = read_script(path, &status);
    if (!script) {
        slot->entry.status = status;
        return slot;
    }
    slot->digest = [digest_of(script) retain];
    exteria_plugin *host = NULL;
    status = open_host(script, &host);
    slot->entry.status = status;
    if (status != EXTERIA_OK) {
        if (host) free(host);
        return slot;
    }
    slot->entry.name = [NSString stringWithUTF8String:host->name];
    slot->entry.permissions = host->permissions;
    slot->entry.hooks = host->hooks;
    NSString *approved = [enabled_digests() objectForKey:file];
    if ([approved isEqualToString:slot->digest]) {
        slot->entry.enabled = YES;
        slot->host = host;
    } else {
        slot->entry.changed = approved != nil;
        exteria_plugin_close(host);
        free(host);
    }
    return slot;
}

static void rescan(void) {
    if (!g_slots) g_slots = [[NSMutableArray alloc] init];
    NSString *directory = ExteriaPluginsDirectory();
    NSError *error = nil;
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:&error] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    if (!names) NSLog(@"exteria: the plugins folder could not be listed: %@", error);
    NSMutableArray *fresh = [NSMutableArray array];
    BOOL differs = NO;
    for (NSString *file in names) {
        if (![[file pathExtension] isEqualToString:@"lua"]) continue;
        if (fresh.count == PLUGINS_LISTED_MAX) break;
        NSString *path = [directory stringByAppendingPathComponent:file];
        ExteriaPluginSlot *old = slot_for_file(file);
        int status = EXTERIA_OK;
        NSData *script = old && old->digest ? read_script(path, &status) : nil;
        /* an unchanged file keeps its open host and its fault count */
        if (old && old->digest && script && [digest_of(script) isEqualToString:old->digest]) {
            [fresh addObject:old];
            continue;
        }
        ExteriaPluginSlot *slot = make_slot(file, path);
        [fresh addObject:slot];
        /* a script that stays unreadable or refused is the same entry as before */
        if (!old || old->digest || slot->digest) differs = YES;
    }
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

void ExteriaPluginsStart(void) {
    if (g_started) return;
    g_started = YES;
    exteria_plugin_set_log(plugin_log);
    if (!g_results) g_results = [[NSMutableDictionary alloc] init];
    rescan();
    ExteriaPluginsEvent("start");
}

void ExteriaPluginsSetEnabled(NSString *file, BOOL enabled) {
    ExteriaPluginSlot *slot = slot_for_file(file);
    if (!slot || slot->entry.status != EXTERIA_OK || !slot->digest) return;
    if (enabled) {
        /* the file may have changed since the page listed it: the digest the person saw is the one that is approved */
        int status = EXTERIA_OK;
        NSData *script = read_script([ExteriaPluginsDirectory() stringByAppendingPathComponent:file], &status);
        if (!script || ![digest_of(script) isEqualToString:slot->digest]) {
            rescan();
            return;
        }
        if (!slot->host) {
            exteria_plugin *host = NULL;
            if (open_host(script, &host) != EXTERIA_OK) {
                if (host) free(host);
                return;
            }
            slot->host = host;
        }
        slot->entry.enabled = YES;
        slot->entry.changed = NO;
        slot->entry.fault = nil;
        slot->faults = 0;
        store_enabled(file, slot->digest);
    } else {
        [slot closeHost];
        slot->entry.enabled = NO;
        store_enabled(file, nil);
    }
    changed();
}

static void switch_off_for_faults(ExteriaPluginSlot *slot) {
    NSLog(@"exteria: plugin %@ failed %d calls in a row and is switched off: %@", slot->entry.file, slot->faults, slot->entry.fault);
    [slot closeHost];
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
    NSLog(@"exteria: plugin %@ failed (%d): %s", slot->entry.file, (int)status, slot->host->error);
    slot->entry.fault = [NSString stringWithFormat:@"%s", slot->host->error[0] ? slot->host->error : "plugin failed"];
    if (++slot->faults >= EXTERIA_PLUGIN_FAULTS_MAX) switch_off_for_faults(slot);
}

static BOOL on_main_thread(const char *what) {
    if ([NSThread isMainThread]) return YES;
    NSLog(@"exteria: plugin hook %s called off the main thread, skipped", what);
    return NO;
}

void ExteriaPluginsEvent(const char *name) {
    if (!g_started || !on_main_thread("on_event")) return;
    for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
        if (!slot->host || !(slot->host->hooks & EXTERIA_HOOK_EVENT)) continue;
        note_outcome(slot, exteria_plugin_on_event(slot->host, name));
    }
}

/* a text that does not fit the host buffer bypasses the plugins, a plugin cannot see half of a message */
static BOOL fits(NSString *text, NSUInteger *bytes) {
    *bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return *bytes <= EXTERIA_PLUGIN_TEXT_MAX;
}

BOOL ExteriaPluginsHidesMessage(ExteriaMessage *message, long long chat) {
    if (!g_started || !g_slots.count || message.service || message.outgoing || message.messageId <= 0) return NO;
    if (!on_main_thread("on_message")) return NO;
    NSString *source = message.sourceText;
    if (!source) source = @"";
    NSString *key = [NSString stringWithFormat:@"%lld:%d:%lu:%lu:%u", chat, (int)message.messageId, (unsigned long)source.length, (unsigned long)source.hash, g_generation];
    id cached = [g_results objectForKey:key];
    if (cached) {
        if ([cached isKindOfClass:[NSString class]]) [message showPluginText:cached];
        else if (cached == [NSNull null]) [message restoreSourceText];
        return [cached isKindOfClass:[NSNumber class]];
    }
    static char buffer[EXTERIA_PLUGIN_TEXT_MAX + 1];
    NSString *current = source;
    BOOL hidden = NO;
    NSUInteger bytes = 0;
    if (fits(current, &bytes)) {
        for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
            if (!slot->host || !(slot->host->hooks & EXTERIA_HOOK_MESSAGE)) continue;
            const char *utf8 = [current UTF8String];
            /* a string with a lone surrogate has no utf-8 form, the plugins cannot read it */
            if (!utf8) break;
            exteria_plugin_message in = {message.messageId, chat, message.senderKey, 0, utf8, strlen(utf8)};
            exteria_plugin_action action = EXTERIA_PLUGIN_PASS;
            size_t length = 0;
            exteria_status status = exteria_plugin_on_message(slot->host, &in, &action, buffer, sizeof(buffer), &length);
            note_outcome(slot, status);
            if (status != EXTERIA_OK) continue;
            if (action == EXTERIA_PLUGIN_CANCEL) {
                hidden = YES;
                break;
            }
            if (action == EXTERIA_PLUGIN_REPLACE) {
                NSString *next = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] autorelease];
                if (next && fits(next, &bytes)) current = next;
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

BOOL ExteriaPluginsStopsSend(NSString **text, long long chat, int replyTo) {
    if (!g_started || !g_slots.count || !text || !*text || !on_main_thread("on_send")) return NO;
    static char buffer[EXTERIA_PLUGIN_TEXT_MAX + 1];
    NSString *current = *text;
    NSUInteger bytes = 0;
    if (!fits(current, &bytes)) return NO;
    for (ExteriaPluginSlot *slot in [[g_slots copy] autorelease]) {
        if (!slot->host || !(slot->host->hooks & EXTERIA_HOOK_SEND)) continue;
        const char *utf8 = [current UTF8String];
        if (!utf8) return NO;
        exteria_plugin_send in = {chat, replyTo, utf8, strlen(utf8)};
        exteria_plugin_action action = EXTERIA_PLUGIN_PASS;
        size_t length = 0;
        exteria_status status = exteria_plugin_on_send(slot->host, &in, &action, buffer, sizeof(buffer), &length);
        note_outcome(slot, status);
        if (status != EXTERIA_OK) continue;
        if (action == EXTERIA_PLUGIN_CANCEL) return YES;
        if (action == EXTERIA_PLUGIN_REPLACE) {
            NSString *next = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding] autorelease];
            if (next && fits(next, &bytes)) current = next;
        }
    }
    *text = current;
    return NO;
}
