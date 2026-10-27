#ifndef EXTERIA_UDP_H
#define EXTERIA_UDP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

#ifdef __cplusplus
extern "C" {
#endif

/* UDP over IPv4 for the tunnel, and the frame the tunnel's datagram sockets speak with the rest of the program */

/* the largest payload: the tunnel MTU of 1280 less the IPv4 header of 20 bytes and the UDP header of 8 */
#define EXTERIA_UDP_MAX_PAYLOAD 1252u
#define EXTERIA_UDP_PACKET_MAX 1280u
#define EXTERIA_UDP_FRAME_HEADER 6u

typedef struct exteria_udp_datagram {
    uint32_t src_ip, dst_ip;
    uint16_t src_port, dst_port;
    const uint8_t *payload;         /* points into the packet that was parsed */
    size_t payload_len;
} exteria_udp_datagram;

/* 1 for a packet that starts as IPv4 and carries protocol 17, whatever else is wrong with it; the owner of the stack uses it to tell UDP from TCP */
int exteria_udp_is_udp(const uint8_t *packet, size_t len);

/* EXTERIA_E_ARG for a zero address or port, EXTERIA_E_LIMIT for a payload over EXTERIA_UDP_MAX_PAYLOAD or a cap
   that is too small. ident is the IPv4 identification field */
exteria_status exteria_udp_build(uint32_t src_ip, uint16_t src_port, uint32_t dst_ip, uint16_t dst_port, uint16_t ident, const uint8_t *payload, size_t len,
                                 uint8_t *out, size_t cap, size_t *out_len);

/* EXTERIA_E_MALFORMED for anything that is not a whole, valid UDP packet (a bad version, header length, total
   length, protocol, or either checksum), EXTERIA_E_UNSUPPORTED for a fragment */
exteria_status exteria_udp_parse(const uint8_t *packet, size_t len, exteria_udp_datagram *out);

/* the frame of a datagram socket of the tunnel: the peer's IPv4 address (big endian), its port (big endian) and
   the payload */
exteria_status exteria_udp_frame_encode(uint32_t ip, uint16_t port, const uint8_t *payload, size_t len, uint8_t *out, size_t cap, size_t *out_len);
/* EXTERIA_E_MALFORMED for a frame shorter than its header or with a zero address or port, EXTERIA_E_LIMIT for a payload over the maximum */
exteria_status exteria_udp_frame_decode(const uint8_t *frame, size_t len, uint32_t *ip, uint16_t *port, const uint8_t **payload, size_t *payload_len);

#ifdef __cplusplus
}
#endif

#endif
