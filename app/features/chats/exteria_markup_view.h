#import <UIKit/UIKit.h>

#import "exteria_bot_markup.h"

/* the buttons a bot puts under a message: rows of equal buttons laid out by the core, each a touch target of its own */
@interface ExteriaMarkupView : UIView {
    ExteriaMarkup *_markup;
    NSMutableArray *_buttons;
    NSData *_frames;
    NSInteger _busy;
    void (^_pressHandler)(ExteriaMarkupButton *button);
}

/* runs on a press of an enabled button */
@property (nonatomic, copy) void (^pressHandler)(ExteriaMarkupButton *button);
@property (nonatomic, readonly, retain) ExteriaMarkup *markup;

/* shows the buttons at the frames the item worked out; the frames are relative to this view */
- (void)setMarkup:(ExteriaMarkup *)markup frames:(NSData *)frames;
/* a spinner on the button while its press is being answered; the button of a markup, or nil for none */
- (void)setBusyButton:(ExteriaMarkupButton *)button;

@end
