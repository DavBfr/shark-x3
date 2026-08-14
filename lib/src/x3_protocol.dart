/// Pure protocol codec for the ATTACK SHARK X3 configuration reports.
///
/// Ported 1:1 from `analysis/x3ctl.py` (which was verified against
/// differential USB captures). This file has **no I/O and no Flutter
/// dependency**, so it is safe to use in unit tests.
///
/// The X3 is configured by sending HID feature reports through the config
/// interface (System Control collection, usage 0x01/0x80):
///   * report 0x04 — main config (51-byte payload): DPI stages, lift-off,
///     ripple / angle snap / motion sync flags, active stage, checksum.
///   * report 0x05 — power (12-byte payload): sleep time, deep sleep, key
///     response time, checksum.
///   * report 0x06 — polling rate (9-byte payload).
///
/// All offsets below are relative to the **payload** (report-ID byte
/// stripped). On the wire the report ID is prepended.
library;

/// Number of DPI stages the mouse stores.
const int x3StageCount = 6;

/// Report IDs used by the config interface.
const int x3Report04 = 0x04; // main config (51-byte payload)
const int x3Report05 = 0x05; // sleep / deep sleep / key response (12 bytes)
const int x3Report06 = 0x06; // polling rate (9 bytes)

/// Polling codes for report 0x06: code = 1000 / Hz.
const Map<int, int> x3PollCode = {
  1000: 0x01,
  500: 0x02,
  250: 0x04,
  125: 0x08,
};

/// Report-0x04 payload field offsets.
const int x3LodOffset = 2; // 0 = 1 mm, 1 = 2 mm
const int x3RippleOffset = 3; // 0/1
const int x3AngleOffset = 5; // 0/1
const int x3MotionOffset = 6; // 0/1
const int x3DpiLowBase = 7; // DPI stage i low byte  at 7 + i
const int x3DpiHighBase = 15; // DPI stage i high byte at 15 + i (carry >12800)
const int x3ActiveOffset = 23; // active DPI stage, 1-based
const int x3ChecksumHiOffset = 49;
const int x3ChecksumLoOffset = 50;

/// Report-0x05 payload field offsets.
const int x5DeepHi = 3;
const int x5DeepLo = 4;
const int x5Sleep = 8; // minutes * 2
const int x5Key = 9; // ms / 2
const int x5DeepX = 10; // 1 (deep <= 30) or 2 (deep > 30)
const int x5Checksum = 11;

/// Report-0x06 payload field offsets.
const int x6Code = 2; // 1000 / Hz
const int x6Check = 3; // 0xFF - code

/// Default report-0x04 payload template (report ID stripped, 51 bytes).
///
/// The constant header / padding bytes are kept as-is; every mutable byte
/// (DPI, flags, active stage, checksums) is overwritten when building a
/// report. Verified against the capture: checksum == (0x0f, 0x89).
const List<int> x3Baseline04 = [
  0x38, 0x01, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x0e, 0x18, 0x35, 0x63, 0xc7, 0x8f,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0xff, 0x00,
  0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0x00, 0x00, 0xff, 0xff,
  0xff, 0x00, 0xff, 0xff, 0x40, 0x00, 0xff, 0xff, 0xff, 0x01, 0x0f, 0x89,
];

/// Report-0x05 default payload template (report ID stripped, 12 bytes).
/// Deep sleep 10 min, sleep 4.5 min, key response 6 ms; checksum recomputed.
const List<int> _x3Baseline05 = [
  0x0f, 0x01, 0x00, 0x03, 0xa8, 0x00, 0x00, 0xff, 0x09, 0x03, 0x01, 0x00,
];

/// Sums `p[from]` .. `p[toInclusive]` (inclusive).
int _sumRange(List<int> p, int from, int toInclusive) {
  var s = 0;
  for (var i = from; i <= toInclusive; i++) {
    s += p[i];
  }
  return s;
}

/// Encode a DPI value into its (low, high) payload bytes.
///
/// Encoding is `byte = DPI / 50 - 1`, split little-endian across the low
/// (offset 7+i) and high/carry (offset 15+i) bytes. The high byte is nonzero
/// only when `DPI > 12800` (max 26000 -> `07 02`).
(int, int) dpiToBytes(int dpi) {
  if (dpi % 50 != 0) {
    throw ArgumentError.value(dpi, 'dpi', 'must be a multiple of 50');
  }
  if (dpi < 50 || dpi > 26000) {
    throw ArgumentError.value(dpi, 'dpi', 'must be in range 50..26000');
  }
  final v = dpi ~/ 50 - 1;
  return (v & 0xff, (v >> 8) & 0xff);
}

