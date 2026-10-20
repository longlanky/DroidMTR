// ignore_for_file: avoid_print

// Developer tool: validates the Dart FFI ABI against a host build of libdmtr.
//
//   cmake -S native -B build/native-host
//   cmake --build build/native-host
//   LD_LIBRARY_PATH=build/native-host dart run tool/verify_native.dart 1.1.1.1
import 'dart:ffi';
import 'dart:io';

import 'package:droid_mtr/services/native_bindings.dart';
import 'package:ffi/ffi.dart';

void main(List<String> args) {
  final address = args.isEmpty ? '1.1.1.1' : args.first;
  final bindings = NativeBindings.instance();
  print('engine version: ${bindings.version}');
  print('snapshot size: ${sizeOf<DmtrSnapshot>()}');
  print('config size: ${sizeOf<DmtrConfig>()}');
  print('capabilities: 0x${bindings.capabilities.toRadixString(16)}');

  final family = address.contains(':') ? 6 : 4;
  bindings.start(
    address: address,
    family: family,
    maxHops: 30,
    intervalMs: 1000,
    timeoutMs: 2000,
    payloadBytes: 64,
    mode: 0,
  );

  final out = calloc<DmtrSnapshot>();
  try {
    for (var tick = 0; tick < 30; tick++) {
      sleep(const Duration(milliseconds: 200));
      final rc = bindings.snapshot(out);
      if (rc != 1) {
        print('snapshot failed: $rc');
        exitCode = 1;
        break;
      }
      final snap = out.ref;
      if (snap.magic != dmtrMagic) {
        print('bad magic: 0x${snap.magic.toRadixString(16)}');
        exitCode = 1;
        break;
      }
      if (tick % 5 == 4 || snap.reached != 0) {
        print(
          '${(snap.elapsedMs / 1000).toStringAsFixed(1)}s '
          'mode=${snap.mode} hops=${snap.hopCount} '
          'reached=${snap.reached} ttl=${snap.reachedTtl} '
          'sent=${snap.totalSent} recv=${snap.totalRecv} '
          'lost=${snap.totalLost} error="${_string(snap.error.elements)}"',
        );
        for (var i = 0; i < snap.hopCount; i++) {
          final hop = snap.hops[i];
          if (hop.sent == 0 && hop.recv == 0) continue;
          print(
            '  ${hop.ttl} ${_string(hop.addr.elements).padRight(40)} '
            'loss=${hop.lost + hop.recv == 0 ? 0 : (100 * hop.lost / (hop.lost + hop.recv)).toStringAsFixed(1)}% '
            'sent=${hop.sent} recv=${hop.recv} '
            'best=${hop.bestUs ~/ 1000}ms avg=${hop.avgUs ~/ 1000}ms '
            'worst=${hop.worstUs ~/ 1000}ms samples=${hop.sampleCount}',
          );
        }
      }
      if (tick > 10 && snap.reached != 0) break;
    }
  } finally {
    bindings.stop();
    calloc.free(out);
  }
}

String _string(List<int> bytes) {
  var length = bytes.length;
  while (length > 0 && bytes[length - 1] == 0) {
    length--;
  }
  return String.fromCharCodes(bytes.sublist(0, length));
}
