import 'dart:math' as math;

import 'package:polevaya_kuhnya/shared/price_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';

import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/features/cart/orders_calendar.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_banner.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_banner.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({
    this.selectedDateKey,
    this.onSelectDay,
    this.onStartOrder,
    this.onRepeatReady,
    super.key,
  });

  final String? selectedDateKey;
  final ValueChanged<String>? onSelectDay;
  final ValueChanged<String>? onStartOrder;
  final VoidCallback? onRepeatReady;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String? _selectedDateKey;
  bool _syncScheduled = false;

  void _repeatReady() {
    if (widget.onRepeatReady != null) {
      widget.onRepeatReady!();
    } else {
      GoRouter.maybeOf(context)?.go('/cart');
    }
  }

  Future<void> _chooseRepeat(
    List<String> allDates,
    List<String> emptyDates,
    String? selected,
  ) async {
    final source = GoRouter.maybeOf(context)?.routerDelegate.state.uri;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Повторить заказ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Один'),
              subtitle: Text(
                selected == null
                    ? 'Выберите день'
                    : formatCartDayTitle(selected),
              ),
              enabled: emptyDates.contains(selected),
              onTap: emptyDates.contains(selected)
                  ? () => Navigator.pop(context, 'one')
                  : null,
            ),
            ListTile(
              title: const Text('Все'),
              subtitle: const Text('Пустые доступные дни обеих недель'),
              enabled: emptyDates.isNotEmpty,
              onTap: emptyDates.isNotEmpty
                  ? () => Navigator.pop(context, 'all')
                  : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Назад'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    final ready = await ref
        .read(cartRepeatControllerProvider.notifier)
        .repeat(
          choice == 'one' ? [selected!] : allDates,
          selected: selected,
          viewCurrent: () =>
              mounted &&
              GoRouter.maybeOf(context)?.routerDelegate.state.uri == source,
        );
    if (mounted && ready) _repeatReady();
  }

  void _select(String dateKey, String? activeDateKey) {
    final edit = ref.read(cartEditControllerProvider);
    if (edit.loading) {
      ref.read(cartEditControllerProvider.notifier).end();
    }
    setState(() => _selectedDateKey = dateKey);
    widget.onSelectDay?.call(dateKey);
  }

  void _syncSelection(String? selected) {
    if (selected == null ||
        widget.onSelectDay == null ||
        selected == widget.selectedDateKey ||
        _syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted ||
          ref.read(sessionStatusProvider) != SessionStatus.signedIn) {
        return;
      }
      final profile = ref.read(sessionProfileProvider);
      final menu = ref.read(menuControllerProvider);
      if (profile == null || menu.isLoading || menu.hasError) return;
      final latest = initialOrderCalendarDate(
        buildOrderCalendar(menu.asData?.value ?? const [], profile.orders),
        selectedDateKey: widget.selectedDateKey ?? _selectedDateKey,
        today: DateTime.now(),
      );
      if (latest != null && latest != widget.selectedDateKey) {
        widget.onSelectDay?.call(latest);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionStatusProvider, (_, next) {
      if (next != SessionStatus.signedIn) _selectedDateKey = null;
    });
    ref.listen(sessionProfileProvider, (previous, next) {
      if ((previous?.login, previous?.employee, previous?.name) !=
          (next?.login, next?.employee, next?.name)) {
        _selectedDateKey = null;
      }
    });
    final status = ref.watch(sessionStatusProvider);
    if (status != SessionStatus.signedIn) {
      final (heading, message) = switch (status) {
        SessionStatus.restoring => (AppStrings.orders, AppStrings.pleaseWait),
        SessionStatus.unavailable => (
          AppStrings.sessionUnavailable,
          AppStrings.sessionUnavailableMessage,
        ),
        _ => (AppStrings.orders, AppStrings.signInRequired),
      };
      return RoutePage(
        title: heading,
        message: message,
        isLoading: status == SessionStatus.restoring,
        quietLoading: true,
        onHome: () => context.go('/'),
        onRetry: status == SessionStatus.unavailable
            ? () => ref.read(sessionControllerProvider.notifier).restore()
            : null,
      );
    }

    final repeatUri = GoRouter.maybeOf(context)?.routerDelegate.state.uri;
    final profile = ref.watch(sessionProfileProvider);
    final menu = ref.watch(menuControllerProvider);
    final dates = ref.watch(menuAllowedDatesProvider);
    ref.watch(cartPersistenceControllerProvider);
    final repeat = ref.watch(cartRepeatControllerProvider);
    final draft = ref.watch(cartDraftProvider);
    final calendar = buildOrderCalendar(
      menu.asData?.value ?? const [],
      profile?.orders ?? const [],
    );
    final selected = initialOrderCalendarDate(
      calendar,
      selectedDateKey: widget.selectedDateKey ?? _selectedDateKey,
      today: DateTime.now(),
    );
    OrderCalendarDay? selectedDay;
    for (final week in calendar) {
      for (final day in week.days) {
        if (day.menuDay.dateKey == selected) selectedDay = day;
      }
    }
    if (profile != null && !menu.isLoading && !menu.hasError) {
      _syncSelection(selected);
    }
    final allDates = <String>[
      if (!menu.isLoading &&
          !menu.hasError &&
          !dates.isLoading &&
          !dates.hasError &&
          dates.asData?.value != null)
        for (final week in calendar)
          for (final day in week.days)
            if (isOrderDateAllowed(dates.asData!.value, day.menuDay.dateKey))
              day.menuDay.dateKey,
    ];
    final occupied = {
      for (final day in profile?.orders ?? const <UserOrderDay>[])
        if (day.dateRaw.length >= 10 &&
            day.status != 'Нет заказа' &&
            day.dishes.isNotEmpty)
          day.dateRaw.substring(0, 10),
    };
    final emptyDates = allDates
        .where((d) => !occupied.contains(d) && !(draft[d]?.isNotEmpty ?? false))
        .toList();
    final repeatLocked =
        repeat.loading ||
        repeat.saved != null ||
        repeat.recoveryBlocked ||
        ref.watch(cartEditControllerProvider).loading ||
        ref.watch(cartSubmitControllerProvider).editingLocked ||
        versionBlocksWork(ref.watch(appVersionControllerProvider));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          (profile?.employee.trim().isNotEmpty ?? false)
              ? profile!.employee.trim()
              : profile?.name.trim() ?? '',
          key: const ValueKey('route-page-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: profile == null
          ? const Center(child: Text(AppStrings.ordersLoadError))
          : ListView(
              key: const PageStorageKey('orders-calendar-scroll'),
              padding: const EdgeInsets.all(16),
              children: [
                CartRepeatBanner(
                  onReady: _repeatReady,
                  viewCurrent: () =>
                      mounted &&
                      GoRouter.maybeOf(context)?.routerDelegate.state.uri ==
                          repeatUri,
                ),
                CartWorkBanner(onReady: _repeatReady),
                if (ref.watch(cartEditControllerProvider).loading)
                  const Center(child: CircularProgressIndicator()),
                if (menu.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (menu.hasError) ...[
                  const Text(AppStrings.ordersMenuError),
                  TextButton(
                    onPressed: () =>
                        ref.read(menuControllerProvider.notifier).reload(),
                    child: const Text(AppStrings.ordersRetryMenu),
                  ),
                ] else ...[
                  if (dates.hasError ||
                      (!dates.isLoading && dates.asData?.value == null)) ...[
                    const Text(AppStrings.ordersAvailabilityUnknown),
                    TextButton(
                      onPressed: () =>
                          ref.read(menuAllowedDatesProvider.notifier).reload(),
                      child: const Text(AppStrings.ordersRetryDates),
                    ),
                    const SizedBox(height: 12),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const buttonWidth = 44.0;
                      final days = calendar
                          .expand((week) => week.days)
                          .toList();
                      const beside = true;
                      final metrics = _CalendarMetrics.measure(
                        context,
                        days,
                        dates,
                        dayWidth: (constraints.maxWidth - 12) / 2,
                        buttonWidth: buttonWidth,
                        hasStartOrder: widget.onStartOrder != null,
                      );
                      final columns = [
                        for (final week in calendar)
                          _WeekColumn(
                            week: week,
                            selected: selected,
                            dates: dates,
                            onSelect: (dateKey) => _select(dateKey, selected),
                            beside: beside,
                            metrics: metrics,
                            onStartOrder: widget.onStartOrder,
                            startLocked:
                                ref.watch(cartEditControllerProvider).loading ||
                                ref
                                    .watch(cartSubmitControllerProvider)
                                    .editingLocked ||
                                versionBlocksWork(
                                  ref.watch(appVersionControllerProvider),
                                ),
                          ),
                      ];
                      return Row(
                        key: const ValueKey('orders-weeks-row'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: columns[0]),
                          const SizedBox(width: 12),
                          Expanded(child: columns[1]),
                        ],
                      );
                    },
                  ),
                  if (selectedDay != null) ...[
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              formatCartDayTitle(selectedDay!.menuDay.dateKey),
                              key: const ValueKey('orders-selected-heading'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: AppStrings.repeatOrder,
                            child: SizedBox(
                              width: math.min(200, constraints.maxWidth * 0.55),
                              child: TextButton(
                                key: const ValueKey('orders-repeat'),
                                onPressed: repeatLocked || emptyDates.isEmpty
                                    ? null
                                    : () => _chooseRepeat(
                                        allDates,
                                        emptyDates,
                                        selected,
                                      ),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(AppStrings.repeatOrder),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedDay.order != null)
                      _OrderDayTile(day: selectedDay.order!)
                    else
                      const Text(
                        AppStrings.ordersNoOrder,
                        key: ValueKey('orders-selected-empty'),
                      ),
                  ],
                ],
              ],
            ),
    );
  }
}

