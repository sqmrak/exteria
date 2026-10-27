#import <Foundation/Foundation.h>
@class UIImage;
#import "exteria_poll_model.h"

#import "exteria_bot_markup.h"

#include "exteria_messages.h"

@class ExteriaRemoteFile;

/* the photo, sticker or file of a message, built off the main thread */
@interface ExteriaMedia : NSObject {
    exteria_media_info _info;
    NSString *_name;
    NSString *_alt;
    NSString *_title;
    NSString *_performer;
    NSData *_waveformBars;
}

+ (ExteriaMedia *)mediaWithInfo:(const exteria_media_info *)info;

@property (nonatomic, readonly) exteria_preview_kind kind;
@property (nonatomic, readonly) exteria_geo_point location;
@property (nonatomic, readonly) exteria_sticker_format stickerFormat;
/* the set a sticker belongs to, zero when its document does not name one by id */
@property (nonatomic, readonly) long long stickerSetId;
@property (nonatomic, readonly) long long stickerSetHash;
/* the sender hid the picture or the video under a spoiler */
@property (nonatomic, readonly) BOOL spoiler;
@property (nonatomic, readonly) int32_t width;
@property (nonatomic, readonly) int32_t height;
@property (nonatomic, readonly) int32_t duration;
@property (nonatomic, readonly) long long size;
/* the file name, empty when the file has none */
@property (nonatomic, readonly, copy) NSString *name;
/* the emoji a sticker stands for */
@property (nonatomic, readonly, copy) NSString *alt;
/* the tags of a song, empty when the file has none */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *performer;
/* the bars of a voice note's waveform, one byte each from 0 to 31; nil when the note carries none */
@property (nonatomic, readonly, retain) NSData *waveformBars;
/* the file the bubble shows, and a smaller picture of it for while that loads; nil when there is nothing to fetch */
@property (nonatomic, readonly) ExteriaRemoteFile *file;
@property (nonatomic, readonly) ExteriaRemoteFile *previewFile;
/* the largest size of a photo, for the viewer; its bubble keeps the smaller file */
@property (nonatomic, readonly) ExteriaRemoteFile *fullPhotoFile;
@property (nonatomic, readonly) long long fullPhotoSize;
/* what it takes to send this sticker again */
@property (nonatomic, readonly) exteria_media_ref ref;

@end

/* turns bounded core entities into text runs, dropping ranges outside the displayed UTF-16 text */
NSArray *ExteriaTextEntities(NSString *text, const exteria_entity *entities, size_t count, const char *urls);

typedef enum {
    ExteriaTextStyleBold,
    ExteriaTextStyleItalic,
    ExteriaTextStyleUnderline,
    ExteriaTextStyleStrike,
    ExteriaTextStyleCode,
    ExteriaTextStyleLink,
    ExteriaTextStyleMention,
    ExteriaTextStyleHashtag,
    ExteriaTextStyleCustomEmoji,
    ExteriaTextStyleBotCommand,
    ExteriaTextStyleSpoiler,
    ExteriaTextStylePre,
    ExteriaTextStyleQuote,
    ExteriaTextStyleMentionName,
    ExteriaTextStyleDate
} ExteriaTextStyle;

/* a styled run of a message text; the range counts UTF-16 units */
@interface ExteriaTextEntity : NSObject {
    ExteriaTextStyle _style;
    NSRange _range;
    NSString *_url;
    long long _documentId;
    long long _userId;
    long long _accessHash;
    int32_t _date;
    uint8_t _flags;
}
@property (nonatomic, readonly) ExteriaTextStyle style;
@property (nonatomic, readonly) NSRange range;
/* the address a link opens, nil when the text is the address or there is none */
@property (nonatomic, readonly, copy) NSString *url;
/* the document that draws a custom emoji, zero for every other style */
@property (nonatomic, assign) long long documentId;
/* a mention name: the user it opens, and the hash the server wants to accept it in a sent message */
@property (nonatomic, assign) long long userId;
@property (nonatomic, assign) long long accessHash;
/* a date: the moment, and the EXTERIA_DATE_ shape bits; a quote: EXTERIA_ENTITY_COLLAPSED in flags */
@property (nonatomic, assign) int32_t date;
@property (nonatomic, assign) uint8_t flags;
/* the language of a block of code, the address of a link and nothing else is kept in url */
- (id)initWithStyle:(ExteriaTextStyle)style range:(NSRange)range url:(NSString *)url;
@end

