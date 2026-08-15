/// Device service: talks to the ATTACK SHARK X3 through the `hid` plugin.
///
/// The X3 is a composite HID device; its configuration interface is the
/// **System Control** collection (usage page 0x01 / usage 0x80), which is the
/// only place the firmware accepts config feature reports. The stock `open()`
/// of the hid package opens by VID/PID and can pick the wrong interface, so
/// this service finds the config collection by its usage (or Windows `mi_02`
/// path, or interface 2) and opens it **by path** (`openPath`).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hid/hid.dart' as hid;

import 'x3_protocol.dart';
import 'x3_status.dart';

const int x3VendorId = 0x1d57;

/// Supported product IDs: `0xfa61` (wired USB mouse) and `0xfa60` (2.4G
/// wireless dongle). Both use the same config protocol.
const Set<int> x3ProductIds = {0xfa61, 0xfa60};

bool _isX3(int vendorId, int productId) =>
    vendorId == x3VendorId && x3ProductIds.contains(productId);

/// Public info about one of the mouse's HID interfaces.
class X3DeviceInfo {
  const X3DeviceInfo({
    required this.path,
    required this.productName,
    this.usagePage,
    this.usage,
    this.interfaceNumber,
  });

  final String path;
  final String productName;
  final int? usagePage;
  final int? usage;
  final int? interfaceNumber;

  String get label {
    final usage = this.usage;
    return usage != null
        ? '0x${usage.toRadixString(16).padLeft(2, '0')}'
        : path;
  }
}

/// Result of trying to find the config interface.
class X3FindResult {
  const X3FindResult({
    required this.found,
    this.config,
    this.configs = const [],
    this.other = const [],
    this.message = '',
  });

  final bool found;

  /// The preferred config interface (the first of [configs]).
  final X3DeviceInfo? config;

  /// Config interfaces in priority order (wired before wireless); [connect]
  /// tries each until one opens.
  final List<X3DeviceInfo> configs;

  final List<X3DeviceInfo> other;
  final String message;
}

/// Result of applying a set of reports.
class X3SendResult {
  const X3SendResult({required this.ok, required this.messages});

  final bool ok;
  final List<String> messages;
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

class X3DeviceService {
  hid.HidDevice? _device;
  X3DeviceInfo? _config;

  bool get isConnected => _device != null;
  X3DeviceInfo? get config => _config;
  bool get available => hid.hid.available;

  /// Convert an enumerated hid device into our public info type.
  X3DeviceInfo _toInfo(hid.HidDevice d) => X3DeviceInfo(
    path: d.path ?? '',
    productName: d.productName,
    usagePage: d.usagePage,
    usage: d.usage,
    interfaceNumber: d.interfaceNumber,
  );

  /// Enumerate the mouse and locate the configuration interface.
  ///
  /// Selection order:
  ///   1. System Control collection (usage 0x01/0x80) — where report 0x04 lives
  ///   2. Windows `mi_02` path marker (interface 2)
  ///   3. interface number 2
  ///   4. any interface with a usable path
  Future<X3FindResult> find() async {
    if (!available) {
      return const X3FindResult(
        found: false,
        message:
            'HID is not available on this platform. Run this app on macOS, Windows or Linux.',
      );
    }
    final List<hid.HidDevice> devices;
    try {
      devices = await hid.hid.getDeviceList();
    } catch (e) {
      return X3FindResult(
        found: false,
        message: 'Could not list HID devices: $e',
      );
    }
    final matches = devices
        .where((d) => _isX3(d.vendorId, d.productId))
        .toList();
    if (matches.isEmpty) {
      return const X3FindResult(
        found: false,
        message:
            'No ATTACK SHARK X3 mouse found. Plug it in (or pair it) and try again.',
      );
    }
    // Prefer the wired mouse (0xfa61) over the 2.4G wireless dongle (0xfa60).
    final ordered = [
      ...matches.where((d) => d.productId == 0xfa61),
      ...matches.where((d) => d.productId == 0xfa60),
    ];
    final infos = ordered.map(_toInfo).toList();
    // Config candidates in priority order (dedup by path): the System Control
    // collection first, then the Windows mi_02 marker, then interface 2, then
    // any usable path. connect() tries each in order.
    final configs = <X3DeviceInfo>[];
    final seen = <String>{};
    void addCandidates(Iterable<X3DeviceInfo> items) {
      for (final i in items) {
        if (i.path.isNotEmpty && seen.add(i.path)) {
          configs.add(i);
        }
      }
    }

    addCandidates(infos.where((i) => i.usagePage == 0x01 && i.usage == 0x80));
    addCandidates(infos.where((i) => i.path.contains('mi_02')));
    addCandidates(infos.where((i) => i.interfaceNumber == 2));
    addCandidates(infos.where((i) => i.path.isNotEmpty));
    if (configs.isEmpty) {
      return X3FindResult(
        found: false,
        other: infos,
        message:
            'Found the mouse, but could not locate its configuration '
            'interface. Try unplugging and replugging it.',
      );
    }
    return X3FindResult(
      found: true,
      config: configs.first,
      configs: configs,
      other: infos,
    );
  }

