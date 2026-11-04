#ifndef EXTERIA_PYHOST_H
#define EXTERIA_PYHOST_H

#include <stddef.h>
#include <stdint.h>
#include "exteria_status.h"

/* largest reply a service may return to python, and the largest json a call may take or give back */
#define EXTERIA_PYHOST_REPLY_MAX 65536u
#define EXTERIA_PYHOST_ARGS_MAX 262144u
#define EXTERIA_PYHOST_PATHS_MAX 8u

/* answers a request from python: name is the service ("log", "settings.get"), payload is json. the reply is json written to
   out (capacity cap, not terminated). on failure the status says why and out carries a short text for the exception.
   called with the interpreter lock held, on whichever thread python runs; a service that touches uikit must hop itself */
typedef exteria_status (*exteria_pyhost_service_fn)(void *ctx, const char *name, const char *payload, size_t payload_len,
                                                    char *out, size_t cap, size_t *out_len);

/* a python module written in c and built into the app: name is the import name, init the PyInit function of the module */
typedef struct exteria_pyhost_module {
    const char *name;
    void *(*init)(void);
} exteria_pyhost_module;

#define EXTERIA_PYHOST_MODULES_MAX 8u

typedef struct exteria_pyhost_config {
    const char *stdlib;                                 /* directory of the pure python standard library */
    const char *paths[EXTERIA_PYHOST_PATHS_MAX];        /* import directories after the stdlib, NULL ends the list */
    exteria_pyhost_module modules[EXTERIA_PYHOST_MODULES_MAX];   /* a NULL name ends the list */
    exteria_pyhost_service_fn service;
    void *service_ctx;
} exteria_pyhost_config;

/* starts one interpreter for the process, isolated from the environment, with no site module, no user site and no
   bytecode written. EXTERIA_E_STATE when it is already running, EXTERIA_E_IO when the stdlib cannot start python */
exteria_status exteria_pyhost_init(const exteria_pyhost_config *cfg);

/* calls module.func(*args) where json_args is a json list. the result is the json of the return value (None is "null").
   timeout_ms stops a python loop that outruns it with EXTERIA_E_TIMEOUT, 0 means no limit; it cannot stop one blocked in C.
   EXTERIA_E_STATE: the call raised, see exteria_pyhost_error. EXTERIA_E_SECURITY: it raised PermissionError.
   EXTERIA_E_LIMIT: reply larger than cap. EXTERIA_E_MALFORMED: json_args is not a list or the result is not json */
exteria_status exteria_pyhost_call(const char *module, const char *func, const char *json_args, uint32_t timeout_ms,
                                   char *out, size_t cap, size_t *out_len);

/* the text of the last failed call, empty after a good one. only valid until the next call */
const char *exteria_pyhost_error(void);

void exteria_pyhost_shutdown(void);

#endif
