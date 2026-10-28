#import "exteria_passcode_store.h"

#include "exteria_random.h"

static NSString *const ExteriaPasscodeHashKey = @"exteria.passcode.hash";
static NSString *const ExteriaPasscodeSaltKey = @"exteria.passcode.salt";
static NSString *const ExteriaPasscodeTypeKey = @"exteria.passcode.type";
static NSString *const ExteriaPasscodeAutoLockKey = @"exteria.passcode.autolock";
static NSString *const ExteriaPasscodeBiometricKey = @"exteria.passcode.biometric";
static NSString *const ExteriaPasscodeFailuresKey = @"exteria.passcode.failures";
static NSString *const ExteriaPasscodeUntilKey = @"exteria.passcode.until";

/* the default: an hour away */
#define AUTO_LOCK_DEFAULT 3600
#define WAIT_MAX_SECONDS 300

static NSData *ExteriaPasscodeSalt(void) {
    NSData *salt = [[NSUserDefaults standardUserDefaults] dataForKey:ExteriaPasscodeSaltKey];
    return salt.length == EXTERIA_PASSCODE_SALT_LEN ? salt : nil;
}

BOOL ExteriaPasscodeEnabled(void) {
    NSString *hash = [[NSUserDefaults standardUserDefaults] stringForKey:ExteriaPasscodeHashKey];
    return hash.length == EXTERIA_PASSCODE_HEX_LEN && ExteriaPasscodeSalt() != nil;
}

exteria_passcode_type ExteriaPasscodeType(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:ExteriaPasscodeTypeKey] == EXTERIA_PASSCODE_PASSWORD ? EXTERIA_PASSCODE_PASSWORD : EXTERIA_PASSCODE_PIN;
}

BOOL ExteriaPasscodeSet(exteria_passcode_type type, NSString *code) {
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes || !exteria_passcode_valid(type, bytes.bytes, bytes.length)) return NO;
    uint8_t salt[EXTERIA_PASSCODE_SALT_LEN];
    char hex[EXTERIA_PASSCODE_HEX_LEN + 1];
    if (exteria_random(salt, sizeof(salt)) != EXTERIA_OK || exteria_passcode_hash(salt, bytes.bytes, bytes.length, hex) != EXTERIA_OK) {
        NSLog(@"exteria: the passcode could not be hashed");
        return NO;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[NSString stringWithUTF8String:hex] forKey:ExteriaPasscodeHashKey];
    [defaults setObject:[NSData dataWithBytes:salt length:sizeof(salt)] forKey:ExteriaPasscodeSaltKey];
    [defaults setInteger:type forKey:ExteriaPasscodeTypeKey];
    [defaults removeObjectForKey:ExteriaPasscodeFailuresKey];
    [defaults removeObjectForKey:ExteriaPasscodeUntilKey];
    if (![defaults synchronize]) NSLog(@"exteria: the passcode was not saved");
    return YES;
}

void ExteriaPasscodeClear(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:ExteriaPasscodeHashKey];
    [defaults removeObjectForKey:ExteriaPasscodeSaltKey];
    [defaults removeObjectForKey:ExteriaPasscodeTypeKey];
    [defaults removeObjectForKey:ExteriaPasscodeBiometricKey];
    [defaults removeObjectForKey:ExteriaPasscodeFailuresKey];
    [defaults removeObjectForKey:ExteriaPasscodeUntilKey];
    if (![defaults synchronize]) NSLog(@"exteria: the removal of the passcode was not saved");
}

NSUInteger ExteriaPasscodeWaitRemaining(void) {
    double until = [[NSUserDefaults standardUserDefaults] doubleForKey:ExteriaPasscodeUntilKey];
    double left = until - [[NSDate date] timeIntervalSince1970];
    /* a clock set back must not stretch the wait past its longest step */
    if (left <= 0) return 0;
    return (NSUInteger)MIN(ceil(left), (double)WAIT_MAX_SECONDS);
}

ExteriaPasscodeResult ExteriaPasscodeCheck(NSString *code, NSUInteger *waitSeconds) {
    if (waitSeconds) *waitSeconds = 0;
    NSUInteger remaining = ExteriaPasscodeWaitRemaining();
    if (remaining > 0) {
        if (waitSeconds) *waitSeconds = remaining;
        return ExteriaPasscodeResultWait;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *salt = ExteriaPasscodeSalt();
    NSData *bytes = [code dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hash = [defaults stringForKey:ExteriaPasscodeHashKey];
    if (salt && bytes && hash && exteria_passcode_matches(salt.bytes, bytes.bytes, bytes.length, hash.UTF8String)) {
        [defaults removeObjectForKey:ExteriaPasscodeFailuresKey];
        [defaults removeObjectForKey:ExteriaPasscodeUntilKey];
        return ExteriaPasscodeResultOK;
    }
    NSInteger failures = [defaults integerForKey:ExteriaPasscodeFailuresKey] + 1;
    uint32_t wait = exteria_passcode_wait_seconds((uint32_t)MIN(failures, (NSInteger)INT32_MAX));
    [defaults setInteger:failures forKey:ExteriaPasscodeFailuresKey];
    if (wait > 0) [defaults setDouble:[[NSDate date] timeIntervalSince1970] + wait forKey:ExteriaPasscodeUntilKey];
    /* the count must survive a kill of the app, or restarting it would give four more tries each time */
    if (![defaults synchronize]) NSLog(@"exteria: the count of wrong passcodes was not saved");
    if (waitSeconds) *waitSeconds = wait;
    return ExteriaPasscodeResultWrong;
}

uint32_t ExteriaPasscodeAutoLock(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:ExteriaPasscodeAutoLockKey];
    return stored ? (uint32_t)MAX(0, [stored integerValue]) : AUTO_LOCK_DEFAULT;
}

void ExteriaPasscodeSetAutoLock(uint32_t seconds) {
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)seconds forKey:ExteriaPasscodeAutoLockKey];
}

BOOL ExteriaPasscodeBiometricEnabled(void) {
    return ExteriaPasscodeEnabled() && [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaPasscodeBiometricKey];
}

void ExteriaPasscodeSetBiometric(BOOL on) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:on forKey:ExteriaPasscodeBiometricKey];
    if (![defaults synchronize]) NSLog(@"exteria: the biometric choice was not saved");
}
