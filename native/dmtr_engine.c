/*
 * DroidMTR native probe engine
 *
 * Copyright (C) 2026 DroidMTR contributors
 * Licensed under the GNU General Public License version 2.
 */

#define _GNU_SOURCE

#include "dmtr_engine.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/errqueue.h>
#include <math.h>
#include <netdb.h>
#include <netinet/icmp6.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifndef IP_RECVERR
#define IP_RECVERR 11
#endif
#ifndef IPV6_RECVERR
#define IPV6_RECVERR 25
#endif
#ifndef MSG_ERRQUEUE
#define MSG_ERRQUEUE 0x2000
#endif
#ifndef SO_EE_OFFENDER
#define SO_EE_OFFENDER(ee) ((struct sockaddr *)((ee) + 1))
#endif
#ifndef ICMP6_ECHO_REQUEST
#define ICMP6_ECHO_REQUEST 128
#endif
#ifndef ICMP6_ECHO_REPLY
#define ICMP6_ECHO_REPLY 129
#endif
#ifndef ICMP6_DST_UNREACH
#define ICMP6_DST_UNREACH 1
#endif
#ifndef ICMP6_PACKET_TOO_BIG
#define ICMP6_PACKET_TOO_BIG 2
#endif
#ifndef ICMP6_TIME_EXCEEDED
#define ICMP6_TIME_EXCEEDED 3
#endif

#define MAX_PROBES_PER_HOP 128
#define MAX_PACKET_PAYLOAD 1400
#define MIN_PACKET_PAYLOAD 8
#define POLL_SLICE_MS 25

typedef struct {
    int used;
    uint16_t seq;
    uint16_t dest_port;
    uint64_t sent_ns;
} ProbeSlot;

typedef struct {
    uint32_t ttl;
    uint32_t sent;
    uint32_t recv;
    uint32_t lost;
    uint32_t pending;
    uint32_t flags;

    int32_t last_us;
    int32_t best_us;
    int32_t avg_us;
    int32_t worst_us;
    int32_t stdev_us;
    int32_t jitter_us;
    int32_t jitter_avg_us;
    int32_t jitter_worst_us;

    int32_t error_type;
    int32_t error_code;

    char addr[DMTR_ADDR_LEN];
    char alts[DMTR_MAX_ALT][DMTR_ADDR_LEN];
    uint32_t alt_count;

    int32_t samples[DMTR_MAX_SAMPLES];
    uint32_t sample_total;
    uint32_t sample_head;

    double avg_d;
    double ssd_d;
    double jitter_avg_d;
    uint32_t jitter_count;
    int32_t last_sample_us;
    int have_sample;

    ProbeSlot probes[MAX_PROBES_PER_HOP];
    int fd;
} Hop;

typedef struct {
    pthread_mutex_t lock;
    pthread_t thread;
    atomic_int stop_requested;
    int thread_started;
    int valid;
    int running;

    int mode; /* actual */
    int requested_mode;
    int family;
    int af;
    int max_hops;
    int interval_ms;
    int timeout_ms;
    int payload_bytes;

    char target[DMTR_ADDR_LEN];
    struct sockaddr_storage dst;
    socklen_t dst_len;

    Hop hops[DMTR_MAX_HOPS];
    uint32_t hop_count;
    int reached;
    int reached_ttl;
    int scan_ttl;
    int prune_hidden;

    uint32_t next_seq;
    uint64_t started_ns;
    uint64_t stopped_ns;
    uint64_t next_send_ns;

    uint32_t total_sent;
    uint32_t total_recv;
    uint32_t total_lost;

    int last_errno;
    int error_type;
    int error_code;
    char error[DMTR_ERROR_LEN];
} Engine;

static Engine g_engine = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .thread_started = 0,
    .valid = 0,
    .running = 0,
};

