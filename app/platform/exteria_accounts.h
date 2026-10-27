#import <Foundation/Foundation.h>

/* the accounts signed in on this phone; one of them is active, and only that one has a connection */

/* the support directory that holds all the accounts */
NSString *ExteriaAccountsRoot(void);
NSString *ExteriaAccountDirectory(NSString *name);
/* the names of the accounts that are signed in, the first one first */
NSArray *ExteriaAccountNames(void);
/* the name of the active account; the first one when none was chosen or the chosen one is gone */
NSString *ExteriaAccountActive(void);
void ExteriaAccountSetActive(NSString *name);
/* a name no account has used, with its directory made */
NSString *ExteriaAccountMakeNew(void);
/* takes an account that never signed in, or signed out, off the disk; the first one only loses its record */
void ExteriaAccountRemove(NSString *name);

/* what the list of accounts shows for an account that is not connected: the name, the username, and the user id to tell the same person twice */
NSDictionary *ExteriaAccountInfo(NSString *name);
void ExteriaAccountSetInfo(NSString *name, NSString *title, NSString *username, long long userId);
/* the name of another account that is signed in as the same user, or nil */
NSString *ExteriaAccountNameOfUser(long long userId, NSString *except);

/* posted by the account page: the active account is to become userInfo[@"name"], or a new one is to be signed in */
extern NSString *const ExteriaAccountSwitchNotification;
extern NSString *const ExteriaAccountAddNotification;