typedef enum {
    ExteriaMessageStateSent,
    ExteriaMessageStateSending,
    ExteriaMessageStateFailed
} ExteriaMessageState;

typedef enum {
    ExteriaOutgoingVoice,
    ExteriaOutgoingRound,
    ExteriaOutgoingPhoto,
    ExteriaOutgoingVideo,
    ExteriaOutgoingFile,
    ExteriaOutgoingLocation,
    ExteriaOutgoingContact
} ExteriaOutgoingKind;

/* everything a send of a file or a point needs, kept with the pending message so a failed send can be tried again */
@interface ExteriaOutgoing : NSObject {
@public
    ExteriaOutgoingKind kind;
    int32_t replyTo;
    NSString *path;
    NSString *name;
    NSString *mime;
    NSString *phone;
    NSData *waveform;
    /* the text sent with a photo, a video or a file */
    NSString *caption;
    /* a photo or a video shown blurred until it is tapped */
    BOOL spoiler;
    int32_t durationMs;
    int32_t width;
    int32_t height;
    double latitude;
    double longitude;
    exteria_geo_point location;
    /* a copy made for the send, deleted once the server has it; a file the person chose is never deleted */
    BOOL temporary;
    /* a small picture of a photo or the first frame of a video, which the bubble shows while the file goes up and the server has none yet */
    UIImage *preview;
}
@end

@interface ExteriaReaction : NSObject {
    exteria_reaction _row;
    NSArray *_faces;
}
+ (ExteriaReaction *)reactionWithRow:(const exteria_reaction *)row;
/* the emoji that stand for custom emoji, by document id (NSNumber to NSString); a chip shows a placeholder until its id is here */
+ (void)rememberCustomTexts:(NSDictionary *)texts;
+ (BOOL)knowsCustomDocument:(long long)documentId;
@property (nonatomic, readonly) exteria_reaction row;
@property (nonatomic, readonly) NSString *emoji;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) NSString *displayText;
/* the entity that has a custom reaction drawn as its own picture over the emoji in displayText; nil for the other kinds and while the
   emoji it stands for is not known */
@property (nonatomic, readonly) NSArray *displayEntities;
@property (nonatomic, readonly) BOOL chosen;
@property (nonatomic, readonly) int32_t count;
/* the users the server's recent list names for this reaction, as NSNumbers, in list order */
@property (nonatomic, readonly) NSArray *reactorIds;
/* the people whose pictures stand on the chip in the place of the number (ExteriaPerson items), set by the screen that knows who they
   are; nil keeps the number */
@property (nonatomic, retain) NSArray *faces;
/* what the faces are, as a string, so two chips with the same faces compare equal */
@property (nonatomic, readonly) NSString *faceKey;
@end

