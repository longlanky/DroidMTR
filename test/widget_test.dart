import 'package:droid_mtr/models/trace_models.dart';
import 'package:droid_mtr/services/report_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trace config survives JSON round trip and clamps values', () {
    const config = TraceConfig(
      maxHops: 999,
      intervalMs: 50,
      timeoutMs: 99999,
      payloadBytes: 4,
      mode: ProbeMode.udp,
      resolveNames: false,
    );
    final restored = TraceConfig.fromJson(config.toJson());
    expect(restored.maxHops, 64);
    expect(restored.intervalMs, 200);
    expect(restored.timeoutMs, 10000);
    expect(restored.payloadBytes, 8);
    expect(restored.mode, ProbeMode.udp);
    expect(restored.resolveNames, isFalse);
  });

  test('trace session survives JSON round trip', () {
    final session = TraceSession(
      id: 'abc',
      host: 'example.com',
      address: '93.184.216.34',
      family: 4,
      config: const TraceConfig(),
      startedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      endedAt: DateTime.utc(2026, 1, 2, 3, 4, 15),
      durationMs: 10000,
      mode: ProbeMode.icmp,
      reached: true,
      reachedTtl: 2,
      totalSent: 20,
      totalRecv: 18,
      totalLost: 2,
      hops: const [
        HopStats(
          ttl: 1,
          address: '192.168.1.1',
          hostname: 'router.lan',
          sent: 10,
          received: 10,
          lost: 0,
          lastUs: 2400,
          bestUs: 1800,
          avgUs: 2200,
          worstUs: 3100,
          stdevUs: 320,
          samples: [2200, 2400, -1],
          responded: true,
        ),
        HopStats(
          ttl: 2,
          address: '93.184.216.34',
          sent: 10,
          received: 8,
          lost: 2,
          lastUs: 15000,
          bestUs: 14000,
          avgUs: 15000,
          worstUs: 17000,
          samples: [15000, -1, 16000],
          responded: true,
          isDestination: true,
        ),
      ],
    );

    final restored = TraceSession.fromJson(session.toJson());
    expect(restored.id, 'abc');
    expect(restored.host, 'example.com');
    expect(restored.hops.length, 2);
    expect(restored.hops[0].hostname, 'router.lan');
    expect(restored.hops[1].isDestination, isTrue);
    expect(restored.hops[1].lossPercent, closeTo(20, 0.001));
    expect(restored.lossPercent, closeTo(10, 0.001));
    expect(restored.averageRttMs, closeTo(15, 0.001));
    expect(restored.destinationHop?.ttl, 2);
  });

  test('report formatter includes the WinMTR-style columns', () {
    final session = TraceSession(
      id: 'abc',
      host: 'example.com',
      address: '93.184.216.34',
      family: 4,
      config: const TraceConfig(),
      startedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      endedAt: DateTime.utc(2026, 1, 2, 3, 4, 15),
      durationMs: 10000,
      mode: ProbeMode.icmp,
      reached: true,
      reachedTtl: 1,
      totalSent: 1,
      totalRecv: 1,
      totalLost: 0,
      hops: const [
        HopStats(
          ttl: 1,
          address: '1.1.1.1',
          sent: 1,
          received: 1,
          avgUs: 12000,
          bestUs: 12000,
          worstUs: 12000,
          lastUs: 12000,
          samples: [12000],
          responded: true,
          isDestination: true,
        ),
      ],
    );
    final text = ReportFormatter.text(session);
    expect(text, contains('Loss%'));
    expect(text, contains('Best'));
    expect(text, contains('1.1.1.1'));
    final csv = ReportFormatter.csv(session);
    expect(csv, contains('ttl,hostname,address,loss_percent'));
    expect(csv, contains('1,,')); // no hostname, address follows
    expect(csv, contains('1.1.1.1'));
  });
}
