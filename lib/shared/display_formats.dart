import 'package:intl/intl.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

/// Только представление; расчётные значения остаются в исходных моделях.
String formatRubles(num? value) {
  if (value == null || !value.isFinite) return AppStrings.profileValueMissing;
  final rounded = num.parse(value.toStringAsFixed(2));
  final pattern = rounded == rounded.roundToDouble() ? '#,##0' : '#,##0.00';
  return '${NumberFormat(pattern, 'ru_RU').format(rounded)} ₽';
}

String formatQuantity(num value) =>
    NumberFormat('#,##0.##', 'ru_RU').format(value);

/// Граммы пищевой ценности без пробела перед «г»: `22г`.
String formatNutrientGrams(num? value) {
  final text = _nutrientNumber(value);
  return text == null ? AppStrings.menuWeightUnknown : '$textг';
}

/// Калории без единицы: подпись колонки уже «Ккал».
String formatNutrientCalories(num? value) =>
    _nutrientNumber(value) ?? AppStrings.menuWeightUnknown;

String? _nutrientNumber(num? value) {
  if (value == null || !value.isFinite) return null;
  if (value == value.roundToDouble()) return value.round().toString();
  var text = value.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text;
}

/// ISO-дата источника — календарная дата, без перевода timezone в локальный.
String formatCalendarDate(String? raw, {bool includeYear = true}) {
  final parts = _calendarParts(raw);
  if (parts == null) return AppStrings.profileValueMissing;
  final label = '${parts.day}.${parts.month}';
  return includeYear ? '$label.${parts.year}' : label;
}

/// Заголовок дня корзины: «Чт 01.10.26». Год — две цифры, без сдвига пояса.
String formatCartDayTitle(String? raw) {
  final parts = _calendarParts(raw);
  if (parts == null) return AppStrings.profileValueMissing;
  final weekday = DateTime.utc(
    int.parse(parts.year),
    int.parse(parts.month),
    int.parse(parts.day),
  ).weekday;
  return '${AppStrings.cartWeekdays[weekday - 1]} ${parts.day}.${parts.month}.${parts.year.substring(2)}';
}

final class _CalendarParts {
  const _CalendarParts({
    required this.year,
    required this.month,
    required this.day,
  });

  final String year;
  final String month;
  final String day;
}

_CalendarParts? _calendarParts(String? raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|T| )')
      .firstMatch(raw?.trim() ?? '');
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return _CalendarParts(year: match[1]!, month: match[2]!, day: match[3]!);
}

/// Выбранный день меню для нижней панели: «Пн 05.10».
String formatMenuDayLabel(String? raw) {
  final parts = _calendarParts(raw);
  if (parts == null) return AppStrings.orderDay;
  final weekday = DateTime.utc(
    int.parse(parts.year),
    int.parse(parts.month),
    int.parse(parts.day),
  ).weekday;
  return '${AppStrings.cartWeekdays[weekday - 1]} ${parts.day}.${parts.month}';
}
