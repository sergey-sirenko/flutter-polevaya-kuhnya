import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';

class CartWorkBanner extends ConsumerWidget {
  const CartWorkBanner({this.onReady, this.showDiscard = true, super.key});
  final VoidCallback? onReady;
  final bool showDiscard;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edit = ref.watch(cartEditControllerProvider);
    if (edit.isRepeat ||
        (!edit.active && !edit.hasSavedWork && edit.message == null)) {
      return const SizedBox.shrink();
    }
    final locked =
        edit.loading ||
        edit.restoring ||
        ref.watch(cartRepeatWorkProvider).loading ||
        ref.watch(cartSubmitControllerProvider).editingLocked ||
        versionBlocksWork(ref.watch(appVersionControllerProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (edit.loading || edit.restoring) const LinearProgressIndicator(),
        if (edit.recovery != null || edit.blocked) ...[
          const Text(
            'Есть сохранённый набор. Перед продолжением проверим заказы в 1С.',
          ),
          TextButton(
            key: const ValueKey('work-resume'),
            onPressed: locked
                ? null
                : () async {
                    final ready = await ref
                        .read(cartEditControllerProvider.notifier)
                        .resume();
                    if (context.mounted && ready) {
                      final date = ref.read(cartEditControllerProvider).dateKey;
                      final weeks = ref
                          .read(menuControllerProvider)
                          .asData
                          ?.value;
                      if (date != null && weeks != null) {
                        await ref
                            .read(menuSelectionProvider.notifier)
                            .openDate(date, weeks);
                      }
                      if (context.mounted) onReady?.call();
                    }
                  },
            child: const Text('Продолжить набор'),
          ),
        ],
        if (edit.recoveryError)
          TextButton(
            key: const ValueKey('work-retry-read'),
            onPressed: locked
                ? null
                : () =>
                      ref.read(cartEditControllerProvider.notifier).retryRead(),
            child: const Text('Повторить чтение'),
          ),
        if (edit.storageError)
          TextButton(
            key: const ValueKey('work-retry-save'),
            onPressed: locked
                ? null
                : () async {
                    try {
                      await ref
                          .read(cartEditControllerProvider.notifier)
                          .persistNow();
                    } catch (_) {}
                  },
            child: const Text('Повторить сохранение набора'),
          ),
        if (showDiscard &&
            (edit.recovery != null || edit.recoveryError || edit.blocked))
          TextButton(
            key: const ValueKey('work-discard'),
            onPressed: locked
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Начать набор заново?'),
                        content: const Text(
                          'Локальные правки всех дней будут удалены. Сохранённые заказы в 1С останутся. Затем нажмите корзину нужного дня.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Назад'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Начать заново'),
                          ),
                        ],
                      ),
                    );
                    if (context.mounted && confirmed == true) {
                      await ref
                          .read(cartEditControllerProvider.notifier)
                          .discard();
                    }
                  },
            child: const Text('Начать заново'),
          ),
      ],
    );
  }
}
