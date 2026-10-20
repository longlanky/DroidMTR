import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trace_models.dart';

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.maxHops = 30,
    this.intervalMs = 1000,
    this.timeoutMs = 2000,
    this.payloadBytes = 64,
    this.probeMode = ProbeMode.auto,
    this.resolveNames = true,
    this.themeMode = AppThemeMode.system,
    this.keepScreenOn = true,
  });

  final int maxHops;
  final int intervalMs;
  final int timeoutMs;
  final int payloadBytes;
  final ProbeMode probeMode;
  final bool resolveNames;
  final AppThemeMode themeMode;
  final bool keepScreenOn;

  TraceConfig get traceConfig => TraceConfig(
    maxHops: maxHops,
    intervalMs: intervalMs,
    timeoutMs: timeoutMs,
    payloadBytes: payloadBytes,
    mode: probeMode,
    resolveNames: resolveNames,
  );

  AppSettings copyWith({
    int? maxHops,
    int? intervalMs,
    int? timeoutMs,
    int? payloadBytes,
    ProbeMode? probeMode,
    bool? resolveNames,
    AppThemeMode? themeMode,
    bool? keepScreenOn,
  }) {
    return AppSettings(
      maxHops: maxHops ?? this.maxHops,
      intervalMs: intervalMs ?? this.intervalMs,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      payloadBytes: payloadBytes ?? this.payloadBytes,
      probeMode: probeMode ?? this.probeMode,
      resolveNames: resolveNames ?? this.resolveNames,
      themeMode: themeMode ?? this.themeMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }

  AppSettings clamped() {
    return copyWith(
      maxHops: maxHops.clamp(1, 64),
      intervalMs: intervalMs.clamp(200, 5000),
      timeoutMs: timeoutMs.clamp(500, 10000),
      payloadBytes: payloadBytes.clamp(8, 1400),
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._settings, this._recentTargets);

  static const _kMaxHops = 'settings.maxHops';
  static const _kIntervalMs = 'settings.intervalMs';
  static const _kTimeoutMs = 'settings.timeoutMs';
  static const _kPayloadBytes = 'settings.payloadBytes';
  static const _kProbeMode = 'settings.probeMode';
  static const _kResolveNames = 'settings.resolveNames';
  static const _kThemeMode = 'settings.themeMode';
  static const _kKeepScreenOn = 'settings.keepScreenOn';
  static const _kRecentTargets = 'recentTargets.v1';

  final SharedPreferences _prefs;
  AppSettings _settings;
  List<RecentTarget> _recentTargets;

  AppSettings get settings => _settings;
  List<RecentTarget> get recentTargets => List.unmodifiable(_recentTargets);

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = const AppSettings();
    final settings = AppSettings(
      maxHops: prefs.getInt(_kMaxHops) ?? defaults.maxHops,
      intervalMs: prefs.getInt(_kIntervalMs) ?? defaults.intervalMs,
      timeoutMs: prefs.getInt(_kTimeoutMs) ?? defaults.timeoutMs,
      payloadBytes: prefs.getInt(_kPayloadBytes) ?? defaults.payloadBytes,
      probeMode: ProbeMode.fromName(prefs.getString(_kProbeMode)),
      resolveNames: prefs.getBool(_kResolveNames) ?? defaults.resolveNames,
      themeMode: AppThemeMode.values.firstWhere(
        (mode) => mode.name == prefs.getString(_kThemeMode),
        orElse: () => defaults.themeMode,
      ),
      keepScreenOn: prefs.getBool(_kKeepScreenOn) ?? defaults.keepScreenOn,
    ).clamped();

    final recent = <RecentTarget>[];
    final raw = prefs.getString(_kRecentTargets);
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              recent.add(RecentTarget.fromJson(item.cast<String, dynamic>()));
            }
          }
        }
      } catch (_) {
        // Ignore corrupted history and start fresh.
      }
    }

    return SettingsController._(prefs, settings, recent);
  }

  Future<void> update(AppSettings value) async {
    _settings = value.clamped();
    await Future.wait([
      _prefs.setInt(_kMaxHops, _settings.maxHops),
      _prefs.setInt(_kIntervalMs, _settings.intervalMs),
      _prefs.setInt(_kTimeoutMs, _settings.timeoutMs),
      _prefs.setInt(_kPayloadBytes, _settings.payloadBytes),
      _prefs.setString(_kProbeMode, _settings.probeMode.name),
      _prefs.setBool(_kResolveNames, _settings.resolveNames),
      _prefs.setString(_kThemeMode, _settings.themeMode.name),
      _prefs.setBool(_kKeepScreenOn, _settings.keepScreenOn),
    ]);
    notifyListeners();
  }

  Future<void> _persistRecent() async {
    await _prefs.setString(
      _kRecentTargets,
      jsonEncode([for (final target in _recentTargets) target.toJson()]),
    );
  }

  Future<void> rememberTarget(String host, String address, int family) async {
    final normalized = host.trim();
    if (normalized.isEmpty) return;
    _recentTargets.removeWhere(
      (target) => target.host.toLowerCase() == normalized.toLowerCase(),
    );
    _recentTargets.insert(
      0,
      RecentTarget(
        host: normalized,
        address: address,
        family: family,
        lastUsed: DateTime.now(),
      ),
    );
    if (_recentTargets.length > 8) {
      _recentTargets = _recentTargets.sublist(0, 8);
    }
    await _persistRecent();
    notifyListeners();
  }

  Future<void> clearRecentTargets() async {
    _recentTargets = [];
    await _persistRecent();
    notifyListeners();
  }
}
