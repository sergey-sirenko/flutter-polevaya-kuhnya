import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Эталон Repository для FL-01-17 (ADR-1, ADR-6). Меню — публичный файл
/// `dishes.json` отдельной базы данных, а не защищённый API; поэтому
/// используется общий `apiClientProvider`, а не `sessionApiProvider`
/// (см. ARCHITECTURE.md, раздел 2).
final menuRepositoryProvider = Provider<MenuRepository>((ref) {
  return MenuRepository(api: ref.watch(apiClientProvider));
});

final class MenuRepository {
  const MenuRepository({required this.api});

  final ApiClient api;

  Future<List<MenuWeek>> loadWeeks() async {
    final data = await api.getDataJson('dishes.json');
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный формат файла меню.',
      );
    }
    final weeksJson = data['weeks'];
    if (weeksJson is! List) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'В файле меню отсутствует weeks.',
      );
    }
    try {
      return [
        for (final item in weeksJson)
          MenuWeek.fromJson(
            item is Map<String, dynamic>
                ? item
                : throw const FormatException(
                    'Элемент weeks не является объектом.',
                  ),
          ),
      ];
    } on FormatException catch (error) {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'Файл меню не соответствует ожидаемой форме: ${error.message}',
      );
    }
  }
}
