/* Small host-side driver for the DroidMTR native engine. */
#include "dmtr_engine.h"

#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *mode_name(int mode)
{
    return mode == DMTR_MODE_ICMP ? "ICMP" : "UDP";
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <ipv4-or-ipv6> [auto|icmp|udp] [seconds]\n", argv[0]);
        return 2;
    }

    const char *target = argv[1];
    int mode = DMTR_MODE_AUTO;
    if (argc > 2) {
        if (strcmp(argv[2], "icmp") == 0)
            mode = DMTR_MODE_ICMP;
        else if (strcmp(argv[2], "udp") == 0)
            mode = DMTR_MODE_UDP;
    }
    int seconds = argc > 3 ? atoi(argv[3]) : 8;
    int family = strchr(target, ':') != NULL ? 6 : 4;

    DmtrConfig cfg = {
        .target_addr = target,
        .family = family,
        .max_hops = 30,
        .interval_ms = 1000,
        .timeout_ms = 2000,
        .payload_bytes = 64,
        .mode = mode,
    };

    char err[DMTR_ERROR_LEN];
    if (dmtr_start(&cfg, err, sizeof(err)) != 0) {
        fprintf(stderr, "start failed: %s\n", err);
        return 1;
    }

    DmtrSnapshot snap;
    uint32_t caps = dmtr_capabilities();
    printf("engine %s, caps=0x%x, target %s\n", dmtr_version(), caps, target);

    for (int tick = 0; tick < seconds * 5; tick++) {
        struct timespec ts = {.tv_sec = 0, .tv_nsec = 200000000};
        nanosleep(&ts, NULL);
        int rc = dmtr_snapshot(&snap, sizeof(snap));
        if (rc != 1) {
            fprintf(stderr, "snapshot failed: %d\n", rc);
            break;
        }
        if (tick % 5 == 4 || snap.reached) {
            printf("\n[%5.1fs] mode=%s hops=%u reached=%u ttl=%u sent=%u recv=%u lost=%u err=%s\n",
                   snap.elapsed_ms / 1000.0, mode_name((int)snap.mode),
                   snap.hop_count, snap.reached, snap.reached_ttl,
                   snap.total_sent, snap.total_recv, snap.total_lost,
                   snap.error);
            for (uint32_t i = 0; i < snap.hop_count; i++) {
                DmtrHop *h = &snap.hops[i];
                if (h->sent == 0 && h->recv == 0)
                    continue;
                printf(" %2u  %-39s  loss=%5.1f%%  sent=%3u recv=%3u best=%4d avg=%4d worst=%4d last=%4d %s\n",
                       h->ttl, h->addr[0] ? h->addr : "*",
                       (h->lost + h->recv) ? 100.0 * h->lost / (h->lost + h->recv) : 0.0,
                       h->sent, h->recv, h->best_us / 1000, h->avg_us / 1000,
                       h->worst_us / 1000, h->last_us / 1000,
                       (h->flags & 2) ? "<-- target" : "");
            }
            fflush(stdout);
        }
    }

    dmtr_stop();
    printf("\nstopped. final sent=%u recv=%u lost=%u\n",
           snap.total_sent, snap.total_recv, snap.total_lost);
    return 0;
}
