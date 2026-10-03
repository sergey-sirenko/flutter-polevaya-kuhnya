import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final repeatWriteQueueProvider = Provider<RepeatWriteQueue>(
  (ref) => RepeatWriteQueue(),
);

class RepeatWriteQueue {
  Future<void> _tail = Future<void>.value();
  Future<void> run(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class RepeatSnapshot {
  RepeatSnapshot({
    required this.ownerScope,
    required this.selectedDateKey,
    required Map<String, String> revisions,
    required Map<String, Map<String, int>> quantities,
  }) : revisions = Map.unmodifiable(revisions),
       quantities = Map.unmodifiable({
         for (final e in quantities.entries)
           e.key: Map<String, int>.unmodifiable(e.value),
       }) {
    if (ownerScope.isEmpty ||
        revisions.isEmpty ||
        revisions.length > 31 ||
        !revisions.containsKey(selectedDateKey) ||
        revisions.values.any((r) => r.isEmpty || r == 'ambiguous') ||
        quantities.keys.any((d) => !revisions.containsKey(d))) {
      throw const FormatException('Некорректный сохранённый повтор.');
    }
    for (final key in revisions.keys) {
      CartItem(dateKey: key, dishId: '_date', quantity: 1);
    }
    Cart.fromDraft(quantities);
  }
  final String ownerScope;
  final String selectedDateKey;
  final Map<String, String> revisions;
  final Map<String, Map<String, int>> quantities;

  Map<String, Object?> toJson() => {
    'version': 1,
    'ownerScope': ownerScope,
    'selectedDateKey': selectedDateKey,
    'revisions': revisions,
    'quantities': quantities,
  };

  factory RepeatSnapshot.parse(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['ownerScope'] is! String ||
        raw['selectedDateKey'] is! String ||
        raw['revisions'] is! Map) {
      throw const FormatException('Не удалось прочитать сохранённый повтор.');
    }
    final draft = CartDraftSnapshot.tryParse({
      'version': 1,
      'ownerKey': 'repeat',
      'quantities': raw['quantities'],
    });
    if (draft == null) {
      throw const FormatException('Некорректный сохранённый состав.');
    }
    return RepeatSnapshot(
      ownerScope: raw['ownerScope'] as String,
      selectedDateKey: raw['selectedDateKey'] as String,
      revisions: Map<String, String>.from(raw['revisions'] as Map),
      quantities: draft.quantities,
    );
  }
}

final cartRepeatStoreProvider = Provider<CartRepeatStore>(
  (ref) => CartRepeatStore(ref.watch(appConfigProvider)),
);

/// Самостоятельный атомарный снимок; формат обычных черновиков v1 не меняется.
class CartRepeatStore {
  CartRepeatStore(AppConfig config, {this.prefs})
    : _scope =
          'field_kitchen.repeat.v1.${config.environment.name}.'
          '${base64Url.encode(utf8.encode(config.apiBaseUri.toString()))}';
  final SharedPreferences? prefs;
  final String _scope;
  String _key(String login, String device) =>
      '$_scope.${Uri.encodeComponent(login)}.$device';
  Future<RepeatSnapshot?> load(String login, String device) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final raw = p.getString(_key(login, device));
    if (raw == null) return null;
    return RepeatSnapshot.parse(jsonDecode(raw));
  }

  Future<void> save(
    String login,
    String device,
    RepeatSnapshot snapshot,
  ) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (!await p.setString(
      _key(login, device),
      jsonEncode(snapshot.toJson()),
    )) {
      throw StateError('Не удалось сохранить повторённую корзину.');
    }
  }

  Future<void> clear(String login, String device) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    if (!await p.remove(_key(login, device))) {
      throw StateError('Не удалось удалить сохранённый повтор.');
    }
  }
}
