/*
 * DroidMTR native probe engine
 *
 * An Android-friendly adaptation of the probing model used by mtr (GPLv2)
 * and WinMTR (GPLv2).  It performs continuous traceroute-style probing
 * without root by using unprivileged ICMP datagram ("ping") sockets, with a
 * UDP fallback for devices or networks where ICMP datagram sockets are not
 * available.  Routers' ICMP errors are collected through IP_RECVERR.
 *
 * Copyright (C) 2026 DroidMTR contributors
 * Licensed under the GNU General Public License version 2.
 */

#ifndef DMTR_ENGINE_H
#define DMTR_ENGINE_H

#include <stdint.h>

#if defined(_WIN32)
#define DMTR_API __declspec(dllexport)
#else
#define DMTR_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define DMTR_MAX_HOPS 64
#define DMTR_MAX_SAMPLES 120
#define DMTR_MAX_ALT 4
#define DMTR_ADDR_LEN 46
#define DMTR_ERROR_LEN 160
#define DMTR_MAGIC 0x4452544dU /* "DRTM" */
#define DMTR_ABI_VERSION 1U

#define DMTR_MODE_AUTO 0
#define DMTR_MODE_ICMP 1
#define DMTR_MODE_UDP 2

#define DMTR_CAP_ICMP4 0x01U
#define DMTR_CAP_UDP4 0x02U
#define DMTR_CAP_ICMP6 0x04U
#define DMTR_CAP_UDP6 0x08U
#define DMTR_CAP_RECVERR4 0x10U
#define DMTR_CAP_RECVERR6 0x20U

typedef struct {
    const char *target_addr; /* numeric IPv4 or IPv6 address */
    int32_t family;          /* 4 or 6 */
    int32_t max_hops;        /* 1..DMTR_MAX_HOPS */
    int32_t interval_ms;     /* full-cycle interval */
    int32_t timeout_ms;      /* per-probe timeout */
    int32_t payload_bytes;   /* payload size, 8..1400 */
    int32_t mode;            /* DMTR_MODE_* */
} DmtrConfig;

typedef struct {
    uint32_t ttl;
    uint32_t flags; /* 1 = responded, 2 = destination, 4 = error, 8 = pending */
    int32_t error_type;
    int32_t error_code;
    uint32_t sent;
    uint32_t recv;
    uint32_t lost;
    uint32_t pending;
    int32_t last_us;
    int32_t best_us;
    int32_t avg_us;
    int32_t worst_us;
    int32_t stdev_us;
    int32_t jitter_us;
    int32_t jitter_avg_us;
    int32_t jitter_worst_us;
    uint32_t alt_count;
    char addr[DMTR_ADDR_LEN];
    char alts[DMTR_MAX_ALT][DMTR_ADDR_LEN];
    uint32_t sample_count;
    int32_t samples[DMTR_MAX_SAMPLES]; /* chronological; -1 = timeout */
} DmtrHop;

typedef struct {
    uint32_t magic;
    uint32_t abi_version;
    uint32_t running;
    uint32_t mode; /* actual mode used */
    uint32_t family;
    uint32_t reached;
    uint32_t reached_ttl;
    uint32_t frontier;
    uint32_t hop_count;
    int32_t error_type;
    int32_t error_code;
    uint32_t total_sent;
    uint32_t total_recv;
    uint32_t total_lost;
    uint32_t hop_capacity;
    uint64_t started_ms;
    uint64_t elapsed_ms;
    char target_addr[DMTR_ADDR_LEN];
    char error[DMTR_ERROR_LEN];
    DmtrHop hops[DMTR_MAX_HOPS];
} DmtrSnapshot;

/* Start probing. Returns 0 on success, -1 on error. errbuf receives a message. */
DMTR_API int dmtr_start(const DmtrConfig *config, char *errbuf, int errbuf_len);

/* Stop probing and join the worker thread. Safe to call repeatedly. */
DMTR_API void dmtr_stop(void);

/* Copy the current snapshot. Returns 1 if a snapshot is available, 0 if not,
 * -2 if the supplied struct size does not match the native ABI. */
DMTR_API int dmtr_snapshot(DmtrSnapshot *out, uint32_t struct_size);

DMTR_API int dmtr_is_running(void);

/* Bitmask of DMTR_CAP_* values. Performs a lightweight socket capability test. */
DMTR_API uint32_t dmtr_capabilities(void);

/* Blocking reverse DNS lookup. Call from a background isolate. Returns 0 on
 * success and fills hostname; -1 otherwise. */
DMTR_API int dmtr_reverse_lookup(const char *ip, char *hostname, int hostname_len);

DMTR_API const char *dmtr_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DMTR_ENGINE_H */