static uint64_t now_ns(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
        return 0;
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void copy_str(char *dst, size_t dst_len, const char *src)
{
    if (dst_len == 0)
        return;
    if (src == NULL)
        src = "";
    size_t n = strlen(src);
    if (n >= dst_len)
        n = dst_len - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

static void set_engine_error(const char *message, int err)
{
    copy_str(g_engine.error, sizeof(g_engine.error), message ? message : "network error");
    g_engine.last_errno = err;
    g_engine.error_type = 0;
    g_engine.error_code = err;
}

static void set_engine_errno(const char *prefix)
{
    char buf[DMTR_ERROR_LEN];
    snprintf(buf, sizeof(buf), "%s: %s", prefix, strerror(errno));
    set_engine_error(buf, errno);
}

static int is_v4(void)
{
    return g_engine.family == 4;
}

static int is_same_addr(const struct sockaddr *a, const struct sockaddr *b)
{
    if (a == NULL || b == NULL)
        return 0;
    if (a->sa_family != b->sa_family)
        return 0;
    if (a->sa_family == AF_INET) {
        const struct sockaddr_in *aa = (const struct sockaddr_in *)a;
        const struct sockaddr_in *bb = (const struct sockaddr_in *)b;
        return memcmp(&aa->sin_addr, &bb->sin_addr, sizeof(aa->sin_addr)) == 0;
    }
    if (a->sa_family == AF_INET6) {
        const struct sockaddr_in6 *aa = (const struct sockaddr_in6 *)a;
        const struct sockaddr_in6 *bb = (const struct sockaddr_in6 *)b;
        return memcmp(&aa->sin6_addr, &bb->sin6_addr, sizeof(aa->sin6_addr)) == 0;
    }
    return 0;
}

static int sockaddr_to_text(const struct sockaddr *sa, char *buf, size_t len)
{
    if (sa == NULL || len == 0)
        return -1;
    const void *src = NULL;
    if (sa->sa_family == AF_INET)
        src = &((const struct sockaddr_in *)sa)->sin_addr;
    else if (sa->sa_family == AF_INET6)
        src = &((const struct sockaddr_in6 *)sa)->sin6_addr;
    if (src == NULL || inet_ntop(sa->sa_family, src, buf, (socklen_t)len) == NULL)
        return -1;
    return 0;
}

static Hop *get_hop(uint32_t ttl)
{
    if (ttl < 1 || ttl > DMTR_MAX_HOPS)
        return NULL;
    Hop *hop = &g_engine.hops[ttl - 1];
    hop->ttl = ttl;
    if (hop->fd == 0)
        hop->fd = -1;
    return hop;
}

static void remember_address(Hop *hop, const char *addr)
{
    if (addr == NULL || addr[0] == '\0')
        return;
    if (hop->addr[0] == '\0') {
        copy_str(hop->addr, sizeof(hop->addr), addr);
        return;
    }
    if (strcmp(hop->addr, addr) == 0)
        return;
    for (uint32_t i = 0; i < hop->alt_count; i++) {
        if (strcmp(hop->alts[i], addr) == 0) {
            copy_str(hop->addr, sizeof(hop->addr), addr);
            return;
        }
    }
    if (hop->alt_count < DMTR_MAX_ALT) {
        copy_str(hop->alts[hop->alt_count], DMTR_ADDR_LEN, addr);
        hop->alt_count++;
    }
    copy_str(hop->addr, sizeof(hop->addr), addr);
}

static void append_sample(Hop *hop, int32_t value)
{
    hop->samples[hop->sample_head] = value;
    hop->sample_head = (hop->sample_head + 1U) % DMTR_MAX_SAMPLES;
    if (hop->sample_total < DMTR_MAX_SAMPLES)
        hop->sample_total++;
}

static void update_rtt(Hop *hop, int32_t rtt_us)
{
    if (rtt_us < 0)
        rtt_us = 0;

    hop->last_us = rtt_us;
    if (hop->recv == 0) {
        hop->best_us = rtt_us;
        hop->worst_us = rtt_us;
        hop->avg_d = (double)rtt_us;
        hop->ssd_d = 0.0;
        hop->avg_us = rtt_us;
    } else {
        if (rtt_us < hop->best_us)
            hop->best_us = rtt_us;
        if (rtt_us > hop->worst_us)
            hop->worst_us = rtt_us;
        double delta = (double)rtt_us - hop->avg_d;
        hop->avg_d += delta / (double)(hop->recv + 1U);
        hop->ssd_d += delta * ((double)rtt_us - hop->avg_d);
        hop->avg_us = (int32_t)llround(hop->avg_d);
        if (hop->recv > 0)
            hop->stdev_us = (int32_t)llround(sqrt(hop->ssd_d / (double)hop->recv));
    }

    if (hop->have_sample) {
        int32_t jitter = rtt_us - hop->last_sample_us;
        if (jitter < 0)
            jitter = -jitter;
        hop->jitter_us = jitter;
        if (jitter > hop->jitter_worst_us)
            hop->jitter_worst_us = jitter;
        hop->jitter_count++;
        hop->jitter_avg_d += ((double)jitter - hop->jitter_avg_d) /
                             (double)hop->jitter_count;
        hop->jitter_avg_us = (int32_t)llround(hop->jitter_avg_d);
    }
    hop->last_sample_us = rtt_us;
    hop->have_sample = 1;
    hop->recv++;
}

static void mark_response(uint32_t ttl, const struct sockaddr *from,
                          int32_t rtt_us, int is_destination,
                          int error_type, int error_code)
{
    Hop *hop = get_hop(ttl);
    if (hop == NULL)
        return;
    if (g_engine.reached && (int)ttl > g_engine.reached_ttl)
        return;

    char addr[DMTR_ADDR_LEN];
    if (sockaddr_to_text(from, addr, sizeof(addr)) == 0)
        remember_address(hop, addr);

    update_rtt(hop, rtt_us);
    append_sample(hop, rtt_us);
    hop->flags |= 1U; /* responded */
    g_engine.total_recv++;
    if (hop->pending > 0)
        hop->pending--;

    if (error_type > 0) {
        hop->error_type = error_type;
        hop->error_code = error_code;
        if (!(error_type == ICMP_TIME_EXCEEDED ||
              (!is_v4() && error_type == ICMP6_TIME_EXCEEDED))) {
            hop->flags |= 4U; /* error */
        }
    }

    if (is_destination) {
        hop->flags |= 2U; /* destination */
        if (!g_engine.reached || (int)ttl < g_engine.reached_ttl) {
            g_engine.reached = 1;
            g_engine.reached_ttl = (int)ttl;
        }
        g_engine.hop_count = (uint32_t)g_engine.reached_ttl;
        g_engine.scan_ttl = 1;
        g_engine.prune_hidden = 1;
    }
}

static void mark_timeout(Hop *hop)
{
    hop->lost++;
    if (hop->pending > 0)
        hop->pending--;
    g_engine.total_lost++;
    append_sample(hop, -1);
}

static ProbeSlot *find_slot_seq(Hop *hop, uint16_t seq)
{
    for (int i = 0; i < MAX_PROBES_PER_HOP; i++) {
        if (hop->probes[i].used && hop->probes[i].seq == seq)
            return &hop->probes[i];
    }
    return NULL;
}

static ProbeSlot *find_slot_port(Hop *hop, uint16_t port)
{
    for (int i = 0; i < MAX_PROBES_PER_HOP; i++) {
        if (hop->probes[i].used && hop->probes[i].dest_port == port)
            return &hop->probes[i];
    }
    return NULL;
}

static ProbeSlot *oldest_slot(Hop *hop)
{
    ProbeSlot *oldest = NULL;
    for (int i = 0; i < MAX_PROBES_PER_HOP; i++) {
        if (!hop->probes[i].used)
            continue;
        if (oldest == NULL || hop->probes[i].sent_ns < oldest->sent_ns)
            oldest = &hop->probes[i];
    }
    return oldest;
}

static ProbeSlot *free_slot(Hop *hop)
{
    for (int i = 0; i < MAX_PROBES_PER_HOP; i++) {
        if (!hop->probes[i].used)
            return &hop->probes[i];
    }
    return NULL;
}

static int create_hop_socket(Hop *hop)
{
    int af = g_engine.af;
    int fd;
    int one = 1;

    if (g_engine.mode == DMTR_MODE_ICMP)
        fd = socket(af, SOCK_DGRAM, is_v4() ? IPPROTO_ICMP : IPPROTO_ICMPV6);
    else
        fd = socket(af, SOCK_DGRAM, IPPROTO_UDP);

    if (fd < 0) {
        set_engine_errno(g_engine.mode == DMTR_MODE_ICMP
                             ? "ICMP socket unavailable"
                             : "UDP socket unavailable");
        return -1;
    }

    if (is_v4()) {
        if (setsockopt(fd, IPPROTO_IP, IP_RECVERR, &one, sizeof(one)) != 0) {
            set_engine_errno("IP_RECVERR unavailable");
            close(fd);
            return -1;
        }
        int ttl = (int)hop->ttl;
        if (setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl)) != 0) {
            set_engine_errno("could not set IP_TTL");
            close(fd);
            return -1;
        }
    } else {
        if (setsockopt(fd, IPPROTO_IPV6, IPV6_RECVERR, &one, sizeof(one)) != 0) {
            set_engine_errno("IPV6_RECVERR unavailable");
            close(fd);
            return -1;
        }
        int hops = (int)hop->ttl;
        if (setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &hops, sizeof(hops)) != 0) {
            set_engine_errno("could not set IPV6_UNICAST_HOPS");
            close(fd);
            return -1;
        }
    }

    int buf = 512 * 1024;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof(buf));
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    hop->fd = fd;
    return 0;
}

