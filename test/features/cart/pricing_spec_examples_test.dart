// Автотесты согласованных примеров pricing-spec §5 (FL-02-08).
// Эталон — клиентский предпросмотр, не runtime Zak.

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
  String limitPeriodRaw = '',
}) {
  final raw = limitPeriodRaw.isNotEmpty
      ? limitPeriodRaw
      : (weekLimit ? 'неделя' : 'день');
  return ClientPricingConditions(
    discountPercentage: pct,
    discountClient: dc,
    isDiscountPromotion: promo,
    minimumPaymentAmount: mpa,
    minimumOrderAmount: minOrder,
    limit: limit,
    limitPeriodRaw: raw,
    isWeekLimitPeriod: weekLimit || raw.trim().toLowerCase() == 'неделя',
  );
}

PricingDayResult dayOf(
  List<PricingLineInput> lines,
  ClientPricingConditions c, {
  String weekType = 'current',
  Object dayKey = 1,
}) {
  return calculateDayResult(
    weekType: weekType,
    dayKey: dayKey,
    lines: lines,
    conditions: c,
  );
}

void main() {
  group('§5.1 DiscountPercentage', () {
    test('P-1: 10% от 190', () {
      final line = calculateLineTotals(
        price: 190,
        quantity: 1,
        discountPercentage: 10,
        discountClientAvailable: 0,
      );
      expect(line.baseTotal, 190);
      expect(line.discountAmount, 19);
      expect(line.totalAfterPercentage, 171);
      expect(line.finalTotal, 171);
    });

    test('P-2: процент 0 / отсутствует', () {
      final zero = calculateLineTotals(
        price: 190,
        quantity: 1,
        discountPercentage: 0,
        discountClientAvailable: 0,
      );
      expect(zero.finalTotal, 190);
      final fromUser = clientPricingConditionsFromUser({
        'DiscountPercentage': null,
      });
      final line = calculateLineTotals(
        price: 190,
        quantity: 1,
        discountPercentage: fromUser.discountPercentage,
        discountClientAvailable: 0,
      );
      expect(line.finalTotal, 190);
    });

    test('P-3: процент 150 клип до 100', () {
      final line = calculateLineTotals(
        price: 190,
        quantity: 1,
        discountPercentage: 150,
        discountClientAvailable: 0,
      );
      expect(line.discountAmount, 190);
      expect(line.totalAfterPercentage, 0);
      expect(line.finalTotal, 0);
    });
  });

  group('§5.2 DiscountClient без дотации', () {
    test('C-1: дневная без оплаты 50', () {
      final c = conditions(dc: 50);
      final day = dayOf([PricingLineInput(price: 190, quantity: 1)], c);
      expect(day.effectiveDiscountClient, 50);
      expect(day.lines.single.discountClientAmount, 50);
      expect(day.lines.single.finalTotal, 140);
      expect(day.totals.finalTotal, 140);
    });

    test('C-2: распределение A→B', () {
      final c = conditions(dc: 150);
      final day = dayOf(
        [
          PricingLineInput(price: 100, quantity: 1, menuOrder: 1),
          PricingLineInput(price: 100, quantity: 1, menuOrder: 2),
        ],
        c,
      );
      expect(day.effectiveDiscountClient, 150);
      expect(day.lines[0].discountClientAmount, 100);
      expect(day.lines[0].finalTotal, 0);
      expect(day.lines[1].discountClientAmount, 50);
      expect(day.lines[1].finalTotal, 50);
      expect(day.totals.discountClientAmount, 150);
      expect(day.totals.finalTotal, 50);
    });

    test('C-3: без оплаты больше суммы дня', () {
      final day = dayOf(
        [PricingLineInput(price: 100, quantity: 1)],
        conditions(dc: 500),
      );
      expect(day.lines.single.discountClientAmount, 100);
      expect(day.lines.single.finalTotal, 0);
    });
  });

  group('§5.3 DiscountPromotion + MPA', () {
    test('D-1: дотация с MPA', () {
      final c = conditions(dc: 250, promo: true, mpa: 100);
      final day = dayOf(
        [
          PricingLineInput(price: 200, quantity: 1, menuOrder: 1),
          PricingLineInput(price: 200, quantity: 1, menuOrder: 2),
        ],
        c,
      );
      expect(day.effectiveDiscountClient, 250);
      expect(day.lines[0].discountClientAmount, 200);
      expect(day.lines[0].finalTotal, 0);
      expect(day.lines[1].discountClientAmount, 50);
      expect(day.lines[1].finalTotal, 150);
      expect(day.totals.finalTotal, 150);
    });

    test('D-2: день ≤ MPA → дотация 0', () {
      final day = dayOf(
        [PricingLineInput(price: 80, quantity: 1)],
        conditions(dc: 50, promo: true, mpa: 100),
      );
      expect(day.effectiveDiscountClient, 0);
      expect(day.totals.finalTotal, 80);
    });

    test('D-3: promo=1, MPA выкл.', () {
      final day = dayOf(
        [PricingLineInput(price: 300, quantity: 1)],
        conditions(dc: 50, promo: true, mpa: 0),
      );
      expect(day.effectiveDiscountClient, 50);
      expect(day.totals.finalTotal, 250);
    });
  });

  group('§5.4 процент и без оплаты', () {
    test('X-1: % затем фиксированная сумма', () {
      final day = dayOf(
        [PricingLineInput(price: 250, quantity: 1)],
        conditions(pct: 10, dc: 50),
      );
      final line = day.lines.single;
      expect(line.baseTotal, 250);
      expect(line.discountAmount, 25);
      expect(line.totalAfterPercentage, 225);
      expect(line.discountClientAmount, 50);
      expect(line.finalTotal, 175);
    });

    test('X-2: % на строках, остаток без оплаты', () {
      final day = dayOf(
        [
          PricingLineInput(price: 100, quantity: 1, menuOrder: 1),
          PricingLineInput(price: 100, quantity: 1, menuOrder: 2),
        ],
        conditions(pct: 10, dc: 50),
      );
      expect(day.lines[0].discountAmount, 10);
      expect(day.lines[0].totalAfterPercentage, 90);
      expect(day.lines[0].discountClientAmount, 50);
      expect(day.lines[0].finalTotal, 40);
      expect(day.lines[1].totalAfterPercentage, 90);
      expect(day.lines[1].discountClientAmount, 0);
      expect(day.lines[1].finalTotal, 90);
      expect(day.totals.finalTotal, 130);
    });

    test('X-3: % + дотация с MPA', () {
      final day = dayOf(
        [
          PricingLineInput(price: 200, quantity: 1, menuOrder: 1),
          PricingLineInput(price: 200, quantity: 1, menuOrder: 2),
        ],
        conditions(pct: 10, dc: 250, promo: true, mpa: 100),
      );
      expect(day.lines[0].totalAfterPercentage, 180);
      expect(day.lines[1].totalAfterPercentage, 180);
      expect(day.effectiveDiscountClient, 250);
      expect(day.lines[0].discountClientAmount, 180);
      expect(day.lines[0].finalTotal, 0);
      expect(day.lines[1].discountClientAmount, 70);
      expect(day.lines[1].finalTotal, 110);
      expect(day.totals.finalTotal, 110);
    });
  });

  group('§5.5 MinimumOrderAmount', () {
    test('M-1: ниже минимума', () {
      final lines = [PricingLineInput(price: 150, quantity: 1)];
      final c = conditions(minOrder: 200);
      final day = dayOf(lines, c);
      final check = checkDayMinimum(
        dayKey: 1,
        lines: lines,
        dayTotals: day.totals,
        conditions: c,
      );
      expect(day.totals.finalTotal, 150);
      expect(check.effectiveMinimum, 200);
      expect(check.isBelowMinimum, isTrue);
    });

    test('M-2: выше минимума', () {
      final lines = [PricingLineInput(price: 250, quantity: 1)];
      final c = conditions(minOrder: 200);
      final day = dayOf(lines, c);
      final check = checkDayMinimum(
        dayKey: 1,
        lines: lines,
        dayTotals: day.totals,
        conditions: c,
      );
      expect(check.isBelowMinimum, isFalse);
    });

    test('M-3: дотация снижает порог; итог 150', () {
      // Итог 150 при DC=80 → блюдо 230 (без оплаты 80).
      final lines = [PricingLineInput(price: 230, quantity: 1)];
      final c = conditions(dc: 80, promo: true, minOrder: 200);
      final day = dayOf(lines, c);
      expect(day.totals.finalTotal, 150);
      expect(effectiveMinimumOrderAmount(c), 120);
      final check = checkDayMinimum(
        dayKey: 1,
        lines: lines,
        dayTotals: day.totals,
        conditions: c,
      );
      expect(check.isBelowMinimum, isFalse);
    });

    test('M-0: пустой день — проверка не выполняется', () {
      final c = conditions(minOrder: 200);
      final day = dayOf(const [], c);
      final check = checkDayMinimum(
        dayKey: 1,
        lines: const [],
        dayTotals: day.totals,
        conditions: c,
      );
      expect(check.skippedEmptyDay, isTrue);
      expect(check.isBelowMinimum, isFalse);
    });
  });

  group('§5.6 Limit / LimitPeriod', () {
    test('L-1: превышение дневного лимита', () {
      final preview = previewLimit(
        conditions: conditions(limit: 500),
        dayTotals: const AggregateTotals(
          baseTotal: 510,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 510,
        ),
        weekTotals: AggregateTotals.zero,
      );
      expect(preview.isExceeded, isTrue);
      expect(preview.remainder, -10);
    });

    test('L-2: лимит недели по сумме дней меню', () {
      final c = conditions(limit: 350, weekLimit: true);
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
      expect(preview.isWeekPeriod, isTrue);
      expect(preview.comparedFinalTotal, 400);
      expect(preview.isExceeded, isTrue);
    });

    test('L-3: запас дневного лимита', () {
      final preview = previewLimit(
        conditions: conditions(limit: 500),
        dayTotals: const AggregateTotals(
          baseTotal: 300,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 300,
        ),
        weekTotals: AggregateTotals.zero,
      );
      expect(preview.isExceeded, isFalse);
      expect(preview.remainder, 200);
    });

    test('L-4: период «месяц» сравнивается как день', () {
      final fromUser = clientPricingConditionsFromUser({
        'Limit': 500,
        'LimitPeriod': 'Месяц',
      });
      expect(fromUser.hasLimit, isTrue);
      expect(fromUser.limit, 500);
      expect(fromUser.isWeekLimitPeriod, isFalse);
      final preview = previewLimit(
        conditions: fromUser,
        dayTotals: const AggregateTotals(
          baseTotal: 300,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 300,
        ),
        weekTotals: const AggregateTotals(
          baseTotal: 900,
          discountAmount: 0,
          discountClientAmount: 0,
          finalTotal: 900,
        ),
      );
      expect(preview.isWeekPeriod, isFalse);
      expect(preview.comparedFinalTotal, 300);
      expect(preview.remainder, 200);
      expect(preview.isExceeded, isFalse);
    });
  });

  group('§5.7 пограничные и округление', () {
    test('E-1: пустой день', () {
      final c = conditions(minOrder: 200, limit: 500);
      final day = dayOf(const [], c);
      expect(day.totals.finalTotal, 0);
      final minCheck = checkDayMinimum(
        dayKey: 1,
        lines: const [],
        dayTotals: day.totals,
        conditions: c,
      );
      expect(minCheck.skippedEmptyDay, isTrue);
      final lim = previewLimit(
        conditions: c,
        dayTotals: day.totals,
        weekTotals: AggregateTotals.zero,
      );
      expect(lim.comparedFinalTotal, 0);
      expect(lim.isExceeded, isFalse);
    });

    test('E-2: округление base цены 10.5', () {
      final line = calculateLineTotals(
        price: 10.5,
        quantity: 1,
        discountPercentage: 0,
        discountClientAvailable: 0,
      );
      expect(line.baseTotal, 11);
      expect(line.finalTotal, 11);
    });

    test('E-3: округление процентной скидки 7.5%', () {
      final line = calculateLineTotals(
        price: 100,
        quantity: 1,
        discountPercentage: 7.5,
        discountClientAvailable: 0,
      );
      expect(line.discountAmount, 8);
      expect(line.totalAfterPercentage, 92);
    });

    test('E-4: строковое DiscountClient "49.6"', () {
      expect(normalizeDiscountClient('49.6'), 50);
      expect(normalizeDiscountClient('49,6'), 50);
    });

    test('E-5: мусорный / отрицательный процент → 0', () {
      expect(normalizeDiscountPercentage('-5'), 0);
      expect(normalizeDiscountPercentage('abc'), 0);
    });

    test('E-6: кириллический ключ MPA', () {
      final c = clientPricingConditionsFromUser({
        kMinimumPaymentAmountCyrillicKey: 100,
        'DiscountPromotion': 1,
      });
      expect(c.minimumPaymentAmount, 100);
      expect(c.isDiscountPromotion, isTrue);
    });
  });
}
