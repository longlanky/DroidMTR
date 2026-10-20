import 'dart:math' as math;

enum ProbeMode {
  auto,
  icmp,
  udp;

  int get nativeValue => switch (this) {
    ProbeMode.auto => 0,
    ProbeMode.icmp => 1,
    ProbeMode.udp => 2,
  };

  String get label => switch (this) {
    ProbeMode.auto => 'Auto',
    ProbeMode.icmp => 'ICMP',
    ProbeMode.udp => 'UDP',
  };

  String get description => switch (this) {
    ProbeMode.auto => 'ICMP with automatic UDP fallback',
    ProbeMode.icmp => 'ICMP echo probes (recommended)',
    ProbeMode.udp => 'UDP probes for networks that block ICMP',
  };

  static ProbeMode fromName(String? value) {
    return ProbeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ProbeMode.auto,
    );
  }

  static ProbeMode fromNative(int value) => switch (value) {
    1 => ProbeMode.icmp,
    2 => ProbeMode.udp,
    _ => ProbeMode.auto,
  };
}

class TraceConfig {
  const TraceConfig({
    this.maxHops = 30,
    this.intervalMs = 1000,
    this.timeoutMs = 2000,
    this.payloadBytes = 64,
    this.mode = ProbeMode.auto,
    this.resolveNames = true,
  });

  final int maxHops;
  final int intervalMs;
  final int timeoutMs;
  final int payloadBytes;
  final ProbeMode mode;
  final bool resolveNames;

  TraceConfig clamped() {
    return TraceConfig(
      maxHops: maxHops.clamp(1, 64),
      intervalMs: intervalMs.clamp(200, 5000),
      timeoutMs: timeoutMs.clamp(500, 10000),
      payloadBytes: payloadBytes.clamp(8, 1400),
      mode: mode,
      resolveNames: resolveNames,
    );
  }

  TraceConfig copyWith({
    int? maxHops,
    int? intervalMs,
    int? timeoutMs,
    int? payloadBytes,
    ProbeMode? mode,
    bool? resolveNames,
  }) {
    return TraceConfig(
      maxHops: maxHops ?? this.maxHops,
      intervalMs: intervalMs ?? this.intervalMs,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      mode: mode ?? this.mode,
      resolveNames: resolveNames ?? this.resolveNames,
    );
  }

  String get intervalLabel =>
      '${(intervalMs / 1000).toStringAsFixed(intervalMs % 1000 == 0 ? 0 : 1)} s';
  String get timeoutLabel =>
      '${(timeoutMs / 1000).toStringAsFixed(timeoutMs % 1000 == 0 ? 0 : 1)} s';

  Map<String, dynamic> toJson() => {
    'maxHops': maxHops,
    'intervalMs': intervalMs,
    'timeoutMs': timeoutMs,
    'payloadBytes': payloadBytes,
    'mode': mode.name,
    'resolveNames': resolveNames,
  };

  factory TraceConfig.fromJson(Map<String, dynamic> json) {
    return TraceConfig(
      maxHops: (json['maxHops'] as num?)?.toInt() ?? 30,
      intervalMs: (json['intervalMs'] as num?)?.toInt() ?? 1000,
      timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 2000,
      payloadBytes: (json['payloadBytes'] as num?)?.toInt() ?? 64,
      mode: ProbeMode.fromName(json['mode'] as String?),
      resolveNames: json['resolveNames'] as bool? ?? true,
    ).clamped();
  }
}

class HopStats {
  const HopStats({
    required this.ttl,
    this.address,
    this.alternates = const [],
    this.hostname,
    this.sent = 0,
    this.received = 0,
    this.lost = 0,
    this.pending = 0,
    this.lastUs = 0,
    this.bestUs = 0,
    this.avgUs = 0,
    this.worstUs = 0,
    this.stdevUs = 0,
    this.jitterUs = 0,
    this.jitterAvgUs = 0,
    this.jitterWorstUs = 0,
    this.samples = const [],
    this.responded = false,
    this.isDestination = false,
    this.errorType = 0,
    this.errorCode = 0,
  });

