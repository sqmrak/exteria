#include "exteria_tgc_ice.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "exteria_random.h"

#define CHECK_PACING_MS 40
#define RTO_BASE_MS 250
#define RTO_MAX_SHIFT 4
#define MAX_TRIES 7
#define RETRY_AFTER_GIVE_UP_MS 3000
/* the priority of a peer reflexive candidate: type preference 110, local preference 65535, component 1 (RFC 8445 section 5.1.2) */
#define CHECK_PRIORITY 1845501695u
#define PEER_REFLEXIVE_DEFAULT_PRIORITY 1u

static void trace(const exteria_tgc_ice *ice, const char *format, ...) {
    char line[200];
    va_list args;
    if (!ice->events.trace) return;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    ice->events.trace(ice->events.context, line);
}

/* where a datagram goes or came from: a reflector of ours and a tag of the other phone, or a TURN allocation of ours and an address of the other phone */
typedef struct path {
    uint8_t turn;
    uint8_t server;
    uint32_t tag;
    uint32_t ip;
    uint16_t port;
} path;

static path path_of(const exteria_tgc_ice_pair *p) {
    path s;
    memset(&s, 0, sizeof(s));
    s.turn = p->turn;
    s.server = p->turn ? p->server : p->reflector;
    s.tag = p->remote_tag;
    s.ip = p->remote_ip;
    s.port = p->remote_port;
    return s;
}

static int same_path(const exteria_tgc_ice_pair *p, const path *s) {
    if (p->turn != s->turn) return 0;
    if (s->turn == 2) return p->remote_ip == s->ip && p->remote_port == s->port;
    if (s->turn) return p->server == s->server && p->remote_ip == s->ip && p->remote_port == s->port;
    return p->reflector == s->server && p->remote_tag == s->tag;
}

static void describe(const path *s, char *out, size_t cap) {
    if (s->turn) snprintf(out, cap, "turn %u peer %u.%u.%u.%u:%u", (unsigned)s->server, (unsigned)(s->ip >> 24), (unsigned)(s->ip >> 16 & 255),
                          (unsigned)(s->ip >> 8 & 255), (unsigned)(s->ip & 255), (unsigned)s->port);
    else snprintf(out, cap, "reflector %u remote tag %lu", (unsigned)s->server, (unsigned long)s->tag);
}

/* the addresses a TURN allocation can send to and the other phone can be reached at: private, loopback, link local, carrier grade NAT and benchmark ranges are not */
static int routable(uint32_t ip) {
    unsigned a = ip >> 24, b = ip >> 16 & 255;
    if (a == 0 || a == 10 || a == 127 || a >= 224) return 0;
    if (a == 169 && b == 254) return 0;
    if (a == 172 && b >= 16 && b <= 31) return 0;
    if (a == 192 && b == 168) return 0;
    if (a == 100 && b >= 64 && b <= 127) return 0;
    if (a == 198 && (b == 18 || b == 19)) return 0;
    return 1;
}

static int credentials_ok(const char *s, size_t min, size_t max) {
    size_t n = s ? strlen(s) : 0, i;
    if (n < min || n > max) return 0;
    for (i = 0; i < n; ++i) {
        /* the characters ICE allows, and none that would break the "remote:local" form of the username */
        char c = s[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '+' || c == '/')) return 0;
    }
    return 1;
}

