#import <UIKit/UIKit.h>

#import "exteria_symbol.h"

/* a small card of rows that grows out of the corner it hangs from, over a see-through layer that closes it on a tap */
@interface ExteriaPopupMenu : UIView

/* height covered by the keyboard in the host view */
@property (nonatomic, assign) CGFloat bottomInset;

/* each row has a glyph and a title; the handler runs after the card has left, with the row's index */
- (id)initWithTitles:(NSArray *)titles symbols:(const ExteriaSymbol *)symbols handler:(void (^)(NSUInteger index))handler;
/* the card hangs from anchor, a point in the coordinates of host, which is covered by the menu while it is open */
- (void)showInView:(UIView *)host anchor:(CGPoint)anchor;
- (void)dismiss;

@end
