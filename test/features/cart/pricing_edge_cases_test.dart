// Пограничные случаи клиентского pricing (FL-02-09).
// Дополняет именованные примеры §5 из pricing_spec_examples_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/cart/pricing.dart';

ClientPricingConditions conditions({
  double pct = 0,
  int dc = 0,
  bool promo = false,
  int mpa = 0,
  int minOrder = 0,
  int? limit,
  bool weekLimit = false,
}) {
  return ClientPricingConditions(
    discountPercentage: pct,
    discountClient: dc,
    isDiscountPromotion: promo,
    minimumPaymentAmount: mpa,
    minimumOrderAmount: minOrder,
    limit: limit,
    limitPeriodRaw: weekLimit ? 'неделя' : 'день',
    isWeekLimitPeriod: weekLimit,
  );
}

void main() {
  group('пустой день', () {
    test(
      'пустой день в корзине не даёт вклад в неделю и не ломает минимум',
      () {
        final c = conditions(minOrder: 200, limit: 500, weekLimit: true);
        final days = [
          PricingDayInput(
            weekType: 'current',
            dayKey: 'empty',
            lines: const [],
          ),
          PricingDayInput(
            weekType: 'current',
            dayKey: 'full',
            lines: [PricingLineInput(price: 250, quantity: 1)],
          ),
        ];
        final cart = calculateCart(days: days, conditions: c);

        final empty = cart.days.firstWhere((d) => d.dayKey == 'empty');
        expect(empty.totals.finalTotal, 0);
        expect(empty.effectiveDiscountClient, 0);

        final emptyMin = checkDayMinimum(
          dayKey: 'empty',
          lines: const [],
          dayTotals: empty.totals,
          conditions: c,
        );
        expect(emptyMin.skippedEmptyDay, isTrue);
        expect(emptyMin.isBelowMinimum, isFalse);

        final full = cart.days.firstWhere((d) => d.dayKey == 'full');
        expect(full.totals.finalTotal, 250);
        expect(cart.weekTotalsByType['current']!.finalTotal, 250);

        final weekLimit = previewLimit(
          conditions: c,
          dayTotals: empty.totals,
          weekTotals: cart.weekTotalsByType['current']!,
        );
        expect(weekLimit.comparedFinalTotal, 250);
        expect(weekLimit.isExceeded, isFalse);
      },
    );

    test('количество 0 на единственной строке — нулевой день', () {
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [PricingLineInput(price: 190, quantity: 0)],
        conditions: conditions(minOrder: 100),
      );
      expect(day.totals.finalTotal, 0);
      expect(day.lines.single.baseTotal, 0);
    });
  });

  group('превышение дотации', () {
    test('профильный DC больше окна выше MPA — усечение', () {
      // после% = 200; MPA = 100 → доступно 100; DC профиля 500 → эфф. 100.
      final c = conditions(dc: 500, promo: true, mpa: 100);
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [PricingLineInput(price: 200, quantity: 1)],
        conditions: c,
      );
      expect(day.effectiveDiscountClient, 100);
      expect(day.totals.finalTotal, 100);
      expect(day.totals.discountClientAmount, 100);
    });

    test('без promo DC больше суммы дня — не выше после%', () {
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [
          PricingLineInput(price: 40, quantity: 1, menuOrder: 1),
          PricingLineInput(price: 40, quantity: 1, menuOrder: 2),
        ],
        conditions: conditions(dc: 1000),
      );
      expect(day.effectiveDiscountClient, 1000);
      expect(day.totals.discountClientAmount, 80);
      expect(day.totals.finalTotal, 0);
    });
  });

  group('скидка с дотацией', () {
    test('день после % ровно равен MPA → дотация 0', () {
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [PricingLineInput(price: 100, quantity: 1)],
        conditions: conditions(dc: 50, promo: true, mpa: 100),
      );
      expect(day.effectiveDiscountClient, 0);
      expect(day.totals.finalTotal, 100);
    });

    test('день после % = MPA + 1 → дотация ровно 1', () {
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [PricingLineInput(price: 101, quantity: 1)],
        conditions: conditions(dc: 50, promo: true, mpa: 100),
      );
      expect(day.effectiveDiscountClient, 1);
      expect(day.totals.finalTotal, 100);
    });

    test('% и дотация: после % затем усечение по MPA', () {
      // 220 − 10% = 198; MPA 100 → max дотации 98; DC 200 → эфф. 98.
      final day = calculateDayResult(
        weekType: 'current',
        dayKey: 1,
        lines: [PricingLineInput(price: 220, quantity: 1)],
        conditions: conditions(pct: 10, dc: 200, promo: true, mpa: 100),
      );
      expect(day.lines.single.discountAmount, 22);
      expect(day.lines.single.totalAfterPercentage, 198);
      expect(day.effectiveDiscountClient, 98);
      expect(day.totals.finalTotal, 100);
    });
  });

  group('предел лимита', () {
    test('итог ровно равен Limit — не превышен, остаток 0', () {
      final preview = previewLimit(
        conditions: conditions(limit: 300),
        dayTotals: const AggregateTotals(
          baseTotal: 300,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 300,
        ),
        weekTotals: AggregateTotals.zero,
      );
      expect(preview.isExceeded, isFalse);
      expect(preview.remainder, 0);
    });

    test('итог Limit + 1 — превышен', () {
      final preview = previewLimit(
        conditions: conditions(limit: 300),
        dayTotals: const AggregateTotals(
          baseTotal: 301,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 301,
        ),
        weekTotals: AggregateTotals.zero,
      );
      expect(preview.isExceeded, isTrue);
      expect(preview.remainder, -1);
    });

    test('недельный лимит: ровно на пороге по двум дням', () {
      final c = conditions(limit: 400, weekLimit: true);
      final days = [
        PricingDayInput(
          weekType: 'current',
          dayKey: 1,
          lines: [PricingLineInput(price: 200, quantity: 1)],
        ),
        PricingDayInput(
          weekType: 'current',
          dayKey: 2,
          lines: [PricingLineInput(price: 200, quantity: 1)],
        ),
      ];
      final cart = calculateCart(days: days, conditions: c);
      final week = cart.weekTotalsByType['current']!;
      expect(week.finalTotal, 400);
      final preview = previewLimit(
        conditions: c,
        dayTotals: cart.days.first.totals,
        weekTotals: week,
      );
      expect(preview.isExceeded, isFalse);
      expect(preview.remainder, 0);
    });
  });

  group('округление', () {
    test('половина вверх: base 1.5 → 2; % от 15 при 10% → 2', () {
      final half = calculateLineTotals(
        price: 1.5,
        quantity: 1,
        discountPercentage: 0,
        discountClientAvailable: 0,
      );
      expect(half.baseTotal, 2);

      final pct = calculateLineTotals(
        price: 15,
        quantity: 1,
        discountPercentage: 10,
        discountClientAvailable: 0,
      );
      expect(pct.discountAmount, 2);
      expect(pct.totalAfterPercentage, 13);
    });

    test('дробное количество: 10 × 2.5 → base 25', () {
      final line = calculateLineTotals(
        price: 10,
        quantity: 2.5,
        discountPercentage: 0,
        discountClientAvailable: 0,
      );
      expect(line.baseTotal, 25);
    });

    test('10.4 → 10; 10.6 → 11', () {
      expect(
        calculateLineTotals(
          price: 10.4,
          quantity: 1,
          discountPercentage: 0,
          discountClientAvailable: 0,
        ).baseTotal,
        10,
      );
      expect(
        calculateLineTotals(
          price: 10.6,
          quantity: 1,
          discountPercentage: 0,
          discountClientAvailable: 0,
        ).baseTotal,
        11,
      );
    });

    test('латинский MPA приоритетнее кириллического', () {
      final c = clientPricingConditionsFromUser({
        'MinimumPaymentAmount': '80',
        kMinimumPaymentAmountCyrillicKey: '100',
      });
      expect(c.minimumPaymentAmount, 80);
    });
  });
}
