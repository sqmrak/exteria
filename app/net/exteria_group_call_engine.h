#import <Foundation/Foundation.h>

#import "exteria_dialog.h"
#import "exteria_group_call_state.h"

#include "exteria_tl.h"

@class ExteriaSession;

/* the one group call (voice chat) a session can be in: the signaling over the session's link and the media of exteria_tgc_group. the methods without a note
   may be called from any thread */
@interface ExteriaGroupCallEngine : NSObject

- (id)initWithSession:(ExteriaSession *)session;

/* what the chat shows about its voice chat: nil with an error name when none runs; the completion runs on the main thread */
- (void)loadVoiceChatOfDialog:(ExteriaDialog *)dialog completion:(void (^)(ExteriaVoiceChat *chat, NSString *errorName))completion;
/* joins the voice chat of a group or channel; inviteHash is the one of a link, or nil. a call already running is left alone and its screen shown again */
- (void)joinVoiceChatOfDialog:(ExteriaDialog *)dialog inviteHash:(NSString *)inviteHash;
/* makes a voice chat in a group or channel and joins it */
- (void)startVoiceChatInDialog:(ExteriaDialog *)dialog title:(NSString *)title;
/* leaves the call; the account that made it can also end it for everybody */
- (void)leave;
- (void)endForEveryone;
/* the microphone: on asks the server to let this account speak, off mutes it */
- (void)setMuted:(BOOL)muted;
/* an admin mutes or unmutes another member */
- (void)setMember:(ExteriaGroupMember *)member muted:(BOOL)muted;
/* how loud another member is heard here, 1 to EXTERIA_GROUP_VOLUME_MAX with EXTERIA_GROUP_VOLUME_DEFAULT for the normal level; the server keeps it for the account */
- (void)setMember:(ExteriaGroupMember *)member volume:(int)volume;
/* the invite link of the call, for the share sheet; the completion runs on the main thread */
- (void)loadInviteLink:(void (^)(NSString *link, NSString *errorName))completion;
/* main thread: the last snapshot, nil when no call runs */
- (ExteriaGroupCall *)current;

/* worker only: an updateGroupCall, updateGroupCallParticipants or updateGroupCallConnection the link delivered, with the container it came in */
- (void)handleUpdate:(const exteria_tl_value *)update container:(const exteria_tl_value *)container;
/* worker only: the session is going down, so the call goes with it */
- (void)shutdown;

@end
