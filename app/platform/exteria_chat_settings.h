#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include "exteria_tab_order.h"

/* the chat settings of the signed in person, from the Chat Settings screen (ThemeActivity) */
extern NSString *const ExteriaChatSettingsDidChangeNotification;
/* TRACE: temporary */
void ExteriaChatTrace(NSString *line);

/* the message text size in points, 12 to 30; the default is 16 (18 on an iPad) */
#define EXTERIA_CHAT_TEXT_SIZE_MIN 12
#define EXTERIA_CHAT_TEXT_SIZE_MAX 30
NSInteger ExteriaChatTextSize(void);
void ExteriaChatSetTextSize(NSInteger size);
NSInteger ExteriaChatDefaultTextSize(void);

/* the corner radius of a message bubble, 0 to 17; the default is 17 */
#define EXTERIA_CHAT_BUBBLE_RADIUS_MIN 0
#define EXTERIA_CHAT_BUBBLE_RADIUS_MAX 17
NSInteger ExteriaChatBubbleRadius(void);
void ExteriaChatSetBubbleRadius(NSInteger radius);
/* the same setting for the classic bubble, whose corners are 15 points where the modern ones are 17; the slider
   scaled to the classic range, so the default of both is the shape each style had before the setting existed */
NSInteger ExteriaChatClassicBubbleRadius(void);

typedef enum {
    /* a row of the chat list is the name and one line of the last message */
    ExteriaChatListTwoLines = 0,
    /* a row gives the last message a second line when it needs it */
    ExteriaChatListThreeLines
} ExteriaChatListStyle;
/* the default is the three line row, which is what the list drew before the setting existed */
ExteriaChatListStyle ExteriaChatListStyleStored(void);
void ExteriaChatSetListStyle(ExteriaChatListStyle style);

/* enter sends the message instead of starting a new line; the default is off */
BOOL ExteriaChatSendByEnter(void);
void ExteriaChatSetSendByEnter(BOOL on);

/* the media and sound switches of the screen, with the defaults (SharedConfig) except where the app already
   behaved one way */
/* a tap near the left or right edge of the media viewer moves to the previous or next picture instead of hiding the bars; default on */
BOOL ExteriaChatNextMediaTap(void);
void ExteriaChatSetNextMediaTap(BOOL on);
/* a voice message plays from the earpiece while the phone is held to the ear; default on */
BOOL ExteriaChatRaiseToListen(void);
void ExteriaChatSetRaiseToListen(BOOL on);
/* holding the phone to the ear in a chat records a voice message, and lowering it sends it; default off */
BOOL ExteriaChatRaiseToSpeak(void);
void ExteriaChatSetRaiseToSpeak(BOOL on);
/* a song that plays is paused while a video message is recorded and goes on afterwards; default on */
BOOL ExteriaChatPauseMusicOnRecord(void);
void ExteriaChatSetPauseMusicOnRecord(BOOL on);
/* a song that plays is paused when a video or a video message starts; default on, which is what the app did before the switch existed */
BOOL ExteriaChatPauseMusicOnMedia(void);
void ExteriaChatSetPauseMusicOnMedia(BOOL on);
/* voice messages are recorded from a Bluetooth headset when one is connected; default off, the built-in microphone */
BOOL ExteriaChatRecordViaBluetooth(void);
void ExteriaChatSetRecordViaBluetooth(BOOL on);

/* a message that is one emoji is shown large; default on */
BOOL ExteriaChatLargeEmoji(void);
void ExteriaChatSetLargeEmoji(BOOL on);

/* the tabs of the bottom bar, four of them in either layout: the first is chats, contacts, settings and the profile; the second is contacts, calls, chats and settings */
typedef enum {
    ExteriaTabLayoutMessenger = 0,
    ExteriaTabLayoutCalls,
    ExteriaTabLayoutCount
} ExteriaTabLayout;
ExteriaTabLayout ExteriaTabLayoutStored(void);
void ExteriaTabLayoutStore(ExteriaTabLayout layout);
void ExteriaTabOrderLoad(int order[EXTERIA_TAB_SLOTS]);
BOOL ExteriaTabOrderStore(const int order[EXTERIA_TAB_SLOTS]);
BOOL ExteriaTabOrderIsCustom(void);
extern NSString *const ExteriaTabOrderDidChangeNotification;

