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
/* the sheet that picks a photo or a video for the profile and nothing else: the grid under its own title, one tap on a picture hands it over, and none of the buttons for files, places, gifts and
   contacts, nor the words and the menu of a message; set before the sheet is shown */
@property (nonatomic, assign) BOOL profilePicker;
- (void)showInView:(UIView *)host;
- (void)dismiss;
@end
