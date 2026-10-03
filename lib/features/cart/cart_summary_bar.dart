import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_freshness.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

/// Итог отправляемых дат; без подготовки сохранённые черновики не показываются.
/// Переход не отправляет заказ и не даёт разрешение редактирования.
class CartSummaryBar extends ConsumerWidget {
  const CartSummaryBar({required this.onOpenCart, super.key});

  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionStatusProvider);
    ref.watch(cartPersistenceControllerProvider);
    if (status != SessionStatus.signedIn) return const SizedBox.shrink();
    final cart = ref.watch(submittingCartProvider);
    if (cart.isEmpty && !ref.watch(cartEditControllerProvider).active) {
      return const SizedBox.shrink();
    }
    final pricing = ref.watch(cartSubmissionPricingProvider);
    final menu = ref.watch(menuControllerProvider);
    final dates = ref.watch(menuAllowedDatesProvider);
    final weeks = menu.asData?.value;
    final warning =
        weeks == null ||
        dates.hasError ||
        (pricing?.missingDishCount ?? 0) > 0 ||
        checkCartFreshness(
          cart: cart,
          weeks: weeks,
          allowedDateKeys: dates.asData?.value,
        ).isNotEmpty;
    final portions = cart.days.fold<int>(
      0,
      (sum, day) =>
          sum + day.items.fold<int>(0, (sum, item) => sum + item.quantity),
    );
    final amount = pricing == null || pricing.missingDishCount > 0
        ? AppStrings.cartAmountPending
        : formatRubles(pricing.cartTotals.finalTotal);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Material(
        key: const ValueKey('cart-summary-bar'),
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    MediaQuery.textScalerOf(context).scale(16) >= 20.8;
                final totals = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppStrings.cartPortions}: $portions',
                      key: const ValueKey('cart-summary-portions'),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      amount,
                      key: const ValueKey('cart-summary-amount'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                );
                final action = FilledButton(
                  onPressed: onOpenCart,
                  key: const ValueKey('cart-summary-open'),
                  child: const Text(AppStrings.cartOpen),
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stacked) ...[
                      totals,
                      const SizedBox(height: 8),
                      action,
                    ] else
                      Row(
                        children: [
                          Expanded(child: totals),
                          const SizedBox(width: 12),
                          action,
                        ],
                      ),
                    if (warning)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppStrings.cartReviewFreshness,
                                key: const ValueKey('cart-summary-warning'),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
