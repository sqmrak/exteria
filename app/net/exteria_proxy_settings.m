#import "exteria_proxy_settings.h"

#import <Security/Security.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "exteria_clock.h"
#include "exteria_bytes.h"

NSString *const ExteriaProxyDidChangeNotification = @"ExteriaProxyDidChange";
static NSString *const ExteriaProxyEnabledKey = @"exteria.proxy.enabled";
static NSString *const ExteriaProxyService = @"com.sqmrak.exteria.proxy";
#define PROXY_LIST_MAX 64
#define PROXY_DATA_MAX (256u * 1024u)

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

static NSString *ExteriaProxyFilePath(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [[[roots objectAtIndex:0] stringByAppendingPathComponent:@"Exteria"] stringByAppendingPathComponent:@"proxy-link"];
}

/* the jailbreak build may lack a keychain entitlement; the private file keeps the same complete record */
static exteria_status ExteriaProxyReadData(NSData **out, BOOL *fileBacked) {
    *out = nil;
    *fileBacked = NO;
    NSString *path = ExteriaProxyFilePath();
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
    if (attributes) {
        if ([[attributes objectForKey:NSFileSize] unsignedLongLongValue] > PROXY_DATA_MAX) return EXTERIA_E_LIMIT;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) return EXTERIA_E_STORAGE;
        *out = data;
        *fileBacked = YES;
        return EXTERIA_OK;
    }
    if (error && !([error.domain isEqualToString:NSCocoaErrorDomain] && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError))) return EXTERIA_E_STORAGE;
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:ExteriaProxyQuery()];
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    CFTypeRef value = NULL;
    OSStatus result = SecItemCopyMatching((CFDictionaryRef)query, &value);
    if (result == errSecItemNotFound) return EXTERIA_E_NOTFOUND;
    if (result == -34018) return EXTERIA_E_UNSUPPORTED;
    if (result != errSecSuccess) return EXTERIA_E_STORAGE;
    NSData *data = [(NSData *)value autorelease];
    if (data.length > PROXY_DATA_MAX) return EXTERIA_E_LIMIT;
    *out = data;
    return EXTERIA_OK;
}

static exteria_status ExteriaProxyLoad(NSMutableArray **links, NSUInteger *selected, BOOL *fileBacked) {
    NSData *data = nil;
    *links = nil;
    *selected = 0;
    exteria_status status = ExteriaProxyReadData(&data, fileBacked);
    if (status != EXTERIA_OK) return status;
    NSString *legacy = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    exteria_proxy proxy;
    if (legacy && ExteriaProxyDecode(legacy, &proxy) == EXTERIA_OK) {
        exteria_wipe(&proxy, sizeof(proxy));
        *links = [NSMutableArray arrayWithObject:legacy];
        return EXTERIA_OK;
    }
    exteria_wipe(&proxy, sizeof(proxy));
    NSError *error = nil;
    id record = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    if (![record isKindOfClass:[NSDictionary class]] || ![[record objectForKey:@"version"] isKindOfClass:[NSNumber class]] ||
        [[record objectForKey:@"version"] integerValue] != 1 || ![[record objectForKey:@"links"] isKindOfClass:[NSArray class]] ||
        ![[record objectForKey:@"selected"] isKindOfClass:[NSNumber class]]) return EXTERIA_E_MALFORMED;
    NSArray *saved = [record objectForKey:@"links"];
    long long index = [[record objectForKey:@"selected"] longLongValue];
    if (saved.count > PROXY_LIST_MAX || index < 0 || (saved.count ? (unsigned long long)index >= saved.count : index != 0)) return EXTERIA_E_MALFORMED;
    for (id text in saved) {
        status = ExteriaProxyDecode(text, &proxy);
        exteria_wipe(&proxy, sizeof(proxy));
        if (status != EXTERIA_OK) return EXTERIA_E_MALFORMED;
    }
    *links = [NSMutableArray arrayWithArray:saved];
    *selected = (NSUInteger)index;
    return EXTERIA_OK;
}

static BOOL ExteriaProxyWriteFile(NSData *data) {
    NSString *path = ExteriaProxyFilePath();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"exteria: proxy directory could not be created: %@", error);
        return NO;
    }
    char *temporary = strdup([[path stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]);
    if (!temporary) return NO;
    int fd = mkstemp(temporary);
    BOOL ok = fd >= 0;
    const uint8_t *bytes = data.bytes;
    size_t left = data.length;
    while (ok && left) {
        ssize_t written = write(fd, bytes, left);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { ok = NO; break; }
        bytes += written;
        left -= (size_t)written;
    }
    if (fd >= 0 && close(fd) != 0) ok = NO;
    if (ok && rename(temporary, path.fileSystemRepresentation) != 0) ok = NO;
    if (!ok) { NSLog(@"exteria: proxy file could not be written: %s", strerror(errno)); unlink(temporary); }
    free(temporary);
    return ok;
}

