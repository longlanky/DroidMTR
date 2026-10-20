import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/trace_models.dart';
import 'native_bindings.dart';

class NativeEngine {
  NativeEngine() : _bindings = NativeBindings.instance() {
    _snapshotPtr = calloc<DmtrSnapshot>();
  }

  final NativeBindings _bindings;
  late final Pointer<DmtrSnapshot> _snapshotPtr;
  bool _disposed = false;

  String get version => _bindings.version;
  bool get isRunning => _bindings.isRunning != 0;
  int get capabilities => _bindings.capabilities;

  void start({required TraceTarget target, required TraceConfig config}) {
    _bindings.start(
      address: target.address,
      family: target.family,
      maxHops: config.maxHops,
      intervalMs: config.intervalMs,
      timeoutMs: config.timeoutMs,
      payloadBytes: config.payloadBytes,
      mode: config.mode.nativeValue,
    );
  }

  TraceSnapshot? poll() {
    if (_disposed) return null;
    final result = _bindings.snapshot(_snapshotPtr);
    if (result == 0) return null;
    if (result != 1) {
      throw NativeEngineException(
        'Native engine ABI mismatch (code $result). Rebuild the application.',
      );
    }

    final snapshot = _snapshotPtr.ref;
    if (snapshot.magic != dmtrMagic || snapshot.abiVersion != dmtrAbiVersion) {
      throw NativeEngineException(
        'Native engine returned an invalid snapshot.',
      );
    }

    final hopCount = snapshot.hopCount.clamp(0, dmtrMaxHops);
    final hops = <HopStats>[];
    for (var index = 0; index < hopCount; index++) {
      final nativeHop = snapshot.hops[index];
      final sampleCount = nativeHop.sampleCount.clamp(0, dmtrMaxSamples);
      final samples = <int>[
        for (var sample = 0; sample < sampleCount; sample++)
          nativeHop.samples[sample],
      ];
      final alternates = <String>[];
      final altCount = nativeHop.altCount.clamp(0, dmtrMaxAlt);
      if (altCount > 0) {
        final flat = nativeHop.alts.elements;
        for (var alt = 0; alt < altCount; alt++) {
          final value = _decodeFixed(
            flat.sublist(alt * dmtrAddrLen, (alt + 1) * dmtrAddrLen),
          );
          if (value.isNotEmpty) alternates.add(value);
        }
      }

      hops.add(
        HopStats(
          ttl: nativeHop.ttl == 0 ? index + 1 : nativeHop.ttl,
          address: _decodeFixed(nativeHop.addr.elements).ifEmptyNull(),
          alternates: alternates,
          sent: nativeHop.sent,
          received: nativeHop.recv,
          lost: nativeHop.lost,
          pending: nativeHop.pending,
          lastUs: nativeHop.lastUs,
          bestUs: nativeHop.bestUs,
          avgUs: nativeHop.avgUs,
          worstUs: nativeHop.worstUs,
          stdevUs: nativeHop.stdevUs,
          jitterUs: nativeHop.jitterUs,
          jitterAvgUs: nativeHop.jitterAvgUs,
          jitterWorstUs: nativeHop.jitterWorstUs,
          samples: samples,
          responded: nativeHop.flags & 1 != 0,
          isDestination: nativeHop.flags & 2 != 0,
          errorType: nativeHop.errorType,
          errorCode: nativeHop.errorCode,
        ),
      );
    }

    return TraceSnapshot(
      running: snapshot.running != 0,
      mode: ProbeMode.fromNative(snapshot.mode),
      family: snapshot.family == 6 ? 6 : 4,
      reached: snapshot.reached != 0,
      reachedTtl: snapshot.reachedTtl,
      hopCount: hopCount,
      totalSent: snapshot.totalSent,
      totalRecv: snapshot.totalRecv,
      totalLost: snapshot.totalLost,
      startedMs: snapshot.startedMs,
      elapsedMs: snapshot.elapsedMs,
      targetAddr: _decodeFixed(snapshot.targetAddr.elements),
      hops: hops,
      error: _decodeFixed(snapshot.error.elements),
    );
  }

  void stop() {
    if (_disposed) return;
    _bindings.stop();
  }

  void dispose() {
    if (_disposed) return;
    try {
      _bindings.stop();
    } catch (_) {
      // Best effort when tearing down.
    }
    _disposed = true;
    calloc.free(_snapshotPtr);
  }

  static String? reverseLookup(String ip) {
    return NativeBindings.instance().reverseLookupSync(ip);
  }

  static String? reverseLookupIsolate(String ip) {
    final library = NativeBindings.openLibrary();
    // A lightweight local binding, safe to construct in a short-lived isolate.
    final engine = _IsolateLookup(library);
    return engine.lookup(ip);
  }

  static String _decodeFixed(List<int> bytes) {
    var length = bytes.length;
    while (length > 0 && bytes[length - 1] == 0) {
      length--;
    }
    if (length == 0) return '';
    return utf8.decode(bytes.sublist(0, length), allowMalformed: true);
  }
}

extension on String {
  String? ifEmptyNull() => isEmpty ? null : this;
}

class _IsolateLookup {
  _IsolateLookup(DynamicLibrary library)
    : _function = library
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Int32),
            int Function(Pointer<Utf8>, Pointer<Uint8>, int)
          >('dmtr_reverse_lookup');

  final int Function(Pointer<Utf8>, Pointer<Uint8>, int) _function;

  String? lookup(String ip) {
    final ipPtr = ip.toNativeUtf8();
    final out = calloc<Uint8>(256);
    try {
      if (_function(ipPtr, out, 256) != 0) return null;
      final bytes = out.asTypedList(256);
      var length = 0;
      while (length < 256 && bytes[length] != 0) {
        length++;
      }
      if (length == 0) return null;
      return utf8.decode(bytes.sublist(0, length), allowMalformed: true);
    } finally {
      calloc.free(ipPtr);
      calloc.free(out);
    }
  }
}

bool get nativeEngineSupported => Platform.isAndroid || Platform.isLinux;

/// Parses an IPv4 or IPv6 literal without a DNS lookup.
int? familyOfAddress(String address) {
  final parsed = InternetAddress.tryParse(address);
  if (parsed == null) return null;
  return parsed.type == InternetAddressType.IPv6 ? 6 : 4;
}
