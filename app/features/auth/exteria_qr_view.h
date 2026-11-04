#import <UIKit/UIKit.h>

/* the smallest version of a code that carries the logo: the logo and the room cleared round it hide a share of the modules that does not change with the size of the
   code, and the corrections of versions 1 to 3 do not make up for it, so a short link (a profile's t.me address is version 2) did not read at all. Versions 4 to 6 read
   in every try with the drawing of this view, and the later ones put an alignment pattern under the logo */
#define EXTERIA_QR_LOGO_MIN_VERSION 5

/* a QR code drawn in rounded modules with the app logo in the middle */
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
