import 'package:polevaya_kuhnya/app/navigation.dart';
import 'package:polevaya_kuhnya/app/order_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_banner.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_banner.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_work.dart';
import 'package:polevaya_kuhnya/features/cart/cart_freshness.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

class CartPage extends ConsumerStatefulWidget {
  const CartPage({this.onOpenDay, this.onAddDishes, super.key});

  /// Открыть меню на дате этой позиции корзины.
  final ValueChanged<String>? onOpenDay;
  final ValueChanged<String>? onAddDishes;

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  bool _autoRestoreAttempted = false;
  bool _restoringSaved = false;

  ValueChanged<String>? get onOpenDay => widget.onOpenDay;
  ValueChanged<String>? get onAddDishes => widget.onAddDishes;

  Future<void> _restoreSaved(Uri? source) async {
    try {
      if (!mounted ||
          GoRouter.maybeOf(context)?.routerDelegate.state.uri != source) {
        return;
      }
      final ready = await ref
          .read(cartEditControllerProvider.notifier)
          .resume(restoreOpenedCart: true);
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
    } finally {
      if (mounted) setState(() => _restoringSaved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cartPersistenceControllerProvider);
    final status = ref.watch(sessionStatusProvider);
    if (status != SessionStatus.signedIn) {
      final (heading, message) = switch (status) {
        SessionStatus.restoring => (AppStrings.cart, AppStrings.pleaseWait),
        SessionStatus.unavailable => (
          AppStrings.sessionUnavailable,
          AppStrings.sessionUnavailableMessage,
        ),
        _ => (AppStrings.cart, AppStrings.signInRequired),
      };
      return RoutePage(
        title: heading,
        message: message,
        isLoading: status == SessionStatus.restoring,
        quietLoading: true,
        showTitle: MediaQuery.sizeOf(context).width < orderColumnsMinWidth,
        onHome: () => context.go('/'),
        onRetry: status == SessionStatus.unavailable
            ? () => ref.read(sessionControllerProvider.notifier).restore()
            : null,
        onSignIn: status == SessionStatus.signedOut
            ? () => context.go('/sign-in?from=${Uri.encodeComponent('/cart')}')
            : null,
      );
    }

    final repeatUri = GoRouter.maybeOf(context)?.routerDelegate.state.uri;
    final cart = ref.watch(editingCartProvider);
    final edit = ref.watch(cartEditControllerProvider);
    final recovery = edit.recovery;
    if (!_autoRestoreAttempted &&
        !_restoringSaved &&
        (recovery != null || (!edit.active && !edit.recoveryError)) &&
        !edit.isRepeat &&
        !edit.loading &&
        !edit.restoring &&
        !ref.watch(cartRepeatWorkProvider).loading &&
        !ref.watch(cartSubmitControllerProvider).editingLocked &&
        !versionBlocksWork(ref.watch(appVersionControllerProvider))) {
      _autoRestoreAttempted = true;
      _restoringSaved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreSaved(repeatUri);
      });
    }
    if (edit.restoring || _restoringSaved) {
      return RoutePage(
        title: AppStrings.cart,
        isLoading: true,
        quietLoading: true,
        showTitle: MediaQuery.sizeOf(context).width < orderColumnsMinWidth,
        onHome: () => context.go('/'),
      );
    }
    final changed = ref.watch(cartChangedDatesProvider);
    final cancelled = ref.watch(cartCancelledDatesProvider).toSet();
    final editable =
        edit.active &&
        changed.isNotEmpty &&
        !edit.storageError &&
        changed.every((d) => ref.watch(cartDayEditableProvider(d)));
    final selectedEditable =
        edit.dateKey != null &&
        ref.watch(cartDayEditableProvider(edit.dateKey!));
    final visibleDates = <String>{
      ...cart.days.map((d) => d.dateKey),
      ...cancelled,
      if (edit.active) edit.dateKey!,
    }.toList()..sort();
    final pricing = ref.watch(cartPricingProvider);
    final submissionPricing = ref.watch(cartSubmissionPricingProvider);
    final submit = ref.watch(cartSubmitControllerProvider);
    if (submit.phase == CartSubmitPhase.succeeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted ||
            ref.read(cartSubmitControllerProvider).phase !=
                CartSubmitPhase.succeeded) {
          return;
        }
        ref.read(cartSubmitControllerProvider.notifier).acknowledge();
        final messenger = ScaffoldMessenger.of(context);
        if (GoRouter.maybeOf(context) != null) {
          appNavigate(context, '/orders');
        }
        messenger.showSnackBar(
          SnackBar(content: Text(submit.message ?? AppStrings.cartAccepted)),
        );
      });
    }
    final menu = ref.watch(menuControllerProvider).asData?.value;
    final allowed = ref.watch(menuAllowedDatesProvider).asData?.value;
    final freshness = menu == null
        ? const <CartFreshnessIssue>[]
        : checkCartFreshness(
            cart: ref.watch(submittingCartProvider),
            weeks: menu,
            allowedDateKeys: allowed,
          );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            if (MediaQuery.sizeOf(context).width < orderColumnsMinWidth) ...[
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppStrings.cart,
                    key: ValueKey('route-page-title'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: _CartActions(
                pricingReady:
                    editable &&
                    submissionPricing != null &&
                    !submissionPricing.hasBlockingConstraint,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 480;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visibleDates.isNotEmpty)
                SingleChildScrollView(
                  key: const ValueKey('cart-day-tabs'),
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: compact ? 0 : 8,
                  ),
                  child: Row(
                    children: [
                      for (final date in visibleDates)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Semantics(
                            selected: date == edit.dateKey,
                            label:
                                '${formatCalendarDate(date)}${changed.contains(date) ? ', изменён' : ''}${cancelled.contains(date) ? ', отмена' : ''}',
                            child: TextButton(
                              key: ValueKey('cart-tab-$date'),
                              style: TextButton.styleFrom(
                                backgroundColor: date == edit.dateKey
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                              ),
                              onPressed: submit.editingLocked || edit.loading
                                  ? null
                                  : () async {
                                      ref
                                          .read(
                                            cartEditControllerProvider.notifier,
                                          )
                                          .selectDay(date);
                                      if (menu != null) {
                                        await ref
                                            .read(
                                              menuSelectionProvider.notifier,
                                            )
                                            .openDate(date, menu);
                                      }
                                    },
                              child: Text(
                                '${formatMenuDayLabel(date).split(' ').first}${changed.contains(date) ? '!' : ''}\n${formatCalendarDate(date, includeYear: false)}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  key: const ValueKey('cart-items-scroll'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    const CartWorkBanner(
                      showDiscard: false,
                      autoRestore: false,
                    ),
                    if (edit.message != null && edit.recovery != null)
                      Text(edit.message!),
                    CartRepeatBanner(
                      showDiscard: false,
                      viewCurrent: () =>
                          context.mounted &&
                          GoRouter.maybeOf(context)?.routerDelegate.state.uri ==
                              repeatUri,
                    ),
                    if (edit.active) ...[
                      if (cart.isEmpty)
                        Text(
                          formatMenuDayLabel(edit.dateKey!)
                              .replaceFirst(' ', '\n'),
                          key: const ValueKey('cart-edit-day'),
                        ),
                      if (MediaQuery.sizeOf(context).width <
                          orderColumnsMinWidth) ...[
                        FilledButton.tonal(
                          key: const ValueKey('cart-add-dishes'),
                          onPressed: selectedEditable && onAddDishes != null
                              ? () => onAddDishes!(edit.dateKey!)
                              : null,
                          child: const Text('Добавить блюда'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (edit.blocked)
                        TextButton(
                          onPressed: () => appNavigate(context, '/orders'),
                          child: const Text('Вернуться в заказы'),
                        ),
                    ] else if (submit.phase != CartSubmitPhase.succeeded)
                      const Text(
                        'Для изменения заказа нажмите значок корзины у выбранного дня в заказах.',
                      ),
                    if (edit.dateKey != null &&
                        cancelled.contains(edit.dateKey))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Заказ на этот день будет отменён при сохранении.',
                        ),
                      ),
                    if (cart.dayFor(edit.dateKey ?? '') == null &&
                        cancelled.isEmpty &&
                        !submit.editingLocked &&
                        submit.phase != CartSubmitPhase.succeeded)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          AppStrings.cartEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (pricing == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(AppStrings.cartPricingUnavailable),
                      ),
                    if (freshness.isNotEmpty) ...[
                      Text(
                        AppStrings.cartFreshnessTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final issue in freshness)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(_freshnessText(issue, pricing)),
                        ),
                      const SizedBox(height: 12),
                    ],
                    if (pricing != null && !cart.isEmpty) ...[
                      for (final day in pricing.days)
                        if (day.dateKey == edit.dateKey) ...[
                          _CartDaySection(day: day, onOpenDay: onOpenDay),
                          const SizedBox(height: 16),
                        ],
                    ],
                    if (edit.active &&
                        pricing != null &&
                        cart.dayFor(edit.dateKey!) == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Итого за день: ${formatRubles(0)}',
                          key: ValueKey('cart-day-total-${edit.dateKey}'),
                        ),
                      ),
                    if (edit.active ||
                        !cart.isEmpty ||
                        submit.phase != CartSubmitPhase.idle)
                      _SubmitSection(submit: submit),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _freshnessText(CartFreshnessIssue issue, CartPricingView? pricing) {
    final date = formatCalendarDate(issue.dateKey);
    var name = AppStrings.cartUnavailableDish;
    for (final day in pricing?.days ?? const <CartPricedDay>[]) {
      if (day.dateKey != issue.dateKey) continue;
      for (final line in day.lines) {
        if (line.dishId == issue.dishId && !line.missingFromMenu) {
          name = line.dishName;
        }
      }
    }
    switch (issue.kind) {
      case CartFreshnessKind.closedDate:
        return '${AppStrings.cartDayClosed}: $date';
      case CartFreshnessKind.missingDish:
        if (name == AppStrings.cartUnavailableDish) {
          return '${AppStrings.cartDishMissing} ($date)';
        }
        return '${AppStrings.cartDishMissing}: $name ($date)';
      case CartFreshnessKind.priceChanged:
        return '${AppStrings.cartPriceChanged}: $name ($date) '
            '${formatRubles(issue.expectedPrice)} → ${formatRubles(issue.actualPrice)}';
    }
  }
}

class _CartDaySection extends ConsumerWidget {
  const _CartDaySection({required this.day, required this.onOpenDay});

  final CartPricedDay day;
  final ValueChanged<String>? onOpenDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final locked = !ref.watch(cartDayEditableProvider(day.dateKey));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        key: ValueKey('cart-open-day-${day.dateKey}'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          textStyle: theme.textTheme.titleMedium,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: onOpenDay == null
                            ? null
                            : () => onOpenDay!(day.dateKey),
                        child: Semantics(
                          label: formatCalendarDate(day.dateKey),
                          child: Text(
                            formatMenuDayLabel(day.dateKey)
                                .replaceFirst(' ', '\n'),
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.55,
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          alignment: Alignment.centerRight,
                        ),
                        onPressed: locked
                            ? null
                            : () => ref
                                  .read(cartDraftProvider.notifier)
                                  .clearDay(day.dateKey),
                        child: const Text(
                          AppStrings.cartClearDay,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            for (final line in day.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.dishName, style: theme.textTheme.titleSmall),
                    if (line.missingFromMenu)
                      const Text(AppStrings.cartDishMissing)
                    else
                      Text.rich(
                        TextSpan(
                          children: [
                            if (line.hasDiscount)
                              TextSpan(
                                text: '${formatRubles(line.price)} ',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize:
                                      (theme.textTheme.bodyMedium?.fontSize ??
                                          14) *
                                      0.8,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            TextSpan(
                              text:
                                  '${formatRubles(line.displayUnitPrice)} × ${line.quantity} · ${AppStrings.cartTotal}: ${formatRubles(line.totals.finalTotal)}',
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: AppStrings.menuDecreaseQuantity,
                            onPressed: locked
                                ? null
                                : () => ref
                                      .read(cartDraftProvider.notifier)
                                      .decrement(day.dateKey, line.dishId),
                            icon: const Icon(Icons.remove),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '${line.quantity}',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: AppStrings.menuIncreaseQuantity,
                            onPressed: locked || line.missingFromMenu
                                ? null
                                : () => ref
                                      .read(cartDraftProvider.notifier)
                                      .increment(day.dateKey, line.dishId),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            onPressed: locked
                                ? null
                                : () => ref
                                      .read(cartDraftProvider.notifier)
                                      .removeItem(day.dateKey, line.dishId),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: AppStrings.cartRemoveItem,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (day.minimum.isBelowMinimum)
              Text(
                '${AppStrings.cartBelowMinimum}: ${formatRubles(day.minimum.finalTotal)} < '
                '${formatRubles(day.minimum.effectiveMinimum)}. ${AppStrings.cartFixMinimum}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (day.limit.isExceeded)
              Text(
                '${AppStrings.cartLimitExceeded}: ${formatRubles(day.limit.comparedFinalTotal)} > '
                '${formatRubles(day.limit.limit)}. ${AppStrings.cartFixLimit}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Итого за день: ${formatRubles(day.totals.finalTotal)}',
              key: ValueKey('cart-day-total-${day.dateKey}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Общие действия над всеми датами текущего набора.
class _CartActions extends ConsumerWidget {
  const _CartActions({required this.pricingReady});
  final bool pricingReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edit = ref.watch(cartEditControllerProvider);
    final repeat = ref.watch(cartRepeatControllerProvider);
    final submit = ref.watch(cartSubmitControllerProvider);
    final locked =
        submit.editingLocked ||
        edit.loading ||
        edit.restoring ||
        repeat.loading ||
        versionBlocksWork(ref.watch(appVersionControllerProvider));
    final canDiscard =
        edit.active ||
        edit.hasSavedWork ||
        repeat.saved != null ||
        repeat.recoveryBlocked;
    return Row(
      children: [
        Expanded(
          child: TextButton(
            key: const ValueKey('cart-cancel-all'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 44),
            ),
            onPressed: locked || !canDiscard
                ? null
                : () => _discard(context, ref),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Отменить'),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: FilledButton(
            key: const ValueKey('cart-save-all'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 44),
            ),
            onPressed: locked || !pricingReady
                ? null
                : () => _save(context, ref),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Сохранить'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final edit = ref.read(cartEditControllerProvider);
    final repeat = ref.read(cartRepeatControllerProvider);
    if (edit.isRepeat || repeat.saved != null || repeat.recoveryBlocked) {
      await ref.read(cartRepeatControllerProvider.notifier).discard();
    } else {
      await ref.read(cartEditControllerProvider.notifier).discard();
    }
    if (!context.mounted) return;
    final remaining = ref.read(cartEditControllerProvider);
    final remainingRepeat = ref.read(cartRepeatControllerProvider);
    if (remaining.active ||
        remaining.hasSavedWork ||
        remainingRepeat.saved != null ||
        remainingRepeat.recoveryBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining.message ??
                remainingRepeat.message ??
                'Не удалось отменить изменения. Повторите.',
          ),
        ),
      );
      return;
    }
    // Сброс legacy draft также фиксируется до выхода из корзины.
    ref.read(cartDraftProvider.notifier).clearAll();
    try {
      await ref.read(cartPersistenceControllerProvider.notifier).persistNow();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отменить изменения. Повторите.'),
          ),
        );
      }
      return;
    }
    if (context.mounted && GoRouter.maybeOf(context) != null) {
      appNavigate(context, '/orders');
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final cancelled = ref.read(cartCancelledDatesProvider).toSet();
    if (cancelled.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Подтвердить отмену заказов?'),
          content: SingleChildScrollView(
            child: Text(
              'При сохранении будут отменены заказы:\n${cancelled.map(formatCartDayTitle).join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Назад'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      );
      if (!context.mounted || confirmed != true) return;
    }
    await ref
        .read(cartSubmitControllerProvider.notifier)
        .submit(confirmedCancellations: cancelled);
  }
}

class _SubmitSection extends ConsumerWidget {
  const _SubmitSection({required this.submit});
  final CartSubmitState submit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Принятая квитанция обрабатывается переходом и уведомлением CartPage.
    if (submit.phase == CartSubmitPhase.succeeded) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (submit.message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              submit.message!,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (submit.isBusy) ...[
          const Center(child: CircularProgressIndicator()),
          Text(
            submit.phase == CartSubmitPhase.restoring
                ? AppStrings.cartRestoringAttempt
                : AppStrings.pleaseWait,
          ),
        ] else if (submit.phase == CartSubmitPhase.recoveryBlocked)
          OutlinedButton(
            onPressed: () =>
                ref.read(cartSubmitControllerProvider.notifier).retryRestore(),
            child: const Text(AppStrings.cartRetryRestore),
          )
        else if (submit.phase == CartSubmitPhase.outcomeUnknown)
          FilledButton(
            onPressed: () => ref
                .read(cartSubmitControllerProvider.notifier)
                .resolveUnknownOutcome(),
            child: const Text(AppStrings.cartCheckResult),
          ),
      ],
    );
  }
}