@interface ExteriaMessage : NSObject {
    int32_t _messageId;
    int32_t _date;
    int32_t _replyTo;
    int32_t _replyPeerKind;
    long long _replyPeerId;
    NSString *_replyQuote;
    int32_t _topicId;
    long long _fromId;
    long long _fromChannel;
    long long _targetId;
    int32_t _views;
    BOOL _hasComments;
    int32_t _comments;
    long long _discussionId;
    NSArray *_commenters;
    long long _randomId;
    BOOL _outgoing;
    BOOL _spoilersRevealed;
    BOOL _post;
    BOOL _forwarded;
    BOOL _edited;
    BOOL _deletedLocally;
    int _service;
    int32_t _serviceValue;
    ExteriaMessageState _state;
    NSString *_text;
    NSString *_forwardName;
    int32_t _forwardDate;
    long long _groupedId;
    long long _forwardKey;
    BOOL _savedOut;
    int32_t _savedPeerKind;
    long long _savedPeerId;
    int _callOutcome;
    BOOL _callVideo;
    NSString *_senderRank;
    NSArray *_entities;
    ExteriaMedia *_media;
    NSString *_giftTitle;
    long long _giftStars;
    int32_t _giftNumber;
    NSArray *_reactions;
    long long _viaBotId;
    int32_t _sendReplyTo;
    ExteriaMarkup *_markup;
    BOOL _reactionsPossible;
    BOOL _hasReactions;
    ExteriaOutgoing *_pendingSend;
    ExteriaPoll *_poll;
}

/* nil for a message the screen cannot show */
+ (ExteriaMessage *)messageWithRow:(const exteria_message_row *)row;
/* a message that only exists here until the server answers: the id is zero and the random id matches the answer */
/* a message that only exists here until its file or point is on the server; the file stays until then */
+ (ExteriaMessage *)pendingOutgoing:(ExteriaOutgoing *)outgoing randomId:(long long)randomId date:(int32_t)date;
/* what has to be sent for a pending message, nil for text and stickers */
@property (nonatomic, readonly, retain) ExteriaOutgoing *pendingSend;
+ (ExteriaMessage *)pendingText:(NSString *)text randomId:(long long)randomId date:(int32_t)date;
/* with the custom emoji entities the person typed, so the pending bubble draws them as the server's copy will */
+ (ExteriaMessage *)pendingText:(NSString *)text entities:(NSArray *)entities randomId:(long long)randomId date:(int32_t)date;
+ (ExteriaMessage *)pendingSticker:(ExteriaMedia *)sticker randomId:(long long)randomId date:(int32_t)date;

/* zero while sending */
@property (nonatomic, assign) int32_t messageId;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t replyTo;
@property (nonatomic, readonly) int32_t replyPeerKind;
@property (nonatomic, readonly) long long replyPeerId;
@property (nonatomic, readonly, copy) NSString *replyQuote;
/* the forum topic the message was written in; 1, General, for a message of a chat without topics too */
@property (nonatomic, readonly) int32_t topicId;
@property (nonatomic, readonly) long long fromId;
/* the channel a group message was written as, zero when a user wrote it */
@property (nonatomic, readonly) long long fromChannel;
/* a channel post's counters: how many saw it, zero when the server did not count */
@property (nonatomic, readonly) int32_t views;
/* the post has a comment thread; how many comments it has, the discussion group it lives in, and the user ids (NSNumber) of the
   newest commenters, at most three */
@property (nonatomic, readonly) BOOL hasComments;
@property (nonatomic, readonly) int32_t comments;
@property (nonatomic, readonly) long long discussionId;
@property (nonatomic, readonly, retain) NSArray *commenters;
/* names the sender in the people of a chat: the user id, or the channel id made negative so the two never meet; zero for none */
@property (nonatomic, readonly) long long senderKey;
@property (nonatomic, readonly) long long targetId;
@property (nonatomic, readonly) long long randomId;
@property (nonatomic, readonly) BOOL outgoing;
@property (nonatomic, readonly) BOOL post;
/* a message waiting to be sent into a broadcast channel looks like the post it will become: the channel writes it, not the account */
- (void)showAsChannelPost;
/* the person tapped the spoilers of this message open; kept here so a rebuilt layout does not cover them again */
@property (nonatomic, assign) BOOL spoilersRevealed;
@property (nonatomic, readonly) BOOL forwarded;
@property (nonatomic, readonly) BOOL edited;
/* the other side deleted it and the phone kept it, as AyuMoments asks; set by the session when it reads the kept ones */
@property (nonatomic, assign) BOOL deletedLocally;
/* an exteria_service_kind plus one, zero for an ordinary message */
@property (nonatomic, readonly) int service;
@property (nonatomic, assign) ExteriaMessageState state;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly, copy) NSString *forwardName;
/* when the original of a forwarded message was written, zero when the header does not say */
@property (nonatomic, readonly) int32_t forwardDate;
/* the album the message belongs to: the photos and videos that were sent together share this number; zero for a
   message of its own */
