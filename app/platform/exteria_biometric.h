#import <Foundation/Foundation.h>

/* touch id and face id through LocalAuthentication, which the armv7 sdk may not carry and ios 5 to 7 do not have: the framework is
   opened by name when first asked, and the calls go by selector */

typedef enum {
    ExteriaBiometricNone,
    ExteriaBiometricTouchID,
    ExteriaBiometricFaceID
} ExteriaBiometricKind;

/* what the device can use right now: None without the framework, without the sensor, or with no finger or face enrolled */
ExteriaBiometricKind ExteriaBiometricAvailable(void);

/* the localized name of the sensor, nil for None */
NSString *ExteriaBiometricName(ExteriaBiometricKind kind);

/* asks the sensor; done runs once on the main thread with YES only when the person matched. The returned token cancels the
   question and is nil when the question could not start (done has run by then); it stays valid until the caller releases it */
id ExteriaBiometricEvaluate(NSString *reason, void (^done)(BOOL matched));

/* a question still open is dismissed and its done block never runs */
void ExteriaBiometricCancel(id token);
