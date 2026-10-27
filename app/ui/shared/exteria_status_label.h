#import <UIKit/UIKit.h>

#import "exteria_typing_board.h"

typedef enum {
    ExteriaStatusPlain = 0,     /* last seen, a kind of chat, a count: the quiet color */
    ExteriaStatusOnline,        /* the person is on line: the same words in the accent color */
    ExteriaStatusTyping         /* the person is typing or sending something; the accent color and three dots before the words */
} ExteriaStatusKind;

/* the line under a name in a chat or a profile; it colors itself by what it says, and while someone is typing it
   shows three dots that light one after the other before the text, as the status of the original does */
@interface ExteriaStatusLabel : UILabel {
    ExteriaStatusKind _kind;
    UIColor *_plainColor;
    UIColor *_activeColor;
    NSArray *_dots;
}

/* the colors of the quiet and the active states; the defaults are the secondary text color and the accent of the app */
@property (nonatomic, retain) UIColor *plainColor;
@property (nonatomic, retain) UIColor *activeColor;
@property (nonatomic, readonly) ExteriaStatusKind kind;

/* text and kind together, so the color and the dots never lag behind the words */
- (void)setStatus:(NSString *)text kind:(ExteriaStatusKind)kind;

@end

/* the words for what someone is doing in a chat, without the dots (the label draws those) */
NSString *ExteriaTypingStatusText(int action, NSUInteger count);
/* the same with who acts: in a group a single person is named before the words ("Ann is typing"), two are joined
   ("Ann and Bob are typing") */
NSString *ExteriaTypingStatusTextNamed(int action, NSUInteger count, NSArray *names);
/* the same for a row of the chat list; nil when nobody acts in that chat */
NSString *ExteriaTypingTextForDialog(ExteriaTypingBoard *board, ExteriaDialog *dialog);