class _WeekColumn extends StatelessWidget {
  const _WeekColumn({
    required this.week,
    required this.selected,
    required this.dates,
    required this.onSelect,
    required this.beside,
    required this.metrics,
    required this.onStartOrder,
    required this.startLocked,
  });

  final OrderCalendarWeek week;
  final String? selected;
  final AsyncValue<Set<String>?> dates;
  final ValueChanged<String> onSelect;
  final bool beside;
  final _CalendarMetrics metrics;
  final ValueChanged<String>? onStartOrder;
  final bool startLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = week.weekType == 'current'
        ? AppStrings.ordersCurrentWeek
        : AppStrings.ordersNextWeek;
    return Column(
      key: ValueKey('orders-week-${week.weekType}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          beside ? heading.replaceFirst(' ', '\n') : heading,
          style: theme.textTheme.titleSmall,
        ),
        const Divider(),
        if (week.days.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              week.weekType == 'next'
                  ? AppStrings.ordersNextWeekEmpty
                  : AppStrings.ordersNoDeliveryDays,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        for (final day in week.days) ...[
          _CalendarDayButton(
            day: day,
            selected: selected == day.menuDay.dateKey,
            dates: dates,
            onPressed: () => onSelect(day.menuDay.dateKey),
            onStartOrder: onStartOrder == null
                ? null
                : () => onStartOrder!(day.menuDay.dateKey),
            startLocked: startLocked,
            metrics: metrics,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          '${AppStrings.cartTotal}: ${formatRubles(week.total)}',
          key: ValueKey('orders-total-${week.weekType}'),
          style: theme.textTheme.titleSmall,
        ),
      ],
    );
  }
}

