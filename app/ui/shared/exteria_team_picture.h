#import <UIKit/UIKit.h>

/* the pictures of the people of the team, kept in memory for the run and on disk for the next launch, so a screen that shows one has it at once and the server only corrects it.
   the credits page and the customization previews share them */
UIImage *ExteriaStoredTeamImage(NSNumber *identifier);
void ExteriaKeepTeamImage(NSNumber *identifier, UIImage *image);
