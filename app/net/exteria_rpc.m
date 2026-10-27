#import "exteria_rpc.h"

#include <string.h>

NSString *ExteriaRpcErrorName(const exteria_mt_rpc_result *result) {
    char name[128];
    int32_t number;
    if (result->status == EXTERIA_E_TIMEOUT) return @"TIMEOUT";
    if (result->status != EXTERIA_E_RPC || !result->error_text) return @"INTERNAL";
    exteria_mt_rpc_error_split(result->error_text, name, sizeof(name), &number);
    return [NSString stringWithUTF8String:name];
}

NSString *ExteriaDownloadErrorName(const exteria_mt_rpc_result *result) {
    if (result->status == EXTERIA_E_IO || result->status == EXTERIA_E_STATE || result->status == EXTERIA_E_RETRY) return @"OFFLINE";
    if (result->status == EXTERIA_E_RPC && result->error_text) {
        char name[128];
        int32_t seconds;
        exteria_mt_rpc_error_split(result->error_text, name, sizeof(name), &seconds);
        if ((!strcmp(name, "FLOOD_WAIT") || !strcmp(name, "FLOOD_PREMIUM_WAIT")) && seconds > 0)
            return [NSString stringWithFormat:@"%s_%d", name, (int)seconds];
    }
    return ExteriaRpcErrorName(result);
}

BOOL ExteriaIsRevokedError(NSString *name) {
    return [name isEqualToString:@"AUTH_KEY_UNREGISTERED"] || [name isEqualToString:@"SESSION_REVOKED"] ||
           [name isEqualToString:@"USER_DEACTIVATED"] || [name isEqualToString:@"SESSION_EXPIRED"];
}
