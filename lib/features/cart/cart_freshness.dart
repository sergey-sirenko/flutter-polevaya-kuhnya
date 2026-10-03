import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

enum CartFreshnessKind { closedDate, missingDish, priceChanged }

final class CartFreshnessIssue {
  const CartFreshnessIssue({
    required this.kind,
    required this.dateKey,
    this.dishId,
    this.expectedPrice,
    this.actualPrice,
  });

  final CartFreshnessKind kind;
  final String dateKey;
  final String? dishId;
  final num? expectedPrice;
  final num? actualPrice;
}

/// Сверка черновика с актуальным меню и разрешёнными датами (FL-05-07).
///
/// [knownPrices] — цены на момент сохранения позиции (`dateKey|dishId` → price);
/// отсутствие записи не считается сменой цены.
List<CartFreshnessIssue> checkCartFreshness({
  required Cart cart,
  required List<MenuWeek> weeks,
  required Set<String>? allowedDateKeys,
  Map<String, num> knownPrices = const {},
}) {
  final dishesByDate = indexMenuByDate(weeks).dishesByDate;

  final issues = <CartFreshnessIssue>[];
  for (final day in cart.days) {
    if (!isOrderDateAllowed(allowedDateKeys, day.dateKey)) {
      issues.add(
        CartFreshnessIssue(
          kind: CartFreshnessKind.closedDate,
          dateKey: day.dateKey,
        ),
      );
    }
    final dishes = dishesByDate[day.dateKey] ?? const {};
    for (final item in day.items) {
      final dish = dishes[item.dishId];
      if (dish == null) {
        issues.add(
          CartFreshnessIssue(
            kind: CartFreshnessKind.missingDish,
            dateKey: day.dateKey,
            dishId: item.dishId,
          ),
        );
        continue;
      }
      final known = knownPrices['${day.dateKey}|${item.dishId}'];
      if (known != null && known != dish.price) {
        issues.add(
          CartFreshnessIssue(
            kind: CartFreshnessKind.priceChanged,
            dateKey: day.dateKey,
            dishId: item.dishId,
            expectedPrice: known,
            actualPrice: dish.price,
          ),
        );
      }
    }
  }
  return List.unmodifiable(issues);
}
