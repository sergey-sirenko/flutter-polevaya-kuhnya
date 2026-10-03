import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Полностью проверенный ответ Orders/snapshot v1.0, без реквизитов сессии.
final class OrderSnapshot {
  const OrderSnapshot._(
    this.ownerScope,
    this.profile,
    this.allowedDates,
    this.revisions,
  );

  final String ownerScope;
  final UserProfile profile;
  final Set<String> allowedDates;
  final Map<String, String> revisions;

  factory OrderSnapshot.parse(
    Map<String, dynamic> raw,
    List<String>? requested,
  ) {
    if (raw['success'] != true || raw['schemaVersion'] != 1) {
      throw const FormatException(
        'Неподдерживаемый или неполный снимок заказа.',
      );
    }
    final scope = raw['ownerScope'];
    const uuid =
        r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';
    if (scope is! String ||
        !RegExp('^snapshot-v1:$uuid:$uuid\$').hasMatch(scope)) {
      throw const FormatException('Некорректный владелец снимка заказа.');
    }
    final user = raw['user'];
    if (user is! Map) {
      throw const FormatException('Снимок не содержит профиль.');
    }
    for (final key in [
      'login',
      'name',
      'employee',
      'email',
      'phone',
      'LimitPeriod',
    ]) {
      if (user[key] is! String) {
        throw FormatException('Неполный профиль снимка: $key.');
      }
    }
    if ((user['login'] as String).trim().isEmpty || user['order'] is! List) {
      throw const FormatException('Снимок не содержит владельца или историю.');
    }
    for (final key in [
      'DiscountPercentage',
      'DiscountClient',
      'DiscountPromotion',
      'Limit',
      'MinimumOrderAmount',
      'MinimumPaymentAmount',
    ]) {
      final value = user[key];
      if (key == 'DiscountPercentage' &&
          user.containsKey(key) &&
          value == null) {
        continue;
      }
      if (value is! num || !value.isFinite) {
        throw FormatException('Некорректные условия снимка: $key.');
      }
    }
    for (final day in user['order'] as List) {
      if (day is! Map ||
          day['dishes'] is! List ||
          day['changes'] is! String ||
          day['status'] is! String ||
          day['weekType'] is! String) {
        throw const FormatException('Некорректная история снимка.');
      }
      _snapshotDate(day['date']);
      for (final key in ['sum', 'discount']) {
        final value = day[key];
        if (value is! num || !value.isFinite) {
          throw const FormatException('Некорректные суммы истории.');
        }
      }
      if (day.containsKey('finalPayable') ||
          day.containsKey('finalPayableScope')) {
        final amount = day['finalPayable'];
        if (amount is! num ||
            !amount.isFinite ||
            amount < 0 ||
            ![
              'document',
              'employee_dishes',
            ].contains(day['finalPayableScope'])) {
          throw const FormatException('Некорректная итоговая оплата снимка.');
        }
      }
      for (final dish in day['dishes'] as List) {
        if (dish is! Map ||
            dish['dish'] is! String ||
            dish['name'] is! String ||
            dish['quantity'] is! num ||
            !(dish['quantity'] as num).isFinite ||
            dish['sum'] is! num ||
            !(dish['sum'] as num).isFinite) {
          throw const FormatException('Некорректный состав истории снимка.');
        }
      }
    }
    final dates = raw['menudates'];
    final states = raw['states'];
    if (dates is! List || states is! List) {
      throw const FormatException('Неполные даты или версии снимка.');
    }
    final allowed = <String>{for (final date in dates) _snapshotDate(date)};
    if (allowed.length != dates.length) {
      throw const FormatException('Повторяющиеся даты доступности снимка.');
    }
    final revisions = <String, String>{};
    for (final state in states) {
      if (state is! Map) {
        throw const FormatException('Некорректное состояние снимка.');
      }
      final date = _snapshotDate(state['date']);
      final revision = state['revision'];
      if (revision is! String ||
          revision.trim().isEmpty ||
          revision.trim() != revision ||
          revisions.containsKey(date)) {
        throw const FormatException(
          'Некорректная или повторяющаяся версия снимка.',
        );
      }
      revisions[date] = revision;
    }
    if (requested != null) {
      if (requested.toSet().length != requested.length ||
          revisions.length != requested.length ||
          requested.any((date) => !revisions.containsKey(date))) {
        throw const FormatException(
          'Набор версий снимка не соответствует запросу.',
        );
      }
    } else {
      // Две недели определяет сервер; проверяем полный последовательный горизонт.
      final ordered = revisions.keys.toList()..sort();
      if (ordered.length != 14 ||
          menuCalendarDate(ordered.first).weekday != DateTime.monday ||
          List.generate(
            14,
            (i) =>
                DateTime.parse('${ordered.first}T00:00:00Z')
                    .add(Duration(days: i)),
          ).asMap().entries.any(
            (entry) =>
                entry.value !=
                DateTime.parse('${ordered[entry.key]}T00:00:00Z'),
          )) {
        throw const FormatException('Неполный горизонт снимка.');
      }
    }
    return OrderSnapshot._(
      scope,
      UserProfile.fromUserJson(user),
      Set.unmodifiable(allowed),
      Map.unmodifiable(revisions),
    );
  }
}

String _snapshotDate(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T00:00:00$').hasMatch(raw)) {
    throw const FormatException('Некорректная календарная дата снимка.');
  }
  return menuCalendarDateKey(raw);
}