exteria_status exteria_tgc_ice_init_direct(exteria_tgc_ice *ice, int controlling, uint64_t tie_breaker, const char *local_ufrag, const char *local_pwd,
                                           const exteria_tgc_ice_events *events) {
    if (!ice) return EXTERIA_E_ARG;
    memset(ice, 0, sizeof(*ice));
    if (!events || !events->send || !credentials_ok(local_ufrag, 4, EXTERIA_TGC_ICE_UFRAG_MAX - 1) ||
        !credentials_ok(local_pwd, 22, EXTERIA_TGC_ICE_PWD_MAX - 1)) return EXTERIA_E_ARG;
    ice->events = *events;
    ice->controlling = controlling ? 1 : 0;
    ice->tie_breaker = tie_breaker;
    memcpy(ice->local_ufrag, local_ufrag, strlen(local_ufrag) + 1);
    memcpy(ice->local_pwd, local_pwd, strlen(local_pwd) + 1);
    ice->selected = -1;
    ice->direct_mode = 1;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_ice_init(exteria_tgc_ice *ice, int controlling, uint64_t tie_breaker, const char *local_ufrag, const char *local_pwd,
                                    const exteria_tgc_ice_reflector_config *reflectors, size_t reflector_count, const exteria_tgc_ice_events *events) {
    size_t i;
    if (!ice) return EXTERIA_E_ARG;
    memset(ice, 0, sizeof(*ice));
    if (!reflectors || !events || !events->send || reflector_count == 0 || reflector_count > EXTERIA_TGC_ICE_MAX_REFLECTORS) return EXTERIA_E_ARG;
    if (!credentials_ok(local_ufrag, 4, EXTERIA_TGC_ICE_UFRAG_MAX - 1) || !credentials_ok(local_pwd, 22, EXTERIA_TGC_ICE_PWD_MAX - 1)) return EXTERIA_E_ARG;
    for (i = 0; i < reflector_count; ++i) {
        exteria_tgc_ice_reflector *r = &ice->reflectors[i];
        r->config = reflectors[i];
        if (r->config.port == 0 || exteria_tgc_reflector_init(&r->wire, r->config.server_id, r->config.peer_tag, r->config.local_tag, r->config.tcp) != EXTERIA_OK) {
            memset(ice, 0, sizeof(*ice));
            return EXTERIA_E_ARG;
        }
    }
    ice->events = *events;
    ice->controlling = controlling ? 1 : 0;
    ice->tie_breaker = tie_breaker;
    memcpy(ice->local_ufrag, local_ufrag, strlen(local_ufrag) + 1);
    memcpy(ice->local_pwd, local_pwd, strlen(local_pwd) + 1);
    ice->reflector_count = (uint8_t)reflector_count;
    ice->selected = -1;
    ice->state = EXTERIA_TGC_ICE_NEW;
    return EXTERIA_OK;
}

static void turn_send(void *context, const uint8_t *data, size_t len) {
    exteria_tgc_ice_turn_link *link = (exteria_tgc_ice_turn_link *)context;
    link->ice->events.send(link->ice->events.context, link->ice->reflector_count + link->index, data, len);
}

static void turn_trace(void *context, const char *line) {
    exteria_tgc_ice_turn_link *link = (exteria_tgc_ice_turn_link *)context;
    trace(link->ice, "turn %u: %s", link->index, line);
}

exteria_status exteria_tgc_ice_add_turn(exteria_tgc_ice *ice, uint32_t ip, uint16_t port, const char *username, const char *password) {
    exteria_tgc_turn_events events;
    unsigned index;
    if (!ice || ice->reflector_count == 0) return EXTERIA_E_ARG;
    if (ice->turn_count >= EXTERIA_TGC_ICE_MAX_TURNS) return EXTERIA_E_LIMIT;
    index = ice->turn_count;
    ice->turn_links[index].ice = ice;
    ice->turn_links[index].index = index;
    events.context = &ice->turn_links[index];
    events.send = turn_send;
    events.trace = turn_trace;
    if (exteria_tgc_turn_init(&ice->turns[index], ip, port, username, password, &events) != EXTERIA_OK) return EXTERIA_E_ARG;
    ++ice->turn_count;
    return EXTERIA_OK;
}

exteria_status exteria_tgc_ice_set_remote(exteria_tgc_ice *ice, const char *ufrag, const char *pwd) {
    if (!ice) return EXTERIA_E_ARG;
    if (!credentials_ok(ufrag, 4, EXTERIA_TGC_ICE_UFRAG_MAX - 1) || !credentials_ok(pwd, 22, EXTERIA_TGC_ICE_PWD_MAX - 1)) return EXTERIA_E_MALFORMED;
    if (ice->has_remote) return strcmp(ice->remote_ufrag, ufrag) == 0 && strcmp(ice->remote_pwd, pwd) == 0 ? EXTERIA_OK : EXTERIA_E_STATE;
    memcpy(ice->remote_ufrag, ufrag, strlen(ufrag) + 1);
    memcpy(ice->remote_pwd, pwd, strlen(pwd) + 1);
    ice->has_remote = 1;
    return EXTERIA_OK;
}

static void set_state(exteria_tgc_ice *ice, exteria_tgc_ice_state state) {
    if (ice->state == state) return;
    trace(ice, "ice state %d -> %d", (int)ice->state, (int)state);
    ice->state = state;
    if (ice->events.state) ice->events.state(ice->events.context, state);
}

static exteria_tgc_ice_pair *find_pair(exteria_tgc_ice *ice, const path *s) {
    int i;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        if (ice->pairs[i].used && same_path(&ice->pairs[i], s)) return &ice->pairs[i];
    }
    return NULL;
}