  /// Connect to the configuration interface and keep it open.
  ///
  /// Returns a friendly status message; on success [isConnected] is true.
  Future<String> connect() async {
    await disconnect();
    final findResult = await find();
    if (!findResult.found || findResult.config == null) {
      return findResult.message.isEmpty
          ? 'Could not connect to the mouse.'
          : findResult.message;
    }
    final cfg = findResult.config!;
    final List<hid.HidDevice> devices;
    try {
      devices = await hid.hid.getDeviceList();
    } catch (_) {
      return 'Could not open the mouse (device list error).';
    }
    final match =
        _firstWhereOrNull(devices, (d) => d.path == cfg.path) ??
        _firstWhereOrNull(devices, (d) => _isX3(d.vendorId, d.productId));
    if (match == null) return 'Could not reopen the mouse to configure it.';
    final opened = await match.openPath(cfg.path);
    if (!opened) {
      final detail = match.lastError;
      final hint =
          ' It may be in use — close other programs that talk to the mouse '
          'and try again.';
      return 'Could not open the mouse’s configuration interface'
          '${detail != null && detail.isNotEmpty ? ' — $detail' : ''}.$hint';
    }
    _device = match;
    _config = cfg;
    return 'Connected to ${cfg.productName.isEmpty ? 'the mouse' : cfg.productName}.';
  }

  /// Close the open handle, if any.
  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    _config = null;
    if (device != null) {
      await device.close();
    }
  }

  /// Send one feature report: [reportId] followed by [payload].
  ///
  /// Returns true when the device accepted the write.
  Future<bool> sendReport(int reportId, List<int> payload) async {
    final device = _device;
    if (device == null) return false;
    final frame = Uint8List(payload.length + 1)..[0] = reportId;
    frame.setRange(1, frame.length, payload);
    try {
      final written = await device.setFeatures(frame);
      return written >= 1;
    } catch (_) {
      return false;
    }
  }

  /// Apply reports in the canonical order: 0x04 (config) -> 0x06 (polling) ->
  /// 0x08 (buttons) -> 0x05 (power). Null reports are skipped.
  Future<X3SendResult> sendAll({
    List<int>? report04,
    List<int>? report05,
    List<int>? report06,
    List<int>? report08,
  }) async {
    final messages = <String>[];
    var allOk = true;
    const labels = {
      x3Report04: 'Sensitivity (DPI)',
      x3Report05: 'Power settings',
      x3Report06: 'Polling rate',
      x3Report08: 'Buttons',
    };
    for (final (rid, payload) in [
      (x3Report04, report04),
      (x3Report06, report06),
      (x3Report08, report08),
      (x3Report05, report05),
    ]) {
      if (payload == null) continue;
      final ok = await sendReport(rid, payload);
      final label = labels[rid] ?? 'Report 0x${rid.toRadixString(16)}';
      messages.add('$label: ${ok ? 'sent' : 'failed'}');
      if (!ok) allOk = false;
    }
    return X3SendResult(ok: allOk, messages: messages);
  }

  /// Best-effort read of a feature report.
  ///
  /// This device normally times out on reads (expected); returns null on any
  /// failure. Handles the platform asymmetry of the hid plugin (Windows strips
  /// the report-ID byte, macOS/Linux keep it at index 0).
  Future<List<int>?> readReport(
    int reportId, {
    required int payloadLength,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final device = _device;
    if (device == null) return null;
    final isWindows = Platform.isWindows;
    final bufLen = isWindows ? payloadLength : payloadLength + 1;
    final input = Uint8List(bufLen)..[0] = reportId;
    try {
      final data = await device.getFeatures(input).timeout(timeout);
      if (data.isEmpty) return null;
      final payload = isWindows
          ? List<int>.of(data)
          : stripReportId(data, reportId);
      return payload.length >= payloadLength ? payload : null;
    } on Exception {
      return null;
    }
  }

  /// Best-effort read of the report-0x04 config (decoded), or null.
  Future<X3ConfigDecode?> readConfig04() async {
    final payload = await readReport(x3Report04, payloadLength: 51);
    return payload == null ? null : decode04(payload);
  }

  /// A live stream of decoded status reports the mouse pushes on the config
  /// interface (report 0x03). Empty when not connected; the stream ends when
  /// the device is closed.
  Stream<X3StatusReport> watchStatus() {
    final device = _device;
    if (device == null) return const Stream<X3StatusReport>.empty();
    return device
        .read(64, 50) // input reports, polled every 50 ms
        .where((chunk) => chunk.isNotEmpty)
        .map((chunk) => decodeStatusReport(chunk))
        .where((report) => report != null)
        .map((report) => report!);
  }
}
