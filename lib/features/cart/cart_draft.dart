import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';

/// Типизированный снимок выбора меню. Источник изменений — [cartDraftProvider].
final cartModelProvider = Provider<Cart>((ref) {
  return Cart.fromDraft(ref.watch(cartDraftProvider));
});

/// Черновик количеств меню → корзина.
///
/// Ключ верхнего уровня — `dateKey` (YYYY-MM-DD), вложенный — `dishId`.
final cartDraftProvider =
    NotifierProvider<CartDraftController, Map<String, Map<String, int>>>(
      CartDraftController.new,
    );

class CartDraftController extends Notifier<Map<String, Map<String, int>>> {
  @override
  Map<String, Map<String, int>> build() => const {};

  int quantity(String dateKey, String dishId) {
    return state[dateKey]?[dishId] ?? 0;
  }

  /// Добавляет блюдо с количеством 1 или увеличивает существующее.
  void addItem(String dateKey, String dishId) {
    increment(dateKey, dishId);
  }

  void setQuantity(String dateKey, String dishId, int quantity) {
    _checkKeys(dateKey, dishId);
    final nextDay = Map<String, int>.from(state[dateKey] ?? const {});
    if (quantity <= 0) {
      nextDay.remove(dishId);
    } else {
      nextDay[dishId] = quantity;
    }
    final next = Map<String, Map<String, int>>.from(state);
    if (nextDay.isEmpty) {
      next.remove(dateKey);
    } else {
      next[dateKey] = Map.unmodifiable(nextDay);
    }
    state = Map.unmodifiable(next);
  }

  void increment(String dateKey, String dishId) {
    setQuantity(dateKey, dishId, quantity(dateKey, dishId) + 1);
  }

  void decrement(String dateKey, String dishId) {
    setQuantity(dateKey, dishId, quantity(dateKey, dishId) - 1);
  }

  /// Удаляет позицию; отсутствие позиции — no-op.
  void removeItem(String dateKey, String dishId) {
    if (!state.containsKey(dateKey) ||
        !(state[dateKey]?.containsKey(dishId) ?? false)) {
      return;
    }
    setQuantity(dateKey, dishId, 0);
  }

  /// Очищает все позиции выбранного дня.
  void clearDay(String dateKey) {
    if (!state.containsKey(dateKey)) return;
    final next = Map<String, Map<String, int>>.from(state)..remove(dateKey);
    state = Map.unmodifiable(next);
  }

  void clearAll() {
    state = const {};
  }

  /// Полная замена снимка (восстановление черновика / после успеха).
  void replaceAll(Map<String, Map<String, int>> draft) {
    final normalized = <String, Map<String, int>>{};
    final dateKeys = draft.keys.toList()..sort();
    for (final dateKey in dateKeys) {
      final day = draft[dateKey]!;
      final nextDay = <String, int>{};
      final dishIds = day.keys.toList()..sort();
      for (final dishId in dishIds) {
        final qty = day[dishId]!;
        if (qty <= 0) continue;
        _checkKeys(dateKey, dishId);
        nextDay[dishId] = qty;
      }
      if (nextDay.isNotEmpty) {
        normalized[dateKey] = Map.unmodifiable(nextDay);
      }
    }
    state = Map.unmodifiable(normalized);
  }

  void _checkKeys(String dateKey, String dishId) {
    if (dishId.trim().isEmpty) {
      throw const FormatException('dishId позиции корзины пуст.');
    }
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
}