static int parse_embedded(const uint8_t *packet, int len, uint16_t *seq,
                          uint16_t *dest_port)
{
    if (packet == NULL || len < 8)
        return 0;

    int offset = 0;
    if ((packet[0] >> 4) == 4 && len >= 20) {
        int ihl = (packet[0] & 0x0f) * 4;
        if (ihl < 20 || ihl > len)
            return 0;
        offset = ihl;
    } else if ((packet[0] >> 4) == 6 && len >= 40) {
        offset = 40;
    }

    if (len < offset + 8)
        return 0;

    uint8_t type = packet[offset];
    if (type == ICMP_ECHO || type == ICMP_ECHOREPLY ||
        type == ICMP6_ECHO_REQUEST || type == ICMP6_ECHO_REPLY) {
        uint16_t s;
        memcpy(&s, packet + offset + 6, sizeof(s));
        *seq = ntohs(s);
        return 1;
    }

    /* UDP header: source port (2), destination port (2). */
    uint16_t d;
    memcpy(&d, packet + offset + 2, sizeof(d));
    *dest_port = ntohs(d);
    return 2;
}

typedef struct {
    int have;
    int type;
    int code;
    struct sockaddr_storage offender;
    socklen_t offender_len;
} ErrorInfo;

static void parse_error_cmsg(struct msghdr *msg, ErrorInfo *out)
{
    for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(msg); cmsg != NULL;
         cmsg = CMSG_NXTHDR(msg, cmsg)) {
        int wanted_level = is_v4() ? IPPROTO_IP : IPPROTO_IPV6;
        int wanted_type = is_v4() ? IP_RECVERR : IPV6_RECVERR;
        if (cmsg->cmsg_level != wanted_level || cmsg->cmsg_type != wanted_type)
            continue;

        const uint8_t *data = (const uint8_t *)CMSG_DATA(cmsg);
        size_t data_len = (size_t)cmsg->cmsg_len - CMSG_LEN(0);
        if (data_len < sizeof(struct sock_extended_err))
            break;

        struct sock_extended_err ee;
        memcpy(&ee, data, sizeof(ee));
        out->have = 1;
        out->type = ee.ee_type;
        out->code = ee.ee_code;

        if (data_len >= sizeof(ee) + sizeof(struct sockaddr_in)) {
            const struct sockaddr *offender =
                (const struct sockaddr *)(data + sizeof(ee));
            socklen_t len = 0;
            if (offender->sa_family == AF_INET)
                len = sizeof(struct sockaddr_in);
            else if (offender->sa_family == AF_INET6)
                len = sizeof(struct sockaddr_in6);
            if (len > 0 && data_len >= sizeof(ee) + (size_t)len) {
                memcpy(&out->offender, offender, len);
                out->offender_len = len;
            }
        }
        break;
    }
}

