#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

/* a plain browser of the folders the phone lets the app read, for choosing one file to send: iOS 5 has no document
   picker */
@interface ExteriaFilePicker : UITableViewController

/* nil directory opens the list of locations; the handler receives a chosen file on the main thread */
- (id)initWithDirectory:(NSString *)directory handler:(void (^)(NSString *path))handler cancel:(void (^)(void))cancel;

/* the picker can choose something other than a file to send: with extensions set (without the dot, say "tgios-theme") only folders and files of those kinds are listed, and
   the root, the search and the empty list speak of what is being chosen; set them before the picker is shown, folders opened inside carry them on */
@property (nonatomic, copy) NSArray *extensions;
@property (nonatomic, copy) NSString *rootTitle;
@property (nonatomic, copy) NSString *searchPlaceholder;
@property (nonatomic, copy) NSString *emptyText;
/* the glyph of a chosen kind of file in the list */
@property (nonatomic, assign) ExteriaSymbol fileSymbol;

@end
