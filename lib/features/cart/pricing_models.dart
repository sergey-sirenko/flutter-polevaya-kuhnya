// Чистые модели клиентского предпросмотра корзины (pricing-spec v1.0).
// Без Flutter, сети и хранилища.

/// Нормализованные условия клиента для расчёта.
final class ClientPricingConditions {
  const ClientPricingConditions({
    required this.discountPercentage,
    required this.discountClient,
    required this.isDiscountPromotion,
    required this.minimumPaymentAmount,
    required this.minimumOrderAmount,
    required this.limit,
    required this.limitPeriodRaw,
    required this.isWeekLimitPeriod,
  });

  /// Процент скидки 0…100 (дробный допускается; без round при нормализации).
  final double discountPercentage;

  /// Дневная «без оплаты» / лимит дотации профиля (целое ≥ 0).
  final int discountClient;

  /// `Number(DiscountPromotion) === 1`.
  final bool isDiscountPromotion;

  /// Минимальная оплата при дотации (целое ≥ 0).
  final int minimumPaymentAmount;

  /// Минимальная сумма заказа за день (целое ≥ 0; 0 = проверка выкл.).
  final int minimumOrderAmount;

  /// Лимит суммы; `null` если неактивен (≤ 0 / отсутствует).
  final int? limit;

  /// Сырая строка периода с сервера (для UI профиля).
  final String limitPeriodRaw;

  /// `true` только если нормализованный период строго «неделя».
  final bool isWeekLimitPeriod;

  bool get hasLimit => limit != null;
}

/// Вход одной позиции дня (блюдо в корзине).
final class PricingLineInput {
  const PricingLineInput({
    required this.price,
    required this.quantity,
    this.menuOrder = 0x7fffffffffffffff,
  });

  final Object? price;
  final Object? quantity;

  /// Порядок в меню; меньше — раньше. Без порядка — в конец.
  final int menuOrder;
}

/// Итоги одной строки после скидок.
final class LineTotals {
  const LineTotals({
    required this.baseTotal,
    required this.discountAmount,
    required this.totalAfterPercentage,
    required this.discountClientAmount,
    required this.finalTotal,
  });

  final int baseTotal;
  final int discountAmount;
  final int totalAfterPercentage;
  final int discountClientAmount;
  final int finalTotal;
}

/// Агрегат дня или недели (четыре поля после round суммы).
final class AggregateTotals {
  const AggregateTotals({
    required this.baseTotal,
    required this.discountAmount,
    required this.discountClientAmount,
    required this.finalTotal,
  });

  static const AggregateTotals zero = AggregateTotals(
    baseTotal: 0,
    discountAmount: 0,
    discountClientAmount: 0,
    finalTotal: 0,
  );

  final int baseTotal;
  final int discountAmount;
  final int discountClientAmount;
  final int finalTotal;
}

/// День корзины с привязкой к типу недели меню.
final class PricingDayInput {
  const PricingDayInput({
    required this.weekType,
    required this.dayKey,
    required this.lines,
  });

  /// Идентификатор типа недели меню (`current` / `next` и т.п. — произвольная метка).
  final String weekType;

  /// Ключ дня внутри недели (дата или номер — для вызывающего кода).
  final Object dayKey;

  final List<PricingLineInput> lines;

  bool get isEmpty => lines.isEmpty;
}

/// День с посчитанными строками и агрегатом.
final class PricingDayResult {
  const PricingDayResult({
    required this.weekType,
    required this.dayKey,
    required this.lines,
    required this.totals,
    required this.effectiveDiscountClient,
  });

  final String weekType;
  final Object dayKey;
  final List<LineTotals> lines;
  final AggregateTotals totals;

  /// Эффективная дневная «без оплаты» до распределения (§3.2).
  final int effectiveDiscountClient;
}

/// Предпросмотр лимита (§3.6).
final class LimitPreview {
  const LimitPreview({
    required this.hasLimit,
    required this.limit,
    required this.isWeekPeriod,
    required this.comparedFinalTotal,
    required this.remainder,
    required this.isExceeded,
  });

  final bool hasLimit;
  final int? limit;
  final bool isWeekPeriod;
  final int comparedFinalTotal;

  /// `round(Limit − finalTotal)` при активном лимите; иначе `null`.
  final int? remainder;
  final bool isExceeded;
}

/// Проверка минимума заказа для одного дня (§4.1 клиент).
final class DayMinimumCheck {
  const DayMinimumCheck({
    required this.dayKey,
    required this.finalTotal,
    required this.effectiveMinimum,
    required this.isBelowMinimum,
    required this.skippedEmptyDay,
  });

  final Object dayKey;
  final int finalTotal;
  final int effectiveMinimum;
  final bool isBelowMinimum;
  final bool skippedEmptyDay;
}
