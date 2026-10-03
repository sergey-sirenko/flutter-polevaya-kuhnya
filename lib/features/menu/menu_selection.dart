import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _weekKey = 'menu.currentWeekType';
const _dayKey = 'menu.currentDateKey';

final class MenuSelection {
  const MenuSelection({required this.weekType, required this.dateKey});

  final String weekType;
  final String dateKey;
}

final menuSelectionProvider =
    NotifierProvider<MenuSelectionController, MenuSelection?>(
      MenuSelectionController.new,
    );

class MenuActiveCategoryController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String categoryId) {
    if (state == categoryId) return;
    state = categoryId;
  }
}

/// Категория текущего сеанса. Переживает смену ширины, когда страница меню
/// собирается заново рядом с корзиной или профилем.
final menuActiveCategoryProvider =
    NotifierProvider<MenuActiveCategoryController, String?>(
      MenuActiveCategoryController.new,
    );

class MenuSelectionController extends Notifier<MenuSelection?> {
  SharedPreferences? _prefs;

  @override
  MenuSelection? build() => null;

  /// Синхронизирует сохранённый выбор с актуальным меню.
  /// Неделя без блюд не выбирается. Если блюд нет ни в одной неделе,
  /// остаётся текущая неделя.
  Future<void> syncWithWeeks(List<MenuWeek> weeks) async {
    _prefs ??= await SharedPreferences.getInstance();
    final visible = menuWeeksForDisplay(weeks);
    if (visible.isEmpty) {
      state = null;
      return;
    }

    final savedWeek = _prefs!.getString(_weekKey);
    final savedDay = _prefs!.getString(_dayKey);

    var week = visible.first;
    for (final candidate in visible) {
      if (candidate.weekType == 'current') {
        week = candidate;
        break;
      }
    }
    if (week.deliveryDays.isEmpty) {
      for (final candidate in visible) {
        if (candidate.deliveryDays.isNotEmpty) {
          week = candidate;
          break;
        }
      }
    }
    for (final candidate in visible) {
      if (candidate.weekType == savedWeek &&
          menuWeekHasDishes(candidate) &&
          (candidate.deliveryDays.isNotEmpty || week.deliveryDays.isEmpty)) {
        week = candidate;
        break;
      }
    }
    if (week.deliveryDays.isEmpty) {
      final empty = MenuSelection(weekType: week.weekType, dateKey: '');
      state = empty;
      await _persist(empty);
      return;
    }

    var day = week.deliveryDays.first;
    for (final candidate in week.deliveryDays) {
      if (candidate.dateKey == savedDay) {
        day = candidate;
        break;
      }
    }

    final next = MenuSelection(weekType: week.weekType, dateKey: day.dateKey);
    state = next;
    await _persist(next);
  }

  Future<void> selectWeek(String weekType, List<MenuWeek> weeks) async {
    MenuWeek? week;
    for (final candidate in weeks) {
      if (candidate.weekType == weekType) {
        week = candidate;
        break;
      }
    }
    if (week == null) return;
    if (week.deliveryDays.isEmpty) {
      final empty = MenuSelection(weekType: week.weekType, dateKey: '');
      state = empty;
      await _persist(empty);
      return;
    }
    final currentDay = state?.dateKey;
    var day = week.deliveryDays.first;
    for (final candidate in week.deliveryDays) {
      if (candidate.dateKey == currentDay) {
        day = candidate;
        break;
      }
    }
    final next = MenuSelection(weekType: week.weekType, dateKey: day.dateKey);
    state = next;
    await _persist(next);
  }

  /// Открывает день, в котором есть категория. Текущий день сохраняется,
  /// если категория уже на нём.
  Future<void> showCategory(String categoryId, List<MenuWeek> weeks) async {
    final next = selectionContainingCategory(weeks, categoryId, state);
    if (next == null) return;
    if (state?.weekType == next.weekType && state?.dateKey == next.dateKey) {
      return;
    }
    state = next;
    await _persist(next);
  }

  /// День из корзины: ищет дату во всех неделях и открывает ту, где есть блюда.
  Future<bool> openDate(String dateKey, List<MenuWeek> weeks) async {
    final next = selectionForDate(weeks, dateKey);
    if (next == null) return false;
    state = next;
    await _persist(next);
    return true;
  }

