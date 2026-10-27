#import <UIKit/UIKit.h>

NSString *ExteriaFileSizeText(long long bytes);

#import "exteria_bot_markup.h"
#import "exteria_message.h"
#import "exteria_person.h"
#import "exteria_text_layout.h"

typedef enum {
    ExteriaChatItemPill,        /* a date or a service line, centered in a capsule */
    ExteriaChatItemBubble,
    ExteriaChatItemSticker,     /* a sticker, drawn without a bubble */
    ExteriaChatItemRound,       /* a round video, drawn as a circle without a bubble */
    ExteriaChatItemEmoji        /* one emoji alone in a message, drawn large and animated when Telegram has an animation for it */
} ExteriaChatItemKind;

/* what a bubble holds above its text */
typedef enum {
    ExteriaChatItemContentNone,
    ExteriaChatItemContentPicture,  /* a photo, or the thumbnail of a video */
    ExteriaChatItemContentFile,     /* an icon and two lines */
    ExteriaChatItemContentPoll      /* a question, its answers with their bars, and the button that votes */
} ExteriaChatItemContent;

/* one row of the chat: the message and everything the cell needs to draw it, worked out for a width; built and
   laid out on the main thread, since the fonts and the text layout come from UIKit */
/* the pictures of the last voters of a public poll, small circles that overlap them before the count of votes */
#define EXTERIA_POLL_VOTER_SIDE 18.0
#define EXTERIA_POLL_VOTER_STEP 12.0
CGFloat ExteriaPollVotersWidth(NSUInteger count);

@interface ExteriaChatItem : NSObject {
    ExteriaChatItemKind _kind;
    NSUInteger _singleEmoji;
    ExteriaChatItemContent _content;
    ExteriaMessage *_message;
    NSString *_pillText;
    NSString *_senderName;
    /* the document drawn after the sender name: their status, or the Premium star, zero for none */
    long long _senderBadge;
    NSUInteger _senderDeveloper;
    NSString *_transcript;
    NSString *_senderTag;
    ExteriaPerson *_senderPerson;
    BOOL _avatarColumn;
    UIColor *_senderColor;
    NSString *_forwardText;
    NSString *_replyTitle;
    NSString *_replyText;
    NSArray *_replyEntities;
    UIColor *_replyColor;
    CGRect _replyFrame;
    ExteriaTextLayout *_replyTitleLayout;
    ExteriaTextLayout *_replyTextLayout;
    NSString *_timeText;
    NSString *_viewsText;
    CGFloat _viewsWidth;
    NSString *_commentsText;
    NSArray *_commenterPeople;
    BOOL _showsShare;
    BOOL _reactionsHidden;
    NSString *_fileTitle;
    NSString *_fileDetail;
    BOOL _joinsPrevious;
    BOOL _joinsNext;
    BOOL _read;
    /* the message as it was when the item was built; the message object can change under the item */
    int32_t _builtMessageId;
    long long _builtRandomId;
    ExteriaMessageState _builtState;
    BOOL _builtEdited;
    BOOL _builtDeleted;
    int _builtService;
    NSString *_builtText;
    /* the reactions and the faces on their chips as they were when the row was laid out, to tell whether a message changed them */
    NSString *_builtReactionKey;
    NSString *_builtMarkupKey;
    NSString *_builtPollKey;
    /* an album: the photos and videos sent together, in order, which the one bubble shows as a collage, and where each picture stands in the bubble */
    NSArray *_albumMessages;
    NSArray *_albumFrames;
    NSString *_builtAlbumKey;
    /* the grouping and read flags the table last drew */
    BOOL _shownJoinsPrevious;
    BOOL _shownJoinsNext;
    BOOL _shownRead;
    ExteriaTextLayout *_textLayout;
    ExteriaTextLayout *_pillLayout;
    CGFloat _pillShift;
    ExteriaTextLayout *_senderLayout;
    ExteriaTextLayout *_senderTagLayout;
    ExteriaTextLayout *_forwardLayout;
    ExteriaTextLayout *_fileTitleLayout;
    CGFloat _layoutWidth;
    CGFloat _height;
    CGRect _bubbleFrame;
    CGRect _reactionFrame;
    BOOL _reactionsInside;
    ExteriaMarkup *_markup;
    CGRect _markupFrame;
    NSData *_markupButtons;
    CGRect _commentsFrame;
    CGRect _shareFrame;
    CGRect _pictureFrame;
    CGRect _fileFrame;
    /* a poll: the question and the line about its kind, an answer per row, the button that votes or takes the vote back, and the count of votes */
    ExteriaTextLayout *_pollQuestionLayout;
    CGPoint _pollQuestionOrigin;
    ExteriaTextLayout *_pollKindLayout;
    CGPoint _pollKindOrigin;
    NSArray *_pollVoterPeople;
    BOOL _pollFooterOwnRow;
    CGFloat _pollFooterY;
    NSMutableArray *_pollAnswerLayouts;
    NSMutableArray *_pollAnswerFrames;
    BOOL _pollShowsResults;
    CGRect _pollButtonFrame;
    NSString *_pollButtonTitle;
    NSString *_pollFooterText;
    BOOL _call;
    BOOL _callIncoming;
    BOOL _callFailed;
    BOOL _callVideo;
    CGPoint _senderOrigin;
    CGPoint _senderTagOrigin;
    CGPoint _forwardOrigin;
    CGPoint _textOrigin;
    CGPoint _timeOrigin;
    CGSize _timeSize;
}

