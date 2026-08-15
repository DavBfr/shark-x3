/// User-facing profile model for the X3 configuration app.
///
/// Holds every setting the app can change, its factory defaults, the LED
/// color shown by the mouse for each DPI stage, and JSON round-tripping for
/// profile persistence.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'x3_protocol.dart' as proto;

/// The mouse LED color associated with each DPI stage.
///
/// This is a property of the mouse firmware (the LED reflects the active
/// stage); it is displayed in the UI for guidance, not sent as a setting.
class X3LedInfo {
  const X3LedInfo(this.name, this.color);

  final String name;
  final Color color;
}

/// Stage order: 800 (red), 1600 (green, default active), 2400 (blue),
/// 3200 (cyan), 5000 (yellow), 26000 (purple).
const List<X3LedInfo> x3StageLed = [
  X3LedInfo('red', Color(0xFFE53935)),
  X3LedInfo('green', Color(0xFF43A047)),
  X3LedInfo('blue', Color(0xFF1E88E5)),
  X3LedInfo('cyan', Color(0xFF00ACC1)),
  X3LedInfo('yellow', Color(0xFFFDD835)),
  X3LedInfo('purple', Color(0xFF8E24AA)),
];

class X3Profile {
  X3Profile({
    required this.dpi,
    required this.activeStage,
    required this.polling,
    required this.lod,
    required this.ripple,
    required this.angle,
    required this.motion,
    required this.sleepMinutes,
    required this.deepMinutes,
    required this.keyMs,
    this.buttonCodes,
  });

  /// Factory defaults: DPI stages 800/1600/2400/3200/5000/26000 with the
  /// 1600 (green) stage active, polling 1000 Hz, LOD 1 mm, all toggles off,
  /// sleep 2 min, deep sleep 10 min, key response 6 ms.
  factory X3Profile.defaults() => X3Profile(
    dpi: const [800, 1600, 2400, 3200, 5000, 26000],
    activeStage: 1, // 1600 DPI = green LED is the default active stage
    polling: 1000,
    lod: 1,
    ripple: false,
    angle: false,
    motion: false,
    sleepMinutes: 2,
    deepMinutes: 10,
    keyMs: 6,
  );

  final List<int> dpi; // 6 DPI values
  final int activeStage; // 0..5
  final int polling; // Hz: 125 / 250 / 500 / 1000
  final int lod; // 1 or 2 mm
  final bool ripple;
  final bool angle;
  final bool motion;
  final double sleepMinutes; // 0.5..30
  final int deepMinutes; // 1..60
  final int keyMs; // 1..50

  /// 18 button action codes for report 0x08, or null when the user hasn't
  /// touched the buttons (nothing is sent until one is changed).
  final List<int>? buttonCodes;

  int get activeDpi => dpi[activeStage];
  X3LedInfo get activeLed => x3StageLed[activeStage];

  X3Profile copyWith({
    List<int>? dpi,
    int? activeStage,
    int? polling,
    int? lod,
    bool? ripple,
    bool? angle,
    bool? motion,
    double? sleepMinutes,
    int? deepMinutes,
    int? keyMs,
    List<int>? buttonCodes,
    bool clearButtons = false,
  }) {
    return X3Profile(
      dpi: List<int>.of(dpi ?? this.dpi),
      activeStage: activeStage ?? this.activeStage,
      polling: polling ?? this.polling,
      lod: lod ?? this.lod,
      ripple: ripple ?? this.ripple,
      angle: angle ?? this.angle,
      motion: motion ?? this.motion,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      deepMinutes: deepMinutes ?? this.deepMinutes,
      keyMs: keyMs ?? this.keyMs,
      buttonCodes: clearButtons
          ? null
          : (buttonCodes != null
                ? List<int>.of(buttonCodes)
                : this.buttonCodes),
    );
  }

  /// Build the report-0x04 payload for this profile.
  List<int> toReport04() => proto.buildReport04(
    dpi: dpi,
    activeStage: activeStage,
    lod: lod,
    ripple: ripple,
    angle: angle,
    motion: motion,
  );

