import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';

/// Эталон Controller для FL-01-17 (ADR-6). Состояние — `AsyncValue`, поэтому
/// UI различает loading/data/error без отдельного enum, как в
/// `SessionController` для составного статуса сессии.
///
/// `retry: null` отключает скрытый автоматический повтор Riverpod
/// (`ProviderContainer.defaultRetry`, до 10 попыток с задержкой до 6.4 c).
/// Явный повтор для чтения — только через кнопку пользователя ([reload]),
/// без бесшумных фоновых попыток, которые задержали бы видимую ошибку.
final menuControllerProvider =
    AsyncNotifierProvider<MenuController, List<MenuWeek>>(
      MenuController.new,
      retry: (retryCount, error) => null,
    );

class MenuController extends AsyncNotifier<List<MenuWeek>> {
  @override
  Future<List<MenuWeek>> build() {
    return ref.watch(menuRepositoryProvider).loadWeeks();
  }

  /// Явный повтор пользователя после отказа или для обновления списка.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(menuRepositoryProvider).loadWeeks(),
    );
  }
}
