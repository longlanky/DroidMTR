import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const int dmtrMaxHops = 64;
const int dmtrMaxSamples = 120;
const int dmtrMaxAlt = 4;
const int dmtrAddrLen = 46;
const int dmtrErrorLen = 160;
const int dmtrMagic = 0x4452544d;
const int dmtrAbiVersion = 1;

const int dmtrModeAuto = 0;
const int dmtrModeIcmp = 1;
const int dmtrModeUdp = 2;

const int capIcmp4 = 0x01;
const int capUdp4 = 0x02;
const int capIcmp6 = 0x04;
const int capUdp6 = 0x08;
const int capRecverr4 = 0x10;
const int capRecverr6 = 0x20;

/// C ABI mirrors of the structures in native/dmtr_engine.h.
final class DmtrConfig extends Struct {
  external Pointer<Utf8> targetAddr;
  @Int32()
  external int family;
  @Int32()
  external int maxHops;
  @Int32()
  external int intervalMs;
  @Int32()
  external int timeoutMs;
  @Int32()
  external int payloadBytes;
  @Int32()
  external int mode;
}

final class DmtrHop extends Struct {
  @Uint32()
  external int ttl;
  @Uint32()
  external int flags;
  @Int32()
  external int errorType;
  @Int32()
  external int errorCode;
  @Uint32()
  external int sent;
  @Uint32()
  external int recv;
  @Uint32()
  external int lost;
  @Uint32()
  external int pending;
  @Int32()
  external int lastUs;
  @Int32()
  external int bestUs;
  @Int32()
  external int avgUs;
  @Int32()
  external int worstUs;
  @Int32()
  external int stdevUs;
  @Int32()
  external int jitterUs;
  @Int32()
  external int jitterAvgUs;
  @Int32()
  external int jitterWorstUs;
  @Uint32()
  external int altCount;
  @Array(dmtrAddrLen)
  external Array<Uint8> addr;
  @Array(dmtrMaxAlt * dmtrAddrLen)
  external Array<Uint8> alts;
  @Uint32()
  external int sampleCount;
  @Array(dmtrMaxSamples)
  external Array<Int32> samples;
}

final class DmtrSnapshot extends Struct {
  @Uint32()
  external int magic;
  @Uint32()
  external int abiVersion;
  @Uint32()
  external int running;
  @Uint32()
  external int mode;
  @Uint32()
  external int family;
  @Uint32()
  external int reached;
  @Uint32()
  external int reachedTtl;
  @Uint32()
  external int frontier;
  @Uint32()
  external int hopCount;
  @Int32()
  external int errorType;
  @Int32()
  external int errorCode;
  @Uint32()
  external int totalSent;
  @Uint32()
  external int totalRecv;
  @Uint32()
  external int totalLost;
  @Uint32()
  external int hopCapacity;
  @Uint64()
  external int startedMs;
  @Uint64()
  external int elapsedMs;
  @Array(dmtrAddrLen)
  external Array<Uint8> targetAddr;
  @Array(dmtrErrorLen)
  external Array<Uint8> error;
  @Array(dmtrMaxHops)
  external Array<DmtrHop> hops;
}

typedef _StartNative = Int32 Function(
  Pointer<DmtrConfig>,
  Pointer<Uint8>,
  Int32,
);
typedef _StartDart = int Function(Pointer<DmtrConfig>, Pointer<Uint8>, int);

typedef _SnapshotNative = Int32 Function(Pointer<DmtrSnapshot>, Uint32);
typedef _SnapshotDart = int Function(Pointer<DmtrSnapshot>, int);

typedef _CapsNative = Uint32 Function();
typedef _CapsDart = int Function();

typedef _ReverseNative = Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Int32);
typedef _ReverseDart = int Function(Pointer<Utf8>, Pointer<Uint8>, int);

typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

