import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Строка блюда в `Orders/basket` (контракт FL-00-11 / FL-02-16).
Map<String, Object?> buildBasketDish({
  required String dishId,
  required String name,
  required int quantity,
  required int discountClient,
}) {
  return {
    'dish': dishId,
    'name': name,
    'quantity': quantity,
    'DiscountClient': discountClient,
  };
}

String basketDateIso(String dateKey) => '${dateKey}T00:00:00';

/// Формирует `order[]` для явно переданных дат, включая пустой состав.
/// Новая отправка FL-10-12 передаёт только выбранную дату и её корзину.
List<Map<String, Object?>> buildBasketOrderDays({
  required Cart cart,
  required CartPricingView pricing,
  required Set<String> allowedDateKeys,
  Map<String, String>? revisionsByDate,
  List<MenuWeek>? weeksForNames,
}) {
  final names = <String, String>{};
  if (weeksForNames != null) {
    for (final week in weeksForNames) {
      for (final day in week.days) {
        for (final category in day.categories) {
          for (final dish in category.dishes) {
            names['${day.dateKey}|${dish.dishId}'] = dish.dishName;
          }
        }
      }
    }
  }
  for (final day in pricing.days) {
    for (final line in day.lines) {
      names.putIfAbsent('${day.dateKey}|${line.dishId}', () => line.dishName);
    }
  }

  final pricedDays = {for (final day in pricing.days) day.dateKey: day};
  final dateKeys = <String>{
    ...allowedDateKeys,
    ...cart.days.map((d) => d.dateKey),
  }.toList()..sort();

  final result = <Map<String, Object?>>[];
  for (final dateKey in dateKeys) {
    final priced = pricedDays[dateKey];
    final dishes = <Map<String, Object?>>[
      if (priced != null)
        for (final line in priced.lines)
          buildBasketDish(
            dishId: line.dishId,
            name: names['$dateKey|${line.dishId}'] ?? line.dishName,
            quantity: line.quantity,
            discountClient: line.totals.discountClientAmount,
          ),
    ];
    final day = <String, Object?>{
      'date': basketDateIso(dateKey),
      'dishes': dishes,
    };
    if (revisionsByDate != null) {
      day['revision'] = revisionsByDate[dateKey] ?? 'none';
    }
    result.add(day);
  }
  return result;
}

/// Полное тело нового режима с `submissionId` (без token — его добавляет SessionApi).
Map<String, Object?> buildBasketRequestBody({
  required String submissionId,
  required List<Map<String, Object?>> orderDays,
}) {
  if (submissionId.trim().isEmpty) {
    throw const FormatException('submissionId пуст.');
  }
  return {'submissionId': submissionId, 'order': orderDays};
}