/* who wrote a forwarded message, by the header or by the people the answer named; empty when it is hidden */
NSString *ExteriaForwardName(ExteriaMessage *message, NSDictionary *people);

+ (ExteriaChatItem *)pillWithText:(NSString *)text;
/* group: the chat names its senders; the item picks up the person's name when the people dictionary has it */
+ (ExteriaChatItem *)itemForMessage:(ExteriaMessage *)message group:(BOOL)group people:(NSDictionary *)people;
/* role: the group role of the sender, shown beside the name when the message carries no custom rank */
+ (ExteriaChatItem *)itemForMessage:(ExteriaMessage *)message group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role;
/* the one item of an album of two or more photos and videos: the sender, the words and the reactions are those of the first message that has words, else the first */
+ (ExteriaChatItem *)itemForAlbum:(NSArray *)messages group:(BOOL)group people:(NSDictionary *)people role:(NSString *)role;
@property (nonatomic, readonly, retain) NSArray *albumMessages;
/* NSValue rects, one per album message, in the coordinates of the bubble */
@property (nonatomic, readonly, retain) NSArray *albumFrames;
/* whether the item shows exactly these messages, in this order */
- (BOOL)reflectsAlbum:(NSArray *)messages;
/* the album message whose picture holds the point, or nil */
- (ExteriaMessage *)albumMessageAtPoint:(CGPoint)point;

@property (nonatomic, readonly) ExteriaChatItemKind kind;
/* the emoji table entry of an emoji item */
@property (nonatomic, readonly) NSUInteger singleEmoji;
@property (nonatomic, readonly) ExteriaChatItemContent content;
@property (nonatomic, readonly, retain) ExteriaMessage *message;
@property (nonatomic, readonly, copy) NSString *pillText;
@property (nonatomic, readonly, copy) NSString *senderName;
/* the words of a voice message that the server wrote down, shown under it as the text of a message would be; nil
   until asked for */
@property (nonatomic, copy) NSString *transcript;
/* the chat shows no reactions (the setting for its kind of chat): neither the chips under the bubble nor the room
   they take; set before the item is laid out */
@property (nonatomic, assign) BOOL reactionsHidden;
/* a poll: the layouts and rows its bubble draws, in the coordinates of the bubble */
@property (nonatomic, readonly, retain) ExteriaTextLayout *pollQuestionLayout;
@property (nonatomic, readonly) CGPoint pollQuestionOrigin;
@property (nonatomic, readonly, retain) ExteriaTextLayout *pollKindLayout;
/* the people (ExteriaPerson) who voted last in a public poll, whose pictures stand before the count of votes */
@property (nonatomic, readonly, retain) NSArray *pollVoterPeople;
/* the count of votes has a row of its own over the chips of the reactions, at pollFooterY; otherwise it shares the row of the time */
@property (nonatomic, readonly) BOOL pollFooterOwnRow;
@property (nonatomic, readonly) CGFloat pollFooterY;
@property (nonatomic, readonly) CGPoint pollKindOrigin;
@property (nonatomic, readonly, retain) NSArray *pollAnswerLayouts;
/* NSValue rects, one per answer, each the whole row with its bar */
@property (nonatomic, readonly, retain) NSArray *pollAnswerFrames;
/* the bars and percentages show */
@property (nonatomic, readonly) BOOL pollShowsResults;
/* the button under the answers, a zero rect and no title when there is none */
@property (nonatomic, readonly) CGRect pollButtonFrame;
@property (nonatomic, readonly, copy) NSString *pollButtonTitle;
@property (nonatomic, readonly, copy) NSString *pollFooterText;
/* the answer whose row holds the point, or NSNotFound */
- (NSUInteger)pollAnswerAtPoint:(CGPoint)point;
/* the reactions the item draws: none when they are hidden */
- (NSArray *)shownReactions;
/* the rank or role of the sender and the bot mark, drawn after the name */
@property (nonatomic, readonly, copy) NSString *senderTag;
@property (nonatomic, readonly, retain) ExteriaTextLayout *senderTagLayout;
@property (nonatomic, readonly) CGPoint senderTagOrigin;
@property (nonatomic, readonly, retain) UIColor *senderColor;
@property (nonatomic, readonly, copy) NSString *forwardText;
@property (nonatomic, readonly, copy) NSString *replyTitle;
@property (nonatomic, readonly, copy) NSString *replyText;
@property (nonatomic, copy) NSArray *replyEntities;
@property (nonatomic, readonly, retain) UIColor *replyColor;
@property (nonatomic, readonly) CGRect replyFrame;
@property (nonatomic, readonly, retain) ExteriaTextLayout *replyTitleLayout;
@property (nonatomic, readonly, retain) ExteriaTextLayout *replyTextLayout;
- (void)setReplyTitle:(NSString *)title text:(NSString *)text color:(UIColor *)color;
@property (nonatomic, readonly, copy) NSString *timeText;
/* a channel post's view count in short form ("79", "1.2K"), nil without one; it is drawn before the time, behind a small eye, and
   viewsWidth is the room that takes */
