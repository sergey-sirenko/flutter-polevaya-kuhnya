import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/cart/pricing.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Процентная цена одной порции. Дневная дотация требует состава корзины.
final menuDiscountedPriceProvider = Provider.family<num, num>((ref, price) {
  final profile = ref.watch(sessionProfileProvider);
  final conditions = clientPricingConditionsFromUser(profile?.rawUser);
  if (conditions.discountPercentage <= 0) return price;
  return calculateLineTotals(
    price: price,
    quantity: 1,
    discountPercentage: conditions.discountPercentage,
    discountClientAvailable: 0,
  ).finalTotal;
});

/// Позиция предпросмотра с данными меню.
final class CartPricedLine {
  const CartPricedLine({
    required this.dishId,
    required this.dishName,
    required this.price,
    required this.quantity,
    required this.totals,
    this.missingFromMenu = false,
  });

  final String dishId;
  final String dishName;
  final num price;
  final int quantity;
  final LineTotals totals;
  final bool missingFromMenu;

  bool get hasDiscount =>
      totals.discountAmount > 0 || totals.discountClientAmount > 0;

  /// Справочная цена порции из уже округлённой суммы строки.
  num get displayUnitPrice =>
      hasDiscount && quantity > 0 ? totals.finalTotal / quantity : price;
}

/// День предпросмотра с ограничениями.
final class CartPricedDay {
  const CartPricedDay({
    required this.dateKey,
    required this.weekType,
    required this.lines,
    required this.totals,
    required this.minimum,
    required this.limit,
  });

  final String dateKey;
  final String weekType;
  final List<CartPricedLine> lines;
  final AggregateTotals totals;
  final DayMinimumCheck minimum;
  final LimitPreview limit;

  bool get hasBlockingConstraint => minimum.isBelowMinimum || limit.isExceeded;
}

/// Полный предпросмотр корзины без формул в UI.
final class CartPricingView {
  const CartPricingView({
    required this.days,
    required this.weekTotalsByType,
    required this.conditions,
    required this.missingDishCount,
  });

  final List<CartPricedDay> days;
  final Map<String, AggregateTotals> weekTotalsByType;
  final ClientPricingConditions conditions;
  final int missingDishCount;

  bool get isEmpty => days.isEmpty;

  bool get hasBlockingConstraint =>
      days.any((day) => day.hasBlockingConstraint) || missingDishCount > 0;

  AggregateTotals get cartTotals {
    var base = 0;
    var discount = 0;
    var client = 0;
    var finalSum = 0;
    for (final day in days) {
      base += day.totals.baseTotal;
      discount += day.totals.discountAmount;
      client += day.totals.discountClientAmount;
      finalSum += day.totals.finalTotal;
    }
    return AggregateTotals(
      baseTotal: pricingRound(base),
      discountAmount: pricingRound(discount),
      discountClientAmount: pricingRound(client),
      finalTotal: pricingRound(finalSum),
    );
  }
}

CartPricingView buildCartPricingView({
  required Cart cart,
  required List<MenuWeek> weeks,
  required ClientPricingConditions conditions,
  Map<String, String> fallbackNames = const {},
}) {
  final index = indexMenuByDate(weeks);
  final pricingDays = <PricingDayInput>[];
  final lineMeta = <String, List<({CartItem item, MenuDish? dish})>>{};

  for (final day in cart.days) {
    final dishes = index.dishesByDate[day.dateKey] ?? const {};
    final weekType = index.weekTypeByDate[day.dateKey] ?? '';
    final meta = <({CartItem item, MenuDish? dish})>[];
    final lines = <PricingLineInput>[];
    for (final item in day.items) {
      final dish = dishes[item.dishId];
      meta.add((item: item, dish: dish));
      lines.add(
        PricingLineInput(
          price: dish?.price ?? 0,
          quantity: item.quantity,
          menuOrder: dish?.menuOrder ?? missingMenuOrder,
        ),
      );
    }
    lineMeta[day.dateKey] = meta;
    pricingDays.add(
      PricingDayInput(weekType: weekType, dayKey: day.dateKey, lines: lines),
    );
  }

  final priced = calculateCart(days: pricingDays, conditions: conditions);
  final viewDays = <CartPricedDay>[];
  var missing = 0;

  for (final result in priced.days) {
    final dateKey = result.dayKey.toString();
    final meta = lineMeta[dateKey]!;
    final sortedMeta = List<({CartItem item, MenuDish? dish})>.of(meta)
      ..sort((a, b) {
        final ao = a.dish?.menuOrder ?? missingMenuOrder;
        final bo = b.dish?.menuOrder ?? missingMenuOrder;
        return ao.compareTo(bo);
      });
    final lines = <CartPricedLine>[];
    for (var i = 0; i < sortedMeta.length; i++) {
      final entry = sortedMeta[i];
      final dish = entry.dish;
      if (dish == null) missing++;
      lines.add(
        CartPricedLine(
          dishId: entry.item.dishId,
          dishName:
              dish?.dishName ??
              fallbackNames['$dateKey|${entry.item.dishId}'] ??
              fallbackNames[entry.item.dishId] ??
              AppStrings.cartUnavailableDish,
          price: dish?.price ?? 0,
          quantity: entry.item.quantity,
          totals: result.lines[i],
          missingFromMenu: dish == null,
        ),
      );
    }
    final weekTotals =
        priced.weekTotalsByType[result.weekType] ?? AggregateTotals.zero;
    final minimum = checkDayMinimum(
      dayKey: dateKey,
      lines: pricingDays.firstWhere((d) => d.dayKey == dateKey).lines,
      dayTotals: result.totals,
      conditions: conditions,
    );
    final limit = previewLimit(
      conditions: conditions,
      dayTotals: result.totals,
      weekTotals: weekTotals,
    );
    viewDays.add(
      CartPricedDay(
        dateKey: dateKey,
        weekType: result.weekType,
        lines: lines,
        totals: result.totals,
        minimum: minimum,
        limit: limit,
      ),
    );
  }

  return CartPricingView(
    days: viewDays,
    weekTotalsByType: priced.weekTotalsByType,
    conditions: conditions,
    missingDishCount: missing,
  );
}

/// Предпросмотр при наличии меню и профиля; иначе `null`.
final cartPricingProvider = Provider<CartPricingView?>((ref) {
  final cart = ref.watch(editingCartProvider);
  if (cart.isEmpty) {
    return CartPricingView(
      days: const [],
      weekTotalsByType: const {},
      conditions: clientPricingConditionsFromUser(const {}),
      missingDishCount: 0,
    );
  }
  final menu = ref.watch(menuControllerProvider).asData?.value;
  final profile = ref.watch(sessionProfileProvider);
  if (menu == null || profile == null) return null;
  return buildCartPricingView(
    cart: cart,
    weeks: menu,
    conditions: clientPricingConditionsFromUser(profile.rawUser),
    fallbackNames: ref.watch(cartEditControllerProvider).names,
  );
});

/// Ограничения и итог только отправляемых дат; нетронутые заказы не входят.
final cartSubmissionPricingProvider = Provider<CartPricingView?>((ref) {
  final cart = ref.watch(submittingCartProvider);
  final menu = ref.watch(menuControllerProvider).asData?.value;
  final profile = ref.watch(sessionProfileProvider);
  if (menu == null || profile == null) return null;
  return buildCartPricingView(
    cart: cart,
    weeks: menu,
    conditions: clientPricingConditionsFromUser(profile.rawUser),
    fallbackNames: ref.watch(cartEditControllerProvider).names,
  );
});