static exteria_tgc_ice_pair *add_pair(exteria_tgc_ice *ice, const path *s, uint32_t priority) {
    int i;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        if (!ice->pairs[i].used) {
            exteria_tgc_ice_pair *p = &ice->pairs[i];
            char text[80];
            memset(p, 0, sizeof(*p));
            p->used = 1;
            p->turn = s->turn;
            if (s->turn) {
                p->server = s->server;
                p->remote_ip = s->ip;
                p->remote_port = s->port;
            } else {
                p->reflector = s->server;
                p->remote_tag = s->tag;
            }
            p->remote_priority = priority;
            describe(s, text, sizeof(text));
            trace(ice, "ice pair: %s", text);
            return p;
        }
    }
    return NULL;
}

exteria_status exteria_tgc_ice_add_direct(exteria_tgc_ice *ice, uint32_t ip, uint16_t port, uint32_t priority, unsigned *index) {
    path s;
    exteria_tgc_ice_pair *pair;
    if (index) *index = 0;
    if (!ice || !ice->direct_mode || !index || !ip || !port) return EXTERIA_E_ARG;
    memset(&s, 0, sizeof(s));
    s.turn = 2;
    s.ip = ip;
    s.port = port;
    pair = find_pair(ice, &s);
    if (!pair) pair = add_pair(ice, &s, priority);
    if (!pair) return EXTERIA_E_LIMIT;
    *index = (unsigned)(pair - ice->pairs);
    pair->server = (uint8_t)*index;
    return EXTERIA_OK;
}

/* the fields of "candidate:F 1 udp P a.b.c.d PORT typ T ...", for the kinds this agent can reach through TURN; 0
   for anything else */
static int parse_ip_candidate(const char *sdp, uint32_t *ip, uint16_t *port, uint32_t *priority) {
    unsigned long prio, p, a, b, c, d, comp;
    char proto[8], type[12], found[40];
    int n = 0;
    const char *text = strstr(sdp, "candidate:");
    if (!text) return 0;
    text += 10;
    if (sscanf(text, "%39s %lu %7s %lu %lu.%lu.%lu.%lu %lu typ %11s%n", found, &comp, proto, &prio, &a, &b, &c, &d, &p, type, &n) != 10) return 0;
    if (comp != 1 || (strcmp(proto, "udp") != 0 && strcmp(proto, "UDP") != 0)) return 0;
    if (a > 255 || b > 255 || c > 255 || d > 255 || p == 0 || p > 65535 || prio > 0xFFFFFFFFul) return 0;
    if (strcmp(type, "host") != 0 && strcmp(type, "srflx") != 0 && strcmp(type, "prflx") != 0 && strcmp(type, "relay") != 0) return 0;
    *ip = (uint32_t)(a << 24 | b << 16 | c << 8 | d);
    *port = (uint16_t)p;
    *priority = (uint32_t)prio;
    return 1;
}

exteria_status exteria_tgc_ice_add_remote_candidate(exteria_tgc_ice *ice, const char *sdp, uint64_t now_ms) {
    uint8_t server_id;
    uint32_t tag, priority, ip;
    uint16_t port;
    unsigned i;
    exteria_status status;
    (void)now_ms;
    if (!ice || !sdp) return EXTERIA_E_ARG;
    status = exteria_tgc_reflector_parse_candidate(sdp, &server_id, &tag, &port, &priority);
    if (status != EXTERIA_OK) {
        /* not a reflector candidate: one that a TURN allocation of ours can send to is paired with each of them */
        if (parse_ip_candidate(sdp, &ip, &port, &priority) && routable(ip) && ice->turn_count > 0) {
            trace(ice, "ice remote candidate through turn: %.70s", sdp);
            for (i = 0; i < ice->turn_count; ++i) {
                path s;
                memset(&s, 0, sizeof(s));
                s.turn = 1;
                s.server = (uint8_t)i;
                s.ip = ip;
                s.port = port;
                if (find_pair(ice, &s)) continue;
                add_pair(ice, &s, priority);
                (void)exteria_tgc_turn_permit(&ice->turns[i], ip);
            }
            return EXTERIA_OK;
        }
        trace(ice, "ice remote candidate of another kind: %.60s", sdp);
        if (strstr(sdp, " typ host") || strstr(sdp, " typ srflx") || strstr(sdp, " typ prflx") || (strstr(sdp, " typ relay") && !strstr(sdp, ".reflector"))) return EXTERIA_E_UNSUPPORTED;
        return EXTERIA_E_MALFORMED;
    }
    trace(ice, "ice remote candidate: reflector id %u tag %lu port %u", (unsigned)server_id, (unsigned long)tag, (unsigned)port);
    for (i = 0; i < ice->reflector_count; ++i) {
        const exteria_tgc_ice_reflector *r = &ice->reflectors[i];
        path s;
        if (r->config.server_id != server_id || r->config.port != port) continue;
        memset(&s, 0, sizeof(s));
        s.server = (uint8_t)i;
        s.tag = tag;
        if (find_pair(ice, &s)) continue;
        add_pair(ice, &s, priority);
    }
    return EXTERIA_OK;
}

