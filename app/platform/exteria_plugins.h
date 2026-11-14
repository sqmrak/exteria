#import <Foundation/Foundation.h>

@class ExteriaMessage;

/* the python plugins of Documents/Plugins: files of the exteraGram format, .plugin or .py. a plugin is imported only after
   the person turns it on, and the switch is tied to the digest of the file: a changed file asks again, because it may now
   ask for more. plugins run in the process of the app with the interpreter of core/pyhost, so a permission is a promise
   the sdk keeps and the person reads, not a wall. everything here runs on the main thread, a call from another thread
   passes the message through and writes the reason to the log */

extern NSString *const ExteriaPluginsDidChangeNotification;

/* a plugin that fails this many calls in a row is switched off and shows the last failure */
#define EXTERIA_PLUGIN_FAULTS_MAX 3

@interface ExteriaPluginEntry : NSObject {
    NSString *_file;
    NSString *_pluginId;
    NSString *_name;
    NSString *_author;
    NSString *_version;
    NSString *_error;
    NSString *_fault;
    NSDictionary *_failure;
    NSDictionary *_notice;
    NSArray *_permissions;
    BOOL _hasSettings;
    int _status;
    BOOL _enabled;
    BOOL _changed;
}
/* the file name inside the plugins folder */
@property (nonatomic, readonly, copy) NSString *file;
/* the __id__ of the plugin, nil when the file was refused */
@property (nonatomic, readonly, copy) NSString *pluginId;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *author;
@property (nonatomic, readonly, copy) NSString *version;
/* why the file was refused, an exteria_status; zero for a plugin that can be turned on */
@property (nonatomic, readonly) int status;
/* the words that go with a refusal: the syntax error or the reason the metadata is wrong */
@property (nonatomic, readonly, copy) NSString *error;
/* the permission keys the plugin needs, from its own list and from a scan of what its code calls */
@property (nonatomic, readonly, retain) NSArray *permissions;
/* the plugin builds a page of settings with create_settings(); known once it runs */
@property (nonatomic, readonly) BOOL hasSettings;
@property (nonatomic, readonly) BOOL enabled;
/* the file is not the one the person turned on, so the switch is off until they turn it on again */
@property (nonatomic, readonly) BOOL changed;
/* the last failure of a plugin that was switched off for failing, else nil */
@property (nonatomic, readonly, copy) NSString *fault;
/* why the plugin did not load, as the plain values of python/shim/exteria_diagnose.py (kind, classes, missing, total, detail), nil when it loaded or was not tried */
@property (nonatomic, readonly, retain) NSDictionary *failure;
/* what a plugin that loaded names and the app lacks (the same plain values, kind android), nil when it needs nothing the app lacks or was not checked: some of what it does may not happen */
@property (nonatomic, readonly, retain) NSDictionary *notice;
@end

/* the folder the plugins live in; made when missing */
NSString *ExteriaPluginsDirectory(void);

/* starts the interpreter and loads the plugins that are on. nothing starts while no plugin is on, so a phone without
   plugins pays no memory for the interpreter */
void ExteriaPluginsStart(void);

/* reads the folder again and answers one entry for every plugin file, at most 64. the interpreter starts here when the
   folder holds a file, because the metadata is read by the sdk */
NSArray *ExteriaPluginsList(void);

void ExteriaPluginsSetEnabled(NSString *file, BOOL enabled);

/* copies a .plugin or .py file into the plugins folder under name (the file name of path when name is empty) and reads the
   folder again. a file of the same name is replaced, which switches the plugin off until the person turns it on, as any
   changed file does. the plugin is never turned on here. returns nil when the file is in, else the text to show;
   *installed gets the file name inside the folder on success */
NSString *ExteriaPluginsImport(NSString *path, NSString *name, NSString **installed);

/* switches the plugin off, forgets its approval and deletes its file from the plugins folder. returns nil when it is gone, else the text to show. a name that is not a plain
   plugin file name of the folder is refused */
NSString *ExteriaPluginsRemove(NSString *file);

