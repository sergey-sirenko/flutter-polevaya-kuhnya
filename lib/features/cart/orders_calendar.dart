import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Представление существующих данных; суммы остаются серверными.
final class OrderCalendarDay {
  const OrderCalendarDay({required this.menuDay, this.order});

  final MenuDay menuDay;
  final UserOrderDay? order;
}

final class OrderCalendarWeek {
  const OrderCalendarWeek({required this.weekType, required this.days});

  final String weekType;
  final List<OrderCalendarDay> days;

  num get total => days.fold<num>(0, (sum, day) => sum + (day.order?.payable ?? 0));
}

List<OrderCalendarWeek> buildOrderCalendar(
  List<MenuWeek> weeks,
  List<UserOrderDay> orders,
) {
  final byDate = <String, UserOrderDay>{};
  for (final order in orders) {
    if (order.dishes.isEmpty) continue;
    try {
      byDate.putIfAbsent(menuCalendarDateKey(order.dateRaw), () => order);
    } on FormatException {
      // Повреждённая дата истории не должна скрывать даты меню.
    }
  }
  final seen = <String>{};
  return List.unmodifiable([
    for (final type in const ['current', 'next'])
      OrderCalendarWeek(
        weekType: type,
        days: List.unmodifiable([
          for (final day in _deliveryDays(weeks, type))
            if (seen.add(day.dateKey))
              OrderCalendarDay(menuDay: day, order: byDate[day.dateKey]),
        ]),
      ),
  ]);
}

List<MenuDay> _deliveryDays(List<MenuWeek> weeks, String type) {
  final byDate = <String, ({String type, MenuDay day})>{};
  for (final week in weeks) {
    for (final day in week.deliveryDays) {
      final existing = byDate[day.dateKey];
      final filled = day.categories.any(
        (category) => category.dishes.isNotEmpty,
      );
      final existingFilled =
          existing?.day.categories.any(
            (category) => category.dishes.isNotEmpty,
          ) ??
          false;
      if (existing == null || (!existingFilled && filled)) {
        byDate[day.dateKey] = (type: week.weekType, day: day);
      }
    }
  }
  final days = [
    for (final entry in byDate.values)
      if (entry.type == type) entry.day,
  ];
  days.sort((a, b) => a.dateKey.compareTo(b.dateKey));
  return days;
}

String? initialOrderCalendarDate(
  List<OrderCalendarWeek> weeks, {
  String? selectedDateKey,
  required DateTime today,
}) {
  final days = [for (final week in weeks) ...week.days];
  if (days.isEmpty) return null;
  final todayKey =
      '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  for (final preferred in [selectedDateKey, todayKey]) {
    if (days.any((day) => day.menuDay.dateKey == preferred)) return preferred;
  }
  return days.first.menuDay.dateKey;
}