@property (nonatomic, assign) long long groupedId;
/* who wrote a forwarded message, when the header says: the user id, or the negative of the channel id, as the people of a chat are keyed; zero when hidden */
@property (nonatomic, readonly) long long forwardKey;
- (void)placeInSavedMessagesOfUser:(long long)userId;
/* the words the server accepted for an edit of this message, shown at once with the mark of an edited one, before the copy it sends back is read */
- (void)noteEditedToText:(NSString *)text;
/* in the favorites, the chat the message came from: kind 1 user, 2 group, 3 channel, zero when the answer did not say */
@property (nonatomic, readonly) int32_t savedPeerKind;
@property (nonatomic, readonly) long long savedPeerId;
/* a call service message: how it ended (an exteria_call_outcome), and whether it had video; the length in seconds is serviceValue */
@property (nonatomic, readonly) int callOutcome;
@property (nonatomic, readonly) BOOL callVideo;
/* the custom title of an admin of a group, empty when there is none */
@property (nonatomic, readonly, copy) NSString *senderRank;
/* the number some service messages carry: a period, a duration, a count */
@property (nonatomic, readonly) int32_t serviceValue;
@property (nonatomic, readonly, retain) NSArray *entities;
@property (nonatomic, readonly, copy) NSArray *reactions;
@property (nonatomic, readonly) BOOL reactionsPossible;
/* a pending text answers this message when it goes out, zero for none; only a message that has not been sent uses it */
@property (nonatomic, assign) int32_t sendReplyTo;
/* the bot whose inline result the message is, zero for any other */
@property (nonatomic, readonly) long long viaBotId;
/* the buttons under the message, or the keyboard it brought; nil without any */
@property (nonatomic, retain) ExteriaMarkup *markup;
/* the message carries a reply markup that has not been read yet */
@property (nonatomic, readonly) BOOL hasMarkup;
/* a string that differs when what the buttons show differs, empty without markup */
@property (nonatomic, readonly) NSString *markupKey;
@property (nonatomic, readonly) BOOL hasReactions;
@property (nonatomic, readonly) NSString *reactionKey;
@property (nonatomic, readonly, retain) ExteriaMedia *media;
/* the poll of a poll message, nil for any other and for a poll the reader could not use */
@property (nonatomic, retain) ExteriaPoll *poll;
/* a string that differs when what the poll shows differs, empty without a poll */
@property (nonatomic, readonly) NSString *pollKey;
/* a gift service message: its name (empty for an unnamed catalog gift), its price in stars and, for a unique gift, its number */
@property (nonatomic, readonly, copy) NSString *giftTitle;
@property (nonatomic, readonly) long long giftStars;
@property (nonatomic, readonly) int32_t giftNumber;

@end

@interface ExteriaSticker : NSObject {
    ExteriaMedia *_media;
}
+ (ExteriaSticker *)stickerWithRow:(const exteria_sticker_row *)row;
@property (nonatomic, readonly, retain) ExteriaMedia *media;
@end

@interface ExteriaStickerSet : NSObject {
    exteria_sticker_set_row _row;
    NSString *_title;
}
+ (ExteriaStickerSet *)setWithRow:(const exteria_sticker_set_row *)row;
@property (nonatomic, readonly) exteria_sticker_set_row row;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) long long setId;
@property (nonatomic, readonly) ExteriaRemoteFile *coverFile;
@end