/* "start", "stop", "pause" or "resume" for every plugin that is on */
void ExteriaPluginsEvent(const char *name);

/* the update hooks for a message of someone else that is about to be drawn, as TL_updateNewMessage. YES when a plugin
   hid it. a replaced text is put on the message itself, with the original kept, so calling this again for the same
   message gives the same answer */
BOOL ExteriaPluginsHidesMessage(ExteriaMessage *message, long long chat);

/* the send hooks for a text about to go out. YES when a plugin cancelled the send; *text may come back replaced. replyText is the text of the message answered (nil when
   there is none or it is not loaded), and *quote with *quoteOffset the quote the reply carries: a plugin sees them and may set another or clear it */
BOOL ExteriaPluginsStopsSend(NSString **text, long long chat, int replyTo, NSString *replyText, NSString **quote, int32_t *quoteOffset);

/* the display hooks (a plugin that hooks ChatMessageCell.setMessageContent) for the messages about to be laid out: a text they change is put on the message, with the
   original kept. messages that no plugin changes, or that a plugin stopped changing, get their words back */
void ExteriaPluginsRewriteMessages(NSArray *messages, long long chat);

/* Library/Caches/exteria-plugin-files, made on demand: the folder a plugin writes pictures to before it sends them, and the only one a plugin may send a photo from */
NSString *ExteriaPluginsCacheDirectory(void);
/* whether path, with symlinks resolved, lies inside that folder */
BOOL ExteriaPluginsPathInCache(NSString *path);

/* a plugin file the app is asked to open: the extensions the folder scan accepts */
BOOL ExteriaPluginsAcceptsExtension(NSString *extension);

/* whether the interpreter is up and a plugin file is known: the screens that tell plugins about themselves (exteria_host.fragment_event) ask first, so a person
   with no plugins costs the screens a flag test and no log line */
BOOL ExteriaPluginsAreRunning(void);

/* calls exteria_host.<function>(*arguments) on the main thread and gives the decoded result, nil when it failed or returned
   null. for the view layer of exteria_plugin_ui.m, which forwards touches and sensor readings to python */
id ExteriaPluginsCallHost(NSString *function, NSArray *arguments);

/* NSLog, and the same line appended to Library/Caches/exteria-plugins.log, which keeps the last 128 KiB. the device has no
   syslog to read, so this file is where the log of a plugin and the failures of the host can be found */
void ExteriaPluginsLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/* the actions plugins registered with add_menu_item for the whole app (main menu and drawer): dictionaries with plugin (its name),
   pluginId, item (the id of the item) and text. the plugins page lists them, since the app has no menu for them yet */
NSArray *ExteriaPluginsActions(void);
void ExteriaPluginsRunAction(NSString *pluginId, NSString *itemId);
/* the items plugins added to the menu of a chat (CHAT_ACTION_MENU), the ones the three dots of an open chat lists: the same dictionaries as ExteriaPluginsActions */
NSArray *ExteriaPluginsChatActions(void);

/* the items plugins added to the menu of a message (MESSAGE_CONTEXT_MENU), highest priority first: dictionaries with pluginId,
   item and text. a plugin that is not running has none */
NSArray *ExteriaPluginsMessageMenuItems(void);
/* runs one of those items for a message: id, text, out and dialog become the MessageObject the plugin reads */
void ExteriaPluginsRunMessageAction(NSString *pluginId, NSString *itemId, NSDictionary *message);

/* the page of settings a plugin built with create_settings(): the items of ui/settings.py as the sdk serializes them (type header, divider, text,
   switch, selector, input, slider, edittext, custom), nil when the plugin has none or is not running */
NSArray *ExteriaPluginsSettingsItems(NSString *pluginId);
/* a row with a callback_id was tapped */
void ExteriaPluginsSettingClick(NSString *pluginId, NSString *callbackId);
/* a setting of the page took a new value (a number, a string or a bool); the plugin stores it and hears of it */
void ExteriaPluginsSettingChanged(NSString *pluginId, NSString *key, id value);