static void drain_errors(Hop *hop)
{
    for (;;) {
        uint8_t packet[2048];
        char control[512];
        struct sockaddr_storage source;
        memset(&source, 0, sizeof(source));
        struct iovec iov = {.iov_base = packet, .iov_len = sizeof(packet)};
        struct msghdr msg;
        memset(&msg, 0, sizeof(msg));
        msg.msg_name = &source;
        msg.msg_namelen = sizeof(source);
        msg.msg_iov = &iov;
        msg.msg_iovlen = 1;
        msg.msg_control = control;
        msg.msg_controllen = sizeof(control);

        ssize_t n = recvmsg(hop->fd, &msg, MSG_ERRQUEUE | MSG_DONTWAIT);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            break;
        }

        ErrorInfo info;
        memset(&info, 0, sizeof(info));
        parse_error_cmsg(&msg, &info);

        struct sockaddr_storage offender;
        memset(&offender, 0, sizeof(offender));
        socklen_t offender_len = 0;
        if (info.offender_len > 0) {
            memcpy(&offender, &info.offender, info.offender_len);
            offender_len = info.offender_len;
        } else if (msg.msg_namelen > 0 &&
                   source.ss_family != 0 && source.ss_family != AF_UNSPEC) {
            memcpy(&offender, &source, sizeof(source));
            offender_len = msg.msg_namelen;
        }
        if (offender_len == 0)
            continue;

        uint16_t seq = 0, dest_port = 0;
        int parsed = parse_embedded(packet, (int)n, &seq, &dest_port);
        ProbeSlot *slot = NULL;
        if (parsed == 1)
            slot = find_slot_seq(hop, seq);
        else if (parsed == 2)
            slot = find_slot_port(hop, dest_port);
        if (slot == NULL)
            slot = oldest_slot(hop);
        if (slot == NULL)
            continue;

        uint64_t now = now_ns();
        int32_t rtt = now > slot->sent_ns
                          ? (int32_t)((now - slot->sent_ns) / 1000ULL)
                          : 0;
        slot->used = 0;

        int is_dest = is_same_addr((struct sockaddr *)&offender,
                                   (struct sockaddr *)&g_engine.dst) != 0;
        if (!is_dest && !is_v4()) {
            /* IPv6 destination-unreachable from the target. */
            if (info.type == ICMP6_DST_UNREACH)
                is_dest = is_same_addr((struct sockaddr *)&offender,
                                       (struct sockaddr *)&g_engine.dst);
        }
        mark_response(hop->ttl, (struct sockaddr *)&offender, rtt, is_dest,
                      info.have ? info.type : 0, info.have ? info.code : 0);
    }
}

static void drain_normal(Hop *hop)
{
    for (;;) {
        uint8_t packet[2048];
        struct sockaddr_storage source;
        memset(&source, 0, sizeof(source));
        struct iovec iov = {.iov_base = packet, .iov_len = sizeof(packet)};
        struct msghdr msg;
        memset(&msg, 0, sizeof(msg));
        msg.msg_name = &source;
        msg.msg_namelen = sizeof(source);
        msg.msg_iov = &iov;
        msg.msg_iovlen = 1;

        ssize_t n = recvmsg(hop->fd, &msg, MSG_DONTWAIT);
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            break;
        }

        uint16_t seq = 0, dest_port = 0;
        int parsed = parse_embedded(packet, (int)n, &seq, &dest_port);
        ProbeSlot *slot = NULL;
        if (parsed == 1)
            slot = find_slot_seq(hop, seq);
        else if (parsed == 2)
            slot = find_slot_port(hop, dest_port);
        if (slot == NULL)
            continue;

        int is_reply = 0;
        int offset = 0;
        if ((packet[0] >> 4) == 4 && n >= 20)
            offset = (packet[0] & 0x0f) * 4;
        else if ((packet[0] >> 4) == 6 && n >= 40)
            offset = 40;
        if (offset < n) {
            uint8_t type = packet[offset];
            if (type == ICMP_ECHOREPLY || type == ICMP6_ECHO_REPLY)
                is_reply = 1;
        }
        if (g_engine.mode == DMTR_MODE_UDP)
            is_reply = 1; /* a real UDP reply also proves the target was reached */

        uint64_t now = now_ns();
        int32_t rtt = now > slot->sent_ns
                          ? (int32_t)((now - slot->sent_ns) / 1000ULL)
                          : 0;
        slot->used = 0;

        struct sockaddr *from = (struct sockaddr *)&source;
        if (source.ss_family == 0 || source.ss_family == AF_UNSPEC)
            from = (struct sockaddr *)&g_engine.dst;
        int is_dest = is_reply && is_same_addr(from, (struct sockaddr *)&g_engine.dst);
        mark_response(hop->ttl, from, rtt, is_dest, 0, 0);
    }
}