  final int ttl;
  final String? address;
  final List<String> alternates;
  final String? hostname;
  final int sent;
  final int received;
  final int lost;
  final int pending;
  final int lastUs;
  final int bestUs;
  final int avgUs;
  final int worstUs;
  final int stdevUs;
  final int jitterUs;
  final int jitterAvgUs;
  final int jitterWorstUs;

  /// Probe history in microseconds. A value of -1 represents a timeout.
  final List<int> samples;
  final bool responded;
  final bool isDestination;
  final int errorType;
  final int errorCode;

  int get completed => received + lost;

  double get lossPercent {
    final total = completed;
    return total == 0 ? 0 : lost * 100.0 / total;
  }

  bool get hasData => sent > 0 || received > 0;
  bool get hasAddress => address != null && address!.isNotEmpty;
  String get displayAddress => hostname?.isNotEmpty == true
      ? hostname!
      : (address?.isNotEmpty == true ? address! : 'Waiting for reply');

  double get lastMs => lastUs / 1000.0;
  double get bestMs => bestUs / 1000.0;
  double get avgMs => avgUs / 1000.0;
  double get worstMs => worstUs / 1000.0;
  double get stdevMs => stdevUs / 1000.0;
  double get jitterMs => jitterUs / 1000.0;
  double get jitterAvgMs => jitterAvgUs / 1000.0;
  double get jitterWorstMs => jitterWorstUs / 1000.0;

  /// Latency values only, in order, for charts.
  List<double> get latencySamples => [
    for (final sample in samples)
      if (sample >= 0) sample / 1000.0,
  ];

  int get lostSamples => samples.where((sample) => sample < 0).length;

  HopStats withHostname(String? value) {
    if (value == null || value.isEmpty || value == hostname) return this;
    return HopStats(
      ttl: ttl,
      address: address,
      alternates: alternates,
      hostname: value,
      sent: sent,
      received: received,
      lost: lost,
      pending: pending,
      lastUs: lastUs,
      bestUs: bestUs,
      avgUs: avgUs,
      worstUs: worstUs,
      stdevUs: stdevUs,
      jitterUs: jitterUs,
      jitterAvgUs: jitterAvgUs,
      jitterWorstUs: jitterWorstUs,
      samples: samples,
      responded: responded,
      isDestination: isDestination,
      errorType: errorType,
      errorCode: errorCode,
    );
  }

  Map<String, dynamic> toJson() => {
    'ttl': ttl,
    'address': address,
    'alternates': alternates,
    'hostname': hostname,
    'sent': sent,
    'received': received,
    'lost': lost,
    'pending': pending,
    'lastUs': lastUs,
    'bestUs': bestUs,
    'avgUs': avgUs,
    'worstUs': worstUs,
    'stdevUs': stdevUs,
    'jitterUs': jitterUs,
    'jitterAvgUs': jitterAvgUs,
    'jitterWorstUs': jitterWorstUs,
    'samples': samples,
    'responded': responded,
    'isDestination': isDestination,
    'errorType': errorType,
    'errorCode': errorCode,
  };

