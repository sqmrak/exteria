#import <UIKit/UIKit.h>

#import "exteria_avatar_view.h"
#import "exteria_message.h"

@class ExteriaInputBar, ExteriaSession, ExteriaInputFormat;

/* what the round button records when the field is empty; a tap swaps one for the other, a hold records */
typedef enum { ExteriaRecordVoice, ExteriaRecordRound } ExteriaRecordMode;

/* the keyboard of a bot, next to the paperclip: not offered, offered (the grid glyph) or open in place of the system keyboard (the keyboard glyph) */
typedef enum { ExteriaBotKeyboardNone, ExteriaBotKeyboardOffered, ExteriaBotKeyboardOpen } ExteriaBotKeyboardState;

@protocol ExteriaInputBarDelegate <NSObject>
- (void)inputBarDidTapSend:(ExteriaInputBar *)bar;
/* the smiley or keyboard button: the screen swaps the keyboard for the emoji and sticker panel or back */
- (void)inputBarDidTapPanelButton:(ExteriaInputBar *)bar;
/* the text grew or shrank to another number of lines, so the bar needs another height */
- (void)inputBarDidChangeHeight:(ExteriaInputBar *)bar;
- (void)inputBarDidBeginEditing:(ExteriaInputBar *)bar;
/* the paperclip: the screen offers a photo or video, a file or the place the person stands in */
- (void)inputBarDidTapAttach:(ExteriaInputBar *)bar;
/* the button was held long enough: the screen starts the recorder and answers NO when it cannot, which ends the hold */
- (BOOL)inputBar:(ExteriaInputBar *)bar didBeginRecording:(ExteriaRecordMode)mode;
/* the finger came up; cancelled is set when it had slid away to the left */
- (void)inputBar:(ExteriaInputBar *)bar didFinishRecordingCancelled:(BOOL)cancelled;
@optional
/* the pill left of the field, the bot's menu or its web app */
- (void)inputBarDidTapMenu:(ExteriaInputBar *)bar;
- (void)inputBarDidTapBotKeyboard:(ExteriaInputBar *)bar;
/* the wide button that stands in for the field, such as the one that starts a bot */
- (void)inputBarDidTapAction:(ExteriaInputBar *)bar;
/* the picture left of the field that shows who the message is sent as */
- (void)inputBarDidTapSender:(ExteriaInputBar *)bar;
/* the text of the field changed */
- (void)inputBarDidChangeText:(ExteriaInputBar *)bar;
@end

/* the message field with its smiley button and the round button, which sends text or, with an empty field, records */
@interface ExteriaInputBar : UIView <UITextViewDelegate> {
    id<ExteriaInputBarDelegate> _delegate;
    BOOL _panelShown;
}

@property (nonatomic, assign) id<ExteriaInputBarDelegate> delegate;
/* shows the keyboard glyph on the button while the panel stands in for the keyboard */
@property (nonatomic, assign) BOOL panelShown;
@property (nonatomic, readonly) UITextView *textView;
/* what the field says while it is empty; nil for the usual words */
@property (nonatomic, copy) NSString *placeholderText;
/* a pill with this title stands left of the field; nil takes it away */
@property (nonatomic, copy) NSString *menuTitle;
@property (nonatomic, assign) ExteriaBotKeyboardState botKeyboardState;
/* the round picture of the identity the message is sent as stands left of the field while this is set; the owner fills the picture */
@property (nonatomic, assign) BOOL senderVisible;
@property (nonatomic, readonly) ExteriaAvatarView *senderAvatar;
/* a wide button with this title takes the place of the whole bar's controls; nil gives the field back */
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, assign) BOOL actionWithInput;
/* false for a chat the person cannot write in, such as a channel, which swaps the field for a note */
@property (nonatomic, assign) BOOL writable;
@property (nonatomic, copy) NSString *readOnlyNote;

/* the height the bar wants for the text it holds, without the bottom safe area */
/* the timer of the recording shown in place of the field while the button is held */
/* the "1" in the recording strip: the voice note or round video can be heard or seen once; kept until a recording goes out */
@property (nonatomic, readonly) BOOL oneTimeRecording;
- (void)clearOneTimeRecording;
- (void)setRecordingElapsed:(NSTimeInterval)elapsed;
/* a voice message recorded without a finger on the button, for the phone held to the ear */
- (BOOL)beginRaisedRecording;
- (void)endRaisedRecordingCancelled:(BOOL)cancelled;
/* ends a hold that is still down, as when the recorder stopped by itself; the delegate hears a cancelled finish */
- (void)releaseHold;
/* where the round button is, in the coordinates of view */
- (CGPoint)recordButtonCenterInView:(UIView *)view;
- (CGFloat)preferredHeight;
- (NSString *)trimmedText;
/* a custom emoji typed from the premium panel: the field holds the emoji it stands for, and the bar remembers which document draws it
   while the text around it is edited */
- (void)insertCustomEmoji:(long long)documentId alt:(NSString *)alt;
/* the picker types for the person: ios 6 does not tell the text view's delegate about insertText: and deleteBackward, so the
   placeholder, the send button and the height are brought up to date here */
- (void)insertEmoji:(NSString *)emoji;
- (void)deleteBackwardFromPicker;
/* the ExteriaTextEntity items for the custom emoji and the styled runs in trimmedText, offsets counted in that text */
- (NSArray *)sendEntities;
/* the session that resolves a mention and translates, and the view the format sheets and the date picker show over (the screen's own view) */
@property (nonatomic, assign) ExteriaSession *session;
@property (nonatomic, assign) UIView *formatHost;
- (ExteriaInputFormat *)formatter;
/* replaces a range of the text and puts the caret after the new text, the way typing would: the custom emoji after
   the range move with the edit, and the delegate hears of the change */
- (void)replaceRange:(NSRange)range withText:(NSString *)replacement;
- (void)clear;
/* puts a text in the field with the custom emoji and the styled runs it came with, the caret after it, and tells the delegate the text changed */
- (void)setText:(NSString *)text entities:(NSArray *)entities;

@end
