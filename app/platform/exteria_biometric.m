#import "exteria_biometric.h"

#import <dlfcn.h>
#import <objc/message.h>

#define LA_POLICY_BIOMETRICS 1
/* LABiometryType: 1 is touch id and 2 is face id; ios 8 to 10 have no biometryType and only touch id */
#define LA_BIOMETRY_TOUCH 1
#define LA_BIOMETRY_FACE 2
/* LAError codes that mean the person or the system closed the question, which is not worth a log line */
#define LA_ERROR_USER_CANCEL (-2)
#define LA_ERROR_SYSTEM_CANCEL (-4)
#define LA_ERROR_APP_CANCEL (-9)

@interface ExteriaBiometricToken : NSObject {
@public
    id context;
    BOOL cancelled;
}
@end

@implementation ExteriaBiometricToken

- (void)dealloc {
    [context release];
    [super dealloc];
}

@end

static Class ExteriaContextClass(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/Frameworks/LocalAuthentication.framework/LocalAuthentication", RTLD_LAZY)) {
            NSLog(@"exteria: LocalAuthentication is not on this system");
        }
    });
    return NSClassFromString(@"LAContext");
}

/* a fresh context, since biometryType is only valid after the question of the same context; nil when the sensor cannot be used */
static id ExteriaMakeContext(ExteriaBiometricKind *kind) {
    if (kind) *kind = ExteriaBiometricNone;
    Class contextClass = ExteriaContextClass();
    SEL can = NSSelectorFromString(@"canEvaluatePolicy:error:");
    id context = [[[contextClass alloc] init] autorelease];
    if (!context || ![context respondsToSelector:can]) return nil;
    NSError *error = nil;
    if (!((BOOL (*)(id, SEL, NSInteger, NSError **))objc_msgSend)(context, can, LA_POLICY_BIOMETRICS, &error)) return nil;
    NSInteger type = LA_BIOMETRY_TOUCH;
    SEL typeSelector = NSSelectorFromString(@"biometryType");
    if ([context respondsToSelector:typeSelector]) type = ((NSInteger (*)(id, SEL))objc_msgSend)(context, typeSelector);
    if (type != LA_BIOMETRY_TOUCH && type != LA_BIOMETRY_FACE) return nil;
    if (kind) *kind = type == LA_BIOMETRY_FACE ? ExteriaBiometricFaceID : ExteriaBiometricTouchID;
    return context;
}

ExteriaBiometricKind ExteriaBiometricAvailable(void) {
    ExteriaBiometricKind kind = ExteriaBiometricNone;
    ExteriaMakeContext(&kind);
    return kind;
}

NSString *ExteriaBiometricName(ExteriaBiometricKind kind) {
    switch (kind) {
    case ExteriaBiometricTouchID: return NSLocalizedString(@"passcode.biometric.touch", nil);
    case ExteriaBiometricFaceID: return NSLocalizedString(@"passcode.biometric.face", nil);
    case ExteriaBiometricNone: break;
    }
    return nil;
}

id ExteriaBiometricEvaluate(NSString *reason, void (^done)(BOOL matched)) {
    id context = ExteriaMakeContext(NULL);
    SEL evaluate = NSSelectorFromString(@"evaluatePolicy:localizedReason:reply:");
    if (!context || ![context respondsToSelector:evaluate]) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(NO); });
        return nil;
    }
    /* an empty title removes the "enter password" button, which would only return to the pad this question stands over */
    SEL fallback = NSSelectorFromString(@"setLocalizedFallbackTitle:");
    if ([context respondsToSelector:fallback]) ((void (*)(id, SEL, NSString *))objc_msgSend)(context, fallback, @"");
    ExteriaBiometricToken *token = [[[ExteriaBiometricToken alloc] init] autorelease];
    token->context = [context retain];
    void (^reply)(BOOL, NSError *) = ^(BOOL matched, NSError *error) {
        if (!matched && error && error.code != LA_ERROR_USER_CANCEL && error.code != LA_ERROR_SYSTEM_CANCEL && error.code != LA_ERROR_APP_CANCEL) {
            NSLog(@"exteria: the biometric question failed: %@", error);
        }
        /* the reply comes on a queue of the framework */
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!token->cancelled) done(matched);
        });
    };
    ((void (*)(id, SEL, NSInteger, NSString *, void (^)(BOOL, NSError *)))objc_msgSend)(context, evaluate, LA_POLICY_BIOMETRICS, reason, reply);
    return token;
}

void ExteriaBiometricCancel(id token) {
    ExteriaBiometricToken *open = token;
    if (!open) return;
    open->cancelled = YES;
    /* invalidate arrived with ios 9; on ios 8 the sheet stays until answered and the flag drops its late reply */
    SEL invalidate = NSSelectorFromString(@"invalidate");
    if ([open->context respondsToSelector:invalidate]) ((void (*)(id, SEL))objc_msgSend)(open->context, invalidate);
}
