#import <UIKit/UIKit.h>

/* a sheet from the bottom edge with a date wheel, for the birthday: the day, the month and the year, a switch that hides the
   year, and the buttons to cancel, remove the date or keep it */
@interface ExteriaDateSheet : UIView

/* day 0 starts the wheel on a fixed date; year 0 starts with the year hidden */
- (id)initWithDay:(int32_t)day month:(int32_t)month year:(int32_t)year;

/* runs when Done is tapped, with year zero when the switch hides it */
@property (nonatomic, copy) void (^doneHandler)(int32_t day, int32_t month, int32_t year);
/* runs when Remove is tapped; the button only shows when there is a date to remove */
@property (nonatomic, copy) void (^removeHandler)(void);
@property (nonatomic, assign) BOOL canRemove;

- (void)showInView:(UIView *)host;

@end
