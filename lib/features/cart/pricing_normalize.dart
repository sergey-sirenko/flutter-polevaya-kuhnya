// Нормализация условий клиента и чисел (pricing-spec §2, Q1).

import 'pricing_models.dart';

/// Кириллическая «А» в ключе MinimumPaymentАmount (U+0410).
const String kMinimumPaymentAmountCyrillicKey = 'MinimumPayment\u0410mount';

/// Разбор числа как parseFloat с поддержкой `,` и `.` (Q1 / §2.1).
double? parsePricingNumber(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : null;
  }
  if (value is bool) {
    // Как Number(true/false) в JS: 1 / 0.
    return value ? 1.0 : 0.0;
  }
  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return null;
  }
  final normalized = raw.replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite) {
    return null;
  }
  return parsed;
}

double _nonPositiveToZero(double? value) {
  if (value == null || !value.isFinite || value <= 0) {
    return 0;
  }
  return value;
}

/// `DiscountPercentage`: ≤0 → 0; иначе min(value, 100); без round.
double normalizeDiscountPercentage(Object? value) {
  final n = _nonPositiveToZero(parsePricingNumber(value));
  if (n <= 0) {
    return 0;
  }
  return n > 100 ? 100 : n;
}

/// Денежные поля с Math.round после порога ≤0 → 0.
int normalizeMoneyAmount(Object? value) {
  final n = _nonPositiveToZero(parsePricingNumber(value));
  if (n <= 0) {
    return 0;
  }
  return n.round();
}

int normalizeDiscountClient(Object? value) => normalizeMoneyAmount(value);

int normalizeMinimumOrderAmount(Object? value) => normalizeMoneyAmount(value);

int normalizeMinimumPaymentAmount(Object? value) => normalizeMoneyAmount(value);

/// Лимит: неактивен → `null`; иначе round ≥ 1.
int? normalizeLimit(Object? value) {
  final n = parsePricingNumber(value);
  if (n == null || !n.isFinite || n <= 0) {
    return null;
  }
  return n.round();
}

/// Сырая строка периода + признак недели (§2.4).
({String raw, bool isWeek}) normalizeLimitPeriod(Object? value) {
  final raw = value == null ? '' : value.toString();
  final normalized = raw.trim().toLowerCase();
  return (raw: raw, isWeek: normalized == 'неделя');
}

/// `Number(x) === 1` (в т.ч. bool true, "1").
bool normalizeDiscountPromotion(Object? value) {
  if (value is bool) {
    return value;
  }
  final n = parsePricingNumber(value);
  if (n == null) {
    return false;
  }
  return n == 1.0;
}

/// Сырое MPA: латинский ключ, иначе кириллический (§2.3).
Object? readMinimumPaymentAmountRaw(Map<String, Object?>? userData) {
  if (userData == null) {
    return null;
  }
  final latin = userData['MinimumPaymentAmount'];
  if (latin != null && latin.toString() != '') {
    return latin;
  }
  final cyrillic = userData[kMinimumPaymentAmountCyrillicKey];
  if (cyrillic != null && cyrillic.toString() != '') {
    return cyrillic;
  }
  return null;
}

/// Собрать условия из плоского объекта `user` (login/профиль).
ClientPricingConditions clientPricingConditionsFromUser(
  Map<String, Object?>? userData,
) {
  final period = normalizeLimitPeriod(userData?['LimitPeriod']);
  return ClientPricingConditions(
    discountPercentage: normalizeDiscountPercentage(
      userData?['DiscountPercentage'],
    ),
    discountClient: normalizeDiscountClient(userData?['DiscountClient']),
    isDiscountPromotion: normalizeDiscountPromotion(
      userData?['DiscountPromotion'],
    ),
    minimumPaymentAmount: normalizeMinimumPaymentAmount(
      readMinimumPaymentAmountRaw(userData),
    ),
    minimumOrderAmount: normalizeMinimumOrderAmount(
      userData?['MinimumOrderAmount'],
    ),
    limit: normalizeLimit(userData?['Limit']),
    limitPeriodRaw: period.raw,
    isWeekLimitPeriod: period.isWeek,
  );
}

/// Цена/количество строки (§2.5): не finite → 0.
double normalizeLineNumber(Object? value) {
  final n = parsePricingNumber(value);
  if (n == null || !n.isFinite) {
    return 0;
  }
  return n;
}
