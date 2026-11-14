#import <Foundation/Foundation.h>

#import "exteria_status.h"

/* the panel a plugin shows for a job that takes a while (python/shim/org/telegram/ui/ActionBar AlertDialog of the loading and spinner kinds): a title, a text, a bar
   and buttons. a button reports its place in the list to exteria_host.alert_result and closes the panel; the plugin may close it itself. services, main thread only:

   progress.show (token, title, message, percent, buttons)   buttons are the captions in the order the plugin gave them
   progress.update (token, message, percent)
   progress.close (token) */
exteria_status ExteriaPluginProgressService(NSString *name, NSDictionary *request, NSDictionary **reply, NSString **failure);

/* takes every panel away, for when the plugins stop */
void ExteriaPluginProgressReset(void);