static void put_mapped(exteria_stun *m, const exteria_tgc_ice *ice, const path *src) {
    m->has_mapped = 1;
    if (src->turn) {
        /* the address the check came from, as any binding answer names it */
        m->mapped_ipv6 = 0;
        m->mapped_port = src->port;
        memset(m->mapped_address, 0, sizeof(m->mapped_address));
        m->mapped_address[0] = (uint8_t)(src->ip >> 24);
        m->mapped_address[1] = (uint8_t)(src->ip >> 16);
        m->mapped_address[2] = (uint8_t)(src->ip >> 8);
        m->mapped_address[3] = (uint8_t)src->ip;
        return;
    }
    m->mapped_ipv6 = ice->reflectors[src->server].config.ipv6;
    m->mapped_port = ice->reflectors[src->server].config.port;
    memcpy(m->mapped_address, ice->reflectors[src->server].config.address, sizeof(m->mapped_address));
}

static void transmit(exteria_tgc_ice *ice, unsigned reflector, uint32_t remote_tag, const uint8_t *payload, size_t len) {
    uint8_t out[EXTERIA_TGC_REFLECTOR_MAX_DATAGRAM];
    size_t n = 0;
    if (exteria_tgc_reflector_wrap(&ice->reflectors[reflector].wire, remote_tag, payload, len, out, sizeof(out), &n) != EXTERIA_OK) return;
    ice->events.send(ice->events.context, reflector, out, n);
}

static void turn_transmit(exteria_tgc_ice *ice, unsigned server, uint32_t ip, uint16_t port, const uint8_t *payload, size_t len) {
    uint8_t out[EXTERIA_TGC_TURN_MAX_PAYLOAD + EXTERIA_TGC_TURN_WRAP_OVERHEAD + 8];
    size_t n = 0;
    if (exteria_tgc_turn_wrap(&ice->turns[server], ip, port, payload, len, out, sizeof(out), &n) != EXTERIA_OK) return;
    ice->events.send(ice->events.context, ice->reflector_count + server, out, n);
}

static void transmit_path(exteria_tgc_ice *ice, const path *s, const uint8_t *payload, size_t len) {
    if (s->turn == 2) ice->events.send(ice->events.context, s->server, payload, len);
    else if (s->turn) turn_transmit(ice, s->server, s->ip, s->port, payload, len);
    else transmit(ice, s->server, s->tag, payload, len);
}

/* a pair can carry a check once its server is ready: a reflector that answered, a TURN allocation that has the permission for the other phone's address */
static int path_ready(exteria_tgc_ice *ice, const path *s) {
    if (s->turn == 2) return 1;
    if (!s->turn) return ice->reflectors[s->server].wire.ready;
    return exteria_tgc_turn_permit(&ice->turns[s->server], s->ip) == 1;
}

static void send_stun(exteria_tgc_ice *ice, const path *s, const exteria_stun *m, const char *key) {
    uint8_t buf[EXTERIA_STUN_MAX_MESSAGE];
    size_t n = 0;
    if (exteria_stun_write(m, (const uint8_t *)key, strlen(key), 1, buf, sizeof(buf), &n) != EXTERIA_OK) return;
    transmit_path(ice, s, buf, n);
}

