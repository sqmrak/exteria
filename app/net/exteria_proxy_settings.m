#import "exteria_proxy_settings.h"

#import <Security/Security.h>
#include "exteria_clock.h"
#include "exteria_bytes.h"

NSString *const ExteriaProxyDidChangeNotification = @"ExteriaProxyDidChange";
static NSString *const ExteriaProxyEnabledKey = @"exteria.proxy.enabled";
static NSString *const ExteriaProxyService = @"com.sqmrak.exteria.proxy";

static NSDictionary *ExteriaProxyQuery(void) {
    return [NSDictionary dictionaryWithObjectsAndKeys:(id)kSecClassGenericPassword, (id)kSecClass,
            ExteriaProxyService, (id)kSecAttrService, @"selected", (id)kSecAttrAccount, nil];
}

static exteria_status ExteriaProxyDecode(NSString *text, exteria_proxy *proxy) {
    if (![text isKindOfClass:[NSString class]] || !text.length || !proxy) return EXTERIA_E_ARG;
    exteria_tg_link link;
    exteria_status status = exteria_tg_link_parse(text.UTF8String, &link);
    if (status == EXTERIA_OK) status = exteria_proxy_from_link(&link, proxy);
    exteria_wipe(&link, sizeof(link));
    return status;
}

/* where the link lives when the keychain refuses it: the folder of the accounts, which already holds the keys of the session. an install signed without
   a keychain entitlement (a jailbreak ipa) gets an OSStatus error from every SecItem call, so the proxy could never be saved there */
static NSString *ExteriaProxyFilePath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"proxy-link"];
}

static exteria_status ExteriaProxyReadLocked(exteria_proxy *proxy) {
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:ExteriaProxyQuery()];
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    CFTypeRef value = NULL;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef)query, &value);
    NSData *data = nil;
    if (result == errSecSuccess) {
        data = [NSData dataWithData:(NSData *)value];
        CFRelease(value);
    } else {
        data = [NSData dataWithContentsOfFile:ExteriaProxyFilePath()];
    }
    if (!data) return result == errSecItemNotFound ? EXTERIA_E_NOTFOUND : EXTERIA_E_STORAGE;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return ExteriaProxyDecode(text, proxy);
}

/* the file holds the link only while the keychain will not; a link kept in the keychain removes it */
static BOOL ExteriaProxyWriteFile(NSData *data) {
    NSString *path = ExteriaProxyFilePath();
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0600] forKey:NSFilePosixPermissions];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"exteria: the proxy link could not be written: %@", error);
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:path error:NULL];
    return YES;
}

exteria_status ExteriaProxyRead(exteria_proxy *proxy, BOOL *enabled) {
    if (!proxy || !enabled) return EXTERIA_E_ARG;
    memset(proxy, 0, sizeof(*proxy));
    @synchronized (ExteriaProxyService) {
        *enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ExteriaProxyEnabledKey];
        return *enabled ? ExteriaProxyReadLocked(proxy) : EXTERIA_OK;
    }
}

exteria_status ExteriaProxyStoreLink(NSString *text) {
    exteria_proxy proxy;
    exteria_status status = ExteriaProxyDecode(text, &proxy);
    exteria_wipe(&proxy, sizeof(proxy));
    if (status != EXTERIA_OK) return status;
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return EXTERIA_E_ARG;
    @synchronized (ExteriaProxyService) {
        NSDictionary *query = ExteriaProxyQuery();
        NSDictionary *update = [NSDictionary dictionaryWithObject:data forKey:(id)kSecValueData];
        OSStatus result = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
        if (result == errSecItemNotFound) {
            NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:query];
            [item addEntriesFromDictionary:update];
            [item setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
            result = SecItemAdd((CFDictionaryRef)item, NULL);
        }
        if (result == errSecSuccess) {
            [[NSFileManager defaultManager] removeItemAtPath:ExteriaProxyFilePath() error:NULL];
        } else {
            NSLog(@"exteria: the keychain refused the proxy (OSStatus %d), it is kept in a file of the app", (int)result);
            if (!ExteriaProxyWriteFile(data)) return EXTERIA_E_STORAGE;
        }
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ExteriaProxyEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaProxyDidChangeNotification object:nil];
    return EXTERIA_OK;
}

exteria_status ExteriaProxySetEnabled(BOOL enabled) {
    @synchronized (ExteriaProxyService) {
        if (enabled) {
            exteria_proxy proxy;
            exteria_status status = ExteriaProxyReadLocked(&proxy);
            exteria_wipe(&proxy, sizeof(proxy));
            if (status != EXTERIA_OK) return status;
        }
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExteriaProxyEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaProxyDidChangeNotification object:nil];
    return EXTERIA_OK;
}

NSString *ExteriaProxyDisplay(void) {
    exteria_proxy proxy;
    BOOL enabled = NO;
    exteria_status status = ExteriaProxyRead(&proxy, &enabled);
    NSString *text = status == EXTERIA_OK && enabled ? [NSString stringWithFormat:@"%s:%u", proxy.server, (unsigned)proxy.port] : nil;
    exteria_wipe(&proxy, sizeof(proxy));
    return text;
}

exteria_status ExteriaProxyConnect(ExteriaShiro *shiro, exteria_mt_socket *socket, const char *host, uint16_t port,
                                   int timeout, exteria_mt_client_config *config, BOOL *tunneled) {
    exteria_proxy proxy;
    BOOL enabled = NO;
    exteria_status status = ExteriaProxyRead(&proxy, &enabled);
    if (status != EXTERIA_OK) return status;
    config->transport = EXTERIA_MT_INTERMEDIATE;
    config->obfuscation.has_secret = 0;
    memset(config->obfuscation.secret, 0, sizeof(config->obfuscation.secret));
    if (!enabled) return ExteriaShiroConnectSocket(shiro, socket, host, port, timeout, tunneled);
    uint64_t deadline = exteria_system_clock.monotonic_ms(NULL) + (uint64_t)timeout;
    status = ExteriaShiroConnectSocket(shiro, socket, proxy.server, proxy.port, timeout, tunneled);
    uint64_t now = exteria_system_clock.monotonic_ms(NULL);
    int left = now < deadline ? (int)(deadline - now) : 0;
    if (status == EXTERIA_OK && !left) { exteria_mt_socket_close(socket); status = EXTERIA_E_TIMEOUT; }
    if (status == EXTERIA_OK && proxy.kind == EXTERIA_PROXY_SOCKS5)
        status = exteria_mt_socket_negotiate_socks5(socket, proxy.user[0] ? proxy.user : NULL,
                    proxy.user[0] ? proxy.password : NULL, host, port, left);
    if (status == EXTERIA_OK && proxy.kind == EXTERIA_PROXY_MTPROTO) {
        if (proxy.tls_domain[0]) status = exteria_mt_socket_start_faketls(socket, proxy.secret, proxy.tls_domain, left);
        if (status == EXTERIA_OK) {
            config->transport = proxy.padded ? EXTERIA_MT_PADDED_INTERMEDIATE : EXTERIA_MT_INTERMEDIATE;
            config->obfuscation.has_secret = 1;
            memcpy(config->obfuscation.secret, proxy.secret, sizeof(proxy.secret));
        }
    }
    exteria_wipe(&proxy, sizeof(proxy));
    return status;
}
