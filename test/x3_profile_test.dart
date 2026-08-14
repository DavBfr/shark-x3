import 'package:flutter_test/flutter_test.dart';
import 'package:shark_x3/src/x3_profile.dart';

void main() {
  group('buildApplyPlan', () {
    test('first time (no last-applied) sends everything', () {
      final plan = buildApplyPlan(X3Profile.defaults(), null);
      expect(plan.send04, isTrue);
      expect(plan.send05, isTrue);
      expect(plan.send06, isTrue);
      expect(plan.anything, isTrue);
      expect(plan.changed, ['all settings (first time)']);
    });

    test('no changes -> nothing to send', () {
      final current = X3Profile.defaults();
      final plan = buildApplyPlan(current, current);
      expect(plan.anything, isFalse);
      expect(plan.send04, isFalse);
      expect(plan.send05, isFalse);
      expect(plan.send06, isFalse);
      expect(plan.changed, isEmpty);
    });

    test('only a DPI stage changed -> report 0x04 only', () {
      final last = X3Profile.defaults();
      final dpi = List<int>.of(last.dpi)..[2] = 3000;
      final current = last.copyWith(dpi: dpi);
      final plan = buildApplyPlan(current, last);
      expect(plan.send04, isTrue);
      expect(plan.send05, isFalse);
      expect(plan.send06, isFalse);
      expect(plan.changed, contains('DPI stage 3'));
    });

    test('only polling changed -> report 0x06 only', () {
      final last = X3Profile.defaults();
      final current = last.copyWith(polling: 500);
      final plan = buildApplyPlan(current, last);
      expect(plan.send06, isTrue);
      expect(plan.send04, isFalse);
      expect(plan.send05, isFalse);
      expect(plan.changed, ['polling rate']);
    });

    test('only a power setting changed -> report 0x05 only', () {
      final last = X3Profile.defaults();
      final current = last.copyWith(deepMinutes: 25);
      final plan = buildApplyPlan(current, last);
      expect(plan.send05, isTrue);
      expect(plan.send04, isFalse);
      expect(plan.send06, isFalse);
      expect(plan.changed, ['deep sleep']);
    });

    test('mixed changes -> several reports and labels', () {
      final last = X3Profile.defaults();
      final current = last.copyWith(
        dpi: [800, 1600, 2400, 3200, 6000, 26000],
        activeStage: 3,
        lod: 2,
        polling: 500,
        sleepMinutes: last.sleepMinutes + 1,
      );
      final plan = buildApplyPlan(current, last);
      expect(plan.send04, isTrue);
      expect(plan.send06, isTrue);
      expect(plan.send05, isTrue);
      expect(plan.changed, contains('DPI stage 5'));
      expect(plan.changed, contains('active DPI stage'));
      expect(plan.changed, contains('lift-off distance'));
      expect(plan.changed, contains('polling rate'));
      expect(plan.changed, contains('sleep time'));
    });
  });
}
