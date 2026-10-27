#include "exteria_rtp.h"

#include <string.h>

#define RTP_VERSION 2
#define RTCP_PT_PSFB 206
#define RTCP_FMT_PLI 1

static void put32(uint8_t *out, uint32_t value) {
    out[0] = (uint8_t)(value >> 24);
    out[1] = (uint8_t)(value >> 16);
    out[2] = (uint8_t)(value >> 8);
    out[3] = (uint8_t)value;
}

exteria_status exteria_rtp_parse(const uint8_t *packet, size_t len, exteria_rtp_header *out) {
    size_t offset, end;
    if (!out) return EXTERIA_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!packet) return EXTERIA_E_ARG;
    if (len < EXTERIA_RTP_FIXED_LEN) return EXTERIA_E_TRUNCATED;
    if ((packet[0] >> 6) != RTP_VERSION) return EXTERIA_E_MALFORMED;
    offset = EXTERIA_RTP_FIXED_LEN + 4u * (size_t)(packet[0] & 0x0F);
    if (offset > len) return EXTERIA_E_MALFORMED;
    if (packet[0] & 0x10) {
        size_t words;
        if (offset + 4 > len) return EXTERIA_E_MALFORMED;
        words = ((size_t)packet[offset + 2] << 8) | packet[offset + 3];
        offset += 4 + words * 4;
        if (offset > len) return EXTERIA_E_MALFORMED;
    }
    end = len;
    if (packet[0] & 0x20) {
        size_t padding = packet[len - 1];
        if (padding == 0 || padding > end - offset) return EXTERIA_E_MALFORMED;
        end -= padding;
    }
    out->marker = (uint8_t)(packet[1] >> 7);
    out->payload_type = (uint8_t)(packet[1] & 0x7F);
    out->sequence = (uint16_t)(((unsigned)packet[2] << 8) | packet[3]);
    out->timestamp = ((uint32_t)packet[4] << 24) | ((uint32_t)packet[5] << 16) | ((uint32_t)packet[6] << 8) | packet[7];
    out->ssrc = ((uint32_t)packet[8] << 24) | ((uint32_t)packet[9] << 16) | ((uint32_t)packet[10] << 8) | packet[11];
    out->payload_offset = offset;
    out->payload_len = end - offset;
    return EXTERIA_OK;
}

exteria_status exteria_rtp_write_header(uint8_t *out, size_t capacity, uint8_t payload_type, int marker, uint16_t sequence,
                                        uint32_t timestamp, uint32_t ssrc) {
    if (!out) return EXTERIA_E_ARG;
    if (payload_type > 127) return EXTERIA_E_ARG;
    if (capacity < EXTERIA_RTP_FIXED_LEN) return EXTERIA_E_LIMIT;
    out[0] = RTP_VERSION << 6;
    out[1] = (uint8_t)((marker ? 0x80 : 0) | payload_type);
    out[2] = (uint8_t)(sequence >> 8);
    out[3] = (uint8_t)sequence;
    put32(out + 4, timestamp);
    put32(out + 8, ssrc);
    return EXTERIA_OK;
}

exteria_status exteria_rtcp_write_pli(uint8_t *out, size_t capacity, uint32_t sender_ssrc, uint32_t media_ssrc) {
    if (!out) return EXTERIA_E_ARG;
    if (capacity < EXTERIA_RTCP_PLI_LEN) return EXTERIA_E_LIMIT;
    out[0] = (uint8_t)(RTP_VERSION << 6 | RTCP_FMT_PLI);
    out[1] = RTCP_PT_PSFB;
    /* the length counts 32 bit words after the first, so 2 for a 12 byte packet */
    out[2] = 0;
    out[3] = 2;
    put32(out + 4, sender_ssrc);
    put32(out + 8, media_ssrc);
    return EXTERIA_OK;
}

