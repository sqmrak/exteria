#import <UIKit/UIKit.h>

/* the face the user picked for the whole app: a font file of their own, or Rubik, or neither (San Francisco, and Inter before ios 9). a font file wins over
   Rubik, since it is the narrower choice */

/* weight 0 to 3 is regular, medium, semibold, bold. nil when the user picked nothing or the picked face is missing, so the caller falls back to its own face */
UIFont *ExteriaFontChoiceFont(int weight, CGFloat size);

BOOL ExteriaFontRubikEverywhere(void);
void ExteriaFontStoreRubikEverywhere(BOOL on);

/* the name of the font file that is set, nil when there is none */
NSString *ExteriaFontCustomName(void);
/* copies a .ttf or .otf file into the app's own folder and registers it for this process; returns nil, or the text of the reason it was refused. main thread */
NSString *ExteriaFontImportCustom(NSString *path);
void ExteriaFontRemoveCustom(void);