static uint64_t cycle_spacing_ns(void)
{
    int horizon = g_engine.reached ? g_engine.reached_ttl : g_engine.max_hops;
    if (horizon < 1)
        horizon = 1;
    uint64_t spacing = (uint64_t)g_engine.interval_ms * 1000000ULL /
                       (uint64_t)horizon;
    if (spacing < 10ULL * 1000000ULL)
        spacing = 10ULL * 1000000ULL;
    return spacing;
}

static void send_probe_locked(uint64_t now)
{
    if (g_engine.reached && g_engine.scan_ttl > g_engine.reached_ttl)
        g_engine.scan_ttl = 1;
    int ttl = g_engine.scan_ttl;
    if (ttl < 1)
        ttl = 1;
    if (ttl > g_engine.max_hops)
        ttl = g_engine.max_hops;

    Hop *hop = get_hop((uint32_t)ttl);
    if (hop == NULL)
        return;

    if (g_engine.hop_count < (uint32_t)ttl)
        g_engine.hop_count = (uint32_t)ttl;

    if (hop->fd < 0 && create_hop_socket(hop) != 0) {
        g_engine.next_send_ns = now + cycle_spacing_ns();
        return;
    }

    ProbeSlot *slot = free_slot(hop);
    if (slot == NULL) {
        g_engine.next_send_ns = now + cycle_spacing_ns();
        return;
    }

    uint16_t seq = (uint16_t)g_engine.next_seq;
    g_engine.next_seq++;
    if (g_engine.next_seq == 0 || g_engine.next_seq > 65535)
        g_engine.next_seq = 1;

    uint16_t dest_port = (uint16_t)(33434U + (seq % 20000U));
    uint8_t buffer[8 + MAX_PACKET_PAYLOAD];
    size_t length = 0;

    if (g_engine.mode == DMTR_MODE_ICMP) {
        memset(buffer, 0, 8 + (size_t)g_engine.payload_bytes);
        buffer[0] = is_v4() ? ICMP_ECHO : ICMP6_ECHO_REQUEST;
        buffer[1] = 0;
        uint16_t net_seq = htons(seq);
        memcpy(buffer + 6, &net_seq, sizeof(net_seq));
        for (int i = 0; i < g_engine.payload_bytes; i++)
            buffer[8 + i] = (uint8_t)((seq + i) & 0xff);
        length = 8 + (size_t)g_engine.payload_bytes;
    } else {
        for (int i = 0; i < g_engine.payload_bytes; i++)
            buffer[i] = (uint8_t)((seq + i) & 0xff);
        length = (size_t)g_engine.payload_bytes;
    }

    struct sockaddr_storage dest;
    memcpy(&dest, &g_engine.dst, sizeof(dest));
    if (g_engine.mode == DMTR_MODE_UDP) {
        if (is_v4())
            ((struct sockaddr_in *)&dest)->sin_port = htons(dest_port);
        else
            ((struct sockaddr_in6 *)&dest)->sin6_port = htons(dest_port);
    }

    ssize_t sent = sendto(hop->fd, buffer, length, 0,
                          (struct sockaddr *)&dest, g_engine.dst_len);
    if (sent < 0) {
        set_engine_errno("probe send failed");
        g_engine.next_send_ns = now + cycle_spacing_ns();
    } else {
        slot->used = 1;
        slot->seq = seq;
        slot->dest_port = dest_port;
        slot->sent_ns = now;
        hop->sent++;
        hop->pending++;
        g_engine.total_sent++;
        g_engine.next_send_ns = now + cycle_spacing_ns();
    }

    int horizon = g_engine.reached ? g_engine.reached_ttl : g_engine.max_hops;
    if (horizon < 1)
        horizon = 1;
    if (g_engine.scan_ttl >= horizon)
        g_engine.scan_ttl = 1;
    else
        g_engine.scan_ttl++;
}

static void process_timeouts_locked(uint64_t now)
{
    uint64_t timeout_ns = (uint64_t)g_engine.timeout_ms * 1000000ULL;
    for (uint32_t h = 0; h < g_engine.hop_count; h++) {
        Hop *hop = &g_engine.hops[h];
        for (int i = 0; i < MAX_PROBES_PER_HOP; i++) {
            if (!hop->probes[i].used)
                continue;
            if (now - hop->probes[i].sent_ns >= timeout_ns) {
                hop->probes[i].used = 0;
                mark_timeout(hop);
            }
        }
    }
}

static void prune_hidden_hops_locked(void)
{
    if (!g_engine.prune_hidden || !g_engine.reached)
        return;
    g_engine.prune_hidden = 0;
    for (int h = g_engine.reached_ttl; h < DMTR_MAX_HOPS; h++) {
        Hop *hop = &g_engine.hops[h];
        if (hop->fd >= 0) {
            close(hop->fd);
            hop->fd = -1;
        }
        memset(hop->probes, 0, sizeof(hop->probes));
        hop->pending = 0;
    }
}

