import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import '../models/trace_models.dart';
import 'native_engine.dart';

class TargetResolutionException implements Exception {
  TargetResolutionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TargetResolver {
  static Future<TraceTarget> resolve(String rawInput) async {
    var input = rawInput.trim();
    if (input.isEmpty) {
      throw TargetResolutionException('Enter a hostname or IP address.');
    }
    if (input.contains('://')) {
      final uri = Uri.tryParse(input);
      if (uri != null && uri.host.isNotEmpty) input = uri.host;
    }
    if (input.startsWith('[') && input.endsWith(']')) {
      input = input.substring(1, input.length - 1);
    }
    if (input.endsWith('.')) {
      input = input.substring(0, input.length - 1);
    }
    if (input.isEmpty) {
      throw TargetResolutionException('Enter a hostname or IP address.');
    }

    final literal = InternetAddress.tryParse(input);
    if (literal != null) {
      return TraceTarget(
        host: input,
        address: literal.address,
        family: literal.type == InternetAddressType.IPv6 ? 6 : 4,
      );
    }

    final List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(input).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TargetResolutionException(
          'DNS lookup timed out for "$input".',
        ),
      );
    } on SocketException {
      throw TargetResolutionException(
        'Could not resolve "$input". Check the name and your connection.',
      );
    } on TargetResolutionException {
      rethrow;
    } catch (_) {
      throw TargetResolutionException(
        'Could not resolve "$input". Check the name and your connection.',
      );
    }

    if (addresses.isEmpty) {
      throw TargetResolutionException(
        '"$input" did not resolve to an address.',
      );
    }

    final preferred = addresses.firstWhere(
      (address) => address.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
    return TraceTarget(
      host: input,
      address: preferred.address,
      family: preferred.type == InternetAddressType.IPv6 ? 6 : 4,
    );
  }
}

class DnsResolver {
  DnsResolver({this.maxConcurrent = 2});

  final int maxConcurrent;
  final Map<String, String?> _cache = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _queued = {};
  int _active = 0;
  bool _disposed = false;

  void Function(String address, String? hostname)? onResolved;

  String? cached(String address) => _cache[address];

  void lookup(String address) {
    if (_disposed || address.isEmpty) return;
    if (_cache.containsKey(address) || _queued.contains(address)) return;
    _queued.add(address);
    _queue.add(address);
    _pump();
  }

  void _pump() {
    if (_disposed) return;
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final address = _queue.removeFirst();
      _active++;
      unawaited(_run(address));
    }
  }

  Future<void> _run(String address) async {
    String? hostname;
    try {
      hostname = await Isolate.run(
        () => NativeEngine.reverseLookupIsolate(address),
      ).timeout(const Duration(seconds: 5));
      if (hostname != null && (hostname.isEmpty || hostname == address)) {
        hostname = null;
      }
    } catch (_) {
      hostname = null;
    }
    _queued.remove(address);
    _cache[address] = hostname;
    _active--;
    if (!_disposed) onResolved?.call(address, hostname);
    _pump();
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
  }
}