static void send_check(exteria_tgc_ice *ice, exteria_tgc_ice_pair *p, int nominate, uint64_t now_ms, int retransmit) {
    exteria_stun m;
    path s = path_of(p);
    memset(&m, 0, sizeof(m));
    m.type = EXTERIA_STUN_BINDING_REQUEST;
    if (!retransmit || !p->outstanding) {
        if (exteria_random(p->txid, sizeof(p->txid)) != EXTERIA_OK) return;
        p->tries = 0;
        p->outstanding_nominating = nominate ? 1 : 0;
    }
    memcpy(m.txid, p->txid, sizeof(m.txid));
    m.has_username = 1;
    snprintf(m.username, sizeof(m.username), "%s:%s", ice->remote_ufrag, ice->local_ufrag);
    m.has_priority = 1;
    m.priority = CHECK_PRIORITY;
    if (ice->controlling) {
        m.has_controlling = 1;
        m.controlling = ice->tie_breaker;
        m.use_candidate = p->outstanding_nominating;
    } else {
        m.has_controlled = 1;
        m.controlled = ice->tie_breaker;
    }
    p->outstanding = 1;
    p->state = 1;
    p->triggered = 0;
    p->last_tx_ms = now_ms;
    ++p->tries;
    if (p->tries == 1 || p->tries == 4) {
        char text[80];
        describe(&s, text, sizeof(text));
        trace(ice, "ice check %u to %s%s", (unsigned)p->tries, text, nominate ? " (nominating)" : "");
    }
    send_stun(ice, &s, &m, ice->remote_pwd);
}

static void select_pair(exteria_tgc_ice *ice, exteria_tgc_ice_pair *p, uint64_t now_ms) {
    int i;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) ice->pairs[i].nominated = 0;
    p->nominated = 1;
    p->last_rx_ms = now_ms;
    ice->selected = (int)(p - ice->pairs);
    {
        path s = path_of(p);
        char text[80];
        describe(&s, text, sizeof(text));
        trace(ice, "ice selected pair: %s", text);
    }
    set_state(ice, EXTERIA_TGC_ICE_CONNECTED);
}

static void handle_request(exteria_tgc_ice *ice, const path *src, const uint8_t *data, size_t len, const exteria_stun *m, uint64_t now_ms) {
    char expected[EXTERIA_TGC_ICE_UFRAG_MAX * 2 + 2];
    exteria_stun answer;
    exteria_tgc_ice_pair *p;
    if (!ice->has_remote) return;
    snprintf(expected, sizeof(expected), "%s:%s", ice->local_ufrag, ice->remote_ufrag);
    if (!m->has_username || strcmp(m->username, expected) != 0) {
        if (++ice->rejected_stun <= 5) trace(ice, "ice request refused: username %s, expected %s", m->has_username ? m->username : "(none)", expected);
        return;
    }
    if (exteria_stun_check_integrity(data, len, m, (const uint8_t *)ice->local_pwd, strlen(ice->local_pwd)) != EXTERIA_OK) {
        if (++ice->rejected_stun <= 5) trace(ice, "ice request refused: integrity does not match");
        return;
    }
    if (m->fingerprint_offset && exteria_stun_check_fingerprint(data, len, m) != EXTERIA_OK) return;

    memset(&answer, 0, sizeof(answer));
    memcpy(answer.txid, m->txid, sizeof(answer.txid));
    /* a role conflict is settled by the tie breakers (RFC 8445 section 7.3.1.1): the larger one keeps its role and the other gives it up */
    if ((ice->controlling && m->has_controlling) || (!ice->controlling && m->has_controlled)) {
        uint64_t theirs = ice->controlling ? m->controlling : m->controlled;
        int keep = ice->controlling ? ice->tie_breaker >= theirs : ice->tie_breaker < theirs;
        if (keep) {
            answer.type = EXTERIA_STUN_BINDING_ERROR;
            answer.has_error = 1;
            answer.error_code = EXTERIA_STUN_ERROR_ROLE_CONFLICT;
            send_stun(ice, src, &answer, ice->local_pwd);
            return;
        }
        ice->controlling = ice->controlling ? 0 : 1;
        trace(ice, "ice role is now %s", ice->controlling ? "controlling" : "controlled");
    }
    p = find_pair(ice, src);
    if (!p) p = add_pair(ice, src, m->has_priority ? m->priority : PEER_REFLEXIVE_DEFAULT_PRIORITY);
    if (!p) return;
    answer.type = EXTERIA_STUN_BINDING_SUCCESS;
    put_mapped(&answer, ice, src);
    send_stun(ice, src, &answer, ice->local_pwd);
    if (p->last_rx_ms == 0) {
        char text[80];
        describe(src, text, sizeof(text));
        trace(ice, "ice first check from %s answered", text);
    }
    p->last_rx_ms = now_ms;
    if (p->state == 0) p->triggered = 1;
    if (m->use_candidate && !ice->controlling) {
        p->nominate_wanted = 1;
        if (p->valid) select_pair(ice, p, now_ms);
        else p->triggered = 1;
    }
    if (ice->state == EXTERIA_TGC_ICE_DISCONNECTED && ice->selected >= 0 && &ice->pairs[ice->selected] == p) set_state(ice, EXTERIA_TGC_ICE_CONNECTED);
}

