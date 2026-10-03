import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Нормализация недель как на сайте (FL-00-10): две самые ранние по
/// минимальной календарной дате → `current` / `next`.
List<MenuWeek> normalizeMenuWeeks(List<MenuWeek> weeks) {
  if (weeks.isEmpty) return const [];

  final withMin = <({MenuWeek week, String minDateKey})>[];
  for (final week in weeks) {
    String? minKey;
    for (final day in week.days) {
      if (minKey == null || day.dateKey.compareTo(minKey) < 0) {
        minKey = day.dateKey;
      }
    }
    if (minKey != null) {
      withMin.add((week: week, minDateKey: minKey));
    }
  }
  if (withMin.isEmpty) return List.unmodifiable(weeks);

  withMin.sort((a, b) => a.minDateKey.compareTo(b.minDateKey));
  final selected = withMin.take(2).toList(growable: false);
  return List.unmodifiable([
    for (var index = 0; index < selected.length; index++)
      MenuWeek(
        weekType: index == 0 ? 'current' : 'next',
        weekNumber: index + 1,
        days: selected[index].week.days,
      ),
  ]);
}

/// Разбор корня `dishes.json`. Пустой `weeks: []` — валидное пустое меню.
/// Отсутствие/повреждение `weeks` — FormatException (не маскируется пустым списком).
List<MenuWeek> parseMenuWeeksRoot(Object? data) {
  if (data is! Map) {
    throw const FormatException('Корень меню не является объектом.');
  }
  final root = Map<String, dynamic>.from(data);
  if (!root.containsKey('weeks')) {
    throw const FormatException('В файле меню отсутствует weeks.');
  }
  final weeksJson = root['weeks'];
  if (weeksJson is! List) {
    throw const FormatException('weeks отсутствует или не список.');
  }
  final weeks = [
    for (final item in weeksJson)
      MenuWeek.fromJson(
        item is Map<String, dynamic>
            ? item
            : item is Map
            ? Map<String, dynamic>.from(item)
            : throw const FormatException(
                'Элемент weeks не является объектом.',
              ),
      ),
  ];
  return normalizeMenuWeeks(weeks);
}
