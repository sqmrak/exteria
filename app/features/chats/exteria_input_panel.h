#import <UIKit/UIKit.h>

#import "exteria_custom_emoji_picker.h"
#import "exteria_emoji_picker.h"
#import "exteria_gif_picker.h"
#import "exteria_sticker_picker.h"

@class ExteriaInputPanel;

@protocol ExteriaInputPanelDelegate <NSObject>
- (void)inputPanel:(ExteriaInputPanel *)panel didPickEmoji:(NSString *)emoji;
- (void)inputPanelDidTapBackspace:(ExteriaInputPanel *)panel;
- (void)inputPanel:(ExteriaInputPanel *)panel didPickSticker:(ExteriaSticker *)sticker;
- (void)inputPanel:(ExteriaInputPanel *)panel didPickCustomEmoji:(ExteriaCustomEmojiDocument *)emoji;
- (void)inputPanel:(ExteriaInputPanel *)panel didPickGif:(ExteriaMedia *)gif;
- (void)inputPanel:(ExteriaInputPanel *)panel didPickInlineResult:(ExteriaInlineResult *)result queryId:(long long)queryId;
/* the tile "Create" of the sticker grid */
- (void)inputPanelDidTapCreateSticker:(ExteriaInputPanel *)panel;
@end

/* what stands in for the keyboard: the emoji grid, the animations and the sticker list, and for Premium the custom
   emoji grid */
@interface ExteriaInputPanel : UIView <ExteriaEmojiPickerDelegate, ExteriaStickerPickerDelegate, ExteriaCustomEmojiPickerDelegate, ExteriaGifPickerDelegate> {
    id<ExteriaInputPanelDelegate> _delegate;
}
@property (nonatomic, assign) id<ExteriaInputPanelDelegate> delegate;

- (id)initWithMedia:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library;
/* adds the tab of custom emoji, for an account with Telegram Premium; asking twice is the same as once */
- (void)enableCustomEmojiWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media;
/* the tab of animations; dialog is the chat they are sent to, which the search needs */
- (void)enableGifsWithSession:(ExteriaSession *)session media:(ExteriaMediaCache *)media library:(ExteriaStickerLibrary *)library dialog:(ExteriaDialog *)dialog;

@end