/* what the title of the chat list says: the word Chats, the username, the name of the account, or a text of the person's own */
typedef enum {
    ExteriaChatListTitleDefault = 0,
    ExteriaChatListTitleUsername,
    ExteriaChatListTitleName,
    ExteriaChatListTitleCustom,
    ExteriaChatListTitleCount
} ExteriaChatListTitle;
ExteriaChatListTitle ExteriaChatListTitleStored(void);
void ExteriaChatListTitleStore(ExteriaChatListTitle mode);
NSString *ExteriaChatListCustomTitle(void);
/* the words a mode puts in the title: the username or name of person when it is known, the person's own text, and the word Chats otherwise */
@class ExteriaPerson;
NSString *ExteriaChatListTitleText(ExteriaChatListTitle mode, ExteriaPerson *person);
void ExteriaChatListSetCustomTitle(NSString *text);

/* how round the pictures of people and chats are, from 0 (a square) to 100 (a circle); the default is the rounded square the app began with */
#define EXTERIA_AVATAR_CORNER_DEFAULT 64
NSInteger ExteriaAvatarCornerPercent(void);
void ExteriaAvatarCornerStore(NSInteger percent);
/* the corner radius of a card of the settings, from 0 to 36 points */
#define EXTERIA_SECTION_RADIUS_DEFAULT 22
#define EXTERIA_SECTION_RADIUS_MAX 36
CGFloat ExteriaSectionRadius(void);
void ExteriaSectionRadiusStore(NSInteger points);

/* how many days the files of messages stay on the phone before the cache removes them; zero keeps them until the cache is full, which is the default */
NSInteger ExteriaCacheKeepDays(void);
void ExteriaCacheSetKeepDays(NSInteger days);

/* the set a sticker was sent from moves to the front of the panel; default on */
BOOL ExteriaChatDynamicPackOrder(void);
void ExteriaChatSetDynamicPackOrder(BOOL on);

/* what a swipe to the left on a chat of the list does; the default is the archive, which is what the swipe did before the setting existed */
typedef enum {
    ExteriaChatSwipeArchive = 0,
    ExteriaChatSwipePin,
    ExteriaChatSwipeRead,
    ExteriaChatSwipeMute,
    ExteriaChatSwipeDelete,
    /* the row has no swipe of its own, so a swipe to the left turns the bar of folders to the next one */
    ExteriaChatSwipeFolders
} ExteriaChatSwipe;
ExteriaChatSwipe ExteriaChatSwipeStored(void);
void ExteriaChatSetSwipe(ExteriaChatSwipe swipe);

/* back to the defaults of the size and the corners, the "Reset settings" of the menu of the screen */
void ExteriaChatResetAppearance(void);
/* whether the size and the corners differ from the defaults, which is when the reset is offered */
BOOL ExteriaChatAppearanceChanged(void);

/* the small switches of exteraGram that change one habit of the chat; each has the default of exteraGram, so a
   person who never opens the screen sees the chat as it was */
