#import <UIKit/UIKit.h>

/* the card under the ring of the storage screen: a row for every kind of file with a coloured check, the size of it on the right, and the button that clears
   what is checked */
@interface ExteriaStorageCardView : UIView

/* called with the index of the row that was tapped, and when the button is tapped */
@property (nonatomic, copy) void (^toggleHandler)(NSUInteger index);
@property (nonatomic, copy) void (^clearHandler)(void);

/* titles, shares ("59%"), sizes, colors and checks (NSNumber BOOL) are arrays of one entry per row; sum is the size on the button, and the button is
   dead when nothing is checked */
- (void)setTitles:(NSArray *)titles shares:(NSArray *)shares sizes:(NSArray *)sizes colors:(NSArray *)colors checked:(NSArray *)checked
        buttonTitle:(NSString *)buttonTitle buttonSize:(NSString *)buttonSize enabled:(BOOL)enabled;
/* moves the check of one row and the button without rebuilding the rows */
- (void)setChecked:(BOOL)checked atIndex:(NSUInteger)index;
- (void)setButtonSize:(NSString *)buttonSize enabled:(BOOL)enabled;

+ (CGFloat)heightForRows:(NSUInteger)rows;

@end
