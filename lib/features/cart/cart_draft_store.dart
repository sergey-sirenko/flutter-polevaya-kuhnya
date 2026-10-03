import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Версия локального формата черновика корзины (FL-05-05).
const cartDraftFormatVersion = 1;

/// Ключ владельца: логин профиля. Пустой — гостевой черновик сессии.
String cartDraftOwnerKey(String? login) {
  final value = login?.trim() ?? '';
  return value.isEmpty ? 'guest' : value;
}

final class CartDraftSnapshot {
  const CartDraftSnapshot({
    required this.version,
    required this.ownerKey,
    required this.quantities,
  });

  final int version;
  final String ownerKey;
  final Map<String, Map<String, int>> quantities;

  Map<String, Object?> toJson() => {
    'version': version,
    'ownerKey': ownerKey,
    'quantities': {
      for (final day in quantities.entries)
        day.key: {for (final item in day.value.entries) item.key: item.value},
    },
  };

  static CartDraftSnapshot? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final ownerKey = raw['ownerKey'];
    final quantitiesRaw = raw['quantities'];
    if (version is! int || version != cartDraftFormatVersion) return null;
    if (ownerKey is! String || ownerKey.isEmpty) return null;
    if (quantitiesRaw is! Map) return null;
    final quantities = <String, Map<String, int>>{};
    for (final dayEntry in quantitiesRaw.entries) {
      final dateKey = dayEntry.key.toString();
      final dayRaw = dayEntry.value;
      if (dayRaw is! Map) return null;
      final day = <String, int>{};
      for (final item in dayRaw.entries) {
        final qty = item.value;
        if (qty is! int || qty <= 0) return null;
        final dishId = item.key.toString();
        if (dishId.isEmpty) return null;
        day[dishId] = qty;
      }
      if (day.isNotEmpty) {
        quantities[dateKey] = Map.unmodifiable(day);
      }
    }
    return CartDraftSnapshot(
      version: version,
      ownerKey: ownerKey,
      quantities: Map.unmodifiable(quantities),
    );
  }
}

final cartDraftStoreProvider = Provider<CartDraftStore>((ref) {
  return CartDraftStore(config: ref.watch(appConfigProvider));
});

/// Постоянное хранение черновика с привязкой к владельцу (FL-05-05/06).
final class CartDraftStore {
  CartDraftStore({required AppConfig config, this.prefs})
    : _scope =
          'field_kitchen.cart.v$cartDraftFormatVersion.${config.environment.name}.'
          '${base64Url.encode(utf8.encode(config.apiBaseUri.toString()))}';

  final SharedPreferences? prefs;
  final String _scope;

  String _key(String ownerKey) => '$_scope.$ownerKey';

  Future<SharedPreferences> _preferences() async {
    return prefs ?? await SharedPreferences.getInstance();
  }

  Future<CartDraftSnapshot?> load(String ownerKey) async {
    final prefs = await _preferences();
    final raw = prefs.getString(_key(ownerKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final snapshot = CartDraftSnapshot.tryParse(decoded);
      if (snapshot == null || snapshot.ownerKey != ownerKey) return null;
      return snapshot;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(CartDraftSnapshot snapshot) async {
    final prefs = await _preferences();
    if (!await prefs.setString(
      _key(snapshot.ownerKey),
      jsonEncode(snapshot.toJson()),
    )) {
      throw StateError('Черновик не сохранён.');
    }
  }

  Future<void> clear(String ownerKey) async {
    final prefs = await _preferences();
    if (!await prefs.remove(_key(ownerKey))) {
      throw StateError('Черновик не очищен.');
    }
  }
}
