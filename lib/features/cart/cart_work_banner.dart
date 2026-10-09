import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';

class CartWorkBanner extends ConsumerStatefulWidget {
  const CartWorkBanner({
    this.onReady,
    this.onDiscarded,
    this.showDiscard = true,
    this.autoRestore = true,
    super.key,
  });
  final VoidCallback? onReady;
  final VoidCallback? onDiscarded;
  final bool showDiscard;
  final bool autoRestore;

  @override
  ConsumerState<CartWorkBanner> createState() => _CartWorkBannerState();
}

class _CartWorkBannerState extends ConsumerState<CartWorkBanner> {
  bool _autoAttempted = false;
  bool _autoRestoring = false;

  VoidCallback? get onReady => widget.onReady;
  VoidCallback? get onDiscarded => widget.onDiscarded;
  bool get showDiscard => widget.showDiscard;

  Future<void> _resume() async {
    final source = GoRouter.maybeOf(context)?.routerDelegate.state.uri;
    final ready = await ref.read(cartEditControllerProvider.notifier).resume();
    if (!mounted ||
        !ready ||
        GoRouter.maybeOf(context)?.routerDelegate.state.uri != source) {
      return;
    }
    final date = ref.read(cartEditControllerProvider).dateKey;
    final weeks = ref.read(menuControllerProvider).asData?.value;
    if (date != null && weeks != null) {
      await ref.read(menuSelectionProvider.notifier).openDate(date, weeks);
    }
    if (mounted &&
        GoRouter.maybeOf(context)?.routerDelegate.state.uri == source) {
      onReady?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = ref.watch(cartEditControllerProvider);
    if (edit.recovery == null && !edit.blocked && !_autoRestoring) {
      _autoAttempted = false;
    }
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
    final showResume = edit.recovery != null || edit.blocked;
    if (widget.autoRestore && showResume && !locked && !_autoAttempted) {
      _autoAttempted = true;
      _autoRestoring = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await _resume();
        } finally {
          if (mounted) setState(() => _autoRestoring = false);
        }
      });
    }
    if (_autoRestoring ||
        (widget.autoRestore && showResume && !_autoAttempted)) {
      return const LinearProgressIndicator();
    }
    final canDiscard =
        showDiscard &&
        (edit.recovery != null || edit.recoveryError || edit.blocked);
    final resumeButton = TextButton(
      key: const ValueKey('work-resume'),
      style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
      onPressed: locked ? null : _resume,
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('Продолжить набор'),
      ),
    );
    final discardButton = TextButton(
      key: const ValueKey('work-discard'),
      style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
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
                await ref.read(cartEditControllerProvider.notifier).discard();
                if (context.mounted) {
                  final remaining = ref.read(cartEditControllerProvider);
                  if (!remaining.active &&
                      !remaining.hasSavedWork &&
                      !remaining.blocked &&
                      remaining.message == null) {
                    onDiscarded?.call();
                  }
                }
              }
            },
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('Начать заново'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (edit.loading || edit.restoring) const LinearProgressIndicator(),
        if (widget.autoRestore &&
            (_autoAttempted || edit.recoveryError) &&
            edit.message != null)
          Text(edit.message!, style: const TextStyle(color: AppTheme.danger)),
        if (showResume || canDiscard)
          Row(
            children: [
              if (showResume) Flexible(child: resumeButton),
              if (showResume && canDiscard) const SizedBox(width: 8),
              if (canDiscard) Flexible(child: discardButton),
            ],
          ),
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
      ],
    );
  }
}