static void close_sockets_locked(void)
{
    for (uint32_t h = 0; h < DMTR_MAX_HOPS; h++) {
        if (g_engine.hops[h].fd >= 0) {
            close(g_engine.hops[h].fd);
            g_engine.hops[h].fd = -1;
        }
    }
}

static void *engine_thread(void *arg)
{
    (void)arg;
    for (;;) {
        if (atomic_load(&g_engine.stop_requested))
            break;

        uint64_t now = now_ns();
        int poll_ms = POLL_SLICE_MS;
        if (g_engine.next_send_ns <= now) {
            poll_ms = 0;
        } else {
            uint64_t delta_ms = (g_engine.next_send_ns - now) / 1000000ULL;
            if (delta_ms < (uint64_t)poll_ms)
                poll_ms = (int)delta_ms;
            if (poll_ms < 1)
                poll_ms = 1;
        }

        struct pollfd pfds[DMTR_MAX_HOPS];
        int map[DMTR_MAX_HOPS];
        int count = 0;
        for (uint32_t h = 0; h < g_engine.hop_count; h++) {
            Hop *hop = &g_engine.hops[h];
            if (hop->fd >= 0) {
                pfds[count].fd = hop->fd;
                pfds[count].events = POLLIN | POLLERR;
                pfds[count].revents = 0;
                map[count] = (int)h;
                count++;
            }
        }

        int ready = poll(count > 0 ? pfds : NULL, (nfds_t)count, poll_ms);
        if (atomic_load(&g_engine.stop_requested))
            break;

        pthread_mutex_lock(&g_engine.lock);
        now = now_ns();
        if (ready > 0) {
            for (int i = 0; i < count; i++) {
                if (pfds[i].revents == 0)
                    continue;
                uint32_t h = (uint32_t)map[i];
                if (h >= g_engine.hop_count)
                    continue;
                Hop *hop = &g_engine.hops[h];
                drain_errors(hop);
                drain_normal(hop);
            }
        }
        process_timeouts_locked(now);
        prune_hidden_hops_locked();

        if (now >= g_engine.next_send_ns) {
            for (int i = 0; i < 8; i++) {
                if (atomic_load(&g_engine.stop_requested))
                    break;
                send_probe_locked(now);
                now = now_ns();
                if (now < g_engine.next_send_ns)
                    break;
            }
        }
        pthread_mutex_unlock(&g_engine.lock);
    }

    pthread_mutex_lock(&g_engine.lock);
    close_sockets_locked();
    g_engine.running = 0;
    g_engine.stopped_ns = now_ns();
    g_engine.valid = 1;
    pthread_mutex_unlock(&g_engine.lock);
    return NULL;
}

static int can_open_icmp(int af)
{
    int fd = socket(af, SOCK_DGRAM, af == AF_INET ? IPPROTO_ICMP : IPPROTO_ICMPV6);
    if (fd < 0)
        return 0;
    int one = 1;
    int ok;
    if (af == AF_INET)
        ok = setsockopt(fd, IPPROTO_IP, IP_RECVERR, &one, sizeof(one)) == 0;
    else
        ok = setsockopt(fd, IPPROTO_IPV6, IPV6_RECVERR, &one, sizeof(one)) == 0;
    close(fd);
    return ok;
}

static int can_open_udp(int af)
{
    int fd = socket(af, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0)
        return 0;
    int one = 1;
    int ok;
    if (af == AF_INET)
        ok = setsockopt(fd, IPPROTO_IP, IP_RECVERR, &one, sizeof(one)) == 0;
    else
        ok = setsockopt(fd, IPPROTO_IPV6, IPV6_RECVERR, &one, sizeof(one)) == 0;
    close(fd);
    return ok;
}

uint32_t dmtr_capabilities(void)
{
    uint32_t caps = 0;
    if (can_open_icmp(AF_INET))
        caps |= DMTR_CAP_ICMP4 | DMTR_CAP_RECVERR4;
    if (can_open_udp(AF_INET))
        caps |= DMTR_CAP_UDP4 | DMTR_CAP_RECVERR4;
    if (can_open_icmp(AF_INET6))
        caps |= DMTR_CAP_ICMP6 | DMTR_CAP_RECVERR6;
    if (can_open_udp(AF_INET6))
        caps |= DMTR_CAP_UDP6 | DMTR_CAP_RECVERR6;
    return caps;
}

