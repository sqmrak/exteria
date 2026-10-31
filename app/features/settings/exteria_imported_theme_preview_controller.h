#import <UIKit/UIKit.h>

@interface ExteriaImportedThemePreviewController : UIViewController
+ (void)openURL:(NSURL *)url fromController:(UIViewController *)controller;
- (id)initWithURL:(NSURL *)url name:(NSString *)name dark:(BOOL)dark;
@end
