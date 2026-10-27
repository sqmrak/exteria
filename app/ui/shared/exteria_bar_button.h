#import <UIKit/UIKit.h>

/* a text button for the top bar, with an optional back chevron */
@interface ExteriaBarButton : UIControl

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL chevron;
@property (nonatomic, assign) BOOL bold;
@property (nonatomic, assign) CGFloat titleSize;
@property (nonatomic, assign) BOOL dimmed;

@end
