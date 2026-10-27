#include "exteria_udp.h"

#include <string.h>

#define IP_HEADER 20u
#define UDP_HEADER 8u
#define PROTO_UDP 17u

static void put16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)(v & 0xffu);
}

static void put32(uint8_t *p, uint32_t v) {
    put16(p, (uint16_t)(v >> 16));
    put16(p + 2, (uint16_t)(v & 0xffffu));
}

static uint16_t get16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static uint32_t get32(const uint8_t *p) {
    return ((uint32_t)get16(p) << 16) | get16(p + 2);
}

/* the sum of 16 bit words, before it is folded and inverted; an odd last byte counts as the high half of a word */
static uint32_t sum_words(const uint8_t *p, size_t len, uint32_t sum) {
    while (len > 1) {
        sum += get16(p);
        p += 2;
        len -= 2;
    }
    if (len) sum += (uint32_t)p[0] << 8;
    return sum;
}

static uint16_t fold(uint32_t sum) {
    while (sum >> 16) sum = (sum & 0xffffu) + (sum >> 16);
    return (uint16_t)sum;
}

static uint32_t pseudo_sum(uint32_t src_ip, uint32_t dst_ip, size_t udp_len) {
    return (src_ip >> 16) + (src_ip & 0xffffu) + (dst_ip >> 16) + (dst_ip & 0xffffu) + PROTO_UDP + (uint32_t)udp_len;
}

int exteria_udp_is_udp(const uint8_t *packet, size_t len) {
    return packet && len >= IP_HEADER && (packet[0] >> 4) == 4 && packet[9] == PROTO_UDP;
}

exteria_status exteria_udp_build(uint32_t src_ip, uint16_t src_port, uint32_t dst_ip, uint16_t dst_port, uint16_t ident, const uint8_t *payload, size_t len,
                                 uint8_t *out, size_t cap, size_t *out_len) {
    size_t total = IP_HEADER + UDP_HEADER + len;
    uint16_t check;
    if (out_len) *out_len = 0;
    if (!out || !out_len || (len && !payload) || src_ip == 0 || dst_ip == 0 || src_port == 0 || dst_port == 0) return EXTERIA_E_ARG;
    if (len > EXTERIA_UDP_MAX_PAYLOAD || cap < total) return EXTERIA_E_LIMIT;
    memset(out, 0, IP_HEADER + UDP_HEADER);
    out[0] = 0x45;
    put16(out + 2, (uint16_t)total);
    put16(out + 4, ident);
    put16(out + 6, 0x4000);
    out[8] = 64;
    out[9] = PROTO_UDP;
    put32(out + 12, src_ip);
    put32(out + 16, dst_ip);
    put16(out + 10, (uint16_t)~fold(sum_words(out, IP_HEADER, 0)));
    put16(out + 20, src_port);
    put16(out + 22, dst_port);
    put16(out + 24, (uint16_t)(UDP_HEADER + len));
    if (len) memcpy(out + IP_HEADER + UDP_HEADER, payload, len);
    check = (uint16_t)~fold(sum_words(out + IP_HEADER, UDP_HEADER + len, pseudo_sum(src_ip, dst_ip, UDP_HEADER + len)));
    /* a computed zero is sent as all ones, since zero says that there is no checksum */
    put16(out + 26, check == 0 ? 0xffffu : check);
    *out_len = total;
    return EXTERIA_OK;
}

exteria_status exteria_udp_parse(const uint8_t *packet, size_t len, exteria_udp_datagram *out) {
    size_t header, total, udp_len;
    uint16_t check;
    if (out) memset(out, 0, sizeof(*out));
    if (!packet || !out || len < IP_HEADER + UDP_HEADER) return EXTERIA_E_MALFORMED;
    if ((packet[0] >> 4) != 4) return EXTERIA_E_MALFORMED;
    header = (size_t)(packet[0] & 0x0fu) * 4u;
    total = get16(packet + 2);
    if (header < IP_HEADER || total < header + UDP_HEADER || total > len) return EXTERIA_E_MALFORMED;
    if (packet[9] != PROTO_UDP) return EXTERIA_E_MALFORMED;
    if (fold(sum_words(packet, header, 0)) != 0xffffu) return EXTERIA_E_MALFORMED;
    if (get16(packet + 6) & 0x3fffu) return EXTERIA_E_UNSUPPORTED;
    udp_len = get16(packet + header + 4);
    if (udp_len != total - header) return EXTERIA_E_MALFORMED;
    check = get16(packet + header + 6);
    if (check != 0 && fold(sum_words(packet + header, udp_len, pseudo_sum(get32(packet + 12), get32(packet + 16), udp_len))) != 0xffffu) return EXTERIA_E_MALFORMED;
    if (udp_len - UDP_HEADER > EXTERIA_UDP_MAX_PAYLOAD) return EXTERIA_E_MALFORMED;
    out->src_ip = get32(packet + 12);
    out->dst_ip = get32(packet + 16);
    out->src_port = get16(packet + header);
    out->dst_port = get16(packet + header + 2);
    out->payload = packet + header + UDP_HEADER;
    out->payload_len = udp_len - UDP_HEADER;
    return EXTERIA_OK;
}

exteria_status exteria_udp_frame_encode(uint32_t ip, uint16_t port, const uint8_t *payload, size_t len, uint8_t *out, size_t cap, size_t *out_len) {
    if (out_len) *out_len = 0;
    if (!out || !out_len || (len && !payload) || ip == 0 || port == 0) return EXTERIA_E_ARG;
    if (len > EXTERIA_UDP_MAX_PAYLOAD || cap < EXTERIA_UDP_FRAME_HEADER + len) return EXTERIA_E_LIMIT;
    put32(out, ip);
    put16(out + 4, port);
    if (len) memcpy(out + EXTERIA_UDP_FRAME_HEADER, payload, len);
    *out_len = EXTERIA_UDP_FRAME_HEADER + len;
    return EXTERIA_OK;
}

exteria_status exteria_udp_frame_decode(const uint8_t *frame, size_t len, uint32_t *ip, uint16_t *port, const uint8_t **payload, size_t *payload_len) {
    if (ip) *ip = 0;
    if (port) *port = 0;
    if (payload) *payload = NULL;
    if (payload_len) *payload_len = 0;
    if (!frame || !ip || !port || !payload || !payload_len || len < EXTERIA_UDP_FRAME_HEADER) return EXTERIA_E_MALFORMED;
    if (len - EXTERIA_UDP_FRAME_HEADER > EXTERIA_UDP_MAX_PAYLOAD) return EXTERIA_E_LIMIT;
    *ip = get32(frame);
    *port = get16(frame + 4);
    if (*ip == 0 || *port == 0) {
        *ip = 0;
        *port = 0;
        return EXTERIA_E_MALFORMED;
    }
    *payload = frame + EXTERIA_UDP_FRAME_HEADER;
    *payload_len = len - EXTERIA_UDP_FRAME_HEADER;
    return EXTERIA_OK;
}