class NativeBindings {
  NativeBindings._(DynamicLibrary lib)
    : _start = lib.lookupFunction<_StartNative, _StartDart>('dmtr_start'),
      _stop = lib.lookupFunction<Void Function(), void Function()>('dmtr_stop'),
      _snapshot = lib.lookupFunction<_SnapshotNative, _SnapshotDart>(
        'dmtr_snapshot',
      ),
      _running = lib.lookupFunction<Int32 Function(), int Function()>(
        'dmtr_is_running',
      ),
      _capabilities = lib.lookupFunction<_CapsNative, _CapsDart>(
        'dmtr_capabilities',
      ),
      _reverse = lib.lookupFunction<_ReverseNative, _ReverseDart>(
        'dmtr_reverse_lookup',
      ),
      _version = lib.lookupFunction<_VersionNative, _VersionDart>(
        'dmtr_version',
      );

  static NativeBindings? _instance;
  final _StartDart _start;
  final void Function() _stop;
  final _SnapshotDart _snapshot;
  final int Function() _running;
  final _CapsDart _capabilities;
  final _ReverseDart _reverse;
  final _VersionDart _version;

  static NativeBindings instance() {
    final existing = _instance;
    if (existing != null) return existing;
    final bindings = NativeBindings._(openLibrary());
    _instance = bindings;
    return bindings;
  }

  static DynamicLibrary openLibrary() {
    const override = String.fromEnvironment('DMTR_LIB');
    if (override.isNotEmpty) return DynamicLibrary.open(override);
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libdmtr.so');
    }
    if (Platform.isLinux) {
      // The Flutter Linux bundle keeps libraries in lib/ next to the executable.
      final executable = File(Platform.resolvedExecutable);
      final candidates = [
        '${executable.parent.path}/lib/libdmtr.so',
        '${executable.parent.path}/libdmtr.so',
      ];
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          return DynamicLibrary.open(candidate);
        }
      }
      // Development runs use LD_LIBRARY_PATH (for example the host test library).
      return DynamicLibrary.open('libdmtr.so');
    }
    return DynamicLibrary.process();
  }

  int get sizeOfSnapshot => sizeOf<DmtrSnapshot>();

  int start({
    required String address,
    required int family,
    required int maxHops,
    required int intervalMs,
    required int timeoutMs,
    required int payloadBytes,
    required int mode,
  }) {
    final config = calloc<DmtrConfig>();
    final addressPtr = address.toNativeUtf8();
    final errorPtr = calloc<Uint8>(dmtrErrorLen);
    try {
      config.ref
        ..targetAddr = addressPtr
        ..family = family
        ..maxHops = maxHops
        ..intervalMs = intervalMs
        ..timeoutMs = timeoutMs
        ..payloadBytes = payloadBytes
        ..mode = mode;
      final result = _start(config, errorPtr, dmtrErrorLen);
      if (result != 0) {
        final message = _readCString(errorPtr, dmtrErrorLen);
        throw NativeEngineException(
          message.isEmpty ? 'Unable to start the probe engine.' : message,
        );
      }
      return result;
    } finally {
      calloc.free(config);
      calloc.free(addressPtr);
      calloc.free(errorPtr);
    }
  }

  void stop() => _stop();
  int get isRunning => _running();
  int get capabilities => _capabilities();
  String get version => _version().toDartString();

  int snapshot(Pointer<DmtrSnapshot> out) =>
      _snapshot(out, sizeOf<DmtrSnapshot>());

  String? reverseLookupSync(String ip) {
    final ipPtr = ip.toNativeUtf8();
    final out = calloc<Uint8>(256);
    try {
      if (_reverse(ipPtr, out, 256) == 0) {
        final value = _readCString(out, 256);
        return value.isEmpty ? null : value;
      }
      return null;
    } finally {
      calloc.free(ipPtr);
      calloc.free(out);
    }
  }

  static String _readCString(Pointer<Uint8> pointer, int maxLength) {
    final bytes = pointer.asTypedList(maxLength);
    var length = 0;
    while (length < maxLength && bytes[length] != 0) {
      length++;
    }
    return String.fromCharCodes(bytes.take(length));
  }
}

class NativeEngineException implements Exception {
  NativeEngineException(this.message);
  final String message;

  @override
  String toString() => message;
}
