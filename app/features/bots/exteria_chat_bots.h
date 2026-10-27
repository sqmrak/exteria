#import <UIKit/UIKit.h>

#import "exteria_input_bar.h"
#import "exteria_weak_reference.h"
#import "exteria_link_router.h"
#import "exteria_message_cell.h"
#import "exteria_session_bots.h"
#import "exteria_suggestion_panel.h"

@class ExteriaChatBots;

/* what the coordinator asks of the chat screen it serves */
@protocol ExteriaChatBotsHost <NSObject>
- (ExteriaInputBar *)botsInputBar;
/* the view the panels and cards are added to */
- (UIView *)botsContainerView;
/* sends text as the person's own message in this chat */
- (void)botsSendText:(NSString *)text replyTo:(int32_t)replyTo;
- (long long)botsRandomId;
/* the geometry of the bar or the panels changed */
- (void)botsRelayout;
/* the view that stands in for the system keyboard, nil to give the system keyboard back */
- (void)botsSetInputView:(UIView *)view;
/* the room a replacement keyboard may take */
- (CGFloat)botsKeyboardMaxHeight;
/* the user with this id, as the history of the chat named them; nil when it did not */
- (ExteriaPerson *)botsPersonForUserId:(long long)userId;
/* the chat shares the person's position, which arrives as a message of its own */
- (void)botsRequestLocation;
/* puts text in the field and opens the keyboard */
- (void)botsSetDraft:(NSString *)text;
/* the people of this chat the history has named, for the names offered after an @ */
- (NSArray *)botsMentionCandidates;
@end

/* everything a chat does for bots, so the screen only forwards what happens in it */
@interface ExteriaChatBots : NSObject {
    ExteriaSession *_session;
    ExteriaDialog *_dialog;
    ExteriaLinkRouter *_router;
    id<ExteriaChatBotsHost> _host;
    ExteriaWeakReference *_weak;
    ExteriaMediaCache *_media;
}

- (id)initWithSession:(ExteriaSession *)session dialog:(ExteriaDialog *)dialog router:(ExteriaLinkRouter *)router media:(ExteriaMediaCache *)media
                 host:(id<ExteriaChatBotsHost>)host;

@property (nonatomic, assign) id<ExteriaChatBotsHost> host;
/* the parameter the first press of Start sends, from a link; nil for none */
@property (nonatomic, copy) NSString *startParam;
/* the panel over the bar while commands or answers are offered, nil while none is */
@property (nonatomic, readonly) ExteriaSuggestionPanel *panel;
/* the card with the bot's description in an empty chat, nil when there is none to show */
@property (nonatomic, readonly) UIView *card;

/* loads what a bot says about itself; a chat with anyone else does nothing */
- (void)start;
/* the messages of the chat in order, oldest first, after each change; loaded says the first page has arrived */
- (void)messagesChanged:(NSArray *)messages loaded:(BOOL)loaded;
/* the text in the field changed */
- (void)inputTextChanged;
/* the message a text typed now answers: the one a bot asked for an answer to, zero otherwise */
- (int32_t)replyTargetForText;
/* the person sent something themselves */
- (void)didSendText;

/* the emoji panel is about to take the place of the keyboard or give it back: a bot's keyboard that was open steps aside */
- (void)emojiPanelWillChange;

/* the bar's pill, keyboard button and wide button */
- (void)menuTapped;
- (void)keyboardButtonTapped;
- (void)actionTapped;

/* a button under message was pressed; the cell shows the spinner while the answer is awaited */
- (void)pressButton:(ExteriaMarkupButton *)button ofMessage:(ExteriaMessage *)message cell:(ExteriaMessageCell *)cell;
/* a link in a message: a command, a name, an address */
- (BOOL)openLink:(NSString *)url;

/* puts the card in the middle of the room the chat leaves free */
- (void)layoutCardInRect:(CGRect)rect;
/* the height the panel wants for the width, and its place is up to the screen */
- (CGFloat)panelHeightForWidth:(CGFloat)width maxHeight:(CGFloat)maxHeight;
/* stops everything that is still waiting for an answer */
- (void)teardown;

@end
