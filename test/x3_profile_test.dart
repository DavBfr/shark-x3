import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shark_x3/src/x3_profile.dart';
import 'package:shark_x3/src/x3_protocol.dart' as proto;

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

    test('first time does NOT send buttons (untouched)', () {
      final plan = buildApplyPlan(X3Profile.defaults(), null);
      expect(plan.send08, isFalse);
      expect(plan.anything, isTrue); // 04/05/06 still sent
    });

    test('editing a button makes the plan send report 0x08', () {
      final last = X3Profile.defaults();
      final codes = List<int>.of(proto.x3DefaultButtonCodes)
        ..[1] = proto.x3ButtonActionBrowserHome;
      final current = last.copyWith(buttonCodes: codes);
      final plan = buildApplyPlan(current, last);
      expect(plan.send08, isTrue);
      expect(plan.changed, contains('button map'));
      expect(plan.send04, isFalse);
      expect(plan.anything, isTrue);
      expect(current.toReport08(), isNotNull);
    });

    test('unchanged buttons are not resent', () {
      final codes = List<int>.of(proto.x3DefaultButtonCodes);
      final last = X3Profile.defaults().copyWith(buttonCodes: codes);
      final current = last.copyWith(polling: 500);
      final plan = buildApplyPlan(current, last);
      expect(plan.send08, isFalse);
      expect(plan.send06, isTrue);
    });

    test('button codes survive a JSON round-trip', () {
      final codes = List<int>.of(proto.x3DefaultButtonCodes)
        ..[6] = proto.x3ButtonActionFire;
      final profile = X3Profile.defaults().copyWith(buttonCodes: codes);
      final restored = X3Profile.fromJsonString(jsonEncode(profile.toJson()))!;
      expect(restored.buttonCodes, codes);
    });

    test('JSON without buttonCodes loads with buttons untouched (null)', () {
      final profile = X3Profile.fromJsonString(
        jsonEncode(X3Profile.defaults().toJson()),
      )!;
      expect(profile.buttonCodes, isNull);
      expect(profile.toReport08(), isNull);
    });
  });
}
