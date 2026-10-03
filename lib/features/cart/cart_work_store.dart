import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Один снимок содержит и исходные версии, и правки. Legacy draft не даёт права
/// изменения и не является источником восстановления этого набора.
final class CartWorkSnapshot {
  CartWorkSnapshot({
    required this.ownerScope,
    required this.selectedDateKey,
    required Map<String, String> revisions,
    required Map<String, Map<String, int>> originals,
    required Map<String, Map<String, String>> names,
    required Map<String, Map<String, int>> quantities,
  }) : revisions = Map.unmodifiable(revisions),
       originals = _freeze(originals),
       names = _freeze(names),
       quantities = _freeze(quantities) {
    const uuid =
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
    if (!RegExp('^snapshot-v1:$uuid:$uuid\$').hasMatch(ownerScope) ||
        revisions.isEmpty ||
        revisions.length > 31 ||
        !revisions.containsKey(selectedDateKey) ||
        revisions.values.any(
          (r) => r.trim().isEmpty || r != r.trim() || r == 'ambiguous',
        ) ||
        originals.length != revisions.length ||
        names.keys.any((d) => !revisions.containsKey(d)) ||
        quantities.keys.any((d) => !revisions.containsKey(d))) {
      throw const FormatException('Некорректный сохранённый набор.');
    }
    for (final date in revisions.keys) {
      CartItem(dateKey: date, dishId: '_date', quantity: 1);
      final original = originals[date];
      if (original == null ||
          (revisions[date] == 'none' && original.isNotEmpty)) {
        throw const FormatException('Исходный состав не соответствует версии.');
      }
      for (final item in original.entries) {
        CartItem(dateKey: date, dishId: item.key, quantity: item.value);
      }
      for (final item
          in quantities[date]?.entries ?? const <MapEntry<String, int>>[]) {
        CartItem(dateKey: date, dishId: item.key, quantity: item.value);
      }
    }
  }

  static Map<String, Map<String, T>> _freeze<T>(
    Map<String, Map<String, T>> source,
  ) => Map.unmodifiable({
    for (final e in source.entries) e.key: Map<String, T>.unmodifiable(e.value),
  });

  final String ownerScope;
  final String selectedDateKey;
  final Map<String, String> revisions;
  final Map<String, Map<String, int>> originals;
  final Map<String, Map<String, String>> names;
  final Map<String, Map<String, int>> quantities;

  List<String> get changedDates =>
      revisions.keys
          .where(
            (d) => !mapEquals(
              originals[d],
              quantities[d] ?? const <String, int>{},
            ),
          )
          .toList()
        ..sort();
  List<String> get cancelledDates => changedDates
      .where((d) => revisions[d] != 'none' && (quantities[d]?.isEmpty ?? true))
      .toList();

  Map<String, Object?> toJson() => {
    'version': 1,
    'ownerScope': ownerScope,
    'selectedDateKey': selectedDateKey,
    'revisions': revisions,
    'originals': originals,
    'names': names,
    'quantities': quantities,
  };

  factory CartWorkSnapshot.parse(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['ownerScope'] is! String ||
        value['selectedDateKey'] is! String) {
      throw const FormatException('Не удалось прочитать сохранённый набор.');
    }
    try {
      Map<String, Map<String, T>> nested<T>(Object? raw) => {
        for (final e in (raw as Map).entries)
          e.key as String: Map<String, T>.from(e.value as Map),
      };
      return CartWorkSnapshot(
        ownerScope: value['ownerScope'] as String,
        selectedDateKey: value['selectedDateKey'] as String,
        revisions: Map<String, String>.from(value['revisions'] as Map),
        originals: nested<int>(value['originals']),
        names: nested<String>(value['names']),
        quantities: nested<int>(value['quantities']),
      );
    } on TypeError {
      throw const FormatException('Некорректный сохранённый состав.');
    }
  }
}

final cartWorkStoreProvider = Provider<CartWorkStore>(
  (ref) => CartWorkStore(ref.watch(appConfigProvider)),
);
final cartWorkQueueProvider = Provider<CartWorkQueue>((ref) => CartWorkQueue());

class CartWorkQueue {
  Future<void> _tail = Future<void>.value();
  Future<void> run(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class CartWorkStore {
  CartWorkStore(AppConfig config, {this.prefs})
    : _scope =
          'field_kitchen.work.v1.${config.environment.name}.${base64Url.encode(utf8.encode(config.apiBaseUri.toString()))}';
  final String _scope;
  final SharedPreferences? prefs;
  String key(String login, String device) =>
      '$_scope.${Uri.encodeComponent(login)}.$device';
  Future<CartWorkSnapshot?> load(String login, String device) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final raw = p.getString(key(login, device));
    return raw == null ? null : CartWorkSnapshot.parse(jsonDecode(raw));
  }

  Future<void> save(
    String login,
    String device,
    CartWorkSnapshot snapshot,
  ) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (!await p.setString(key(login, device), jsonEncode(snapshot.toJson()))) {
      throw StateError('Набор не сохранён.');
    }
  }

  Future<void> clear(String login, String device) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (!await p.remove(key(login, device))) {
      throw StateError('Набор не удалён.');
    }
  }
}
