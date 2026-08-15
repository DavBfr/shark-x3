/// Decoder for the live status/input reports the X3 pushes on its config
/// interface (report ID `0x03`).
///
/// No Flutter dependency — safe for unit tests. This encodes what we've
/// decoded from live captures so far (2026-08-15):
///
///   `03 00 10 <1..6> 00`  → DPI stage changed (byte 3 = stage, 1-based)
///   `03 10 40 01 <link>`  → wireless-link status — only sent over 2.4G
///                           (stops while charging / wired). Byte 2 is a
///                           link/state code (`0x40`), byte 4 fluctuates
///                           (likely signal). No battery: values don't change
///                           at 100% charge.
///   `03 10 50 xx 04`      → the mouse acknowledged a config write
library;

/// What kind of `0x03` report this is.
enum X3StatusKind {
  /// `03 00 10 <stage> 00` — the active DPI stage changed.
  dpiStage,

  /// `03 10 40 01 <link>` — wireless-link status (2.4G only).
  status,

  /// `03 10 50 xx 04` — the mouse acknowledged a config write.
  writeAck,

  /// Something we haven't decoded yet.
  unknown,
}

/// A single decoded status report pushed by the mouse.
class X3StatusReport {
  const X3StatusReport({
    required this.raw,
    required this.kind,
    this.dpiStage,
    this.stateByte,
    this.linkValue,
    this.description = '',
  });

  /// The raw report bytes (report ID at index 0).
  final List<int> raw;

  final X3StatusKind kind;

  /// For [X3StatusKind.dpiStage]: the active DPI stage, 1-based.
  final int? dpiStage;

  /// For [X3StatusKind.status]: the byte-2 link/state code (`0x40`).
  final int? stateByte;

  /// For [X3StatusKind.status]: the byte-4 link/signal value.
  final int? linkValue;

  /// Short human-readable summary.
  final String description;

  /// The raw bytes as lowercase hex, space separated.
  String get rawHex =>
      raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

/// Decode a pushed input report, or null for an empty buffer.
X3StatusReport? decodeStatusReport(List<int> raw) {
  if (raw.isEmpty) return null;
  final id = raw[0];
  if (id != 0x03) {
    return X3StatusReport(
      raw: List<int>.of(raw),
      kind: X3StatusKind.unknown,
      description: 'report 0x${id.toRadixString(16).padLeft(2, '0')} — unknown',
    );
  }
  // DPI stage change: 03 00 10 <1..6> 00
  if (raw.length >= 5 &&
      raw[1] == 0x00 &&
      raw[2] == 0x10 &&
      raw[4] == 0x00 &&
      raw[3] >= 1 &&
      raw[3] <= 6) {
    final stage = raw[3];
    return X3StatusReport(
      raw: List<int>.of(raw),
      kind: X3StatusKind.dpiStage,
      dpiStage: stage,
      description: 'DPI stage changed → $stage',
    );
  }
  // Config-write acknowledgement: 03 10 50 xx 04
  if (raw.length >= 5 && raw[1] == 0x10 && raw[2] == 0x50) {
    return X3StatusReport(
      raw: List<int>.of(raw),
      kind: X3StatusKind.writeAck,
      description: 'Config write acknowledged',
    );
  }
  // Wireless-link status: 03 10 40 01 <link> (2.4G only)
  if (raw.length >= 5 && raw[1] == 0x10 && raw[2] == 0x40) {
    return X3StatusReport(
      raw: List<int>.of(raw),
      kind: X3StatusKind.status,
      stateByte: raw[2],
      linkValue: raw[4],
      description:
          'Wireless status — link 0x${raw[2].toRadixString(16).padLeft(2, '0')}'
          ' · signal ${raw[4]}',
    );
  }
  return X3StatusReport(
    raw: List<int>.of(raw),
    kind: X3StatusKind.unknown,
    description: 'report 0x03 — unhandled variant',
  );
}