/// Decode a DPI value from its (low, high) payload bytes.
int dpiFromBytes(int lo, int hi) => ((lo | (hi << 8)) + 1) * 50;

/// Report-0x04 dual checksum: returns (high, low).
///
///   [49] = (sum of bytes 1..48) >> 8        (carry of the data sum)
///   [50] = (sum of bytes 0..48 + 0xC7) & 0xFF
(int, int) checksum04(List<int> p) {
  if (p.length < 51) {
    throw ArgumentError.value(p.length, 'p', 'report 0x04 needs >= 51 bytes');
  }
  return (
    (_sumRange(p, 1, 48) >> 8) & 0xff,
    (_sumRange(p, 0, 48) + 0xC7) & 0xff,
  );
}

/// Report-0x05 checksum byte: (sum of bytes 0..9 + 0xF0) & 0xFF.
int checksum05(List<int> p) {
  if (p.length < 11) {
    throw ArgumentError.value(p.length, 'p', 'report 0x05 needs >= 11 bytes');
  }
  return (_sumRange(p, 0, 9) + 0xF0) & 0xff;
}

/// Encode deep-sleep minutes into report-0x05 bytes (hi, lo, x).
///
/// Stepped-linear map verified against 5/10/13/25/27/60 min captures:
///   value = (n << 4) | 8,  n = deep + 48  (deep <= 15)
///                           n = deep + 288 (16 <= deep <= 30)
///                           n = deep + 768 (deep > 30, only 60 verified)
/// `x` ([10]) is 1 for deep <= 30, else 2.
(int, int, int) deepSleepBytes(int deep) {
  if (deep < 1 || deep > 60) {
    throw ArgumentError.value(deep, 'deep', 'must be in range 1..60');
  }
  final n = deep <= 15
      ? deep + 48
      : deep <= 30
          ? deep + 288
          : deep + 768;
  final v = (n << 4) | 8;
  return ((v >> 8) & 0xff, v & 0xff, deep <= 30 ? 1 : 2);
}

/// Decode deep-sleep minutes from report-0x05 bytes [3], [4], [10].
int deepFromBytes(int hi, int lo, int x) {
  final v = (hi << 8) | lo;
  final n = v >> 4;
  if (n > 0x13E) return n - 768; // deep > 30
  if (n > 0x3F) return n - 288; // deep 16..30
  return n - 48; // deep <= 15
}

/// Map a polling code back to Hz (1000, 500, 250, 125) or null if unknown.
int? pollingFromCode(int code) {
  for (final entry in x3PollCode.entries) {
    if (entry.value == code) return entry.key;
  }
  return null;
}

/// Build a report-0x04 payload (51 bytes, report ID stripped).
///
/// Any omitted field keeps the value from the baseline template.
List<int> buildReport04({
  List<int>? dpi, // exactly [x3StageCount] values
  int? activeStage, // 0..5
  int? lod, // 1 or 2 mm
  bool? ripple,
  bool? angle,
  bool? motion,
}) {
  if (dpi != null && dpi.length != x3StageCount) {
    throw ArgumentError.value(
        dpi.length, 'dpi', 'must have exactly $x3StageCount values');
  }
  final p = List<int>.of(x3Baseline04);
  if (dpi != null) {
    for (var i = 0; i < x3StageCount; i++) {
      final (lo, hi) = dpiToBytes(dpi[i]);
      p[x3DpiLowBase + i] = lo;
      p[x3DpiHighBase + i] = hi;
    }
  }
  if (activeStage != null) {
    if (activeStage < 0 || activeStage >= x3StageCount) {
      throw ArgumentError.value(
          activeStage, 'activeStage', 'must be in range 0..5');
    }
    p[x3ActiveOffset] = activeStage + 1;
  }
  if (lod != null) {
    if (lod != 1 && lod != 2) {
      throw ArgumentError.value(lod, 'lod', 'must be 1 or 2');
    }
    p[x3LodOffset] = lod == 2 ? 1 : 0;
  }
  if (ripple != null) p[x3RippleOffset] = ripple ? 1 : 0;
  if (angle != null) p[x3AngleOffset] = angle ? 1 : 0;
  if (motion != null) p[x3MotionOffset] = motion ? 1 : 0;
  final (hi, lo) = checksum04(p);
  p[x3ChecksumHiOffset] = hi;
  p[x3ChecksumLoOffset] = lo;
  return p;
}