int dmtr_start(const DmtrConfig *config, char *errbuf, int errbuf_len)
{
    if (errbuf != NULL && errbuf_len > 0)
        errbuf[0] = '\0';

    if (config == NULL || config->target_addr == NULL) {
        if (errbuf)
            copy_str(errbuf, (size_t)errbuf_len, "missing target");
        return -1;
    }

    dmtr_stop();

    pthread_mutex_lock(&g_engine.lock);

    int family = config->family;
    if (family != 4 && family != 6) {
        set_engine_error("invalid address family", EINVAL);
        g_engine.valid = 1;
        pthread_mutex_unlock(&g_engine.lock);
        if (errbuf)
            copy_str(errbuf, (size_t)errbuf_len, g_engine.error);
        return -1;
    }

    int max_hops = config->max_hops;
    if (max_hops < 1)
        max_hops = 1;
    if (max_hops > DMTR_MAX_HOPS)
        max_hops = DMTR_MAX_HOPS;
    int interval_ms = config->interval_ms;
    if (interval_ms < 100)
        interval_ms = 100;
    if (interval_ms > 10000)
        interval_ms = 10000;
    int timeout_ms = config->timeout_ms;
    if (timeout_ms < 200)
        timeout_ms = 200;
    if (timeout_ms > 30000)
        timeout_ms = 30000;
    int payload = config->payload_bytes;
    if (payload < MIN_PACKET_PAYLOAD)
        payload = MIN_PACKET_PAYLOAD;
    if (payload > MAX_PACKET_PAYLOAD)
        payload = MAX_PACKET_PAYLOAD;

    /* Reset the engine, preserving the mutex and thread handle fields. */
    memset(g_engine.hops, 0, sizeof(g_engine.hops));
    for (int i = 0; i < DMTR_MAX_HOPS; i++)
        g_engine.hops[i].fd = -1;
    g_engine.valid = 1;
    g_engine.running = 0;
    g_engine.mode = DMTR_MODE_UDP;
    g_engine.requested_mode = config->mode;
    g_engine.family = family;
    g_engine.af = family == 4 ? AF_INET : AF_INET6;
    g_engine.max_hops = max_hops;
    g_engine.interval_ms = interval_ms;
    g_engine.timeout_ms = timeout_ms;
    g_engine.payload_bytes = payload;
    g_engine.hop_count = 1;
    g_engine.reached = 0;
    g_engine.reached_ttl = 0;
    g_engine.scan_ttl = 1;
    g_engine.prune_hidden = 0;
    g_engine.next_seq = 1;
    g_engine.started_ns = now_ns();
    g_engine.stopped_ns = 0;
    g_engine.next_send_ns = g_engine.started_ns;
    g_engine.total_sent = 0;
    g_engine.total_recv = 0;
    g_engine.total_lost = 0;
    g_engine.last_errno = 0;
    g_engine.error_type = 0;
    g_engine.error_code = 0;
    g_engine.error[0] = '\0';
    copy_str(g_engine.target, sizeof(g_engine.target), config->target_addr);
    memset(&g_engine.dst, 0, sizeof(g_engine.dst));
    g_engine.dst_len = 0;

    g_engine.hops[0].ttl = 1;
    g_engine.hops[0].fd = -1;

    int ok = 0;
    if (family == 4) {
        struct sockaddr_in *sin = (struct sockaddr_in *)&g_engine.dst;
        sin->sin_family = AF_INET;
        sin->sin_port = 0;
        ok = inet_pton(AF_INET, config->target_addr, &sin->sin_addr) == 1;
        g_engine.dst_len = sizeof(struct sockaddr_in);
    } else {
        struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)&g_engine.dst;
        sin6->sin6_family = AF_INET6;
        sin6->sin6_port = 0;
        ok = inet_pton(AF_INET6, config->target_addr, &sin6->sin6_addr) == 1;
        g_engine.dst_len = sizeof(struct sockaddr_in6);
    }
    if (!ok) {
        set_engine_error("invalid numeric target address", EINVAL);
        pthread_mutex_unlock(&g_engine.lock);
        if (errbuf)
            copy_str(errbuf, (size_t)errbuf_len, g_engine.error);
        return -1;
    }

    if (config->mode == DMTR_MODE_ICMP) {
        if (!can_open_icmp(g_engine.af)) {
            set_engine_error("ICMP ping sockets are not permitted on this device", EACCES);
            pthread_mutex_unlock(&g_engine.lock);
            if (errbuf)
                copy_str(errbuf, (size_t)errbuf_len, g_engine.error);
            return -1;
        }
        g_engine.mode = DMTR_MODE_ICMP;
    } else if (config->mode == DMTR_MODE_UDP) {
        g_engine.mode = DMTR_MODE_UDP;
    } else {
        g_engine.mode = can_open_icmp(g_engine.af) ? DMTR_MODE_ICMP : DMTR_MODE_UDP;
    }

    atomic_store(&g_engine.stop_requested, 0);
    int rc = pthread_create(&g_engine.thread, NULL, engine_thread, NULL);
    if (rc != 0) {
        char buf[DMTR_ERROR_LEN];
        snprintf(buf, sizeof(buf), "could not start probe thread: %s", strerror(rc));
        set_engine_error(buf, rc);
        g_engine.running = 0;
        pthread_mutex_unlock(&g_engine.lock);
        if (errbuf)
            copy_str(errbuf, (size_t)errbuf_len, g_engine.error);
        return -1;
    }
    g_engine.thread_started = 1;
    g_engine.running = 1;
    pthread_mutex_unlock(&g_engine.lock);

    return 0;
}

