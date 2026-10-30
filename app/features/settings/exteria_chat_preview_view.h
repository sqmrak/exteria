#import <UIKit/UIKit.h>

/* what a chat looks like with the text size and the corners the person has set, the preview of
   ThemePreviewMessagesCell */
/* which talk the preview shows: the short one of the settings of chats and the wallpaper (a question with a quote,
   and an answer with a sticker), or the one of the Exteria chat screen */
typedef enum {
    ExteriaChatPreviewTalkSettings = 0,
    ExteriaChatPreviewTalkExteria,
    ExteriaChatPreviewTalkQuickReaction
} ExteriaChatPreviewTalk;

@interface ExteriaChatPreviewView : UIView

- (id)initWithTalk:(ExteriaChatPreviewTalk)talk;

/* runs when the preview comes out taller or shorter than the row it sits in was told, so the table makes the row
   follow it */
@property (nonatomic, copy) void (^heightHandler)(void);
/* the height the preview takes at this width, for the text size now set */
- (CGFloat)heightForWidth:(CGFloat)width;
- (void)setQuickReaction:(NSString *)value display:(NSString *)display;

@end
