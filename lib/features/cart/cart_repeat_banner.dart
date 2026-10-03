import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';

class CartRepeatBanner extends ConsumerWidget {
  const CartRepeatBanner({
    this.onReady,
    this.viewCurrent,
    this.showDiscard = true,
    super.key,
  });
  final VoidCallback? onReady;
  final bool Function()? viewCurrent;
  final bool showDiscard;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repeat = ref.watch(cartRepeatControllerProvider);
    final edit = ref.watch(cartEditControllerProvider);
    final locked =
        repeat.loading ||
        ref.watch(cartSubmitControllerProvider).editingLocked ||
        versionBlocksWork(ref.watch(appVersionControllerProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (repeat.loading) const LinearProgressIndicator(),
        if (repeat.saved != null || (edit.isRepeat && edit.blocked)) ...[
          const Text(
            'Есть сохранённая повторённая корзина. Перед продолжением проверим её доступность.',
          ),
          TextButton(
            key: const ValueKey('repeat-resume'),
            onPressed: locked
                ? null
                : () async {
                    final ready = await ref
                        .read(cartRepeatControllerProvider.notifier)
                        .resume(viewCurrent: viewCurrent);
                    if (context.mounted && ready) onReady?.call();
                  },
            child: const Text('Продолжить повторённую корзину'),
          ),
        ],
        if (showDiscard &&
            (edit.isRepeat || repeat.saved != null || repeat.recoveryBlocked))
          TextButton(
            key: const ValueKey('repeat-discard'),
            onPressed: locked
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить повторённую корзину?'),
                        content: const Text(
                          'Будут удалены только позиции локального повтора. Серверные заказы сохранятся.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Назад'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (context.mounted && confirmed == true) {
                      await ref
                          .read(cartRepeatControllerProvider.notifier)
                          .discard();
                    }
                  },
            child: const Text('Удалить повтор'),
          ),
      ],
    );
  }
}
