#import <UIKit/UIKit.h>

/* changes the rows of a one-section table the way DialogsItemAnimator does; rows that left fade out, new rows fade
   in, and a row that moved travels to its place, where reloadData would redraw the whole list in one frame */
BOOL ExteriaTableUpdateRows(UITableView *table, NSArray *oldKeys, NSArray *newKeys, void (^refresh)(UITableViewCell *cell, NSUInteger newIndex));
