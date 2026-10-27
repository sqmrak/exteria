#import <Foundation/Foundation.h>

#import "exteria_session.h"

#include "exteria_sessions.h"

/* one session of the account as the devices screen shows it */
@interface ExteriaDeviceSession : NSObject {
    exteria_session_info _info;
    NSString *_title;
    NSString *_appLine;
    NSString *_place;
}
- (id)initWithInfo:(const exteria_session_info *)info;
@property (nonatomic, readonly) long long sessionHash;
/* the session of this app, which is online as long as the screen is open */
@property (nonatomic, readonly) BOOL current;
@property (nonatomic, readonly) BOOL passwordPending;
@property (nonatomic, readonly) int32_t dateActive;
/* the app's id at Telegram; the desktop and web apps take no secret chats, and one app takes no calls */
@property (nonatomic, readonly) int32_t apiId;
@property (nonatomic, readonly) BOOL takesSecretChatsSetting;
@property (nonatomic, readonly) BOOL takesCallsSetting;
@property (nonatomic, readonly) exteria_session_kind kind;
/* the device model, or the platform and system when there is none: "Samsung Galaxy S25 Ultra", "iPhone 4S" */
@property (nonatomic, readonly, copy) NSString *title;
/* "Telegram Android 13.1.0" */
@property (nonatomic, readonly, copy) NSString *appLine;
/* "germany", or "Tallinn, Estonia" when the server names a region; empty when it names neither */
@property (nonatomic, readonly, copy) NSString *place;
@property (nonatomic, readonly, copy) NSString *ip;
@property (nonatomic, assign) BOOL secretChatsOn;
@property (nonatomic, assign) BOOL callsOn;
@end

/* the devices screen's calls; implemented in exteria_session_devices.m */
@interface ExteriaSession (Devices)

/* ExteriaDeviceSession items, the current one first, and the days an idle session lives */
- (void)loadDevices:(void (^)(NSArray *sessions, int32_t ttlDays, NSString *errorName))completion;
- (void)endDevice:(ExteriaDeviceSession *)device completion:(void (^)(NSString *errorName))completion;
/* every session but this one */
- (void)endOtherDevicesWithCompletion:(void (^)(NSString *errorName))completion;
/* secretChats and calls are -1 to leave as they are, 0 for off and 1 for on */
- (void)setDevice:(ExteriaDeviceSession *)device secretChats:(int)secretChats calls:(int)calls completion:(void (^)(NSString *errorName))completion;
- (void)setDevicesTTL:(int32_t)days completion:(void (^)(NSString *errorName))completion;
/* the tg://login?token= address a QR code of another device carries; the device is signed in once this succeeds */
- (void)acceptLoginLink:(NSString *)link completion:(void (^)(NSString *errorName))completion;

@end
