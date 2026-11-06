#import <Foundation/Foundation.h>

/* the deb runs the app executable as root with "--system-notifications on" or "off" and exits with the result; there is no screen and no account involved.
   ios 5 and 6 give notification settings only to apps of the user: SpringBoard skips an app that sits in /Applications unless it carries the internal tag, and then
   hides the icon of an internal app unless SBShowInternalApps is set. "on" adds the tag to the Info.plist of this bundle and sets the switch; "off" takes the switch back
   when "on" was the one that set it. Other systems are left alone. Returns the exit status of the process */
int ExteriaSystemNotificationsRun(const char *command);
