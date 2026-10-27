#import <UIKit/UIKit.h>

/* a login QR code drawn in rounded modules with the app logo in the middle */
@interface ExteriaQrView : UIView

/* modules is side * side bytes, 1 for dark, as exteria_qr_encode gives them; with animated a code that is already
   shown fades away under the new one; without it the code simply appears */
- (void)setModules:(NSData *)modules side:(NSInteger)side animated:(BOOL)animated;
/* no code: only the logo, which waits for the first one */
- (void)clear;
/* the logo's own pulse and the pop-in stand still when this is set, as the system's reduce motion asks */
@property (nonatomic, assign) BOOL stillMode;
/* a picture, such as a profile photo, to show in the middle disc in place of the logo; nil goes back to the logo */
@property (nonatomic, retain) UIImage *centerImage;

/* the disc in the middle gets a polished metal rim and a gloss, as the classic style draws its buttons and bars */
@property (nonatomic, assign) BOOL metallic;

/* the modules shade from the top color to the bottom one down the code; nil for both is the dark violet of the
   login code */
- (void)setModuleTopColor:(UIColor *)top bottomColor:(UIColor *)bottom;

/* the color behind the modules, white unless set; a code stays light behind dark modules so a scanner reads it */
@property (nonatomic, retain) UIColor *paperColor;

@end