  Future<void> selectDay(String dateKey, List<MenuWeek> weeks) async {
    final current = state;
    if (current == null) return;
    MenuWeek? week;
    for (final candidate in weeks) {
      if (candidate.weekType == current.weekType) {
        week = candidate;
        break;
      }
    }
    if (week == null) return;
    MenuDay? day;
    for (final candidate in week.deliveryDays) {
      if (candidate.dateKey == dateKey) {
        day = candidate;
        break;
      }
    }
    if (day == null) return;
    final next = MenuSelection(weekType: week.weekType, dateKey: day.dateKey);
    state = next;
    await _persist(next);
  }

  Future<void> _persist(MenuSelection selection) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_weekKey, selection.weekType);
    await _prefs!.setString(_dayKey, selection.dateKey);
  }
}

/// День с категорией: текущий, затем дни доставки выбранной недели,
/// недели `current` и остальных недель.
MenuSelection? selectionContainingCategory(
  List<MenuWeek> weeks,
  String categoryId,
  MenuSelection? current,
) {
  bool contains(MenuDay day) =>
      day.categories.any((item) => item.categoryId == categoryId);

  final currentDay = selectedMenuDay(weeks, current);
  if (currentDay != null && contains(currentDay)) return current;

  final ordered = <MenuWeek>[];
  void addWeek(MenuWeek? week) {
    if (week != null && !ordered.contains(week)) ordered.add(week);
  }

  if (current != null) addWeek(menuWeekByType(weeks, current.weekType));
  for (final week in weeks) {
    if (week.weekType == 'current') addWeek(week);
  }
  for (final week in weeks) {
    addWeek(week);
  }

  for (final week in ordered) {
    for (final day in week.deliveryDays) {
      if (!contains(day)) continue;
      return MenuSelection(weekType: week.weekType, dateKey: day.dateKey);
    }
  }
  return current;
}

/// Дата корзины: сначала день с блюдами и доставкой, затем любой день с блюдами.
MenuSelection? selectionForDate(List<MenuWeek> weeks, String dateKey) {
  MenuSelection? withDishes;
  MenuSelection? any;
  for (final week in weeks) {
    for (final day in week.days) {
      if (day.dateKey != dateKey) continue;
      final next = MenuSelection(weekType: week.weekType, dateKey: day.dateKey);
      final hasDishes = day.categories.any((item) => item.dishes.isNotEmpty);
      if (hasDishes && day.hasDelivery) return next;
      if (hasDishes) withDishes ??= next;
      any ??= next;
    }
  }
  return withDishes ?? any;
}

bool menuWeekHasDishes(MenuWeek week) {
  for (final day in week.days) {
    for (final category in day.categories) {
      if (category.dishes.isNotEmpty) return true;
    }
  }
  return false;
}

/// Недели с блюдами. Если блюд нет ни в одной, остаётся текущая неделя.
List<MenuWeek> menuWeeksForDisplay(List<MenuWeek> weeks) {
  final filled = [
    for (final week in weeks)
      if (menuWeekHasDishes(week)) week,
  ];
  if (filled.isNotEmpty) return filled;
  for (final week in weeks) {
    if (week.weekType == 'current') return [week];
  }
  if (weeks.isEmpty) return weeks;
  return [weeks.first];
}

/// Меню уже загружено до открытия страницы, а день ещё не выбран.
/// Явный пустой выбор сохраняется, только если другой недели с доставкой нет.
bool menuSelectionNeedsSync(List<MenuWeek> weeks, MenuSelection? selection) {
  if (weeks.isEmpty || menuWeeksForDisplay(weeks).isEmpty) return false;
  if (selectedMenuDay(weeks, selection) != null) return false;
  if (selection != null && selection.dateKey.isEmpty) {
    final week = menuWeekByType(weeks, selection.weekType);
    if (week != null && week.deliveryDays.isEmpty) {
      final otherHasDelivery = menuWeeksForDisplay(weeks).any(
        (item) =>
            item.weekType != week.weekType && item.deliveryDays.isNotEmpty,
      );
      if (!otherHasDelivery) return false;
    }
  }
  return true;
}

MenuDay? selectedMenuDay(List<MenuWeek> weeks, MenuSelection? selection) {
  if (selection == null) return null;
  for (final week in weeks) {
    if (week.weekType != selection.weekType) continue;
    for (final day in week.deliveryDays) {
      if (day.dateKey == selection.dateKey) return day;
    }
  }
  return null;
}

MenuWeek? menuWeekByType(List<MenuWeek> weeks, String weekType) {
  for (final week in weeks) {
    if (week.weekType == weekType) return week;
  }
  return null;
}
