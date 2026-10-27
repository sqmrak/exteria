#include "exteria_status.h"

const char *exteria_status_name(exteria_status status) {
    switch (status) {
    case EXTERIA_OK: return "ok";
    case EXTERIA_E_ARG: return "bad argument";
    case EXTERIA_E_MALFORMED: return "malformed input";
    case EXTERIA_E_TRUNCATED: return "truncated input";
    case EXTERIA_E_UNSUPPORTED: return "unsupported input";
    case EXTERIA_E_LIMIT: return "limit exceeded";
    case EXTERIA_E_NOMEM: return "out of memory";
    case EXTERIA_E_CRYPTO: return "crypto failure";
    case EXTERIA_E_SECURITY: return "validation failed";
    case EXTERIA_E_STATE: return "wrong state";
    case EXTERIA_E_TIMEOUT: return "timeout";
    case EXTERIA_E_IO: return "io error";
    case EXTERIA_E_EOF: return "end of stream";
    case EXTERIA_E_RETRY: return "retry";
    case EXTERIA_E_NOTFOUND: return "not found";
    case EXTERIA_E_RPC: return "rpc error";
    case EXTERIA_E_STORAGE: return "storage error";
    }
    return "unknown status";
}
