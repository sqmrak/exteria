#ifndef EXTERIA_QR_H
#define EXTERIA_QR_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

#define EXTERIA_QR_MAX_VERSION 10
#define EXTERIA_QR_MAX_SIDE 57
#define EXTERIA_QR_MAX_MODULES (EXTERIA_QR_MAX_SIDE * EXTERIA_QR_MAX_SIDE)

/* a QR code of version 1 to 10 with error correction level M, the data in byte mode. modules receives side * side
   bytes in rows, top first, 1 for a dark module and 0 for a light one */
exteria_status exteria_qr_encode(const uint8_t *data, size_t len, uint8_t *modules, size_t cap, int *side, int *mask_out);

#endif
