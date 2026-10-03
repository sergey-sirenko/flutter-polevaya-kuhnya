import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';

final class RepeatWork {
  const RepeatWork({
    this.loading = false,
    this.saved = false,
    this.cleared = 0,
  });
  final bool loading;
  final bool saved;
  final int cleared;
}

final cartRepeatWorkProvider =
    NotifierProvider<RepeatWorkController, RepeatWork>(
      RepeatWorkController.new,
    );

/// Координация без зависимости от контроллеров корзины/отправки.
class RepeatWorkController extends Notifier<RepeatWork> {
  @override
  RepeatWork build() {
    ref.watch(cartRepositoryProvider);
    return const RepeatWork();
  }

  void set({required bool loading, required bool saved}) {
    if (state.loading != loading || state.saved != saved) {
      state = RepeatWork(
        loading: loading,
        saved: saved,
        cleared: state.cleared,
      );
    }
  }

  void clear() => state = RepeatWork(cleared: state.cleared + 1);
}
