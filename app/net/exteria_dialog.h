#import <Foundation/Foundation.h>

#include "exteria_dialogs.h"

@class ExteriaPhoto;
@class ExteriaRemoteFile;
@class ExteriaPerson;

/* one chat list row in the form the screens draw; built off the main thread, so it holds no UIKit object */
@interface ExteriaDialog : NSObject {
    int32_t _peerKind;
    long long _peerId;
    exteria_dialog_kind _kind;
    BOOL _contact;
    BOOL _saved;
    BOOL _verified;
    BOOL _premium;
    long long _emojiStatus;
    BOOL _pinned;
    BOOL _muted;
    BOOL _canPost;
    BOOL _noForwards;
    BOOL _outgoing;
    BOOL _forwarded;
    BOOL _read;
    BOOL _unreadMark;
    BOOL _folder;
    BOOL _forum;
    BOOL _community;
    BOOL _communityCollapsed;
    BOOL _left;
    int32_t _topicId;
    BOOL _discussion;
    long long _discussionChannel;
    long long _discussionChannelHash;
    int32_t _discussionPost;
    BOOL _discussionViaChannel;
    NSArray *_discussionMessages;
    NSDictionary *_discussionPeople;
    long long _topicIconEmoji;
    int32_t _topicIconColor;
    BOOL _topicClosed;
    int32_t _folderId;
    long long _peerHash;
    int32_t _date;
    int32_t _topMessage;
    int32_t _readInboxMaxId;
    int32_t _readOutboxMaxId;
    int32_t _seen;
    exteria_presence _presence;
    NSInteger _unreadCount;
    NSInteger _mentions;
    NSInteger _reactions;
    NSInteger _participantsCount;
    NSString *_title;
    BOOL _showsSender;
    long long _senderId;
    NSString *_senderInitials;
    ExteriaPhoto *_senderPhoto;
    NSString *_preview;
    ExteriaRemoteFile *_previewFile;
    NSString *_initials;
    ExteriaPhoto *_photo;
    ExteriaDialog *_savedSource;
    long long _linkedCommunityId;
    long long _linkedCommunityHash;
    NSString *_linkedCommunityTitle;
}
/* the preview names who wrote the last message: the person it was, with the initials and the photo for a small picture in front of the line */
@property (nonatomic, readonly) BOOL showsSender;
@property (nonatomic, readonly) long long senderId;
@property (nonatomic, readonly) BOOL noForwards;
@property (nonatomic, readonly, copy) NSString *senderInitials;
@property (nonatomic, readonly, retain) ExteriaPhoto *senderPhoto;
@property (nonatomic, readonly) int32_t peerKind;
@property (nonatomic, readonly) long long peerId;
@property (nonatomic, readonly) exteria_dialog_kind kind;
@property (nonatomic, readonly) BOOL saved;
@property (nonatomic, readonly) BOOL contact;
/* the archive entry of the list, not a chat; folderId says which folder it opens */
@property (nonatomic, readonly) BOOL folder;
@property (nonatomic, readonly) int32_t folderId;
/* a supergroup split into topics: opening it lists the topics, not the messages */
@property (nonatomic, readonly) BOOL forum;
/* a community, which the list shows as one entry that opens the chats it groups; collapsed is the person's choice to see it so */
@property (nonatomic, readonly) BOOL community;
@property (nonatomic, readonly) BOOL communityCollapsed;
/* the account is not a member of this group or channel */
@property (nonatomic, readonly) BOOL left;
/* a topic of a forum, which reads, sends and marks read inside that thread alone; zero for a whole chat */
@property (nonatomic, readonly) int32_t topicId;
@property (nonatomic, assign) BOOL discussion;
/* a discussion thread remembers the post it belongs to: the channel with the hash this account has for it, and the post's number there. the history of the thread
   is read from the group with the group's copy of the post and, when the server refuses that pair as MSG_ID_INVALID, from the channel with the post itself */
