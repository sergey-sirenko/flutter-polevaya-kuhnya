import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Календарные ключи дней, разрешённых `Orders/menudates`.
///
/// Сопоставление идёт по YYYY-MM-DD, а не по `weekType_dow` сайта: так
/// исключается смещение доставки из-за локального часового пояса (FL-04-05).
Set<String> parseMenuDateKeys(Object? menudates) {
  if (menudates == null) {
    throw const FormatException('menudates отсутствует.');
  }
  if (menudates is! List) {
    throw const FormatException('menudates не является списком.');
  }
  final keys = <String>{};
  for (final item in menudates) {
    if (item is! String || item.isEmpty) {
      throw const FormatException(
        'Элемент menudates не является непустой строкой.',
      );
    }
    keys.add(menuCalendarDateKey(item));
  }
  return Set.unmodifiable(keys);
}

bool isOrderDateAllowed(Set<String>? allowedDateKeys, String dateKey) {
  // Как на сайте: пустой набор = ограничения ещё нет / все дни открыты.
  if (allowedDateKeys == null || allowedDateKeys.isEmpty) return true;
  return allowedDateKeys.contains(dateKey);
}