Size _textSize(
  BuildContext context,
  String text,
  TextStyle? style, {
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
  )..layout(maxWidth: math.max(1, maxWidth));
  final size = painter.size;
  painter.dispose();
  return size;
}

String _daySum(OrderCalendarDay day) => day.order == null
    ? AppStrings.ordersNoOrder
    : '${day.order!.payable < day.order!.sum ? '${formatRubles(day.order!.sum)} ' : ''}${formatRubles(day.order!.payable)}';

String _dayStatus(OrderCalendarDay day, AsyncValue<Set<String>?> dates) {
  if (dates.isLoading) return AppStrings.ordersChecking;
  if (dates.hasError || dates.asData?.value == null) {
    return AppStrings.ordersAvailabilityUnknown;
  }
  return isOrderDateAllowed(dates.asData!.value, day.menuDay.dateKey)
      ? AppStrings.ordersAvailable
      : AppStrings.ordersClosed;
}

bool _dayEditable(OrderCalendarDay day, AsyncValue<Set<String>?> dates) =>
    !dates.isLoading &&
    !dates.hasError &&
    dates.asData?.value != null &&
    isOrderDateAllowed(dates.asData!.value, day.menuDay.dateKey) &&
    (day.order == null || day.order!.changes);

String _calendarDayLabel(OrderCalendarDay day) {
  const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  return '${weekdays[day.menuDay.date.weekday - 1]} '
      '${formatCalendarDate(day.menuDay.dateKey, includeYear: false)}';
}

