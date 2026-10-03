import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/cart/server_order_totals.dart';

void main() {
  test('отличие серверной суммы видно по нужной дате, история не мешает', () {
    final result = reconcileServerOrderTotals(
      response: {
        'success': true,
        'order': [
          {
            'date': '2026-09-29T00:00:00',
            'finalPayable': 999,
            'finalPayableScope': 'document',
          },
          {
            'date': '2026-09-30T00:00:00',
            'finalPayable': 150.25,
            'finalPayableScope': 'employee_dishes',
          },
        ],
      },
      preliminaryRublesByDay: {'2026-09-30': 150},
    );
    expect(result, hasLength(1));
    expect(result.single.status, FinalAmountStatus.changed);
    expect(result.single.preliminaryKopecks, 15000);
    expect(result.single.serverKopecks, 15025);
    expect(result.single.scope, 'employee_dishes');
  });

  test(
    'сумма документа без расхождения подтверждается отдельно от старого sum',
    () {
      final result = reconcileServerOrderTotals(
        response: {
          'success': true,
          'order': [
            {
              'date': '2026-09-30T00:00:00',
              'sum': 180,
              'discount': 0,
              'finalPayable': 200,
              'finalPayableScope': 'document',
            },
          ],
        },
        preliminaryRublesByDay: {'2026-09-30': 200},
      );
      expect(result.single.status, FinalAmountStatus.unchanged);
      expect(result.single.serverKopecks, 20000);
    },
  );

  test(
    'ошибка или отсутствие окончательной суммы не подтверждает предпросмотр',
    () {
      for (final response in <Map<String, Object?>>[
        {
          'success': false,
          'order': [
            {
              'date': '2026-09-30',
              'finalPayable': 150,
              'finalPayableScope': 'document',
            },
          ],
        },
        {
          'success': true,
          'order': [
            {'date': '2026-09-30', 'sum': 150, 'discount': 0},
          ],
        },
        {'success': true, 'order': []},
      ]) {
        final result = reconcileServerOrderTotals(
          response: response,
          preliminaryRublesByDay: {'2026-09-30': 150},
        );
        expect(result.single.status, FinalAmountStatus.unconfirmed);
        expect(result.single.serverKopecks, isNull);
      }
    },
  );

  test('неоднозначный день и дробные доли копейки отклоняются', () {
    final result = reconcileServerOrderTotals(
      response: {
        'success': true,
        'order': [
          {
            'date': '2026-09-30',
            'finalPayable': 100,
            'finalPayableScope': 'document',
          },
          {
            'date': '2026-09-30T00:00:00',
            'finalPayable': 100,
            'finalPayableScope': 'document',
          },
          {
            'date': '2026-10-01',
            'finalPayable': 100.001,
            'finalPayableScope': 'document',
          },
        ],
      },
      preliminaryRublesByDay: {'2026-09-30': 100, '2026-10-01': 100},
    );
    expect(
      result.map((item) => item.status),
      everyElement(FinalAmountStatus.unconfirmed),
    );
  });
}
