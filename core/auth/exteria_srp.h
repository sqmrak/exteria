#ifndef EXTERIA_SRP_H
#define EXTERIA_SRP_H

#include "exteria_tl.h"

typedef struct exteria_srp_proof {
    int64_t id;
    uint8_t A[256];
    uint8_t M1[32];
} exteria_srp_proof;

exteria_status exteria_srp_check(const exteria_tl_value *account_password,
                                const uint8_t *password, size_t len, exteria_srp_proof *out);
exteria_status exteria_srp_verifier(const exteria_tl_value *algo, const uint8_t *password, size_t len,
                                   exteria_arena *arena, exteria_tl_value **new_algo, uint8_t verifier[256]);

#endif
