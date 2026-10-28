#import <UIKit/UIKit.h>

#import "exteria_avatar_cache.h"
#import "exteria_chat_item.h"
#import "exteria_bot_markup.h"
#import "exteria_media_cache.h"

@class ExteriaMessageCell;
@class ExteriaStickerLibrary;

@protocol ExteriaMessageCellDelegate <NSObject>
/* the address of a link in the text was tapped */
- (void)messageCell:(ExteriaMessageCell *)cell didTapLink:(NSString *)url;
/* the red mark of a message that did not go out was tapped */
- (void)messageCellDidLongPress:(ExteriaMessageCell *)cell;
- (void)messageCell:(ExteriaMessageCell *)cell didTapReaction:(ExteriaReaction *)reaction;
- (void)messageCellDidTapFailed:(ExteriaMessageCell *)cell;
/* the preview of the message this one answers */
- (void)messageCellDidTapReply:(ExteriaMessageCell *)cell;
/* the play button or title of a song in a bubble was tapped */
- (void)messageCellDidTapAudio:(ExteriaMessageCell *)cell;
/* the file button of a document that has come was tapped: the file is at path, and name is what it was called */
- (void)messageCell:(ExteriaMessageCell *)cell didOpenFileAtPath:(NSString *)path name:(NSString *)name;
/* the round message played to its end; the next one of the chat can follow */
- (void)messageCellDidFinishRound:(ExteriaMessageCell *)cell;
/* the comments row under a channel post, and the round button beside it */
- (void)messageCellDidTapComments:(ExteriaMessageCell *)cell;
- (void)messageCellDidTapShare:(ExteriaMessageCell *)cell;
/* the name or picture of the sender of a group message was tapped */
- (void)messageCellDidTapSender:(ExteriaMessageCell *)cell;
@optional
/* the card of a one-time photo, video, voice note or round video was tapped */
- (void)messageCellDidTapViewOnce:(ExteriaMessageCell *)cell;
/* the cross on the picture or file of a message that is still going up was tapped */
- (void)messageCellDidCancelSending:(ExteriaMessageCell *)cell;
/* the line "forwarded from" of a bubble was tapped */
- (void)messageCellDidTapForward:(ExteriaMessageCell *)cell;
@required
/* the photo, video or animation of a message was tapped */
- (void)messageCellDidTapMedia:(ExteriaMessageCell *)cell;
/* a button under a bot's message was pressed */
- (void)messageCell:(ExteriaMessageCell *)cell didPressButton:(ExteriaMarkupButton *)button;
/* a swipe to the left over the message answers it: asked before the swipe may start, and told when it went far enough */
- (BOOL)messageCellCanSwipeReply:(ExteriaMessageCell *)cell;
- (void)messageCellDidSwipeReply:(ExteriaMessageCell *)cell;
@optional
- (void)messageCellDidRevealSpoiler:(ExteriaMessageCell *)cell;
/* a tap on a sticker that belongs to a pack: the screen shows the pack */
- (void)messageCellDidTapSticker:(ExteriaMessageCell *)cell;
/* a tap on the message that no link, picture, button or player of it took */
- (void)messageCellDidTapBody:(ExteriaMessageCell *)cell;
/* an answer of a poll was tapped, or the button under the answers when the index is -1 */
- (void)messageCell:(ExteriaMessageCell *)cell didTapPollAnswer:(NSInteger)index;
/* two taps on the message, when the setting for its direction gives them an action */
- (void)messageCellDidDoubleTap:(ExteriaMessageCell *)cell;
/* a tap on a row of a chat in which messages are being selected: the message goes in or out of the selection */
- (void)messageCellDidToggleSelection:(ExteriaMessageCell *)cell;
@end

/* one row of the chat */
@interface ExteriaMessageCell : UITableViewCell {
    id<ExteriaMessageCellDelegate> _delegate;
}

@property (nonatomic, assign) id<ExteriaMessageCellDelegate> delegate;
@property (nonatomic, readonly) ExteriaChatItem *item;
/* the message whose picture the last tap hit: a picture of an album, or the message of the row; set before the delegate hears of the tap */
@property (nonatomic, readonly) ExteriaMessage *tappedMediaMessage;
/* an emoji, sticker or gif eligible for the visible animation budget, including files still loading */
@property (nonatomic, readonly) BOOL animatedSticker;
/* gives a single emoji its animation, nil leaves the emoji picture */
@property (nonatomic, retain) ExteriaStickerLibrary *stickerLibrary;

/* a moving list holds new sticker renderers and inline players until it settles */
@property (nonatomic, assign) BOOL activationDeferred;

/* the ring on the cross of a message that is going up follows the message's uploadProgress */
- (void)showUploadProgress;
/* a band of the accent color fades in over the row and out again: the message a reply, a search or a bookmark led to */
- (void)flashHighlight;
/* the card of a one-time file burns away; completion runs when the animation is over */
- (void)playBurnWithCompletion:(void (^)(void))completion;

/* readies the picture of a row that is not on screen yet; a row without a picture does nothing */
+ (void)prepareItem:(ExteriaChatItem *)item media:(ExteriaMediaCache *)media;

/* the item must already be laid out for the width of the table */
- (void)configureWithItem:(ExteriaChatItem *)item media:(ExteriaMediaCache *)media avatars:(ExteriaAvatarCache *)avatars;
/* a chat that is selecting shows a circle on every message that can be picked and takes every tap on it for a pick; the incoming ones step
   aside to make room for it. selected fills the circle */
- (void)setSelecting:(BOOL)selecting selected:(BOOL)selected animated:(BOOL)animated;
/* a picture of the row as it is drawn now, for the menu that keeps the message lit while the rest of the chat is dimmed */
- (UIImage *)contentSnapshot;
/* a spinner on one button of the keyboard under the message while its press is answered; nil takes it away */
- (void)setBusyMarkupButton:(ExteriaMarkupButton *)button;
/* starts the round message of this cell if it is not already playing */
- (void)startRound;
/* the lottie sticker plays or rests on its first frame; any other cell ignores it */
- (void)setAnimating:(BOOL)animating;
- (BOOL)replySwipeActive;

@end