static void handle_response(exteria_tgc_ice *ice, const path *src, const uint8_t *data, size_t len, const exteria_stun *m, uint64_t now_ms) {
    int i;
    exteria_tgc_ice_pair *p = NULL;
    if (!ice->has_remote) return;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        if (ice->pairs[i].used && ice->pairs[i].outstanding && same_path(&ice->pairs[i], src) &&
            memcmp(ice->pairs[i].txid, m->txid, sizeof(m->txid)) == 0) {
            p = &ice->pairs[i];
            break;
        }
    }
    if (!p) return;
    if (exteria_stun_check_integrity(data, len, m, (const uint8_t *)ice->remote_pwd, strlen(ice->remote_pwd)) != EXTERIA_OK) {
        if (++ice->rejected_stun <= 5) trace(ice, "ice response refused: integrity does not match");
        return;
    }
    if (m->fingerprint_offset && exteria_stun_check_fingerprint(data, len, m) != EXTERIA_OK) return;
    if (!p->valid) {
        path s = path_of(p);
        char text[80];
        describe(&s, text, sizeof(text));
        trace(ice, "ice check answered: %s (%s)", text, m->type == EXTERIA_STUN_BINDING_ERROR ? "error" : "success");
    }
    p->outstanding = 0;
    p->last_rx_ms = now_ms;
    if (m->type == EXTERIA_STUN_BINDING_ERROR) {
        if (m->has_error && m->error_code == EXTERIA_STUN_ERROR_ROLE_CONFLICT) {
            ice->controlling = ice->controlling ? 0 : 1;
            p->state = 0;
            p->triggered = 1;
        }
        return;
    }
    p->state = 2;
    p->valid = 1;
    p->tries = 0;
    if (p->outstanding_nominating) {
        select_pair(ice, p, now_ms);
        return;
    }
    if (ice->controlling) {
        int any = 0;
        for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) any |= ice->pairs[i].used && ice->pairs[i].nominated;
        if (!any) {
            p->nominate_wanted = 1;
            p->triggered = 1;
        }
    } else if (p->nominate_wanted) {
        select_pair(ice, p, now_ms);
    }
}

/* a datagram that came on a path: STUN is the agent's own, anything else comes from a pair whose STUN has been authenticated, or it is not delivered */
static exteria_status handle_payload(exteria_tgc_ice *ice, const path *src, const uint8_t *payload, size_t plen, uint64_t now_ms) {
    exteria_stun m;
    exteria_tgc_ice_pair *p;
    if (exteria_stun_looks_like(payload, plen)) {
        if (exteria_stun_parse(payload, plen, &m) != EXTERIA_OK) return EXTERIA_E_MALFORMED;
        if (m.type == EXTERIA_STUN_BINDING_REQUEST) handle_request(ice, src, payload, plen, &m, now_ms);
        else if (m.type == EXTERIA_STUN_BINDING_SUCCESS || m.type == EXTERIA_STUN_BINDING_ERROR) handle_response(ice, src, payload, plen, &m, now_ms);
        return EXTERIA_OK;
    }
    p = find_pair(ice, src);
    if (!p || p->last_rx_ms == 0) return EXTERIA_OK;
    p->last_rx_ms = now_ms;
    if (ice->state == EXTERIA_TGC_ICE_DISCONNECTED && p->nominated) set_state(ice, EXTERIA_TGC_ICE_CONNECTED);
    if (ice->events.payload) ice->events.payload(ice->events.context, payload, plen);
    return EXTERIA_OK;
}