void exteria_rtp_stats_reset(exteria_rtp_receive_stats *stats, uint32_t ssrc) {
    if (!stats) return;
    memset(stats, 0, sizeof(*stats));
    stats->ssrc = ssrc;
}

void exteria_rtp_stats_update(exteria_rtp_receive_stats *stats, uint16_t sequence) {
    uint16_t delta;
    if (!stats) return;
    if (!stats->started) {
        stats->started = 1;
        stats->base_sequence = sequence;
        stats->max_sequence = sequence;
        stats->received = 1;
        return;
    }
    delta = (uint16_t)(sequence - stats->max_sequence);
    if (delta == 0) return;
    if (delta < 0x8000u) {
        if (sequence < stats->max_sequence) stats->cycles += 0x10000u;
        stats->max_sequence = sequence;
    }
    ++stats->received;
}

void exteria_rtp_stats_sender_report(exteria_rtp_receive_stats *stats, uint32_t ntp_middle, uint64_t now_ms) {
    if (!stats) return;
    stats->last_sr = ntp_middle;
    stats->last_sr_ms = now_ms;
}

exteria_status exteria_rtp_stats_block(exteria_rtp_receive_stats *stats, uint64_t now_ms, uint8_t out[EXTERIA_RTCP_BLOCK_LEN]) {
    uint32_t extended, expected, expected_interval, received_interval, fraction = 0, dlsr = 0;
    int64_t lost;
    uint32_t cumulative;
    if (!stats || !out) return EXTERIA_E_ARG;
    if (!stats->started) return EXTERIA_E_STATE;
    extended = stats->cycles + stats->max_sequence;
    expected = extended - stats->base_sequence + 1u;
    expected_interval = expected - stats->expected_prior;
    received_interval = stats->received - stats->received_prior;
    stats->expected_prior = expected;
    stats->received_prior = stats->received;
    if (expected_interval > received_interval && expected_interval > 0) fraction = ((expected_interval - received_interval) << 8) / expected_interval;
    if (fraction > 255) fraction = 255;
    /* the total is a signed 24 bit number: duplicates can make it negative, and it stops at the ends of the range */
    lost = (int64_t)expected - (int64_t)stats->received;
    if (lost > 0x7FFFFF) lost = 0x7FFFFF;
    if (lost < -0x800000) lost = -0x800000;
    cumulative = (uint32_t)lost & 0xFFFFFFu;
    if (stats->last_sr && now_ms >= stats->last_sr_ms) dlsr = (uint32_t)(((now_ms - stats->last_sr_ms) * 65536u) / 1000u);
    put32(out, stats->ssrc);
    out[4] = (uint8_t)fraction;
    out[5] = (uint8_t)(cumulative >> 16);
    out[6] = (uint8_t)(cumulative >> 8);
    out[7] = (uint8_t)cumulative;
    put32(out + 8, extended);
    put32(out + 12, 0);
    put32(out + 16, stats->last_sr);
    put32(out + 20, stats->last_sr ? dlsr : 0);
    return EXTERIA_OK;
}

exteria_status exteria_rtcp_write_receiver_report(uint8_t *out, size_t capacity, uint32_t sender_ssrc, const uint8_t *blocks, size_t count, size_t *len) {
    size_t total;
    if (len) *len = 0;
    if (!out || !len || (count && !blocks) || count > EXTERIA_RTCP_RR_MAX_BLOCKS) return EXTERIA_E_ARG;
    total = 8 + count * EXTERIA_RTCP_BLOCK_LEN;
    if (capacity < total) return EXTERIA_E_LIMIT;
    out[0] = (uint8_t)((RTP_VERSION << 6) | count);
    out[1] = 201;
    out[2] = (uint8_t)(((total / 4) - 1) >> 8);
    out[3] = (uint8_t)((total / 4) - 1);
    put32(out + 4, sender_ssrc);
    if (count) memcpy(out + 8, blocks, count * EXTERIA_RTCP_BLOCK_LEN);
    *len = total;
    return EXTERIA_OK;
}