String? _calendarDayStatus(
  OrderCalendarDay day,
  AsyncValue<Set<String>?> dates,
) => dates.isLoading || dates.hasError || dates.asData?.value == null
    ? _dayStatus(day, dates)
    : null;

/// Одинаковая высота карточек обеих недель: дата/действие и суммы.
class _CalendarMetrics {
  const _CalendarMetrics(this.height, this.buttonWidth);
  final double height;
  final double buttonWidth;

  static _CalendarMetrics measure(
    BuildContext context,
    List<OrderCalendarDay> days,
    AsyncValue<Set<String>?> dates, {
    required double dayWidth,
    required double buttonWidth,
    required bool hasStartOrder,
  }) {
    final text = Theme.of(context).textTheme;
    var header = _textSize(context, 'Вт 06.10', text.bodyMedium).height;
    if (hasStartOrder) header = math.max(header, 44);
    var details = _textSize(context, '286 ₽  300 ₽', text.bodyMedium).height;
    for (final day in days) {
      final status = _calendarDayStatus(day, dates);
      if (status != null) {
        details = math.max(
          details,
          _textSize(context, _daySum(day), text.bodyMedium).height +
              4 +
              _textSize(
                context,
                status,
                text.bodySmall,
                maxWidth: dayWidth - 16,
              ).height,
        );
      }
    }
    return _CalendarMetrics(
      (16 + header + 4 + details).ceilToDouble(),
      math.min(buttonWidth, dayWidth - 16),
    );
  }
}

class _CalendarDayButton extends StatelessWidget {
  const _CalendarDayButton({
    required this.day,
    required this.selected,
    required this.dates,
    required this.onPressed,
    required this.onStartOrder,
    required this.startLocked,
    required this.metrics,
  });

  final OrderCalendarDay day;
  final bool selected;
  final AsyncValue<Set<String>?> dates;
  final VoidCallback onPressed;
  final VoidCallback? onStartOrder;
  final bool startLocked;
  final _CalendarMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowedKeys = dates.asData?.value;
    final known = !dates.isLoading && !dates.hasError && allowedKeys != null;
    final available =
        known && isOrderDateAllowed(allowedKeys, day.menuDay.dateKey);
    final editable = _dayEditable(day, dates);
    final showAction = editable && onStartOrder != null;
    final status = _calendarDayStatus(day, dates);
    final date = day.menuDay.date;
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final sum = _daySum(day);
    return Semantics(
      selected: selected,
      label: [
        if (isToday) AppStrings.ordersToday,
        _dayStatus(day, dates),
      ].join(', '),
      child: SizedBox(
        height: metrics.height,
        width: double.infinity,
        child: TextButton(
          key: ValueKey('orders-day-${day.menuDay.dateKey}'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            backgroundColor: available
                ? const Color(0xFFE6F4EA)
                : AppTheme.primaryLight,
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(44, 64),
            side: BorderSide(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 2 : 1,
            ),
            alignment: Alignment.centerLeft,
          ),
          onPressed: onPressed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: Text(
                          _calendarDayLabel(day),
                          maxLines: 1,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: theme.textTheme.titleMedium?.fontWeight,
                          ),
                        ),
                      ),
                    ),
                    if (showAction) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: metrics.buttonWidth,
                        child: FilledButton(
                          key: ValueKey('orders-start-${day.menuDay.dateKey}'),
                          onPressed: startLocked ? null : onStartOrder,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          child: const Icon(
                            Icons.shopping_cart_outlined,
                            semanticLabel: 'Изменить заказ',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: day.order == null
                      ? Text(sum, style: theme.textTheme.bodyMedium)
                      : PriceText(
                          original: day.order!.sum,
                          current: day.order!.payable,
                          inline: true,
                        ),
                ),
              ),
              if (status != null) ...[
                const SizedBox(height: 4),
                Text(status, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDayTile extends StatelessWidget {
  const _OrderDayTile({required this.day});

  final UserOrderDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${AppStrings.ordersDaySum}: ',
                    style: theme.textTheme.titleSmall,
                  ),
                  PriceText(
                    original: day.sum,
                    current: day.payable,
                    style: theme.textTheme.titleSmall,
                    inline: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final dish in day.dishes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${dish.name.trim().isEmpty ? AppStrings.cartUnavailableDish : dish.name} × ${formatQuantity(dish.quantity)} — ${formatRubles(dish.sum)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
