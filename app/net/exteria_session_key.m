#import "exteria_session_key.h"

#import <Security/Security.h>
#include <string.h>
#include <unistd.h>
#include "exteria_bytes.h"
#include "exteria_files.h"
#include "exteria_random.h"

static NSString *const ExteriaSessionKeyService = @"com.sqmrak.exteria.session";

static uint8_t g_key[EXTERIA_SESSION_KEY_LEN];
static BOOL g_key_ready;

static NSDictionary *ExteriaSessionKeyQuery(void) {
    return [NSDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass,
            ExteriaSessionKeyService, (id)kSecAttrService, @"device", (id)kSecAttrAccount, nil];
}

/* kept beside the proxy record, outside the account directories */
static NSString *ExteriaSessionKeyFilePath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"session-key"];
}

/* a jailbroken install without the keychain entitlement answers -34018, and none of the other refusals gets better by asking
   again, so the private file holds the key then. a device locked since boot is the one answer that passes by itself: the
   key may sit in the keychain already, and a second one made in the file would seal the sessions with a key that is lost
   at the next unlock */
static BOOL ExteriaSessionKeychainLocked(OSStatus result) {
    return result == errSecInteractionNotAllowed;
}

static exteria_status ExteriaSessionKeyFromFile(uint8_t key[EXTERIA_SESSION_KEY_LEN]) {
    size_t len;
    uint8_t buf[EXTERIA_SESSION_KEY_LEN + 1];
    exteria_status status = ExteriaReadFile(ExteriaSessionKeyFilePath(), buf, sizeof(buf), &len);
    if (status == EXTERIA_OK && len != EXTERIA_SESSION_KEY_LEN) {
        /* a short key was cut by a crash that the rename should have prevented, and the files sealed by it cannot be read anyway */
        NSLog(@"exteria: the session key file has %zu bytes, expected %d", len, EXTERIA_SESSION_KEY_LEN);
        status = EXTERIA_E_MALFORMED;
    }
    if (status == EXTERIA_OK) memcpy(key, buf, EXTERIA_SESSION_KEY_LEN);
    exteria_wipe(buf, sizeof(buf));
    return status;
}

static exteria_status ExteriaSessionKeyToFile(const uint8_t key[EXTERIA_SESSION_KEY_LEN]) {
    NSString *path = ExteriaSessionKeyFilePath();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: the session key directory could not be created: %@", error);
        return EXTERIA_E_STORAGE;
    }
    return ExteriaWriteFile(path, key, EXTERIA_SESSION_KEY_LEN);
}

/* the cache is filled only from a key that is stored, so a failed write never leaves sessions sealed with a key that exists in memory alone */
static exteria_status ExteriaSessionKeyLoad(void) {
    uint8_t key[EXTERIA_SESSION_KEY_LEN];
    BOOL keychainRefused = NO;
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:ExteriaSessionKeyQuery()];
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    CFTypeRef value = NULL;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef)query, &value);
    if (result == errSecSuccess) {
        NSData *data = [(NSData *)value autorelease];
        if (data.length != EXTERIA_SESSION_KEY_LEN) {
            NSLog(@"exteria: the keychain session key has %lu bytes, expected %d", (unsigned long)data.length, EXTERIA_SESSION_KEY_LEN);
            return EXTERIA_E_MALFORMED;
        }
        memcpy(g_key, data.bytes, EXTERIA_SESSION_KEY_LEN);
        g_key_ready = YES;
        return EXTERIA_OK;
    }
    if (ExteriaSessionKeychainLocked(result)) return EXTERIA_E_STORAGE;
    if (result != errSecItemNotFound) {
        NSLog(@"exteria: session key keychain read failed: %d", (int)result);
        keychainRefused = YES;
    }

    exteria_status status = ExteriaSessionKeyFromFile(key);
    if (status == EXTERIA_E_NOTFOUND) {
        status = exteria_random(key, sizeof(key));
        if (status != EXTERIA_OK) return status;
        if (!keychainRefused) {
            NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:ExteriaSessionKeyQuery()];
            [item setObject:[NSData dataWithBytes:key length:sizeof(key)] forKey:(id)kSecValueData];
            [item setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
            result = SecItemAdd((CFDictionaryRef)item, NULL);
            if (result == errSecSuccess) {
                memcpy(g_key, key, sizeof(key));
                g_key_ready = YES;
                exteria_wipe(key, sizeof(key));
                return EXTERIA_OK;
            }
            NSLog(@"exteria: session key keychain write failed: %d", (int)result);
            if (ExteriaSessionKeychainLocked(result)) {
                exteria_wipe(key, sizeof(key));
                return EXTERIA_E_STORAGE;
            }
        }
        status = ExteriaSessionKeyToFile(key);
    }
    if (status == EXTERIA_OK) {
        memcpy(g_key, key, sizeof(key));
        g_key_ready = YES;
    }
    exteria_wipe(key, sizeof(key));
    return status;
}

static exteria_status ExteriaSessionKey(uint8_t out[EXTERIA_SESSION_KEY_LEN]) {
    exteria_status status = EXTERIA_OK;
    @synchronized (ExteriaSessionKeyService) {
        if (!g_key_ready) status = ExteriaSessionKeyLoad();
        if (status == EXTERIA_OK) memcpy(out, g_key, EXTERIA_SESSION_KEY_LEN);
    }
    return status;
}

exteria_status ExteriaSessionStore(NSString *directory, int32_t dc, const exteria_mt_session_state *state) {
    uint8_t key[EXTERIA_SESSION_KEY_LEN];
    uint8_t buf[EXTERIA_SESSION_SEALED_LEN];
    size_t len = 0;
    exteria_status status = ExteriaSessionKey(key);
    if (status == EXTERIA_OK) status = exteria_session_seal(key, dc, state, buf, sizeof(buf), &len);
    if (status == EXTERIA_OK) status = ExteriaWriteFile(ExteriaSessionPath(directory, dc), buf, len);
    exteria_wipe(key, sizeof(key));
    exteria_wipe(buf, sizeof(buf));
    return status;
}

exteria_status ExteriaSessionLoad(NSString *directory, int32_t dc, exteria_mt_session_state *out) {
    uint8_t key[EXTERIA_SESSION_KEY_LEN];
    uint8_t buf[EXTERIA_SESSION_SEALED_LEN + 1];
    size_t len;
    int plain = 0;
    NSString *path = ExteriaSessionPath(directory, dc);
    exteria_status status = ExteriaReadFile(path, buf, sizeof(buf), &len);
    if (status != EXTERIA_OK) return status;
    status = ExteriaSessionKey(key);
    if (status != EXTERIA_OK) {
        exteria_wipe(buf, sizeof(buf));
        return status;
    }
    status = exteria_session_open(key, buf, len, dc, out, &plain);
    exteria_wipe(key, sizeof(key));
    exteria_wipe(buf, sizeof(buf));
    if (status != EXTERIA_OK) {
        /* a damaged key cannot be repaired, a new handshake replaces it */
        NSLog(@"exteria: session file for dc %d is unusable (%s), starting a new session", (int)dc, exteria_status_name(status));
        unlink(path.fileSystemRepresentation);
        return EXTERIA_E_NOTFOUND;
    }
    if (plain) {
        /* the plain file stays readable until the sealed one is in place, a failed write loses nothing */
        exteria_status sealed = ExteriaSessionStore(directory, dc, out);
        if (sealed != EXTERIA_OK) NSLog(@"exteria: session file for dc %d was not sealed: %s", (int)dc, exteria_status_name(sealed));
    }
    return EXTERIA_OK;
}
