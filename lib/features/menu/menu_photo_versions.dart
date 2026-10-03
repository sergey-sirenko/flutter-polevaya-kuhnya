import 'dart:convert';

import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Постоянные версии публичных фото, отдельно от меню/цен и сессии.
/// Байты по этим URL кэширует существующий компонент изображений/браузер.
final class MenuPhotoVersions {
  MenuPhotoVersions({required AppConfig config, this.preferences})
    : storageKey =
          'menu.photo_versions.v1.'
          '${base64Url.encode(utf8.encode(config.dataBaseUri.toString()))}';

  final SharedPreferences? preferences;
  final String storageKey;
  Future<void> _pending = Future.value();

  /// Сериализация read/modify/write не теряет записи параллельных загрузок.
  Future<Map<String, String>> resolve(List<MenuWeek> weeks) {
    final result = _pending.then((_) => _resolve(weeks));
    _pending = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  Future<Map<String, String>> _resolve(List<MenuWeek> weeks) async {
    final incoming = <String, String?>{};
    void collect(String? path, String? version) {
      if (path == null || path.isEmpty) return;
      final previous = incoming[path];
      if (previous != null && version != null && previous != version) {
        throw FormatException('Противоречивые photo_version для $path.');
      }
      incoming[path] = version ?? previous;
    }

    for (final week in weeks) {
      for (final day in week.days) {
        for (final category in day.categories) {
          collect(category.categoryImagePath, category.photoVersion);
          for (final dish in category.dishes) {
            collect(dish.imagePath, dish.photoVersion);
          }
        }
      }
    }
    if (incoming.isEmpty) return const {};

    final prefs = preferences ?? await SharedPreferences.getInstance();
    final versions = _decode(prefs.getString(storageKey));
    final resolved = <String, String>{};
    var changed = false;
    for (final entry in incoming.entries) {
      final version = entry.value == null
          ? versions[entry.key] ?? 'legacy'
          : 'photo:${entry.value}';
      resolved[entry.key] = version;
      if (versions[entry.key] != version) {
        versions[entry.key] = version;
        changed = true;
      }
    }
    if (changed && !await prefs.setString(storageKey, jsonEncode(versions))) {
      throw StateError('Версии фото не сохранены.');
    }
    return Map.unmodifiable(resolved);
  }

  Map<String, String> _decode(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String &&
              entry.value is String &&
              (entry.value == 'legacy' ||
                  (entry.value as String).startsWith('photo:')))
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return {};
    }
  }
}
