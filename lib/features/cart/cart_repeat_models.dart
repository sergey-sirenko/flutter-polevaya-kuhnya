import 'package:polevaya_kuhnya/features/cart/cart_models.dart';

const repeatStatuses = {
  'ready',
  'occupied',
  'closed',
  'no_history',
  'ambiguous',
};

String repeatDateKey(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T00:00:00$').hasMatch(raw)) {
    throw const FormatException('Некорректная дата повторения.');
  }
  final key = raw.substring(0, 10);
  CartItem(dateKey: key, dishId: '_date', quantity: 1);
  return key;
}

final class RepeatDish {
  const RepeatDish(this.id, this.name, this.quantity);
  final String id;
  final String name;
  final int quantity;
}

final class RepeatDay {
  const RepeatDay(
    this.dateKey,
    this.revision,
    this.status,
    this.sourceDateKey,
    this.dishes,
  );
  final String dateKey;
  final String revision;
  final String status;
  final String? sourceDateKey;
  final List<RepeatDish> dishes;
}

final class RepeatResponse {
  const RepeatResponse(this.ownerScope, this.days);
  final String ownerScope;
  final List<RepeatDay> days;

  factory RepeatResponse.parse(
    Map<String, dynamic> raw,
    List<String> requested,
  ) {
    final scope = raw['ownerScope'];
    final daysRaw = raw['days'];
    final uuid =
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    if (scope is! String ||
        !RegExp('^repeat-v1:$uuid:$uuid\$').hasMatch(scope) ||
        daysRaw is! List ||
        daysRaw.length != requested.length) {
      throw const FormatException('Некорректный ответ повтора заказа.');
    }
    final seen = <String>{};
    final days = <RepeatDay>[];
    for (final item in daysRaw) {
      if (item is! Map) {
        throw const FormatException('Некорректный день повтора.');
      }
      final date = repeatDateKey(item['date']);
      final revision = item['revision'];
      final status = item['status'];
      final dishesRaw = item['dishes'];
      if (!requested.contains(date) ||
          !seen.add(date) ||
          revision is! String ||
          revision.isEmpty ||
          !repeatStatuses.contains(status) ||
          dishesRaw is! List ||
          !item.containsKey('sourceDate')) {
        throw const FormatException('Некорректное состояние дня повтора.');
      }
      final source = item['sourceDate'] == null
          ? null
          : repeatDateKey(item['sourceDate']);
      if (source != null) {
        final targetDate = DateTime.parse('${date}T00:00:00Z');
        final sourceDate = DateTime.parse('${source}T00:00:00Z');
        final diff = targetDate.difference(sourceDate).inDays;
        if (diff != 7 && diff != 14) {
          throw const FormatException('Некорректная дата источника.');
        }
      }
      final dishes = <RepeatDish>[];
      final ids = <String>{};
      for (final dish in dishesRaw) {
        if (dish is! Map) {
          throw const FormatException('Некорректное блюдо повтора.');
        }
        final id = dish['dish'];
        final name = dish['name'];
        final qty = dish['quantity'];
        if (id is! String ||
            !RegExp('^$uuid\$').hasMatch(id) ||
            !ids.add(id) ||
            name is! String ||
            qty is! num ||
            !qty.isFinite ||
            qty <= 0 ||
            qty != qty.toInt()) {
          throw const FormatException(
            'Некорректное количество или идентификатор блюда.',
          );
        }
        dishes.add(RepeatDish(id, name, qty.toInt()));
      }
      if ((status == 'ready' &&
              (source == null || dishes.isEmpty || revision == 'ambiguous')) ||
          (status != 'ready' && dishes.isNotEmpty)) {
        throw const FormatException('Несогласованный состав повтора.');
      }
      days.add(
        RepeatDay(
          date,
          revision,
          status as String,
          source,
          List.unmodifiable(dishes),
        ),
      );
    }
    return RepeatResponse(scope, List.unmodifiable(days));
  }
}
