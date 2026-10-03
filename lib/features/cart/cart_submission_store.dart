import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Неизменный снимок операции; реквизиты сессии сюда не входят.
final class CartPendingSubmission {
  CartPendingSubmission({
    required this.owner,
    required Map<String, Object?> body,
    required Map<String, int> preliminary,
  }) : _bodyJson = jsonEncode(body),
       preliminary = Map.unmodifiable(preliminary) {
    // Проверяем и созданный снимок, и восстановленный тем же валидатором.
    _validate();
  }

  final String owner;
  final String _bodyJson;
  final Map<String, int> preliminary;

  Map<String, Object?> get body =>
      Map<String, Object?>.from(jsonDecode(_bodyJson) as Map);
  String get id => body['submissionId']! as String;

  Map<String, Map<String, int>> get quantities => {
    for (final day in body['order']! as List)
      (day['date'] as String).substring(0, 10): {
        for (final dish in day['dishes'] as List)
          dish['dish'] as String: dish['quantity'] as int,
      },
  };

  void _validate() {
    final value = body;
    if (owner.isEmpty ||
        value.length !=
            2 +
                (value.containsKey('includeSnapshot') ? 1 : 0) +
                (value.containsKey('expectedOwnerScope') ? 1 : 0) ||
        (value.containsKey('includeSnapshot') &&
            value['includeSnapshot'] != true) ||
        (value.containsKey('expectedOwnerScope') &&
            (value['includeSnapshot'] != true ||
                value['expectedOwnerScope'] is! String ||
                !RegExp(r'^snapshot-v1:[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36}$')
                    .hasMatch(value['expectedOwnerScope'] as String))) ||
        value['submissionId'] is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(value['submissionId'] as String) ||
        value['order'] is! List ||
        (value['order'] as List).isEmpty) {
      throw const FormatException('Некорректная сохранённая операция.');
    }
    final dates = <String>{};
    for (final day in value['order']! as List) {
      if (day is! Map ||
          day.length != 3 ||
          day['date'] is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}T00:00:00$')
              .hasMatch(day['date'] as String) ||
          day['revision'] is! String ||
          (day['revision'] as String).isEmpty ||
          day['dishes'] is! List ||
          !dates.add((day['date'] as String).substring(0, 10))) {
        throw const FormatException('Некорректный день операции.');
      }
      final ids = <String>{};
      // Пустой состав — отмена дня; дата всё равно проходит общий валидатор.
      CartItem(
        dateKey: (day['date'] as String).substring(0, 10),
        dishId: '_date_validation',
        quantity: 1,
      );
      for (final dish in day['dishes'] as List) {
        if (dish is! Map ||
            dish.length != 4 ||
            dish['dish'] is! String ||
            (dish['dish'] as String).trim().isEmpty ||
            !ids.add(dish['dish'] as String) ||
            dish['name'] is! String ||
            dish['quantity'] is! int ||
            (dish['quantity'] as int) <= 0 ||
            dish['DiscountClient'] is! int ||
            (dish['DiscountClient'] as int) < 0) {
          throw const FormatException('Некорректная позиция операции.');
        }
      }
    }
    Cart.fromDraft({
      for (final entry in quantities.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    });
    if (preliminary.entries.any((e) => !dates.contains(e.key) || e.value < 0)) {
      throw const FormatException('Некорректный расчёт операции.');
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'owner': owner,
    'body': body,
    'preliminary': preliminary,
  };

  factory CartPendingSubmission.fromJson(Object? raw, String owner) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['owner'] != owner ||
        raw['body'] is! Map ||
        raw['preliminary'] is! Map) {
      throw const FormatException('Некорректная сохранённая операция.');
    }
    return CartPendingSubmission(
      owner: owner,
      body: Map<String, Object?>.from(raw['body'] as Map),
      preliminary: Map<String, int>.from(raw['preliminary'] as Map),
    );
  }
}

final cartSubmissionStoreProvider = Provider<CartSubmissionStore>((ref) {
  return CartSubmissionStore(config: ref.watch(appConfigProvider));
});

/// Область API/окружения и владелец обязательны. Старый ключ не переносим:
/// из него невозможно доказать, какому API принадлежала операция.
final class CartSubmissionStore {
  CartSubmissionStore({required AppConfig config, this.prefs})
    : _scope =
          'field_kitchen.submission.v1.${config.environment.name}.'
          '${base64Url.encode(utf8.encode(config.apiBaseUri.toString()))}';

  final SharedPreferences? prefs;
  final String _scope;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function(SharedPreferences) action) {
    final next = _tail.then((_) async {
      return action(prefs ?? await SharedPreferences.getInstance());
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<CartPendingSubmission?> load(String owner) => _serial((prefs) async {
    if (prefs.containsKey('cart.pending.$owner')) {
      throw const FormatException('Старая операция без области API.');
    }
    final raw = prefs.getString('$_scope.$owner');
    if (raw == null) return null;
    return CartPendingSubmission.fromJson(jsonDecode(raw), owner);
  });

  Future<void> save(CartPendingSubmission pending) => _serial((prefs) async {
    if (!await prefs.setString(
      '$_scope.${pending.owner}',
      jsonEncode(pending.toJson()),
    )) {
      throw StateError('Операция не сохранена.');
    }
  });

  Future<void> clear(String owner) => _serial((prefs) async {
    if (!await prefs.remove('$_scope.$owner')) {
      throw StateError('Операция не очищена.');
    }
  });
}
