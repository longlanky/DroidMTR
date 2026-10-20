import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/trace_models.dart';
import 'dns_resolver.dart';
import 'native_bindings.dart';
import 'native_engine.dart';
import 'trace_store.dart';

enum TraceRunState { starting, running, stopping, finished, failed }

class TraceController extends ChangeNotifier {
  TraceController({
    required this.target,
    required this.config,
    required this.store,
    this.keepScreenOn = true,
  });

  final TraceTarget target;
  final TraceConfig config;
  final TraceStore store;
  final bool keepScreenOn;

  final DnsResolver _dns = DnsResolver();
  final Map<String, String> _hostnames = {};
  NativeEngine? _engine;
  Timer? _timer;
  TraceSnapshot? _snapshot;
  TraceRunState _state = TraceRunState.starting;
  String? _error;
  String? _savedSessionId;
  TraceSession? _lastSavedSession;
  Future<TraceSession?>? _stopFuture;
  bool _started = false;
  bool _disposed = false;

  TraceRunState get state => _state;
  TraceSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get isActive =>
      _state == TraceRunState.starting || _state == TraceRunState.running;
  bool get isRunning => _state == TraceRunState.running;
  String? get savedSessionId => _savedSessionId;
  TraceSession? get lastSavedSession => _lastSavedSession;
  TraceConfig get effectiveConfig => config;
  int get resolvedFamily => target.family;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _state = TraceRunState.starting;
    notifyListeners();

    _dns.onResolved = (address, hostname) {
      if (_disposed || hostname == null || hostname.isEmpty) return;
      _hostnames[address] = hostname;
      final current = _snapshot;
      if (current != null) {
        _snapshot = _applyHostnames(current);
        notifyListeners();
      }
    };

    try {
      final engine = NativeEngine();
      _engine = engine;
      engine.start(target: target, config: config);
      _state = TraceRunState.running;
      await _setWakelock(true);
      _poll();
      _timer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _poll(),
      );
      notifyListeners();
    } catch (error) {
      _state = TraceRunState.failed;
      _error = _friendlyError(error);
      await _setWakelock(false);
      _engine?.stop();
      _engine?.dispose();
      _engine = null;
      notifyListeners();
    }
  }

  void _poll() {
    if (_disposed) return;
    final engine = _engine;
    if (engine == null) return;
    try {
      final next = engine.poll();
      if (next == null) return;
      _snapshot = _applyHostnames(next);
      if (config.resolveNames) {
        for (final hop in next.hops) {
          final address = hop.address;
          if (address != null && address.isNotEmpty) {
            _dns.lookup(address);
          }
        }
      }
      if (_state == TraceRunState.starting && next.running) {
        _state = TraceRunState.running;
      }
      notifyListeners();
    } catch (error) {
      _error = _friendlyError(error);
      _state = TraceRunState.failed;
      _timer?.cancel();
      unawaited(_setWakelock(false));
      notifyListeners();
    }
  }

  TraceSnapshot _applyHostnames(TraceSnapshot snapshot) {
    if (_hostnames.isEmpty) return snapshot;
    return snapshot.copyWithHops([
      for (final hop in snapshot.hops)
        _hostnames[hop.address] != null
            ? hop.withHostname(_hostnames[hop.address])
            : hop,
    ]);
  }

  /// Stops probing, saves the completed trace, and returns the saved session.
  Future<TraceSession?> stop({bool save = true}) {
    final existing = _stopFuture;
    if (existing != null) return existing;
    final future = _stopInternal(save: save);
    _stopFuture = future;
    return future;
  }

  Future<TraceSession?> _stopInternal({required bool save}) async {
    if (_disposed) return null;
    if (_state == TraceRunState.failed) {
      return null;
    }
    _state = TraceRunState.stopping;
    notifyListeners();
    _timer?.cancel();
    _timer = null;
    try {
      _engine?.stop();
      final finalSnapshot = _engine?.poll();
      if (finalSnapshot != null) {
        _snapshot = _applyHostnames(finalSnapshot);
      }
    } catch (_) {
      // Keep the last known snapshot.
    }
    final current = _snapshot;
    if (current == null) {
      _state = TraceRunState.finished;
      await _setWakelock(false);
      notifyListeners();
      return null;
    }

    final session = _buildSession(current);
    if (save && session.totalSent > 0) {
      try {
        await store.save(session);
        _savedSessionId = session.id;
        _lastSavedSession = session;
      } catch (error) {
        _error = 'Could not save this trace: $error';
      }
    }
    _state = TraceRunState.finished;
    await _setWakelock(false);
    if (!_disposed) notifyListeners();
    return session;
  }

  /// Saves an intermediate result without stopping the trace.
  Future<TraceSession?> saveSnapshot() async {
    final current = _snapshot;
    if (current == null || current.totalSent == 0) return null;
    final session = _buildSession(current);
    await store.save(session);
    _savedSessionId = session.id;
    _lastSavedSession = session;
    if (!_disposed) notifyListeners();
    return session;
  }

  TraceSession _buildSession(TraceSnapshot current) {
    final now = DateTime.now();
    final session = TraceSession.fromSnapshot(
      id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      host: target.host,
      address: target.address,
      family: target.family,
      config: config,
      snapshot: current,
      endedAt: now,
    );
    return session;
  }

  Future<void> _setWakelock(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      if (enabled && keepScreenOn) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Wakelock support is cosmetic; never fail a trace over it.
    }
  }

  String _friendlyError(Object error) {
    if (error is NativeEngineException) return error.message;
    if (error is TargetResolutionException) return error.message;
    return error.toString();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _dns.dispose();
    try {
      _engine?.stop();
      _engine?.dispose();
    } catch (_) {
      // Best effort during teardown.
    }
    unawaited(_setWakelock(false));
    super.dispose();
  }
}