  /// Build the report-0x05 payload for this profile.
  List<int> toReport05() => proto.buildReport05(
    sleepMinutes: sleepMinutes,
    deepMinutes: deepMinutes,
    keyMs: keyMs,
  );

  /// Build the report-0x06 payload for this profile.
  List<int> toReport06() => proto.buildReport06(polling);

  /// Build the report-0x08 payload, or null when the button map hasn't been
  /// touched (there is nothing to send).
  List<int>? toReport08() {
    final codes = buttonCodes;
    if (codes == null) return null;
    return proto.buildReport08(codes);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'dpi': dpi,
    'activeStage': activeStage,
    'polling': polling,
    'lod': lod,
    'ripple': ripple,
    'angle': angle,
    'motion': motion,
    'sleepMinutes': sleepMinutes,
    'deepMinutes': deepMinutes,
    'keyMs': keyMs,
    'buttonCodes': buttonCodes,
  };

  /// Parse from JSON, clamping every value to its valid range and falling
  /// back to defaults for missing fields. Returns null on malformed input.
  static X3Profile? fromJson(Map<String, dynamic> json) {
    try {
      final defaults = X3Profile.defaults();
      final dpi = <int>[];
      final rawDpi = json['dpi'];
      if (rawDpi is List) {
        for (final v in rawDpi) {
          dpi.add(clampDpi((v as num).toInt()));
        }
      }
      while (dpi.length < proto.x3StageCount) {
        dpi.add(defaults.dpi[dpi.length]);
      }
      if (dpi.length > proto.x3StageCount) {
        dpi.removeRange(proto.x3StageCount, dpi.length);
      }
      List<int>? buttonCodes;
      final rawButtons = json['buttonCodes'];
      if (rawButtons is List) {
        final codes = <int>[];
        for (final v in rawButtons) {
          codes.add((v as num).toInt() & 0xff);
        }
        while (codes.length < proto.x3ButtonRowCount) {
          codes.add(proto.x3DefaultButtonCodes[codes.length]);
        }
        if (codes.length > proto.x3ButtonRowCount) {
          codes.removeRange(proto.x3ButtonRowCount, codes.length);
        }
        buttonCodes = codes;
      }
      return X3Profile(
        dpi: dpi,
        activeStage: clampStage(
          (json['activeStage'] as num?)?.toInt() ?? defaults.activeStage,
        ),
        polling: clampPolling(
          (json['polling'] as num?)?.toInt() ?? defaults.polling,
        ),
        lod: ((json['lod'] as num?)?.toInt() ?? defaults.lod) == 2 ? 2 : 1,
        ripple: json['ripple'] as bool? ?? defaults.ripple,
        angle: json['angle'] as bool? ?? defaults.angle,
        motion: json['motion'] as bool? ?? defaults.motion,
        sleepMinutes: clampSleep(
          (json['sleepMinutes'] as num?)?.toDouble() ?? defaults.sleepMinutes,
        ),
        deepMinutes: clampDeep(
          (json['deepMinutes'] as num?)?.toInt() ?? defaults.deepMinutes,
        ),
        keyMs: clampKey((json['keyMs'] as num?)?.toInt() ?? defaults.keyMs),
        buttonCodes: buttonCodes,
      );
    } catch (_) {
      return null;
    }
  }

  static X3Profile? fromJsonString(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  // ---- Clamping helpers (shared by the UI and JSON loading) ----

  /// Snap to the nearest multiple of 50 within 50..26000.
  static int clampDpi(int v) {
    final snapped = (v / 50).round() * 50;
    return math.max(50, math.min(26000, snapped));
  }

  /// Snap to 0.5 steps within 0.5..30 minutes.
  static double clampSleep(double v) {
    final snapped = (v * 2).round() / 2;
    return math.max(0.5, math.min(30, snapped));
  }

  static int clampDeep(int v) => math.max(1, math.min(60, v));
  static int clampKey(int v) => math.max(1, math.min(50, v));
  static int clampStage(int v) => math.max(0, math.min(5, v));

  /// Snap to the nearest of 125 / 250 / 500 / 1000 Hz.
  static int clampPolling(int v) {
    const options = [125, 250, 500, 1000];
    var best = options.first;
    var bestDiff = (v - best).abs();
    for (final o in options) {
      final diff = (v - o).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = o;
      }
    }
    return best;
  }
}

