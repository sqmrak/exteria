#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* the people who took part in the development of Exteria, the ones of the credits in About */

#include "exteria_team.h"
@class ExteriaPerson;

BOOL ExteriaIsDeveloperId(long long userId);
NSUInteger ExteriaMarksOfId(long long userId);
NSArray *ExteriaOfficialTesterIds(void);
NSString *ExteriaTeamUsername(long long userId);
extern NSString *const ExteriaOpenTeamPersonNotification;
/* resolves a known id with this account's access hash; the username hint is accepted only when it still names that id */
void ExteriaLoadTeamPerson(ExteriaSession *session, long long userId, void (^completion)(ExteriaPerson *person, NSString *errorName));
/* a chat row or a chat header: a private chat or a bot chat with one of them; zero when the person wears nothing */
NSUInteger ExteriaDialogIsDeveloper(ExteriaDialog *dialog);
NSUInteger ExteriaPersonIsDeveloper(ExteriaPerson *person);
NSUInteger ExteriaMarkForDocument(long long document);

/* the plate that says why a mark is there, over whatever screen is up */
void ExteriaShowMarkNotice(NSString *name, NSUInteger mark);
