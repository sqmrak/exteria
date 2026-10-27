#import <UIKit/UIKit.h>

#import "exteria_session.h"

/* the people who took part in the development of Exteria, the ones of the credits in About */

extern NSString *const ExteriaDevelopersDidChangeNotification;

/* the marks a person wears after the name, as bits: the hammer of everyone who took part, and the fox tail of the developer of Senko on top of it */
enum {
    ExteriaMarkDeveloper = 1,
    ExteriaMarkSenko = 2,
    /* the net of the people who tested Exteria */
    ExteriaMarkTester = 4,
    /* the crossed hammers of the lead developer, worn in the place of the plain hammer */
    ExteriaMarkLead = 8,
    ExteriaMarkCaution = 16
};

BOOL ExteriaIsDeveloperUsername(NSString *username);
BOOL ExteriaIsDeveloperId(long long userId);
NSUInteger ExteriaMarksOfId(long long userId);
/* a chat row or a chat header: a private chat or a bot chat with one of them; zero when the person wears nothing */
NSUInteger ExteriaDialogIsDeveloper(ExteriaDialog *dialog);
NSUInteger ExteriaPersonIsDeveloper(ExteriaPerson *person);
/* which mark a tap hit, given how far from the end of the name (past the last mark) it landed, zero for none; the last mark is the one nearest the end */
NSUInteger ExteriaMarkAtDistance(NSUInteger marks, CGFloat distanceFromEnd);

/* looks the usernames up once, keeps the ids between runs, and asks again after a week; posts ExteriaDevelopersDidChangeNotification when a new id arrives */
void ExteriaLearnDevelopers(ExteriaSession *session);

/* the plate that says why a mark is there, over whatever screen is up */
void ExteriaShowMarkNotice(NSString *name, NSUInteger mark);
