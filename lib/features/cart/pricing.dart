// Клиентский предпросмотр расчёта корзины (pricing-spec §3–§4, v1.0).
// Без Flutter, сети и хранилища. Итог записи заказа — на сервере Zak (BL-2).

import 'pricing_models.dart';
import 'pricing_normalize.dart';

export 'pricing_models.dart';
export 'pricing_normalize.dart';

/// Округление как `Math.round` для неотрицательных денежных величин.
int pricingRound(num value) => value.round();

/// Сумма процентной скидки (§3.1 п.3).
int calculateDiscountAmount(int baseTotal, double discountPercentage) {
  final pct = normalizeDiscountPercentage(discountPercentage);
  if (baseTotal <= 0 || pct <= 0) {
    return 0;
  }
  return pricingRound(baseTotal * pct / 100);
}

/// Итоги одной строки (§3.1).
LineTotals calculateLineTotals({
  required Object? price,
  required Object? quantity,
  required double discountPercentage,
  required Object? discountClientAvailable,
}) {
  final normalizedPrice = normalizeLineNumber(price);
  final normalizedQuantity = normalizeLineNumber(quantity);
  final baseTotal = pricingRound(normalizedPrice * normalizedQuantity);
  final safeBase = baseTotal < 0 ? 0 : baseTotal;

  final discountAmount = calculateDiscountAmount(safeBase, discountPercentage);
  final afterPct = pricingRound(safeBase - discountAmount);
  final totalAfterPercentage = afterPct < 0 ? 0 : afterPct;

  final available = normalizeDiscountClient(discountClientAvailable);
  final discountClientAmount = totalAfterPercentage < available
      ? totalAfterPercentage
      : available;

  final afterClient = pricingRound(totalAfterPercentage - discountClientAmount);
  final finalTotal = afterClient < 0 ? 0 : afterClient;

  return LineTotals(
    baseTotal: safeBase,
    discountAmount: discountAmount,
    totalAfterPercentage: totalAfterPercentage,
    discountClientAmount: discountClientAmount,
    finalTotal: finalTotal,
  );
}

/// Сумма дня после % без дотации (§3.2).
int calculateDayTotalAfterPercentage({
  required List<PricingLineInput> lines,
  required double discountPercentage,
}) {
  var sum = 0;
  for (final line in lines) {
    final totals = calculateLineTotals(
      price: line.price,
      quantity: line.quantity,
      discountPercentage: discountPercentage,
      discountClientAvailable: 0,
    );
    sum += totals.totalAfterPercentage;
  }
  return pricingRound(sum);
}

/// Эффективная дневная «без оплаты» (§3.2).
int resolveEffectiveDiscountClientForDay({
  required List<PricingLineInput> lines,
  required ClientPricingConditions conditions,
}) {
  final normalizedDiscountClient = conditions.discountClient;
  if (normalizedDiscountClient <= 0) {
    return 0;
  }
  if (!conditions.isDiscountPromotion || conditions.minimumPaymentAmount <= 0) {
    return normalizedDiscountClient;
  }

  final dayAfterPct = calculateDayTotalAfterPercentage(
    lines: lines,
    discountPercentage: conditions.discountPercentage,
  );
  if (dayAfterPct <= conditions.minimumPaymentAmount) {
    return 0;
  }
  final capped = pricingRound(dayAfterPct - conditions.minimumPaymentAmount);
  final available = capped < 0 ? 0 : capped;
  return normalizedDiscountClient < available
      ? normalizedDiscountClient
      : available;
}

List<PricingLineInput> _sortedByMenuOrder(List<PricingLineInput> lines) {
  final copy = List<PricingLineInput>.of(lines);
  copy.sort((a, b) => a.menuOrder.compareTo(b.menuOrder));
  return copy;
}

AggregateTotals _aggregateLines(Iterable<LineTotals> lines) {
  var base = 0;
  var discount = 0;
  var client = 0;
  var finalSum = 0;
  for (final line in lines) {
    base += line.baseTotal;
    discount += line.discountAmount;
    client += line.discountClientAmount;
    finalSum += line.finalTotal;
  }
  return AggregateTotals(
    baseTotal: pricingRound(base),
    discountAmount: pricingRound(discount),
    discountClientAmount: pricingRound(client),
    finalTotal: pricingRound(finalSum),
  );
}

/// Строки дня с распределением «без оплаты» + агрегат (§3.3–§3.4).
PricingDayResult calculateDayResult({
  required String weekType,
  required Object dayKey,
  required List<PricingLineInput> lines,
  required ClientPricingConditions conditions,
}) {
  final effective = resolveEffectiveDiscountClientForDay(
    lines: lines,
    conditions: conditions,
  );
  var remaining = effective;
  final sorted = _sortedByMenuOrder(lines);
  final lineResults = <LineTotals>[];
  for (final line in sorted) {
    final totals = calculateLineTotals(
      price: line.price,
      quantity: line.quantity,
      discountPercentage: conditions.discountPercentage,
      discountClientAvailable: remaining,
    );
    lineResults.add(totals);
    remaining = remaining - totals.discountClientAmount;
    if (remaining < 0) {
      remaining = 0;
    }
  }
  return PricingDayResult(
    weekType: weekType,
    dayKey: dayKey,
    lines: lineResults,
    totals: _aggregateLines(lineResults),
    effectiveDiscountClient: effective,
  );
}

