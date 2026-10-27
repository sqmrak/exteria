#import <Foundation/Foundation.h>

#include "exteria_mt_client.h"

/* the rpc error name without its number, TIMEOUT for a request that ran out of time, INTERNAL for the rest */
NSString *ExteriaRpcErrorName(const exteria_mt_rpc_result *result);

/* file retries distinguish a dropped link and preserve the seconds of a server flood wait */
NSString *ExteriaDownloadErrorName(const exteria_mt_rpc_result *result);

/* the server no longer knows this key: the account is gone and the stored files with it */
BOOL ExteriaIsRevokedError(NSString *name);
