// Набор сверки FL-02-10: клиентские ожидания из reconciliation_set.json.
// observedServer не проверяется — runtime Zak ещё не заполнен.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/cart/pricing.dart';

Map<String, Object?> _asStringKeyedMap(Object? raw) {
  if (raw is! Map) {
    throw FormatException('Ожидался объект, получено $raw');
  }
  return {for (final entry in raw.entries) entry.key.toString(): entry.value};
}

List<PricingDayInput> _daysFromJson(List<dynamic> daysJson) {
  return [
    for (final dayRaw in daysJson)
      () {
        final day = _asStringKeyedMap(dayRaw);
        final linesRaw = day['lines'];
        if (linesRaw is! List) {
          throw const FormatException('days.lines должен быть списком');
        }
        return PricingDayInput(
          weekType: day['weekType']?.toString() ?? '',
          dayKey: day['dayKey'] ?? '',
          lines: [
            for (final lineRaw in linesRaw)
              () {
                final line = _asStringKeyedMap(lineRaw);
                return PricingLineInput(
                  price: line['price'],
                  quantity: line['quantity'],
                  menuOrder: line['menuOrder'] is num
                      ? (line['menuOrder'] as num).toInt()
                      : missingMenuOrder,
                );
              }(),
          ],
        );
      }(),
  ];
}

void main() {
  late Map<String, Object?> root;
  late List<Map<String, Object?>> cases;

  setUpAll(() {
    final file = File('test/fixtures/pricing/reconciliation_set.json');
    root = _asStringKeyedMap(jsonDecode(file.readAsStringSync()));
    final rawCases = root['cases'];
    expect(rawCases, isA<List>());
    cases = [for (final item in rawCases as List) _asStringKeyedMap(item)];
  });

  test('набор содержит не меньше 10 кейсов', () {
    expect(cases.length, greaterThanOrEqualTo(10));
  });

  test('каждый кейс имеет id, профиль, дни и expectedClient', () {
    for (final c in cases) {
      expect(c['id'], isA<String>());
      expect(c['profile'], isA<Map>());
      expect(c['days'], isA<List>());
      expect(c['expectedClient'], isA<Map>());
    }
  });

  test('клиентский расчёт совпадает с expectedClient по всем кейсам', () {
    for (final c in cases) {
      final id = c['id'] as String;
      final profile = _asStringKeyedMap(c['profile']);
      final conditions = clientPricingConditionsFromUser(profile);
      final dayInputs = _daysFromJson(c['days'] as List);
      final cart = calculateCart(days: dayInputs, conditions: conditions);
      final expected = _asStringKeyedMap(c['expectedClient']);

      final expectedDays = expected['days'] as List;
      expect(cart.days, hasLength(expectedDays.length), reason: id);
      for (var i = 0; i < expectedDays.length; i++) {
        final exp = _asStringKeyedMap(expectedDays[i]);
        final actual = cart.days[i];
        expect(actual.dayKey, exp['dayKey'], reason: '$id dayKey');
        expect(
          actual.totals.finalTotal,
          exp['finalTotal'],
          reason: '$id final',
        );
        expect(actual.totals.baseTotal, exp['baseTotal'], reason: '$id base');
        expect(
          actual.totals.discountAmount,
          exp['discountAmount'],
          reason: '$id %',
        );
        expect(
          actual.totals.discountClientAmount,
          exp['discountClientAmount'],
          reason: '$id DC',
        );
      }

      final weekExp = _asStringKeyedMap(expected['weekFinalByType']);
      for (final entry in weekExp.entries) {
        expect(
          cart.weekTotalsByType[entry.key]?.finalTotal,
          entry.value,
          reason: '$id week ${entry.key}',
        );
      }

      final limitExp = expected['limit'];
      if (limitExp is Map) {
        final lim = _asStringKeyedMap(limitExp);
        final compareDayKey = lim['compareDayKey'];
        final dayTotals = compareDayKey == null
            ? cart.days.first.totals
            : cart.days.firstWhere((d) => d.dayKey == compareDayKey).totals;
        final weekType = dayInputs.first.weekType;
        final preview = previewLimit(
          conditions: conditions,
          dayTotals: dayTotals,
          weekTotals: cart.weekTotalsByType[weekType] ?? AggregateTotals.zero,
        );
        expect(
          preview.isWeekPeriod,
          lim['isWeekPeriod'],
          reason: '$id lim week',
        );
        expect(
          preview.comparedFinalTotal,
          lim['comparedFinalTotal'],
          reason: '$id lim compared',
        );
        expect(preview.isExceeded, lim['isExceeded'], reason: '$id lim exceed');
        expect(preview.remainder, lim['remainder'], reason: '$id lim rem');
      }

      final minExp = expected['minimum'];
      if (minExp is List) {
        for (final item in minExp) {
          final exp = _asStringKeyedMap(item);
          final dayKey = exp['dayKey'];
          final dayIndex = cart.days.indexWhere((d) => d.dayKey == dayKey);
          expect(dayIndex, isNonNegative, reason: '$id min day $dayKey');
          final dayResult = cart.days[dayIndex];
          final lines = dayInputs[dayIndex].lines;
          final check = checkDayMinimum(
            dayKey: dayKey ?? dayResult.dayKey,
            lines: lines,
            dayTotals: dayResult.totals,
            conditions: conditions,
          );
          if (exp.containsKey('skippedEmptyDay')) {
            expect(
              check.skippedEmptyDay,
              exp['skippedEmptyDay'],
              reason: '$id min skip',
            );
          }
          if (exp.containsKey('effectiveMinimum')) {
            expect(
              check.effectiveMinimum,
              exp['effectiveMinimum'],
              reason: '$id min eff',
            );
          }
          expect(
            check.isBelowMinimum,
            exp['isBelowMinimum'],
            reason: '$id min below',
          );
        }
      }
    }
  });

  test('все текущие кейсы помечены synthetic; server пуст', () {
    for (final c in cases) {
      expect(c['provenance'], 'synthetic');
      expect(c['observedServer'], isNull);
    }
  });
}