/// Удобный агрегат только дня.
AggregateTotals calculateDayTotals({
  required List<PricingLineInput> lines,
  required ClientPricingConditions conditions,
}) {
  return calculateDayResult(
    weekType: '',
    dayKey: 0,
    lines: lines,
    conditions: conditions,
  ).totals;
}

/// Итог недели меню: сумма дней с тем же [weekType] (§3.5).
AggregateTotals calculateWeekTotals({
  required String weekType,
  required List<PricingDayInput> days,
  required ClientPricingConditions conditions,
}) {
  var base = 0;
  var discount = 0;
  var client = 0;
  var finalSum = 0;
  for (final day in days) {
    if (day.weekType != weekType) {
      continue;
    }
    final result = calculateDayResult(
      weekType: day.weekType,
      dayKey: day.dayKey,
      lines: day.lines,
      conditions: conditions,
    );
    base += result.totals.baseTotal;
    discount += result.totals.discountAmount;
    client += result.totals.discountClientAmount;
    finalSum += result.totals.finalTotal;
  }
  return AggregateTotals(
    baseTotal: pricingRound(base),
    discountAmount: pricingRound(discount),
    discountClientAmount: pricingRound(client),
    finalTotal: pricingRound(finalSum),
  );
}

/// Полный расчёт корзины: все дни + недельные агрегаты по встречающимся weekType.
final class CartPricingResult {
  const CartPricingResult({required this.days, required this.weekTotalsByType});

  final List<PricingDayResult> days;
  final Map<String, AggregateTotals> weekTotalsByType;
}

CartPricingResult calculateCart({
  required List<PricingDayInput> days,
  required ClientPricingConditions conditions,
}) {
  final dayResults = <PricingDayResult>[
    for (final day in days)
      calculateDayResult(
        weekType: day.weekType,
        dayKey: day.dayKey,
        lines: day.lines,
        conditions: conditions,
      ),
  ];
  final weekTypes = <String>{for (final d in days) d.weekType};
  final weeks = <String, AggregateTotals>{
    for (final wt in weekTypes)
      wt: calculateWeekTotals(weekType: wt, days: days, conditions: conditions),
  };
  return CartPricingResult(days: dayResults, weekTotalsByType: weeks);
}

/// Предпросмотр лимита (§3.6): неделя меню vs день по LimitPeriod.
LimitPreview previewLimit({
  required ClientPricingConditions conditions,
  required AggregateTotals dayTotals,
  required AggregateTotals weekTotals,
}) {
  if (!conditions.hasLimit) {
    return LimitPreview(
      hasLimit: false,
      limit: null,
      isWeekPeriod: conditions.isWeekLimitPeriod,
      comparedFinalTotal: dayTotals.finalTotal,
      remainder: null,
      isExceeded: false,
    );
  }
  final limit = conditions.limit!;
  final compared = conditions.isWeekLimitPeriod
      ? weekTotals.finalTotal
      : dayTotals.finalTotal;
  final remainder = pricingRound(limit - compared);
  return LimitPreview(
    hasLimit: true,
    limit: limit,
    isWeekPeriod: conditions.isWeekLimitPeriod,
    comparedFinalTotal: compared,
    remainder: remainder,
    isExceeded: compared > limit,
  );
}

/// Эффективный минимум заказа для клиента (§1.4 / §4.1).
int effectiveMinimumOrderAmount(ClientPricingConditions conditions) {
  final min = conditions.minimumOrderAmount;
  if (min <= 0) {
    return 0;
  }
  if (!conditions.isDiscountPromotion) {
    return min;
  }
  final reduced = min - conditions.discountClient;
  return reduced < 0 ? 0 : reduced;
}

/// Проверка минимума для одного дня: пустой день пропускается.
DayMinimumCheck checkDayMinimum({
  required Object dayKey,
  required List<PricingLineInput> lines,
  required AggregateTotals dayTotals,
  required ClientPricingConditions conditions,
}) {
  final effective = effectiveMinimumOrderAmount(conditions);
  if (lines.isEmpty || effective <= 0) {
    return DayMinimumCheck(
      dayKey: dayKey,
      finalTotal: dayTotals.finalTotal,
      effectiveMinimum: effective,
      isBelowMinimum: false,
      skippedEmptyDay: lines.isEmpty,
    );
  }
  return DayMinimumCheck(
    dayKey: dayKey,
    finalTotal: dayTotals.finalTotal,
    effectiveMinimum: effective,
    isBelowMinimum: dayTotals.finalTotal < effective,
    skippedEmptyDay: false,
  );
}
