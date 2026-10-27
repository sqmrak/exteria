#ifndef EXTERIA_RTP_H
#define EXTERIA_RTP_H

#include <stddef.h>
#include <stdint.h>

#include "exteria_status.h"

/* the parts of RTP (RFC 3550) and RTCP feedback (RFC 4585) that the video call needs, over buffers the caller
   owns; the packets here are the plain ones, before the SRTP layer protects them and after it unprotects them */

#define EXTERIA_RTP_FIXED_LEN 12
#define EXTERIA_RTCP_PLI_LEN 12

typedef struct exteria_rtp_header {
    uint8_t payload_type;
    uint8_t marker;
    uint16_t sequence;
    uint32_t timestamp;
    uint32_t ssrc;
    /* where the media bytes start and how many there are, after the csrc list, the extension and the padding */
    size_t payload_offset;
    size_t payload_len;
} exteria_rtp_header;

/* EXTERIA_E_TRUNCATED when the packet ends inside its own header, EXTERIA_E_MALFORMED for a version other than 2,
   an extension or csrc list that runs past the end */
exteria_status exteria_rtp_parse(const uint8_t *packet, size_t len, exteria_rtp_header *out);

/* writes the 12 byte header with no csrc and no extension; EXTERIA_E_ARG for a payload type above 127, EXTERIA_E_LIMIT when
   capacity is below 12 */
exteria_status exteria_rtp_write_header(uint8_t *out, size_t capacity, uint8_t payload_type, int marker, uint16_t sequence,
                                        uint32_t timestamp, uint32_t ssrc);

/* a picture loss indication from sender_ssrc about the stream media_ssrc: asks the other side for a key frame */
exteria_status exteria_rtcp_write_pli(uint8_t *out, size_t capacity, uint32_t sender_ssrc, uint32_t media_ssrc);

/* what a receiver counts of one incoming stream to report it (RFC 3550, appendix A.1, without the probation of a new source): every field is zero
   before the first packet */
typedef struct exteria_rtp_receive_stats {
    uint8_t started;
    uint32_t ssrc;
    uint16_t base_sequence;
    uint16_t max_sequence;
    uint32_t cycles;            /* wraps of the 16 bit sequence number, kept shifted left by 16 */
    uint32_t received;
    uint32_t expected_prior;
    uint32_t received_prior;
    uint32_t last_sr;           /* the middle 32 bits of the NTP time in the last sender report of this stream */
    uint64_t last_sr_ms;        /* the clock of the caller when it came */
} exteria_rtp_receive_stats;

#define EXTERIA_RTCP_BLOCK_LEN 24
#define EXTERIA_RTCP_RR_MAX_BLOCKS 4

/* starts counting a stream of this ssrc; the sender report of an earlier stream is forgotten */
void exteria_rtp_stats_reset(exteria_rtp_receive_stats *stats, uint32_t ssrc);
/* a packet of the stream arrived */
void exteria_rtp_stats_update(exteria_rtp_receive_stats *stats, uint16_t sequence);
/* the sender report of the stream said this middle part of its NTP time at now_ms of the caller's clock */
void exteria_rtp_stats_sender_report(exteria_rtp_receive_stats *stats, uint32_t ntp_middle, uint64_t now_ms);
/* the report block of the stream at now_ms: loss since the last block, the total lost, the highest sequence, and
   the time since the last sender report */
exteria_status exteria_rtp_stats_block(exteria_rtp_receive_stats *stats, uint64_t now_ms, uint8_t out[EXTERIA_RTCP_BLOCK_LEN]);
/* a receiver report (RFC 3550, 6.4.2) from sender_ssrc carrying count blocks (at most EXTERIA_RTCP_RR_MAX_BLOCKS,
   each EXTERIA_RTCP_BLOCK_LEN bytes); len is the size written */
exteria_status exteria_rtcp_write_receiver_report(uint8_t *out, size_t capacity, uint32_t sender_ssrc, const uint8_t *blocks, size_t count, size_t *len);

#endif