exteria_status exteria_tgc_ice_input(exteria_tgc_ice *ice, unsigned index, const uint8_t *data, size_t len, uint64_t now_ms) {
    uint32_t tag = 0;
    const uint8_t *payload = NULL;
    size_t plen = 0;
    exteria_status status;
    path src;
    if (!ice || !data) return EXTERIA_E_ARG;
    memset(&src, 0, sizeof(src));
    if (ice->direct_mode) {
        const exteria_tgc_ice_pair *pair;
        if (index >= EXTERIA_TGC_ICE_MAX_PAIRS || !ice->pairs[index].used || ice->pairs[index].turn != 2) return EXTERIA_E_ARG;
        pair = &ice->pairs[index];
        src = path_of(pair);
        return handle_payload(ice, &src, data, len, now_ms);
    }
    if (index >= ice->reflector_count) {
        unsigned server = index - ice->reflector_count;
        exteria_tgc_turn_output out;
        if (server >= ice->turn_count) return EXTERIA_E_ARG;
        status = exteria_tgc_turn_input(&ice->turns[server], data, len, now_ms, &out);
        if (status != EXTERIA_OK || out.kind != EXTERIA_TGC_TURN_INPUT_DATA) return status;
        src.turn = 1;
        src.server = (uint8_t)server;
        src.ip = out.peer_ip;
        src.port = out.peer_port;
        return handle_payload(ice, &src, out.data, out.len, now_ms);
    }
    status = exteria_tgc_reflector_unwrap(&ice->reflectors[index].wire, data, len, &tag, &payload, &plen);
    if (status != EXTERIA_OK) return status;
    if (!payload) return EXTERIA_OK;
    src.server = (uint8_t)index;
    src.tag = tag;
    return handle_payload(ice, &src, payload, plen, now_ms);
}

static uint64_t rto_ms(const exteria_tgc_ice_pair *p) {
    unsigned shift = p->tries > 0 ? (unsigned)p->tries - 1 : 0;
    if (shift > RTO_MAX_SHIFT) shift = RTO_MAX_SHIFT;
    return (uint64_t)RTO_BASE_MS << shift;
}

static void send_hellos(exteria_tgc_ice *ice, uint64_t now_ms) {
    unsigned i;
    for (i = 0; i < ice->reflector_count; ++i) {
        exteria_tgc_ice_reflector *r = &ice->reflectors[i];
        uint8_t hello[EXTERIA_TGC_REFLECTOR_HELLO_UDP_LEN];
        size_t n = 0;
        uint64_t every = r->wire.ready ? EXTERIA_TGC_ICE_HELLO_SLOW_MS : EXTERIA_TGC_ICE_HELLO_FAST_MS;
        if (r->hello_sent && now_ms - r->last_hello_ms < every) continue;
        if (exteria_tgc_reflector_hello(&r->wire, hello, sizeof(hello), &n) != EXTERIA_OK) continue;
        r->hello_sent = 1;
        r->last_hello_ms = now_ms;
        ice->events.send(ice->events.context, i, hello, n);
    }
}

static void announce_candidates(exteria_tgc_ice *ice) {
    unsigned i;
    for (i = 0; i < ice->reflector_count; ++i) {
        exteria_tgc_ice_reflector *r = &ice->reflectors[i];
        char sdp[256];
        if (!r->wire.ready || r->announced) continue;
        if (exteria_tgc_reflector_candidate_sdp(&r->wire, r->config.port, EXTERIA_TGC_ICE_LOCAL_PRIORITY, ice->local_ufrag, sdp, sizeof(sdp)) != EXTERIA_OK) continue;
        r->announced = 1;
        trace(ice, "ice reflector %u (id %u) answered, candidate announced", i, (unsigned)r->config.server_id);
        if (ice->events.local_candidate) ice->events.local_candidate(ice->events.context, sdp);
    }
}

static void announce_turns(exteria_tgc_ice *ice) {
    unsigned i;
    for (i = 0; i < ice->turn_count; ++i) {
        uint32_t relay_ip, mapped_ip;
        uint16_t relay_port, mapped_port;
        char sdp[256];
        if (ice->turn_announced[i] || !exteria_tgc_turn_relayed(&ice->turns[i], &relay_ip, &relay_port, &mapped_ip, &mapped_port)) continue;
        snprintf(sdp, sizeof(sdp), "candidate:%lu 1 udp %lu %u.%u.%u.%u %u typ relay raddr %u.%u.%u.%u rport %u generation 0 ufrag %s network-id 1 network-cost 10",
                 (unsigned long)(1000u + 7u * i + (relay_ip & 0xFFFFu)), (unsigned long)(EXTERIA_TGC_ICE_LOCAL_PRIORITY - 256u * (i + 1u)),
                 (unsigned)(relay_ip >> 24), (unsigned)(relay_ip >> 16 & 255), (unsigned)(relay_ip >> 8 & 255), (unsigned)(relay_ip & 255), (unsigned)relay_port,
                 (unsigned)(mapped_ip >> 24), (unsigned)(mapped_ip >> 16 & 255), (unsigned)(mapped_ip >> 8 & 255), (unsigned)(mapped_ip & 255), (unsigned)mapped_port,
                 ice->local_ufrag);
        ice->turn_announced[i] = 1;
        trace(ice, "ice turn %u allocated, relay candidate announced", i);
        if (ice->events.local_candidate) ice->events.local_candidate(ice->events.context, sdp);
    }
}

