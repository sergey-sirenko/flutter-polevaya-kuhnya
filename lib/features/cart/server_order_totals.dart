/// Сопоставление предварительного расчёта с подтверждённым ответом Zak.
/// UI заказа использует результат после `Orders/basket`, а не подменяет им
/// состояние черновика при ошибке или неполном ответе.
enum FinalAmountStatus { unchanged, changed, unconfirmed }

final class FinalAmountComparison {
  const FinalAmountComparison({
    required this.day,
    required this.preliminaryKopecks,
    required this.status,
    this.serverKopecks,
    this.scope,
  });

  final String day;
  final int preliminaryKopecks;
  final int? serverKopecks;
  final String? scope;
  final FinalAmountStatus status;
}

/// [preliminaryRublesByDay] содержит итоги из pricing-spec v1.0 по датам
/// YYYY-MM-DD. `order[]` может включать старые дни, поэтому сопоставление
/// выполняется по дате и требует ровно одну запись для каждого дня черновика.
List<FinalAmountComparison> reconcileServerOrderTotals({
  required Map<String, Object?> response,
  required Map<String, int> preliminaryRublesByDay,
}) {
  final rawOrders = response['order'];
  final byDay = <String, List<Map>>{};
  if (response['success'] == true && rawOrders is List) {
    for (final raw in rawOrders) {
      if (raw is! Map) continue;
      final day = _dayKey(raw['date']);
      if (day == null) continue;
      byDay.putIfAbsent(day, () => []).add(raw);
    }
  }

  return [
    for (final entry in preliminaryRublesByDay.entries)
      _compareDay(entry.key, entry.value, byDay[entry.key]),
  ];
}

FinalAmountComparison _compareDay(
  String day,
  int preliminaryRubles,
  List<Map>? orders,
) {
  final preliminaryKopecks = preliminaryRubles * 100;
  if (orders == null || orders.length != 1) {
    return FinalAmountComparison(
      day: day,
      preliminaryKopecks: preliminaryKopecks,
      status: FinalAmountStatus.unconfirmed,
    );
  }
  final order = orders.single;
  final scope = order['finalPayableScope'];
  final amount = order['finalPayable'];
  if ((scope != 'document' && scope != 'employee_dishes') || amount is! num) {
    return FinalAmountComparison(
      day: day,
      preliminaryKopecks: preliminaryKopecks,
      status: FinalAmountStatus.unconfirmed,
    );
  }
  final rubles = amount.toDouble();
  if (!rubles.isFinite || rubles < 0) {
    return FinalAmountComparison(
      day: day,
      preliminaryKopecks: preliminaryKopecks,
      status: FinalAmountStatus.unconfirmed,
    );
  }
  final kopecks = (rubles * 100).round();
  if ((rubles * 100 - kopecks).abs() > 0.000001) {
    return FinalAmountComparison(
      day: day,
      preliminaryKopecks: preliminaryKopecks,
      status: FinalAmountStatus.unconfirmed,
    );
  }
  return FinalAmountComparison(
    day: day,
    preliminaryKopecks: preliminaryKopecks,
    serverKopecks: kopecks,
    scope: scope as String,
    status: kopecks == preliminaryKopecks
        ? FinalAmountStatus.unchanged
        : FinalAmountStatus.changed,
  );
}

String? _dayKey(Object? raw) {
  if (raw is! String || raw.length < 10) return null;
  final day = raw.substring(0, 10);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) return null;
  final parsed = DateTime.tryParse(day);
  if (parsed == null ||
      parsed.year.toString().padLeft(4, '0') != day.substring(0, 4) ||
      parsed.month.toString().padLeft(2, '0') != day.substring(5, 7) ||
      parsed.day.toString().padLeft(2, '0') != day.substring(8, 10)) {
    return null;
  }
  return day;
}
