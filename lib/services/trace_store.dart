import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/trace_models.dart';

class TraceStore {
  TraceStore._(this._directory, this._cache);

  final Directory _directory;
  final Map<String, TraceSession> _cache;

  static Future<TraceStore> open() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/traces');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final store = TraceStore._(directory, {});
    await store._load();
    return store;
  }

  Directory get directory => _directory;
  int get count => _cache.length;

  Future<void> _load() async {
    final sessions = <String, TraceSession>{};
    try {
      await for (final entity in _directory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final raw = await entity.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is! Map) continue;
          final session = TraceSession.fromJson(
            decoded.cast<String, dynamic>(),
          );
          if (session.id.isEmpty) continue;
          sessions[session.id] = session;
        } catch (_) {
          // Skip a damaged/unreadable record rather than failing the history.
        }
      }
    } catch (_) {
      // If the directory disappears, keep the app usable.
    }
    _cache
      ..clear()
      ..addAll(sessions);
  }

  Future<List<TraceSession>> list() async {
    await _load();
    final values = _cache.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return values;
  }

  Future<TraceSession?> get(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    await _load();
    return _cache[id];
  }

  Future<void> save(TraceSession session) async {
    final target = File(
      '${_directory.path}/trace_${session.startedAt.millisecondsSinceEpoch}_${session.id}.json',
    );
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
      flush: true,
    );
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
    _cache[session.id] = session;
    await _prune();
  }

  Future<void> delete(String id) async {
    _cache.remove(id);
    try {
      await for (final entity in _directory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is Map && decoded['id']?.toString() == id) {
            await entity.delete();
          }
        } catch (_) {
          // Ignore bad records while deleting.
        }
      }
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> clear() async {
    _cache.clear();
    try {
      await for (final entity in _directory.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _prune() async {
    if (_cache.length <= 200) return;
    final values = _cache.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final remove = values
        .take(_cache.length - 200)
        .map((session) => session.id);
    for (final id in remove.toList()) {
      await delete(id);
    }
  }
}
