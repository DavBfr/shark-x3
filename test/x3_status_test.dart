import 'package:flutter_test/flutter_test.dart';
import 'package:shark_x3/src/x3_status.dart';

void main() {
  group('decodeStatusReport', () {
    test('DPI stage change report', () {
      for (var stage = 1; stage <= 6; stage++) {
        final r = decodeStatusReport([0x03, 0x00, 0x10, stage, 0x00])!;
        expect(r.kind, X3StatusKind.dpiStage);
        expect(r.dpiStage, stage);
        final hex = stage.toRadixString(16).padLeft(2, '0');
        expect(r.rawHex, '03 00 10 $hex 00');
      }
    });

    test('periodic status report decodes battery candidate', () {
      final r = decodeStatusReport([0x03, 0x10, 0x40, 0x01, 0x0a])!;
      expect(r.kind, X3StatusKind.status);
      expect(r.stateByte, 0x40);
      expect(r.batteryPercent, 100); // 0x0a = 100%

      final r70 = decodeStatusReport([0x03, 0x10, 0x40, 0x01, 0x07])!;
      expect(r70.batteryPercent, 70); // 0x07 = 70%
    });

    test('config-write ack report', () {
      final r = decodeStatusReport([0x03, 0x10, 0x50, 0x01, 0x04])!;
      expect(r.kind, X3StatusKind.writeAck);
    });

    test('unknown report id', () {
      final r = decodeStatusReport([0x04, 0x38, 0x01])!;
      expect(r.kind, X3StatusKind.unknown);
      expect(r.rawHex, '04 38 01');
    });

    test('unhandled 0x03 variant', () {
      final r = decodeStatusReport([0x03, 0xff, 0xff, 0xff, 0xff])!;
      expect(r.kind, X3StatusKind.unknown);
    });

    test('empty buffer -> null', () {
      expect(decodeStatusReport(const []), isNull);
    });
  });
}