typedef enum {
    ExteriaChatFlagCommaAfterMention = 0,       /* a name picked at the start of the message is followed by a comma */
    ExteriaChatFlagRemoveTail,                  /* a classic bubble has no tail */
    ExteriaChatFlagEditedIcon,                  /* a pencil in the time line of an edited message instead of the word */
    ExteriaChatFlagPollResultsFirst,            /* the votes of a poll show before the account has voted, when the server counted them */
    ExteriaChatFlagForwardDate,                 /* the header of a forwarded message names the day the original was written */
    ExteriaChatFlagHideShare,
    ExteriaChatFlagHideSendAs,                  /* no picture of who the message is sent as beside the field */                   /* no round share button beside the posts of a channel */
    ExteriaChatFlagHideStickerTime,             /* no time pill over stickers */
    ExteriaChatFlagHideCameraTile,              /* no live camera tile in the attach sheet */
    ExteriaChatFlagAlwaysHD,                    /* photos go out in the largest size */
    ExteriaChatFlagPauseVoiceOnMinimize,        /* a voice message pauses when the app goes to the background */
    ExteriaChatFlagPauseRoundOnMinimize,        /* so does a video message */
    ExteriaChatFlagNoAutoNextVoice,             /* a voice message that ends does not start the next one */
    ExteriaChatFlagUnmuteWithVolume,            /* a volume button unmutes a muted video */
    ExteriaChatFlagSeconds,                     /* the clock under a message has seconds */
    ExteriaChatFlagFilterZalgo,                 /* combining marks piled on a letter are cut to a few */
    ExteriaChatFlagExactNumbers,                /* 1234 stays 1234 and does not become 1.2K */
    ExteriaChatFlagRelativeSeen,                /* "last seen 5 minutes ago" */
    ExteriaChatFlagShowIds,                     /* the id and data center in the profile */
    ExteriaChatFlagHidePhone,                   /* the number of the account is dots in the settings */
    ExteriaChatFlagHideReactionsPrivate,        /* no reactions in chats with a person or a bot */
    ExteriaChatFlagHideReactionsGroups,
    ExteriaChatFlagHideReactionsChannels,
    ExteriaChatFlagMenuCopyPhoto,               /* the entries the menu of a message may add */
    ExteriaChatFlagMenuHistory,
    ExteriaChatFlagMenuReport,
    ExteriaChatFlagMenuNoQuote,
    ExteriaChatFlagMenuSave,                    /* "save to favorites", "repeat", "details" and "bookmark" were always in the menu; as in exteraGram they are off until asked for */
    ExteriaChatFlagMenuRepeat,
    ExteriaChatFlagMenuDetails,
    ExteriaChatFlagMenuBookmark,
    ExteriaChatFlagMenuRemind,
    ExteriaChatFlagMenuReplyPrivate,
    ExteriaChatFlagAskCall,                     /* a question before a call starts */
    ExteriaChatFlagAskRepeat,                   /* and before "repeat" sends the message again */
    ExteriaChatFlagAskRecording,                /* and before a recorded voice or video message goes out */
    ExteriaChatFlagAskBotCommand,               /* and before a tapped bot command is sent */
    ExteriaChatFlagNoLinkPreview,               /* a message goes out without the preview of the first link in it */
    ExteriaChatFlagDeleteForMe,
    ExteriaChatFlagReplyColors,                 /* the quote of a reply takes the color of the name of its author; default on */
    ExteriaChatFlagReplyBackground,             /* the quote of a reply has a plate under it; default on */                 /* deleting a message in a private chat or a group leaves it with the others */
    ExteriaChatFlagGhostNoRead,                 /* AyuMoments, ghost mode: reading a chat does not tell the other side */
    ExteriaChatFlagGhostNoStories,              /* and a story that is looked at is not marked as seen */
    ExteriaChatFlagGhostOffline,                /* and the account says it is offline while the app runs */
    ExteriaChatFlagAyuRegex,                    /* messages that match a filter of the person are not shown */
    ExteriaChatFlagAyuSaveDeleted,              /* a message deleted for everyone stays on the phone, marked as deleted */
    ExteriaChatFlagAyuSaveEdits,                /* the text a message had before it was edited stays on the phone */
    ExteriaChatFlagAyuDeletedPrivate,           /* which chats the deleted messages are kept in */
    ExteriaChatFlagAyuDeletedGroups,
    ExteriaChatFlagAyuDeletedChannels,
    ExteriaChatFlagAyuDeletedBots,
    ExteriaChatFlagAyuTranslucent,              /* a deleted message is drawn faded */
    ExteriaChatFlagAyuReplyQuote,               /* a reply to a deleted message keeps the text of it as a quote */
    ExteriaChatFlagLocalPremium,                /* the client shows the Premium features that need no server (custom emoji and reactions, the full animations) */
    ExteriaChatFlagCrashReports,                /* a crash or a failed call is told to the developer in a private message */
    ExteriaChatFlagBoykisser,                   /* the waves in the corners of the screens give way to boykissers falling over them */
    ExteriaChatFlagSnow,                        /* snow falls over the chat list and the background of a chat */
    ExteriaChatFlagSenderAvatars,               /* a small picture of who wrote the last message stands before the preview of a group */
    ExteriaChatFlagHideSearchBar,               /* the chat list has no field of search over it */
    ExteriaChatFlagHideStories,                 /* the chat list has no strip of stories */
    ExteriaChatFlagHideAllChatsTab,             /* the folders of the chat list do not offer the tab of all chats */
    ExteriaChatFlagNoUnarchiveSwipe,            /* the swipe of a chat in the archive does nothing, so a chat does not leave it by a slip of the finger */
    ExteriaChatFlagHideVpnButton,               /* the chat list has no VPN button beside its menu */
    ExteriaChatFlagFoxes,                       /* foxes fall over the chat list and the background of a chat */
    ExteriaChatFlagHideWaves,                   /* the modern look draws no waves in the corners of the screens */
    ExteriaChatFlagShowMessageEmojiStatus,
    ExteriaChatFlagShowReplyCustomEmoji,
    ExteriaChatFlagCount
} ExteriaChatFlag;
/* the archive entry of the chat list is hidden on this device, and a pull on the list shows it; the server keeps no such state */
BOOL ExteriaArchiveHidden(void);
void ExteriaArchiveSetHidden(BOOL hidden);
/* the avatar corner and the card radius are kept in memory; a reset of the stored settings makes them read again */
void ExteriaChatSettingsForgetCached(void);
/* whether the account has Premium as far as the client is concerned: the server says so, or the person turned on the local Premium */
BOOL ExteriaPremiumEffective(BOOL serverPremium);
BOOL ExteriaChatFlagGet(ExteriaChatFlag flag);
void ExteriaChatFlagSet(ExteriaChatFlag flag, BOOL on);

