#import <UIKit/UIKit.h>

/* the wide call to action button; the label is a real subview so it stays sharp and accessible */
@interface ExteriaWaveButton : UIControl

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat titleSize;

@end
