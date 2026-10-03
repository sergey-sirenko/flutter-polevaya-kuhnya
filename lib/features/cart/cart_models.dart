/// Неизменяемая модель многодневной корзины (FL-05-01).
///
/// Идентичность позиции задают календарная дата и непрозрачный ID блюда.
/// Цены и доступность сверяются с актуальным меню перед расчётом и отправкой.
typedef CartItemId = ({String dateKey, String dishId});

final class CartItem {
  CartItem({
    required this.dateKey,
    required this.dishId,
    required this.quantity,
  }) {
    _checkDateKey(dateKey);
    if (dishId.trim().isEmpty) {
      throw const FormatException('dishId позиции корзины пуст.');
    }
    if (quantity <= 0) {
      throw const FormatException(
        'Количество позиции должно быть положительным.',
      );
    }
  }

  final String dateKey;
  final String dishId;
  final int quantity;

  CartItemId get id => (dateKey: dateKey, dishId: dishId);
}

final class CartDay {
  CartDay({required this.dateKey, required List<CartItem> items})
    : items = List.unmodifiable(items) {
    _checkDateKey(dateKey);
    if (items.isEmpty) {
      throw const FormatException('Пустой день не хранится в черновике.');
    }
    final dishIds = <String>{};
    for (final item in items) {
      if (item.dateKey != dateKey) {
        throw const FormatException('Дата позиции отличается от даты дня.');
      }
      if (!dishIds.add(item.dishId)) {
        throw const FormatException('Блюдо повторяется в одном дне.');
      }
    }
  }

  final String dateKey;
  final List<CartItem> items;

  CartItem? itemFor(String dishId) {
    for (final item in items) {
      if (item.dishId == dishId) return item;
    }
    return null;
  }
}

final class Cart {
  Cart({required List<CartDay> days}) : days = List.unmodifiable(days) {
    final dateKeys = <String>{};
    for (final day in days) {
      if (!dateKeys.add(day.dateKey)) {
        throw const FormatException('Дата повторяется в корзине.');
      }
    }
  }

  final List<CartDay> days;

  bool get isEmpty => days.isEmpty;

  CartDay? dayFor(String dateKey) {
    for (final day in days) {
      if (day.dateKey == dateKey) return day;
    }
    return null;
  }

  /// Типизированный снимок существующего черновика количеств.
  /// Порядок ключей здесь детерминирован; порядок показа задаёт меню/UI.
  factory Cart.fromDraft(Map<String, Map<String, int>> draft) {
    final dateKeys = draft.keys.toList()..sort();
    return Cart(
      days: [
        for (final dateKey in dateKeys)
          CartDay(
            dateKey: dateKey,
            items: [
              for (final dishId in (draft[dateKey]!.keys.toList()..sort()))
                CartItem(
                  dateKey: dateKey,
                  dishId: dishId,
                  quantity: draft[dateKey]![dishId]!,
                ),
            ],
          ),
      ],
    );
  }
}

void _checkDateKey(String dateKey) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateKey);
  if (match == null) {
    throw const FormatException('Дата корзины должна быть YYYY-MM-DD.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('Дата корзины не существует.');
  }
}