/* whether tapping a link asks first: never, only for a link whose words are not its address, or always */
typedef enum {
    ExteriaLinkConfirmNever = 0,
    ExteriaLinkConfirmHidden,
    ExteriaLinkConfirmAlways
} ExteriaLinkConfirm;
ExteriaLinkConfirm ExteriaChatLinkConfirm(void);
void ExteriaChatSetLinkConfirm(ExteriaLinkConfirm mode);

/* what a double tap on a message does, once for the messages of others and once for ours; the default is nothing, which leaves a tap undelayed */
typedef enum {
    ExteriaDoubleTapNone = 0,
    ExteriaDoubleTapReaction,
    ExteriaDoubleTapReactionPicker,
    ExteriaDoubleTapTranslate,
    ExteriaDoubleTapReply,
    ExteriaDoubleTapForward,
    ExteriaDoubleTapSave,
    ExteriaDoubleTapRepeat,
    ExteriaDoubleTapEdit,
    ExteriaDoubleTapDelete,
    ExteriaDoubleTapCount
} ExteriaDoubleTapAction;
ExteriaDoubleTapAction ExteriaChatDoubleTap(BOOL outgoing);
void ExteriaChatSetDoubleTap(BOOL outgoing, ExteriaDoubleTapAction action);
/* the emoji a double tap reacts with, the red heart until the person picks another; if the chat does not offer it, the first reaction it offers is sent */
NSString *ExteriaChatQuickReaction(void);
void ExteriaChatSetQuickReaction(NSString *emoji);

/* the jump of a double tap on the left or right half of a video, in seconds: 5, 10, 15 or 30; the default is 10 */
NSInteger ExteriaChatSeekSeconds(void);
void ExteriaChatSetSeekSeconds(NSInteger seconds);

/* the size of stickers in percent of the usual one, 50 to 130, as the slider of exteraGram; the default is 100 */
#define EXTERIA_STICKER_SCALE_MIN 50
#define EXTERIA_STICKER_SCALE_MAX 130
NSInteger ExteriaChatStickerScale(void);
/* the outline of a sticker in a chat: as it is, with rounded corners, or on a plate shaped like a message bubble; the default is rounded */
typedef enum {
    ExteriaStickerShapeNone = 0,
    ExteriaStickerShapeRounded,
    ExteriaStickerShapeBubble
} ExteriaStickerShape;
ExteriaStickerShape ExteriaChatStickerShape(void);
void ExteriaChatSetStickerShape(ExteriaStickerShape shape);
void ExteriaChatSetStickerScale(NSInteger percent);
