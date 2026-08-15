import 'package:flutter_test/flutter_test.dart';
import 'package:shark_x3/src/x3_protocol.dart';

void main() {
  group('DPI encoding / decoding', () {
    // Known values from the README / differential capture table.
    const cases = <int, (int, int)>{
      50: (0x00, 0x00),
      750: (0x0e, 0x00),
      800: (0x0f, 0x00),
      1000: (0x13, 0x00),
      11600: (0xe7, 0x00),
      1250: (0x18, 0x00),
      5000: (0x63, 0x00),
      10000: (0xc7, 0x00),
      18100: (0x69, 0x01),
      20000: (0x8f, 0x01),
      26000: (0x07, 0x02),
    };

    test('dpiToBytes matches known captures', () {
      cases.forEach((dpi, bytes) {
        expect(dpiToBytes(dpi), bytes, reason: 'DPI $dpi');
      });
    });

    test('dpiFromBytes round-trips known captures', () {
      cases.forEach((dpi, bytes) {
        final (lo, hi) = bytes;
        expect(dpiFromBytes(lo, hi), dpi, reason: 'bytes $lo,$hi');
      });
    });

    test('default profile values round-trip', () {
      const defaults = [800, 1600, 2400, 3200, 5000, 26000];
      for (final dpi in defaults) {
        final (lo, hi) = dpiToBytes(dpi);
        expect(dpiFromBytes(lo, hi), dpi);
      }
    });

    test('26000 on stage 5 uses the carry byte', () {
      final p = buildReport04(dpi: [800, 1600, 2400, 3200, 5000, 26000]);
      expect(p[7 + 5], 0x07); // low
      expect(p[15 + 5], 0x02); // high / carry
    });

    test('rejects non-multiple-of-50 and out-of-range', () {
      expect(() => dpiToBytes(1001), throwsArgumentError);
      expect(() => dpiToBytes(49), throwsArgumentError);
      expect(() => dpiToBytes(26050), throwsArgumentError);
    });
  });

  group('report 0x04', () {
    test('baseline checksum is verified (0x0f, 0x89)', () {
      expect(checksum04(x3Baseline04), (0x0f, 0x89));
    });

    test('empty buildReport04 reproduces the baseline', () {
      final p = buildReport04();
      expect(p, x3Baseline04);
      final d = decode04(p)!;
      expect(d.checksumOk, isTrue);
    });

    test('DPI + active stage + flags round-trip', () {
      const dpi = [800, 1600, 2400, 3200, 5000, 26000];
      final p = buildReport04(
        dpi: dpi,
        activeStage: 3,
        lod: 2,
        ripple: true,
        angle: true,
        motion: true,
      );
      final d = decode04(p)!;
      expect(d.dpi, dpi);
      expect(d.activeStage, 3);
      expect(d.lod, 2);
      expect(d.ripple, isTrue);
      expect(d.angle, isTrue);
      expect(d.motion, isTrue);
      expect(d.checksumOk, isTrue);
    });

    test('active stage is 1-based at byte 23', () {
      final p = buildReport04(activeStage: 4);
      expect(p[23], 5);
      expect(decode04(p)!.activeStage, 4);
    });

    test('LOD default (1 mm) encodes to 0; 2 mm to 1', () {
      expect(buildReport04()[2], 0);
      expect(buildReport04(lod: 2)[2], 1);
    });

    test('rejects invalid arguments', () {
      expect(() => buildReport04(dpi: [800]), throwsArgumentError);
      expect(() => buildReport04(activeStage: 6), throwsArgumentError);
      expect(() => buildReport04(lod: 3), throwsArgumentError);
    });

    test('decode04 returns null when too short', () {
      expect(decode04([1, 2, 3]), isNull);
    });
  });

  group('report 0x05 (sleep / deep / key)', () {
    test('deep-sleep bytes match the README capture table', () {
      const expected = <int, (int, int)>{
        5: (0x03, 0x58),
        10: (0x03, 0xa8),
        13: (0x03, 0xd8),
        25: (0x13, 0x98),
        27: (0x13, 0xb8),
        60: (0x33, 0xc8),
      };
      expected.forEach((deep, bytes) {
        final (hi, lo, x) = deepSleepBytes(deep);
        expect((hi, lo), bytes, reason: 'deep $deep');
        expect(x, deep <= 30 ? 1 : 2, reason: 'deep $deep x');
      });
    });

    test('deep sleep round-trips across all bands', () {
      for (var deep = 1; deep <= 60; deep++) {
        final (hi, lo, x) = deepSleepBytes(deep);
        expect(deepFromBytes(hi, lo, x), deep, reason: 'deep $deep');
      }
    });

    test('default template decodes to sleep 4.5 / key 6 / deep 10', () {
      final p = buildReport05();
      final d = decode05(p)!;
      expect(d.sleepMinutes, 4.5);
      expect(d.keyMs, 6);
      expect(d.deepMinutes, 10);
      expect(d.checksumOk, isTrue);
    });

    test('custom values round-trip', () {
      final p = buildReport05(sleepMinutes: 2, deepMinutes: 25, keyMs: 24);
      final d = decode05(p)!;
      expect(d.sleepMinutes, 2);
      expect(d.deepMinutes, 25);
      expect(d.keyMs, 24);
      expect(d.checksumOk, isTrue);
    });

    test('deep-sleep boundaries (15/16/30/31)', () {
      for (final deep in [15, 16, 30, 31, 45]) {
        final (hi, lo, x) = deepSleepBytes(deep);
        expect(deepFromBytes(hi, lo, x), deep);
      }
    });

    test('rejects out-of-range deep', () {
      expect(() => deepSleepBytes(0), throwsArgumentError);
      expect(() => deepSleepBytes(61), throwsArgumentError);
    });
  });

  group('report 0x06 (polling)', () {
    test('codes match 1000/Hz', () {
      expect(buildReport06(1000), [0x09, 0x01, 0x01, 0xfe, 0, 0, 0, 0, 0]);
      expect(buildReport06(500), [0x09, 0x01, 0x02, 0xfd, 0, 0, 0, 0, 0]);
      expect(buildReport06(250), [0x09, 0x01, 0x04, 0xfb, 0, 0, 0, 0, 0]);
      expect(buildReport06(125), [0x09, 0x01, 0x08, 0xf7, 0, 0, 0, 0, 0]);
    });

    test('decode06 round-trips', () {
      for (final polling in [1000, 500, 250, 125]) {
        final d = decode06(buildReport06(polling))!;
        expect(d.polling, polling);
        expect(d.check, 0xFF - d.code);
      }
    });

    test('rejects invalid polling', () {
      expect(() => buildReport06(750), throwsArgumentError);
    });
  });

  group('report 0x08 (button map)', () {
    List<int> hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ];

    final defaults = x3DefaultButtonCodes;

    test('default map reproduces the "forward" capture (checksum c2)', () {
      expect(
        buildReport08(defaults),
        hex(
          '3b010200000300000400000d00003c00000f00000600000500003c'
          '00000100000100000100000100000100000100000100000a000009'
          '000000c2',
        ),
      );
    });

    test(
      'row 7 = fire (0x10) reproduces the "fire" capture incl. param 03',
      () {
        final codes = List<int>.of(defaults)..[6] = x3ButtonActionFire;
        expect(
          buildReport08(codes),
          hex(
            '3b010200000300000400000d00003c00000f00001000030500003c'
            '00000100000100000100000100000100000100000100000a000009'
            '000000cf',
          ),
        );
      },
    );

    test(
      'row 2 = browser home (0x25) reproduces the "browser home" capture',
      () {
        final codes = List<int>.of(defaults)..[1] = x3ButtonActionBrowserHome;
        expect(
          buildReport08(codes),
          hex(
            '3b010200002500000400000d00003c00000f00000600000500003c'
            '00000100000100000100000100000100000100000100000a000009'
            '000000e4',
          ),
        );
      },
    );

    test('row 2 = left click reproduces the "2 → left click" capture', () {
      final codes = List<int>.of(defaults)..[1] = x3ButtonActionLeft;
      expect(
        buildReport08(codes),
        hex(
          '3b010200000200000400000d00003c00000f00000600000500003c'
          '00000100000100000100000100000100000100000100000a000009'
          '000000c1',
        ),
      );
    });

    test('rows 1+2 swapped reproduces the "1 → right click" capture', () {
      final codes = List<int>.of(defaults)
        ..[0] = x3ButtonActionRight
        ..[1] = x3ButtonActionLeft;
      expect(
        buildReport08(codes),
        hex(
          '3b010300000200000400000d00003c00000f00000600000500003c'
          '00000100000100000100000100000100000100000100000a000009'
          '000000c2',
        ),
      );
    });

    test('row 3 = double click reproduces the "3 → double click" capture', () {
      final codes = List<int>.of(defaults)
        ..[0] = x3ButtonActionRight
        ..[1] = x3ButtonActionLeft
        ..[2] = x3ButtonActionDoubleClick;
      expect(
        buildReport08(codes),
        hex(
          '3b010300000200000700000d00003c00000f00000600000500003c'
          '00000100000100000100000100000100000100000100000a000009'
          '000000c5',
        ),
      );
    });

    test('row 8 = middle click reproduces the "5 → middle click" capture', () {
      final codes = List<int>.of(defaults)
        ..[0] = x3ButtonActionRight
        ..[1] = x3ButtonActionLeft
        ..[2] = x3ButtonActionDoubleClick
        ..[7] = x3ButtonActionMiddle;
      expect(
        buildReport08(codes),
        hex(
          '3b010300000200000700000d00003c00000f00000600000400003c'
          '00000100000100000100000100000100000100000100000a000009'
          '000000c4',
        ),
      );
    });

    test('decode08 round-trips and validates the checksum', () {
      final d = decode08(buildReport08(defaults))!;
      expect(d.codes, defaults);
      expect(d.checksumOk, isTrue);
      expect(d.params.where((p) => p != 0), isEmpty);
    });

    test('fire decode carries the param byte 03', () {
      final codes = List<int>.of(defaults)..[6] = x3ButtonActionFire;
      final d = decode08(buildReport08(codes))!;
      expect(d.codes[6], x3ButtonActionFire);
      expect(d.params[6], 0x03);
      expect(d.checksumOk, isTrue);
    });

    test('detects a corrupt checksum', () {
      final p = buildReport08(defaults);
      p[57] = (p[57] + 1) & 0xff;
      final d = decode08(p)!;
      expect(d.checksumOk, isFalse);
    });

    test('rejects a wrong row count', () {
      expect(() => buildReport08(List.filled(17, 0)), throwsArgumentError);
    });
  });

  group('stripReportId', () {
    test('strips when present, otherwise passes through', () {
      expect(stripReportId([0x04, 0x38, 0x01], 0x04), [0x38, 0x01]);
      expect(stripReportId([0x38, 0x01], 0x04), [0x38, 0x01]);
    });
  });
}
