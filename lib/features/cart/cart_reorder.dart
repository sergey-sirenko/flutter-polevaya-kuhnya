import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

final class CartReorderResult {
  const CartReorderResult({
    required this.draft,
    required this.addedCount,
    required this.skippedMissing,
    required this.skippedClosed,
    required this.currentPriceNotes,
  });

  final Map<String, Map<String, int>> draft;
  final int addedCount;
  final int skippedMissing;
  final int skippedClosed;
  final List<String> currentPriceNotes;
}

/// Дни меню, на которые можно перенести прошлый заказ.
List<MenuDay> reorderTargetDays({
  required List<MenuWeek> weeks,
  required Set<String>? allowedDateKeys,
}) {
  return [
    for (final week in weeks)
      for (final day in week.deliveryDays)
        if (isOrderDateAllowed(allowedDateKeys, day.dateKey)) day,
  ];
}

Map<String, Map<String, int>> _copyDraft(Map<String, Map<String, int>> source) {
  return {
    for (final entry in source.entries)
      entry.key: Map<String, int>.from(entry.value),
  };
}

/// Перенос позиций истории на выбранный доступный день (FR-O2, FL-06-20e).
/// Черновик других дней и прочих блюд сохраняется. Количество переносимого
/// блюда берётся из заказа. Цена в заметках — из меню целевого дня.
CartReorderResult reorderOrderDayToDraft({
  required UserOrderDay orderDay,
  required String targetDateKey,
  required List<MenuWeek> weeks,
  required Set<String>? allowedDateKeys,
  Map<String, Map<String, int>> existingDraft = const {},
}) {
  final preserved = _copyDraft(existingDraft);
  String dateKey;
  try {
    dateKey = menuCalendarDateKey(targetDateKey);
  } on FormatException {
    return CartReorderResult(
      draft: preserved,
      addedCount: 0,
      skippedMissing: 0,
      skippedClosed: orderDay.dishes.length,
      currentPriceNotes: const [],
    );
  }

  if (!isOrderDateAllowed(allowedDateKeys, dateKey)) {
    return CartReorderResult(
      draft: preserved,
      addedCount: 0,
      skippedMissing: 0,
      skippedClosed: orderDay.dishes.length,
      currentPriceNotes: const [],
    );
  }

  final menuDishes = <String, MenuDish>{};
  for (final week in weeks) {
    for (final day in week.days) {
      if (day.dateKey != dateKey) continue;
      for (final category in day.categories) {
        for (final dish in category.dishes) {
          menuDishes[dish.dishId] = dish;
        }
      }
    }
  }

  final dayDraft = Map<String, int>.from(preserved[dateKey] ?? const {});
  var skippedMissing = 0;
  var added = 0;
  final notes = <String>[];

  for (final dish in orderDay.dishes) {
    final qty = dish.quantity.round();
    if (qty <= 0 || dish.dishId.isEmpty) {
      skippedMissing++;
      continue;
    }
    final menuDish = menuDishes[dish.dishId];
    if (menuDish == null) {
      skippedMissing++;
      continue;
    }
    dayDraft[dish.dishId] = qty;
    added++;
    notes.add('${menuDish.dishName}: ${menuDish.price} ₽');
  }

  if (added == 0) {
    return CartReorderResult(
      draft: preserved,
      addedCount: 0,
      skippedMissing: skippedMissing,
      skippedClosed: 0,
      currentPriceNotes: const [],
    );
  }

  preserved[dateKey] = dayDraft;
  Cart.fromDraft(preserved);

  return CartReorderResult(
    draft: _copyDraft(preserved),
    addedCount: added,
    skippedMissing: skippedMissing,
    skippedClosed: 0,
    currentPriceNotes: List.unmodifiable(notes),
  );
}
