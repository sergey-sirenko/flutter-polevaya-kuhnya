import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';

/// Эталон Controller для меню (ADR-6). Состояние — `AsyncValue`.
///
/// `retry: null` отключает скрытый автоматический повтор Riverpod.
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
