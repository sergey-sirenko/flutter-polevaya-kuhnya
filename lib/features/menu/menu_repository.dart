import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_normalize.dart';
import 'package:polevaya_kuhnya/features/menu/menu_photo_versions.dart';

/// Repository меню (ADR-1, ADR-6). `dishes.json` — публичный файл; даты
/// заказа — `Orders/menudates` через SessionApi при входе.
final menuRepositoryProvider = Provider<MenuRepository>((ref) {
  return MenuRepository(
    api: ref.watch(apiClientProvider),
    photoVersions: MenuPhotoVersions(config: ref.watch(appConfigProvider)),
  );
});

final class MenuRepository {
  const MenuRepository({required this.api, required this.photoVersions});

  final ApiClient api;
  final MenuPhotoVersions photoVersions;

  Future<List<MenuWeek>> loadWeeks() async {
    final data = await api.getDataJson('dishes.json');
    try {
      final weeks = parseMenuWeeksRoot(data);
      final versions = await photoVersions.resolve(weeks);
      return List.unmodifiable([
        for (final week in weeks)
          MenuWeek(
            weekType: week.weekType,
            weekNumber: week.weekNumber,
            days: [
              for (final day in week.days)
                MenuDay(
                  dateKey: day.dateKey,
                  date: day.date,
                  hasDelivery: day.hasDelivery,
                  dayNumber: day.dayNumber,
                  dayName: day.dayName,
                  categories: [
                    for (final category in day.categories)
                      MenuCategory(
                        categoryId: category.categoryId,
                        categoryName: category.categoryName,
                        categoryOrder: category.categoryOrder,
                        categoryImagePath: category.categoryImagePath,
                        photoVersion: category.photoVersion,
                        imageVersion: versions[category.categoryImagePath],
                        dishes: [
                          for (final dish in category.dishes)
                            dish.withImageVersion(versions[dish.imagePath]),
                        ],
                      ),
                  ],
                ),
            ],
          ),
      ]);
    } on FormatException catch (error) {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'Файл меню не соответствует ожидаемой форме: ${error.message}',
      );
    }
  }

  /// Загружает разрешённые календарные дни. Требует активный SessionApi.
  Future<Set<String>> loadAllowedDateKeys(SessionApi sessionApi) async {
    final response = await sessionApi.postJson('V1/Orders/menudates', {});
    try {
      return parseMenuDateKeys(response['menudates']);
    } on FormatException catch (error) {
      throw ApiException(
        kind: ApiErrorKind.format,
        message: 'Ответ menudates не соответствует форме: ${error.message}',
      );
    }
  }
}

/// Разрешённые даты заказа. `null` у гостя — ограничения ещё не загружены
/// (локальный выбор количеств не блокируется, как пустой Set на сайте).
final menuAllowedDatesProvider =
    AsyncNotifierProvider<MenuAllowedDatesController, Set<String>?>(
      MenuAllowedDatesController.new,
      retry: (retryCount, error) => null,
    );

class MenuAllowedDatesController extends AsyncNotifier<Set<String>?> {
  int _requestEpoch = 0;

  @override
  Future<Set<String>?> build() async {
    final epoch = ++_requestEpoch;
    ref.onDispose(() => _requestEpoch++);
    final api = ref.watch(sessionApiProvider);
    if (api == null) return null;
    try {
      final dates = await ref
          .read(menuRepositoryProvider)
          .loadAllowedDateKeys(api);
      return epoch == _requestEpoch ? dates : state.asData?.value;
    } catch (_) {
      if (ref.mounted && epoch != _requestEpoch) return state.asData?.value;
      rethrow;
    }
  }

  void applySnapshot(Set<String> dates) {
    _requestEpoch++;
    state = AsyncData(Set.unmodifiable(dates));
  }

  Future<void> reload() async {
    final epoch = ++_requestEpoch;
    final api = ref.read(sessionApiProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      if (api == null) return null;
      return ref.read(menuRepositoryProvider).loadAllowedDateKeys(api);
    });
    if (ref.mounted &&
        epoch == _requestEpoch &&
        identical(api, ref.read(sessionApiProvider))) {
      state = result;
    }
  }
}
