#import <Foundation/Foundation.h>

@class ExteriaMessage;

/* the lua plugins of Documents/Plugins. a script is run only after the person turns it on, and the switch is tied to the
   digest of the file: a changed file asks again, because it may now ask for more. everything here runs on the main thread,
   a call from another thread passes the message through and writes the reason to the log */

extern NSString *const ExteriaPluginsDidChangeNotification;

/* a plugin that fails this many calls in a row is switched off and shows the last failure */
#define EXTERIA_PLUGIN_FAULTS_MAX 3

@interface ExteriaPluginEntry : NSObject {
    NSString *_file;
    NSString *_name;
    NSString *_fault;
    int _status;
    unsigned _permissions;
    unsigned _hooks;
    BOOL _enabled;
    BOOL _changed;
}
/* the file name inside the plugins folder */
@property (nonatomic, readonly, copy) NSString *file;
/* the name the script gives itself, nil when the host refused the script */
@property (nonatomic, readonly, copy) NSString *name;
/* why the host refused the script, an exteria_status; zero for a plugin that loads */
@property (nonatomic, readonly) int status;
@property (nonatomic, readonly) unsigned permissions;
@property (nonatomic, readonly) unsigned hooks;
@property (nonatomic, readonly) BOOL enabled;
/* the file is not the one the person turned on, so the switch is off until they turn it on again */
@property (nonatomic, readonly) BOOL changed;
/* the last failure of a plugin that was switched off for failing, else nil */
@property (nonatomic, readonly, copy) NSString *fault;
@end

/* the folder the scripts live in; made when missing */
NSString *ExteriaPluginsDirectory(void);

/* loads the plugins that are on and tells them "start" */
void ExteriaPluginsStart(void);

/* reads the folder again and answers one entry for every .lua file, at most 64 */
NSArray *ExteriaPluginsList(void);

void ExteriaPluginsSetEnabled(NSString *file, BOOL enabled);

/* "stop", "pause" or "resume" for every plugin that is on */
void ExteriaPluginsEvent(const char *name);

/* the on_message hooks for a message of someone else that is about to be drawn. YES when a plugin hid it. a replaced text
   is put on the message itself, with the original kept, so calling this again for the same message gives the same answer */
BOOL ExteriaPluginsHidesMessage(ExteriaMessage *message, long long chat);

/* the on_send hooks for a text about to go out. YES when a plugin stopped the send; *text may come back replaced */
BOOL ExteriaPluginsStopsSend(NSString **text, long long chat, int replyTo);
