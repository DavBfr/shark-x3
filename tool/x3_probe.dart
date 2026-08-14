// ignore_for_file: avoid_print, dangling_library_doc_comments

/// Live diagnostic probe for the ATTACK SHARK X3.
///
/// Verifies the app's HID stack against a real mouse without launching the UI:
///   dart run tool/x3_probe.dart
///
/// On macOS, the hidapi framework lives inside the built app, so point
/// DYLD_FRAMEWORK_PATH at it first, e.g.:
///   DYLD_FRAMEWORK_PATH="$(pwd)/build/macos/Build/Products/Debug/shark_x3.app/Contents/Frameworks" \
///     dart run tool/x3_probe.dart
///
/// This connects to the config interface and APPLIES a default profile, so the
/// mouse LED should turn green (active stage 1 = 1600 DPI).
import 'dart:io';

import 'package:shark_x3/src/x3_device.dart';
import 'package:shark_x3/src/x3_protocol.dart' as proto;

Future<void> main() async {
  final service = X3DeviceService();
  print('hid available: ${service.available}');

  final find = await service.find();
  print('find.found: ${find.found}');
  print('message: ${find.message}');
  print('-- all matched interfaces --');
  for (final i in find.other) {
    final up = i.usagePage?.toRadixString(16).padLeft(2, '0') ?? '?';
    final u = i.usage?.toRadixString(16).padLeft(2, '0') ?? '?';
    print(
      '  usage $up/$u  intf=${i.interfaceNumber}  path=${i.path}  name="${i.productName}"',
    );
  }
  if (find.config == null) {
    print('NO CONFIG INTERFACE FOUND — aborting.');
    exit(1);
  }
  final cfg = find.config!;
  print(
    'config: ${cfg.path}  (usage ${cfg.usage?.toRadixString(16)}, '
    'intf ${cfg.interfaceNumber})',
  );

  final msg = await service.connect();
  print('connect: $msg  (connected=${service.isConnected})');
  if (!service.isConnected) exit(1);

  // Default profile — same as the app on first launch.
  const dpi = [800, 1600, 2400, 3200, 5000, 26000];
  const activeStage = 1; // 1600 DPI, green LED
  final r04 = proto.buildReport04(
    dpi: dpi,
    activeStage: activeStage,
    lod: 1,
    ripple: false,
    angle: false,
    motion: false,
  );
  final r06 = proto.buildReport06(1000);
  final r05 = proto.buildReport05(sleepMinutes: 4.5, deepMinutes: 10, keyMs: 6);

  print(
    'report 0x04 (${r04.length} B): '
    '${r04.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
  );
  final ok04 = await service.sendReport(proto.x3Report04, r04);
  print(
    'send 0x04 -> $ok04  (active stage $activeStage = ${dpi[activeStage]} '
    'DPI, green LED)',
  );
  final ok06 = await service.sendReport(proto.x3Report06, r06);
  print('send 0x06 -> $ok06  (polling 1000 Hz)');
  final ok05 = await service.sendReport(proto.x3Report05, r05);
  print('send 0x05 -> $ok05  (sleep 4.5 / deep 10 / key 6 ms)');

  print('best-effort read 0x04 (this device usually times out)...');
  final read = await service.readConfig04();
  print(
    'read 0x04 -> ${read != null ? 'OK dpi=${read.dpi} active=${read.activeStage}' : 'null (timeout — expected)'}',
  );

  await service.disconnect();
  print('disconnected. DONE.');
  exit(0);
}