@property (nonatomic, readonly, copy) NSString *viewsText;
@property (nonatomic, readonly) CGFloat viewsWidth;
/* the row under a post that has comments: "10 comments", and the ExteriaPerson items of the newest commenters the chat knows */
@property (nonatomic, readonly, copy) NSString *commentsText;
@property (nonatomic, readonly, retain) NSArray *commenterPeople;
/* a round button stands right of a channel post */
@property (nonatomic, readonly) BOOL showsShare;
/* relative to the bubble */
@property (nonatomic, readonly) CGRect commentsFrame;
@property (nonatomic, readonly) CGRect shareFrame;
@property (nonatomic, readonly, copy) NSString *fileTitle;
@property (nonatomic, readonly, copy) NSString *fileDetail;
/* in a group the messages of others stand to the right of a column that holds the sender's picture under the last message of a run */
@property (nonatomic, readonly) BOOL hasAvatarColumn;
@property (nonatomic, readonly) BOOL showsAvatar;
@property (nonatomic, readonly, retain) ExteriaPerson *senderPerson;
@property (nonatomic, assign) BOOL joinsPrevious;
@property (nonatomic, assign) BOOL joinsNext;
/* the other side has read this message of ours */
@property (nonatomic, assign) BOOL read;
@property (nonatomic, readonly, retain) ExteriaTextLayout *textLayout;
/* the short lines of a bubble, laid out like the text so the emoji in a name or a file name are the app's pictures too */
@property (nonatomic, readonly, retain) ExteriaTextLayout *pillLayout;
/* how far the centered lines sit right of the layout's own left edge; the capsule is as wide as the text, so draw back by it */
@property (nonatomic, readonly) CGFloat pillShift;
@property (nonatomic, readonly, retain) ExteriaTextLayout *senderLayout;
@property (nonatomic, readonly, retain) ExteriaTextLayout *forwardLayout;
@property (nonatomic, readonly, retain) ExteriaTextLayout *fileTitleLayout;
@property (nonatomic, readonly) CGSize timeSize;

@property (nonatomic, readonly) CGFloat height;
@property (nonatomic, readonly) CGRect bubbleFrame;
/* relative to the bubble */
@property (nonatomic, readonly) CGRect reactionFrame;
/* the chips are in the bubble, left aligned, and reactionFrame is where they stand; otherwise they hang under it */
@property (nonatomic, readonly) BOOL reactionsInside;
/* the buttons under the bubble of a bot's message, nil for a message without any */
@property (nonatomic, readonly, retain) ExteriaMarkup *markup;
@property (nonatomic, readonly) CGRect markupFrame;
@property (nonatomic, readonly, retain) NSData *markupButtons;
@property (nonatomic, readonly) CGRect pictureFrame;
@property (nonatomic, readonly) CGRect fileFrame;
/* a call service message drawn as a bubble of its own */
@property (nonatomic, readonly) BOOL call;
@property (nonatomic, readonly) BOOL callIncoming;
@property (nonatomic, readonly) BOOL callFailed;
@property (nonatomic, readonly) BOOL callVideo;
@property (nonatomic, readonly) CGPoint senderOrigin;
/* the name over the bubble ends in the hammer of the developers */
@property (nonatomic, readonly) NSUInteger senderDeveloper;
@property (nonatomic, readonly) CGPoint forwardOrigin;
@property (nonatomic, readonly) CGPoint textOrigin;
@property (nonatomic, readonly) CGPoint timeOrigin;

/* the item was built from what the message holds now, so it can be drawn again instead of building a new one */
- (BOOL)reflectsMessage:(ExteriaMessage *)message;
/* the sender's name, picture and tag are what this item was built with */
- (BOOL)reflectsPeople:(NSDictionary *)people role:(NSString *)role;
/* both stand for the same message, or for the same date pill; the content may differ */
- (BOOL)isSameRowAs:(ExteriaChatItem *)other;
/* the cell drawn for the other item still shows this one; the same item shows itself unless its flags moved since
   markDisplayed */
- (BOOL)displaysSameAs:(ExteriaChatItem *)other;
- (BOOL)hasDifferentReactionsFrom:(ExteriaChatItem *)other;
- (void)markDisplayed;

/* works the frames out for a table of this width; the same width again costs nothing */
- (void)layoutForWidth:(CGFloat)width;
/* forgets the work, for a change of the grouping that moves the corners and the spacing */
- (void)invalidateLayout;

@end