/// Which reports to send to the mouse on an Apply, based on what changed
/// since the last successful apply.
class X3ApplyPlan {
  const X3ApplyPlan({
    required this.send04,
    required this.send05,
    required this.send06,
    required this.send08,
    required this.changed,
  });

  /// Send report 0x04 (sensitivity / DPI, flags, lift-off, active stage)?
  final bool send04;

  /// Send report 0x05 (sleep / deep sleep / key response)?
  final bool send05;

  /// Send report 0x06 (polling rate)?
  final bool send06;

  /// Send report 0x08 (button map)?
  final bool send08;

  /// Human-readable summary of what changed (empty when nothing to send).
  final List<String> changed;

  bool get anything => send04 || send05 || send06 || send08;
}

/// Work out which reports to send to bring the mouse from [lastApplied] up to
/// [current].
///
/// The mouse cannot report its own settings (feature reads time out), so the
/// app keeps a copy of the last successful apply in shared_preferences and
/// treats it as the source of truth for what is on the mouse. The first time
/// there is no such copy, everything is sent; afterwards only the reports
/// whose fields changed are sent. Each report is atomic (a full payload), so a
/// single changed DPI stage still sends the whole report 0x04.
///
/// The button map (report 0x08) is opt-in: it is only sent once the user has
/// actually edited a button ([X3Profile.buttonCodes] is non-null), because the
/// row-to-button mapping is only partially decoded and we don't want to
/// overwrite unknown factory buttons on the very first apply.
X3ApplyPlan buildApplyPlan(X3Profile current, X3Profile? lastApplied) {
  bool sameIntList(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  final changed = <String>[];

  var send08 = false;
  if (current.buttonCodes != null &&
      !sameIntList(current.buttonCodes, lastApplied?.buttonCodes)) {
    send08 = true;
    changed.add('button map');
  }

  if (lastApplied == null) {
    return X3ApplyPlan(
      send04: true,
      send05: true,
      send06: true,
      send08: send08,
      changed: ['all settings (first time)'],
    );
  }

  var send04 = false;
  for (var i = 0; i < current.dpi.length; i++) {
    if (current.dpi[i] != lastApplied.dpi[i]) {
      changed.add('DPI stage ${i + 1}');
      send04 = true;
    }
  }
  if (current.activeStage != lastApplied.activeStage) {
    changed.add('active DPI stage');
    send04 = true;
  }
  if (current.lod != lastApplied.lod) {
    changed.add('lift-off distance');
    send04 = true;
  }
  if (current.ripple != lastApplied.ripple) {
    changed.add('ripple control');
    send04 = true;
  }
  if (current.angle != lastApplied.angle) {
    changed.add('angle snap');
    send04 = true;
  }
  if (current.motion != lastApplied.motion) {
    changed.add('motion sync');
    send04 = true;
  }

  final send06 = current.polling != lastApplied.polling;
  if (send06) changed.add('polling rate');

  var send05 = false;
  if (current.sleepMinutes != lastApplied.sleepMinutes) {
    changed.add('sleep time');
    send05 = true;
  }
  if (current.deepMinutes != lastApplied.deepMinutes) {
    changed.add('deep sleep');
    send05 = true;
  }
  if (current.keyMs != lastApplied.keyMs) {
    changed.add('key response time');
    send05 = true;
  }

  return X3ApplyPlan(
    send04: send04,
    send05: send05,
    send06: send06,
    send08: send08,
    changed: changed,
  );
}