  factory HopStats.fromJson(Map<String, dynamic> json) {
    return HopStats(
      ttl: (json['ttl'] as num?)?.toInt() ?? 1,
      address: json['address'] as String?,
      alternates: [
        for (final value in (json['alternates'] as List<dynamic>? ?? const []))
          value.toString(),
      ],
      hostname: json['hostname'] as String?,
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      received: (json['received'] as num?)?.toInt() ?? 0,
      lost: (json['lost'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      lastUs: (json['lastUs'] as num?)?.toInt() ?? 0,
      bestUs: (json['bestUs'] as num?)?.toInt() ?? 0,
      avgUs: (json['avgUs'] as num?)?.toInt() ?? 0,
      worstUs: (json['worstUs'] as num?)?.toInt() ?? 0,
      stdevUs: (json['stdevUs'] as num?)?.toInt() ?? 0,
      jitterUs: (json['jitterUs'] as num?)?.toInt() ?? 0,
      jitterAvgUs: (json['jitterAvgUs'] as num?)?.toInt() ?? 0,
      jitterWorstUs: (json['jitterWorstUs'] as num?)?.toInt() ?? 0,
      samples: [
        for (final value in (json['samples'] as List<dynamic>? ?? const []))
          (value as num).toInt(),
      ],
      responded: json['responded'] as bool? ?? false,
      isDestination: json['isDestination'] as bool? ?? false,
      errorType: (json['errorType'] as num?)?.toInt() ?? 0,
      errorCode: (json['errorCode'] as num?)?.toInt() ?? 0,
    );
  }
}

class TraceSnapshot {
  const TraceSnapshot({
    required this.running,
    required this.mode,
    required this.family,
    required this.reached,
    required this.reachedTtl,
    required this.hopCount,
    required this.totalSent,
    required this.totalRecv,
    required this.totalLost,
    required this.startedMs,
    required this.elapsedMs,
    required this.targetAddr,
    required this.hops,
    this.error = '',
  });

  final bool running;
  final ProbeMode mode;
  final int family;
  final bool reached;
  final int reachedTtl;
  final int hopCount;
  final int totalSent;
  final int totalRecv;
  final int totalLost;
  final int startedMs;
  final int elapsedMs;
  final String targetAddr;
  final List<HopStats> hops;
  final String error;

  int get totalPending => math.max(0, totalSent - totalRecv - totalLost);
  int get completed => totalRecv + totalLost;

  double get lossPercent {
    final hop = summaryHop;
    if (hop != null) return hop.lossPercent;
    final total = completed;
    if (total == 0) return 0;
    return totalLost * 100.0 / total;
  }

  HopStats? get destinationHop {
    for (final hop in hops) {
      if (hop.isDestination) return hop;
    }
    return null;
  }

  HopStats? get lastRespondingHop {
    for (var i = hops.length - 1; i >= 0; i--) {
      if (hops[i].received > 0) return hops[i];
    }
    return null;
  }

  HopStats? get summaryHop => destinationHop ?? lastRespondingHop;

  double get averageRttMs => summaryHop?.avgMs ?? 0;

  bool get hasResponses => totalRecv > 0;

  String get modeLabel => mode.label;

  TraceSnapshot withHostname(int ttl, String? hostname) {
    return copyWithHops([
      for (final hop in hops) hop.ttl == ttl ? hop.withHostname(hostname) : hop,
    ]);
  }

  TraceSnapshot copyWithHops(List<HopStats> value) {
    return TraceSnapshot(
      running: running,
      mode: mode,
      family: family,
      reached: reached,
      reachedTtl: reachedTtl,
      hopCount: hopCount,
      totalSent: totalSent,
      totalRecv: totalRecv,
      totalLost: totalLost,
      startedMs: startedMs,
      elapsedMs: elapsedMs,
      targetAddr: targetAddr,
      hops: value,
      error: error,
    );
  }
}

class TraceSession {
  const TraceSession({
    required this.id,
    required this.host,
    required this.address,
    required this.family,
    required this.config,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.mode,
    required this.reached,
    required this.reachedTtl,
    required this.totalSent,
    required this.totalRecv,
    required this.totalLost,
    required this.hops,
  });

  final String id;
  final String host;
  final String address;
  final int family;
  final TraceConfig config;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMs;
  final ProbeMode mode;
  final bool reached;
  final int reachedTtl;
  final int totalSent;
  final int totalRecv;
  final int totalLost;
  final List<HopStats> hops;

  int get completed => totalRecv + totalLost;
  double get lossPercent => completed == 0 ? 0 : totalLost * 100.0 / completed;

  HopStats? get destinationHop {
    for (final hop in hops) {
      if (hop.isDestination) return hop;
    }
    return null;
  }

  HopStats? get lastRespondingHop {
    for (var i = hops.length - 1; i >= 0; i--) {
      if (hops[i].received > 0) return hops[i];
    }
    return null;
  }

  HopStats? get summaryHop => destinationHop ?? lastRespondingHop;
  double get averageRttMs => summaryHop?.avgMs ?? 0;
  bool get hasResponses => totalRecv > 0;

  TraceSession copyWith({String? host, List<HopStats>? hops}) {
    return TraceSession(
      id: id,
      host: host ?? this.host,
      address: address,
      family: family,
      config: config,
      startedAt: startedAt,
      endedAt: endedAt,
      durationMs: durationMs,
      mode: mode,
      reached: reached,
      reachedTtl: reachedTtl,
      totalSent: totalSent,
      totalRecv: totalRecv,
      totalLost: totalLost,
      hops: hops ?? this.hops,
    );
  }

  factory TraceSession.fromSnapshot({
    required String id,
    required String host,
    required String address,
    required int family,
    required TraceConfig config,
    required TraceSnapshot snapshot,
    required DateTime endedAt,
  }) {
    final duration = snapshot.elapsedMs;
    return TraceSession(
      id: id,
      host: host,
      address: address,
      family: family,
      config: config,
      startedAt: endedAt.subtract(Duration(milliseconds: duration)),
      endedAt: endedAt,
      durationMs: duration,
      mode: snapshot.mode,
      reached: snapshot.reached,
      reachedTtl: snapshot.reachedTtl,
      totalSent: snapshot.totalSent,
      totalRecv: snapshot.totalRecv,
      totalLost: snapshot.totalLost,
      hops: snapshot.hops,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'id': id,
    'host': host,
    'address': address,
    'family': family,
    'config': config.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'durationMs': durationMs,
    'mode': mode.name,
    'reached': reached,
    'reachedTtl': reachedTtl,
    'totalSent': totalSent,
    'totalRecv': totalRecv,
    'totalLost': totalLost,
    'hops': [for (final hop in hops) hop.toJson()],
  };

  factory TraceSession.fromJson(Map<String, dynamic> json) {
    final hopsJson = json['hops'] as List<dynamic>? ?? const [];
    return TraceSession(
      id: json['id']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      family: (json['family'] as num?)?.toInt() ?? 4,
      config: TraceConfig.fromJson(
        (json['config'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      startedAt:
          DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt:
          DateTime.tryParse(json['endedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      mode: ProbeMode.fromName(json['mode'] as String?),
      reached: json['reached'] as bool? ?? false,
      reachedTtl: (json['reachedTtl'] as num?)?.toInt() ?? 0,
      totalSent: (json['totalSent'] as num?)?.toInt() ?? 0,
      totalRecv: (json['totalRecv'] as num?)?.toInt() ?? 0,
      totalLost: (json['totalLost'] as num?)?.toInt() ?? 0,
      hops: [
        for (final hop in hopsJson)
          HopStats.fromJson((hop as Map).cast<String, dynamic>()),
      ],
    );
  }
}

class TraceTarget {
  const TraceTarget({
    required this.host,
    required this.address,
    required this.family,
  });

  final String host;
  final String address;
  final int family;

  bool get isIpv6 => family == 6;
}

class RecentTarget {
  const RecentTarget({
    required this.host,
    required this.address,
    required this.family,
    required this.lastUsed,
  });

  final String host;
  final String address;
  final int family;
  final DateTime lastUsed;

  TraceTarget toTarget() =>
      TraceTarget(host: host, address: address, family: family);

  Map<String, dynamic> toJson() => {
    'host': host,
    'address': address,
    'family': family,
    'lastUsed': lastUsed.toIso8601String(),
  };

  factory RecentTarget.fromJson(Map<String, dynamic> json) {
    return RecentTarget(
      host: json['host']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      family: (json['family'] as num?)?.toInt() ?? 4,
      lastUsed:
          DateTime.tryParse(json['lastUsed']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

String formatMs(double value, {int decimals = 1}) {
  if (value <= 0) return '—';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)} s';
  return '${value.toStringAsFixed(decimals)} ms';
}

String formatLoss(double percent) {
  if (percent <= 0) return '0%';
  if (percent >= 100) return '100%';
  return '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
}

String formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  return '${seconds}s';
}
