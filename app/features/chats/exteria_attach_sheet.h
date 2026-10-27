#import <UIKit/UIKit.h>

#import "exteria_attach_options.h"

typedef enum { ExteriaAttachGallery, ExteriaAttachFile, ExteriaAttachLocation, ExteriaAttachGift, ExteriaAttachContact, ExteriaAttachCamera } ExteriaAttachChoice;

@class ExteriaAttachSheet;

@protocol ExteriaAttachSheetDelegate <NSObject>
- (void)attachSheet:(ExteriaAttachSheet *)sheet didChoose:(ExteriaAttachChoice)choice;
/* the pictures picked, with the words and the choices of the sheet's menu */
- (void)attachSheet:(ExteriaAttachSheet *)sheet didChooseAssets:(NSArray *)urls options:(ExteriaAttachOptions *)options;
@end

@interface ExteriaAttachSheet : UIView
@property (nonatomic, assign) id<ExteriaAttachSheetDelegate> delegate;
@property (nonatomic, assign) BOOL offersGift;
- (void)showInView:(UIView *)host;
- (void)dismiss;
@end