void dmtr_stop(void)
{
    pthread_mutex_lock(&g_engine.lock);
    int started = g_engine.thread_started;
    pthread_mutex_unlock(&g_engine.lock);
    if (!started)
        return;

    atomic_store(&g_engine.stop_requested, 1);
    pthread_join(g_engine.thread, NULL);

    pthread_mutex_lock(&g_engine.lock);
    g_engine.thread_started = 0;
    g_engine.running = 0;
    close_sockets_locked();
    if (g_engine.stopped_ns == 0)
        g_engine.stopped_ns = now_ns();
    g_engine.valid = 1;
    pthread_mutex_unlock(&g_engine.lock);
}

int dmtr_is_running(void)
{
    pthread_mutex_lock(&g_engine.lock);
    int running = g_engine.running;
    pthread_mutex_unlock(&g_engine.lock);
    return running;
}

int dmtr_snapshot(DmtrSnapshot *out, uint32_t struct_size)
{
    if (out == NULL)
        return 0;
    if (struct_size != (uint32_t)sizeof(DmtrSnapshot))
        return -2;

    pthread_mutex_lock(&g_engine.lock);
    if (!g_engine.valid) {
        pthread_mutex_unlock(&g_engine.lock);
        return 0;
    }

    memset(out, 0, sizeof(*out));
    out->magic = DMTR_MAGIC;
    out->abi_version = DMTR_ABI_VERSION;
    out->running = (uint32_t)g_engine.running;
    out->mode = (uint32_t)g_engine.mode;
    out->family = (uint32_t)g_engine.family;
    out->reached = (uint32_t)g_engine.reached;
    out->reached_ttl = (uint32_t)g_engine.reached_ttl;
    out->frontier = (uint32_t)(g_engine.reached ? g_engine.reached_ttl
                                                : g_engine.max_hops);
    out->hop_count = g_engine.hop_count;
    if (out->hop_count > DMTR_MAX_HOPS)
        out->hop_count = DMTR_MAX_HOPS;
    out->error_type = g_engine.error_type;
    out->error_code = g_engine.error_code;
    out->total_sent = 0;
    out->total_recv = 0;
    out->total_lost = 0;
    out->hop_capacity = DMTR_MAX_HOPS;
    out->started_ms = g_engine.started_ns / 1000000ULL;
    uint64_t end = g_engine.running
                       ? now_ns()
                       : (g_engine.stopped_ns ? g_engine.stopped_ns : now_ns());
    out->elapsed_ms = end > g_engine.started_ns
                          ? (end - g_engine.started_ns) / 1000000ULL
                          : 0;
    copy_str(out->target_addr, sizeof(out->target_addr), g_engine.target);
    copy_str(out->error, sizeof(out->error), g_engine.error);

    for (uint32_t h = 0; h < out->hop_count; h++) {
        Hop *src = &g_engine.hops[h];
        DmtrHop *dst = &out->hops[h];
        dst->ttl = src->ttl ? src->ttl : h + 1;
        dst->sent = src->sent;
        dst->recv = src->recv;
        dst->lost = src->lost;
        dst->pending = src->pending;
        dst->flags = src->flags;
        if (src->pending > 0)
            dst->flags |= 8U;
        dst->error_type = src->error_type;
        dst->error_code = src->error_code;
        dst->last_us = src->last_us;
        dst->best_us = src->best_us;
        dst->avg_us = src->avg_us;
        dst->worst_us = src->worst_us;
        dst->stdev_us = src->stdev_us;
        dst->jitter_us = src->jitter_us;
        dst->jitter_avg_us = src->jitter_avg_us;
        dst->jitter_worst_us = src->jitter_worst_us;
        dst->alt_count = src->alt_count;
        copy_str(dst->addr, sizeof(dst->addr), src->addr);
        for (uint32_t a = 0; a < src->alt_count && a < DMTR_MAX_ALT; a++)
            copy_str(dst->alts[a], DMTR_ADDR_LEN, src->alts[a]);

        uint32_t count = src->sample_total;
        if (count > DMTR_MAX_SAMPLES)
            count = DMTR_MAX_SAMPLES;
        uint32_t start = (src->sample_head + DMTR_MAX_SAMPLES - count) %
                         DMTR_MAX_SAMPLES;
        dst->sample_count = count;
        for (uint32_t i = 0; i < count; i++)
            dst->samples[i] = src->samples[(start + i) % DMTR_MAX_SAMPLES];
        out->total_sent += src->sent;
        out->total_recv += src->recv;
        out->total_lost += src->lost;
    }

    pthread_mutex_unlock(&g_engine.lock);
    return 1;
}

int dmtr_reverse_lookup(const char *ip, char *hostname, int hostname_len)
{
    if (ip == NULL || hostname == NULL || hostname_len <= 1)
        return -1;
    hostname[0] = '\0';

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_NUMERICHOST;
    struct addrinfo *res = NULL;
    if (getaddrinfo(ip, NULL, &hints, &res) != 0 || res == NULL)
        return -1;

    int rc = getnameinfo(res->ai_addr, res->ai_addrlen, hostname,
                         (socklen_t)hostname_len, NULL, 0, NI_NAMEREQD);
    freeaddrinfo(res);
    if (rc != 0) {
        hostname[0] = '\0';
        return -1;
    }
    return 0;
}

const char *dmtr_version(void)
{
    return "1.0.0";
}
