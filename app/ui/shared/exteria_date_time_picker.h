#import <UIKit/UIKit.h>

/* a card with a wheel for the day and the time, over a host view: Cancel and OK on a bar above the wheel. done runs with the date after OK, cancelled
   after Cancel; the card takes itself off the host either way, and a tap outside it does nothing */
@interface ExteriaDateTimePicker : UIView
/* the wheel starts on initialDate (nil for now); minimumDate (nil for none) is the earliest it can show. a time-only wheel takes the day of initialDate */
- (id)initWithFrame:(CGRect)frame mode:(UIDatePickerMode)mode initialDate:(NSDate *)initialDate minimumDate:(NSDate *)minimumDate
               done:(void (^)(NSDate *date))done cancelled:(void (^)(void))cancelled;
@end