/// Build a report-0x05 payload (12 bytes, report ID stripped).
List<int> buildReport05({
  double? sleepMinutes, // 0.5..30 in 0.5 steps
  int? deepMinutes, // 1..60
  int? keyMs, // 1..50 (even values round-trip exactly)
}) {
  final p = List<int>.of(_x3Baseline05);
  if (sleepMinutes != null) {
    p[x5Sleep] = (sleepMinutes * 2).round();
  }
  if (keyMs != null) {
    p[x5Key] = (keyMs / 2).round();
  }
  if (deepMinutes != null) {
    final (hi, lo, x) = deepSleepBytes(deepMinutes);
    p[x5DeepHi] = hi;
    p[x5DeepLo] = lo;
    p[x5DeepX] = x;
  }
  p[x5Checksum] = checksum05(p);
  return p;
}

/// Build a report-0x06 payload (9 bytes, report ID stripped) for a polling
/// rate of 125, 250, 500 or 1000 Hz.
List<int> buildReport06(int polling) {
  final code = x3PollCode[polling];
  if (code == null) {
    throw ArgumentError.value(
        polling, 'polling', 'must be one of ${x3PollCode.keys.toList()..sort()}');
  }
  return [0x09, 0x01, code, (0xFF - code) & 0xff, 0, 0, 0, 0, 0];
}

/// Result of decoding a report-0x04 payload.
class X3ConfigDecode {
  X3ConfigDecode({
    required this.lod,
    required this.ripple,
    required this.angle,
    required this.motion,
    required this.dpi,
    required this.activeStage,
    required this.checksumHi,
    required this.checksumLo,
    required this.checksumOk,
  });

  final int lod; // 1 or 2 mm
  final bool ripple;
  final bool angle;
  final bool motion;
  final List<int> dpi; // 6 values
  final int activeStage; // 0-based
  final int checksumHi;
  final int checksumLo;
  final bool checksumOk;
}

/// Result of decoding a report-0x05 payload.
class X3PowerDecode {
  X3PowerDecode({
    required this.sleepMinutes,
    required this.keyMs,
    required this.deepMinutes,
    required this.checksum,
    required this.checksumOk,
  });

  final double sleepMinutes;
  final int keyMs;
  final int deepMinutes;
  final int checksum;
  final bool checksumOk;
}

/// Result of decoding a report-0x06 payload.
class X3PollingDecode {
  X3PollingDecode({
    required this.polling,
    required this.code,
    required this.check,
  });

  final int? polling; // Hz, null if unknown code
  final int code;
  final int check;
}

/// Decode a report-0x04 payload, or null if it is too short.
X3ConfigDecode? decode04(List<int> p) {
  if (p.length < 51) return null;
  final dpi = [
    for (var i = 0; i < x3StageCount; i++)
      dpiFromBytes(p[x3DpiLowBase + i], p[x3DpiHighBase + i]),
  ];
  final (hi, lo) = checksum04(p);
  return X3ConfigDecode(
    lod: p[x3LodOffset] == 1 ? 2 : 1,
    ripple: p[x3RippleOffset] == 1,
    angle: p[x3AngleOffset] == 1,
    motion: p[x3MotionOffset] == 1,
    dpi: dpi,
    activeStage: p[x3ActiveOffset] - 1,
    checksumHi: p[x3ChecksumHiOffset],
    checksumLo: p[x3ChecksumLoOffset],
    checksumOk: p[x3ChecksumHiOffset] == hi && p[x3ChecksumLoOffset] == lo,
  );
}

/// Decode a report-0x05 payload, or null if it is too short.
X3PowerDecode? decode05(List<int> p) {
  if (p.length < 12) return null;
  return X3PowerDecode(
    sleepMinutes: p[x5Sleep] / 2,
    keyMs: p[x5Key] * 2,
    deepMinutes: deepFromBytes(p[x5DeepHi], p[x5DeepLo], p[x5DeepX]),
    checksum: p[x5Checksum],
    checksumOk: p[x5Checksum] == checksum05(p),
  );
}

/// Decode a report-0x06 payload, or null if it is too short.
X3PollingDecode? decode06(List<int> p) {
  if (p.length < 4) return null;
  final code = p[x6Code];
  return X3PollingDecode(
    polling: pollingFromCode(code),
    code: code,
    check: p[x6Check],
  );
}

/// Strip a leading report-ID byte from a read payload when present.
///
/// macOS/Linux keep the report ID at index 0 of a feature-report read;
/// Windows strips it already. This normalizes both to a pure payload.
List<int> stripReportId(List<int> data, int reportId) =>
    data.isNotEmpty && data.first == reportId
        ? data.sublist(1)
        : List<int>.of(data);