@property (nonatomic, assign) long long discussionChannel;
@property (nonatomic, assign) long long discussionChannelHash;
@property (nonatomic, assign) int32_t discussionPost;
/* the group's pair was refused, so every later page asks the channel at once */
@property (nonatomic, assign) BOOL discussionViaChannel;
@property (nonatomic, copy) NSArray *discussionMessages;
@property (nonatomic, copy) NSDictionary *discussionPeople;
/* the custom emoji document that is the icon of the topic, zero for the plain hash drawn in topicIconColor (0xRRGGBB) */
@property (nonatomic, readonly) long long topicIconEmoji;
@property (nonatomic, readonly) int32_t topicIconColor;
@property (nonatomic, readonly) BOOL topicClosed;
/* the access hash an input peer for this chat needs, zero when it needs none or none is known */
@property (nonatomic, readonly) long long peerHash;
@property (nonatomic, readonly) BOOL verified;
/* the user of a private chat has Telegram Premium, and the custom emoji they show after their name (zero for none) */
@property (nonatomic, readonly) BOOL premium;
@property (nonatomic, readonly) long long emojiStatus;
@property (nonatomic, readonly) BOOL pinned;
@property (nonatomic, readonly) BOOL muted;
/* a broadcast channel this account may post in; a chat of any other kind is open to writing on its own terms */
@property (nonatomic, readonly) BOOL canPost;
@property (nonatomic, readonly) BOOL outgoing;
/* the last message is a forward, and the list puts an arrow before its preview */
@property (nonatomic, readonly) BOOL forwarded;
/* the last message is ours and was read */
@property (nonatomic, readonly) BOOL read;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly) int32_t topMessage;
/* everything of theirs up to this message id we have read, and everything of ours they have read */
@property (nonatomic, readonly) int32_t readInboxMaxId;
@property (nonatomic, readonly) int32_t readOutboxMaxId;
/* when the other side of a user chat was last on line, unknown for the rest */
@property (nonatomic, readonly) exteria_presence presence;
/* the account is gone: the avatar is the ghost and the status reads "a very long time ago" */
@property (nonatomic, readonly) BOOL deleted;
@property (nonatomic, readonly) int32_t seen;
@property (nonatomic, readonly) NSInteger unreadCount;
@property (nonatomic, readonly) NSInteger mentions;
/* messages of the person that got a reaction they have not seen yet */
@property (nonatomic, readonly) NSInteger reactions;
@property (nonatomic, readonly) NSInteger participantsCount;
@property (nonatomic, readonly, copy) NSString *title;
/* the last message ready to show, with a "You:" or sender prefix where that helps */
@property (nonatomic, readonly, copy) NSString *preview;
/* the small picture of a photo or video last message, shown before the preview text; nil for any other last message */
@property (nonatomic, readonly, retain) ExteriaRemoteFile *previewFile;
@property (nonatomic, readonly, copy) NSString *initials;
/* nil when the chat has no photo to fetch */
@property (nonatomic, readonly, retain) ExteriaPhoto *photo;
/* a stable number per chat, to pick the avatar colors */
@property (nonatomic, readonly) NSUInteger avatarSeed;
/* a chat counts as unread through its message count or the manual mark */
@property (nonatomic, readonly) BOOL unread;

- (id)initWithRow:(const exteria_dialog_row *)row;
/* the chat with a contact, for a person who has no chat in the list yet; nil when no access hash is known */
+ (ExteriaDialog *)dialogWithPerson:(ExteriaPerson *)person;
/* the chat with oneself, which the server reaches as the chat with the signed in user */
+ (ExteriaDialog *)savedMessagesWithPerson:(ExteriaPerson *)person;
/* the favorites of the account with that user id, for a place to send to when only the id is known */
+ (ExteriaDialog *)savedMessagesOfUserId:(long long)userId;
/* the favorites narrowed to what came from one chat, as exteraGram opens a row of its saved chats */
- (ExteriaDialog *)savedDialogFromSource:(ExteriaDialog *)source;
/* the community this chat or bot was added to, as the dialog of that community, which the community screen opens; nil when it has none or the answer did not
   carry the hash that opening it needs */
- (ExteriaDialog *)linkedCommunity;
@property (nonatomic, readonly) long long linkedCommunityId;
/* the chat the favorites are narrowed to, nil for the whole favorites */
@property (nonatomic, readonly, retain) ExteriaDialog *savedSource;

@end

/* replaces only the archive shortcut, keeping the current order and every chat model */
NSArray *ExteriaDialogsReplacingArchive(NSArray *dialogs, ExteriaDialog *summary);