static exteria_status ExteriaProxySave(NSArray *links, NSUInteger selected, BOOL fileBacked) {
    NSDictionary *record = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"version", links, @"links",
                            [NSNumber numberWithUnsignedInteger:selected], @"selected", nil];
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || data.length > PROXY_DATA_MAX) return EXTERIA_E_STORAGE;
    if (fileBacked) return ExteriaProxyWriteFile(data) ? EXTERIA_OK : EXTERIA_E_STORAGE;
    NSDictionary *query = ExteriaProxyQuery();
    NSDictionary *update = [NSDictionary dictionaryWithObject:data forKey:(id)kSecValueData];
    OSStatus result = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
    if (result == errSecItemNotFound) {
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:query];
        [item addEntriesFromDictionary:update];
        [item setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
        result = SecItemAdd((CFDictionaryRef)item, NULL);
        if (result == -34018 && ExteriaProxyWriteFile(data)) return EXTERIA_OK;
    }
    if (result != errSecSuccess) {
        NSLog(@"exteria: proxy keychain write failed: %d", (int)result);
        return EXTERIA_E_STORAGE;
    }
    return EXTERIA_OK;
}

static exteria_status ExteriaProxyReadLocked(exteria_proxy *proxy) {
    NSMutableArray *links;
    NSUInteger selected;
    BOOL fileBacked;
    exteria_status status = ExteriaProxyLoad(&links, &selected, &fileBacked);
    if (status != EXTERIA_OK) return status;
    return links.count ? ExteriaProxyDecode([links objectAtIndex:selected], proxy) : EXTERIA_E_NOTFOUND;
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
    @synchronized (ExteriaProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        status = ExteriaProxyLoad(&links, &selected, &fileBacked);
        if (status == EXTERIA_E_NOTFOUND || status == EXTERIA_E_UNSUPPORTED) {
            links = [NSMutableArray array];
            selected = 0;
            fileBacked = status == EXTERIA_E_UNSUPPORTED;
        } else if (status != EXTERIA_OK) return status;
        NSUInteger index = [links indexOfObject:text];
        if (index == NSNotFound) {
            if (links.count >= PROXY_LIST_MAX) return EXTERIA_E_LIMIT;
            [links addObject:text];
            index = links.count - 1;
        }
        status = ExteriaProxySave(links, index, fileBacked);
        if (status != EXTERIA_OK) return status;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:ExteriaProxyEnabledKey];
        if (![[NSUserDefaults standardUserDefaults] synchronize]) return EXTERIA_E_STORAGE;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaProxyDidChangeNotification object:nil];
    return EXTERIA_OK;
}

exteria_status ExteriaProxyList(NSArray **entries) {
    if (!entries) return EXTERIA_E_ARG;
    *entries = nil;
    @synchronized (ExteriaProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        exteria_status status = ExteriaProxyLoad(&links, &selected, &fileBacked);
        if (status == EXTERIA_E_NOTFOUND || status == EXTERIA_E_UNSUPPORTED) { *entries = [NSArray array]; return EXTERIA_OK; }
        if (status != EXTERIA_OK) return status;
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:links.count];
        for (NSUInteger i = 0; i < links.count; ++i) {
            exteria_proxy proxy;
            status = ExteriaProxyDecode([links objectAtIndex:i], &proxy);
            if (status != EXTERIA_OK) { exteria_wipe(&proxy, sizeof(proxy)); return status; }
            NSString *address = [NSString stringWithFormat:@"%s:%u (%@)", proxy.server, (unsigned)proxy.port, proxy.kind == EXTERIA_PROXY_MTPROTO ? @"MTProto" : @"SOCKS5"];
            exteria_wipe(&proxy, sizeof(proxy));
            [list addObject:[NSDictionary dictionaryWithObjectsAndKeys:address, @"address", [NSNumber numberWithBool:i == selected], @"selected", nil]];
        }
        *entries = list;
        return EXTERIA_OK;
    }
}

static exteria_status ExteriaProxyChange(NSUInteger index, BOOL remove) {
    @synchronized (ExteriaProxyService) {
        NSMutableArray *links;
        NSUInteger selected;
        BOOL fileBacked;
        exteria_status status = ExteriaProxyLoad(&links, &selected, &fileBacked);
        if (status != EXTERIA_OK) return status;
        if (index >= links.count) return EXTERIA_E_ARG;
        if (remove) {
            [links removeObjectAtIndex:index];
            if (index < selected) --selected;
            else if (selected >= links.count) selected = links.count ? links.count - 1 : 0;
        } else selected = index;
        status = ExteriaProxySave(links, selected, fileBacked);
        if (status != EXTERIA_OK) return status;
        if (!remove || !links.count) {
            [[NSUserDefaults standardUserDefaults] setBool:!remove forKey:ExteriaProxyEnabledKey];
            if (![[NSUserDefaults standardUserDefaults] synchronize]) return EXTERIA_E_STORAGE;
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ExteriaProxyDidChangeNotification object:nil];
    return EXTERIA_OK;
}

exteria_status ExteriaProxySelect(NSUInteger index) { return ExteriaProxyChange(index, NO); }
exteria_status ExteriaProxyRemove(NSUInteger index) { return ExteriaProxyChange(index, YES); }

exteria_status ExteriaProxySetEnabled(BOOL enabled) {
    @synchronized (ExteriaProxyService) {
        if (enabled) {
            exteria_proxy proxy;
            exteria_status status = ExteriaProxyReadLocked(&proxy);
            exteria_wipe(&proxy, sizeof(proxy));
            if (status != EXTERIA_OK) return status;
        }
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ExteriaProxyEnabledKey];
        if (![[NSUserDefaults standardUserDefaults] synchronize]) return EXTERIA_E_STORAGE;
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