static exteria_tgc_ice_pair *next_check(exteria_tgc_ice *ice, uint64_t now_ms, int *retransmit) {
    int i;
    exteria_tgc_ice_pair *best = NULL;
    *retransmit = 0;
    /* triggered checks first (a check of the other phone just reached this pair), then the highest priority waiting pair, then a retransmission that is due */
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        exteria_tgc_ice_pair *p = &ice->pairs[i];
        path s = path_of(p);
        if (p->used && p->triggered && !p->outstanding && path_ready(ice, &s)) return p;
    }
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        exteria_tgc_ice_pair *p = &ice->pairs[i];
        path s = path_of(p);
        if (!p->used || p->state != 0 || p->outstanding || !path_ready(ice, &s)) continue;
        if (p->gave_up_ms && now_ms - p->gave_up_ms < RETRY_AFTER_GIVE_UP_MS) continue;
        if (!best || p->remote_priority > best->remote_priority) best = p;
    }
    if (best) return best;
    for (i = 0; i < EXTERIA_TGC_ICE_MAX_PAIRS; ++i) {
        exteria_tgc_ice_pair *p = &ice->pairs[i];
        if (p->used && p->outstanding && now_ms - p->last_tx_ms >= rto_ms(p)) {
            *retransmit = 1;
            return p;
        }
    }
    return NULL;
}

void exteria_tgc_ice_tick(exteria_tgc_ice *ice, uint64_t now_ms) {
    exteria_tgc_ice_pair *p;
    int retransmit;
    unsigned i;
    if (!ice) return;
    if (!ice->started) {
        ice->started = 1;
        ice->last_check_ms = now_ms;
    }
    send_hellos(ice, now_ms);
    for (i = 0; i < ice->turn_count; ++i) exteria_tgc_turn_tick(&ice->turns[i], now_ms);
    announce_candidates(ice);
    announce_turns(ice);
    if (!ice->has_remote) return;
    if (now_ms - ice->last_check_ms >= CHECK_PACING_MS) {
        p = next_check(ice, now_ms, &retransmit);
        if (p) {
            if (retransmit && p->tries >= MAX_TRIES) {
                p->outstanding = 0;
                p->state = 0;
                p->tries = 0;
                p->gave_up_ms = now_ms;
            } else {
                if (ice->state == EXTERIA_TGC_ICE_NEW) set_state(ice, EXTERIA_TGC_ICE_CHECKING);
                send_check(ice, p, ice->controlling && p->nominate_wanted, now_ms, retransmit);
                ice->last_check_ms = now_ms;
            }
        }
    }
    if (ice->selected >= 0) {
        exteria_tgc_ice_pair *s = &ice->pairs[ice->selected];
        if (!s->outstanding && now_ms - s->last_tx_ms >= EXTERIA_TGC_ICE_KEEPALIVE_MS) {
            s->nominate_wanted = ice->controlling ? 1 : s->nominate_wanted;
            send_check(ice, s, ice->controlling, now_ms, 0);
        }
        if (ice->state == EXTERIA_TGC_ICE_CONNECTED && now_ms - s->last_rx_ms >= EXTERIA_TGC_ICE_SILENCE_MS) set_state(ice, EXTERIA_TGC_ICE_DISCONNECTED);
    }
}

exteria_status exteria_tgc_ice_send(exteria_tgc_ice *ice, const uint8_t *data, size_t len) {
    const exteria_tgc_ice_pair *p;
    if (!ice || !data) return EXTERIA_E_ARG;
    if (ice->selected < 0) return EXTERIA_E_STATE;
    p = &ice->pairs[ice->selected];
    {
        path s = path_of(p);
        transmit_path(ice, &s, data, len);
    }
    return EXTERIA_OK;
}

int exteria_tgc_ice_selected(const exteria_tgc_ice *ice, unsigned *reflector, uint32_t *remote_tag) {
    if (!ice || ice->selected < 0) return 0;
    if (reflector) *reflector = ice->pairs[ice->selected].turn ? ice->reflector_count + ice->pairs[ice->selected].server : ice->pairs[ice->selected].reflector;
    if (remote_tag) *remote_tag = ice->pairs[ice->selected].turn ? ice->pairs[ice->selected].remote_ip : ice->pairs[ice->selected].remote_tag;
    return 1;
}
