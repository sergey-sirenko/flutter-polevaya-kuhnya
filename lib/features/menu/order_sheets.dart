import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

class OrderSheetLayer extends ConsumerWidget {
  const OrderSheetLayer({
    required this.kind,
    required this.weeks,
    required this.onCategory,
    super.key,
  });

  final OrderSheet kind;
  final List<MenuWeek> weeks;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('order-sheet-barrier'),
            onTap: () => ref.read(orderSheetProvider.notifier).close(),
            child: const ColoredBox(color: Color(0x66000000)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Material(
              key: ValueKey(
                kind == OrderSheet.day
                    ? 'order-day-sheet'
                    : 'order-category-sheet',
              ),
              color: Theme.of(context).colorScheme.surface,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              kind == OrderSheet.day
                                  ? AppStrings.orderDay
                                  : AppStrings.menu,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: AppStrings.close,
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                ref.read(orderSheetProvider.notifier).close(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: kind == OrderSheet.day
                          ? _DaySheet(weeks: weeks)
                          : _CategorySheet(
                              weeks: weeks,
                              onCategory: onCategory,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.weeks});

  final List<MenuWeek> weeks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(menuSelectionProvider);
    final allowedDates = ref.watch(menuAllowedDatesProvider).asData?.value;

    final week = selection == null
        ? null
        : menuWeekByType(weeks, selection.weekType);
    final weekChips = [
      for (final item in menuWeeksForDisplay(weeks))
        Semantics(
          selected: selection?.weekType == item.weekType,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.transparent,
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => ref
                .read(menuSelectionProvider.notifier)
                .selectWeek(item.weekType, weeks),
            child: Text(
              item.weekType == 'current'
                  ? AppStrings.menuCurrentWeek
                  : AppStrings.menuNextWeek,
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontSize: 18,
                fontWeight: selection?.weekType == item.weekType
                    ? FontWeight.bold
                    : FontWeight.normal,
                decoration: selection?.weekType == item.weekType
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
          ),
        ),
    ];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          key: const ValueKey('order-week-row'),
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < weekChips.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Flexible(child: weekChips[index]),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (week == null || week.deliveryDays.isEmpty)
          const Text(AppStrings.menuNoDeliveryDays)
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in week.deliveryDays)
                _DayChoice(
                  day: day,
                  selected: selection?.dateKey == day.dateKey,
                  available:
                      allowedDates != null &&
                      isOrderDateAllowed(allowedDates, day.dateKey),
                  onSelected: () {
                    ref
                        .read(menuSelectionProvider.notifier)
                        .selectDay(day.dateKey, weeks);
                    ref.read(orderSheetProvider.notifier).close();
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _DayChoice extends StatelessWidget {
  const _DayChoice({
    required this.day,
    required this.selected,
    required this.available,
    required this.onSelected,
  });

  final MenuDay day;
  final bool selected;
  final bool available;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final date = formatCalendarDate(day.dateKey, includeYear: false);
    final name = day.dayName;
    final label = name != null && name.isNotEmpty ? '$name ($date)' : date;
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(0, 48),
        ),
        onPressed: onSelected,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            decoration: selected
                ? TextDecoration.underline
                : TextDecoration.none,
            color: available ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ),
    );
  }
}

class _CategorySheet extends ConsumerWidget {
  const _CategorySheet({required this.weeks, required this.onCategory});

  final List<MenuWeek> weeks;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(menuSelectionProvider);
    final activeCategoryId = ref.watch(menuActiveCategoryProvider);
    final day = selectedMenuDay(weeks, selection);
    final categories = day?.categoriesSorted ?? const <MenuCategory>[];
    if (categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(AppStrings.menuNoDishesForDay),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        for (final category in categories)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              backgroundColor: activeCategoryId == category.categoryId
                  ? Theme.of(context).colorScheme.surfaceContainer
                  : null,
              padding: const EdgeInsets.all(12),
              minimumSize: const Size(0, 88),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              children: [
                MenuCategoryThumb(category: category, dimension: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.categoryName,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                if (activeCategoryId == category.categoryId)
                  const Icon(Icons.check),
              ],
            ),
            onPressed: () {
              ref.read(orderSheetProvider.notifier).close();
              onCategory(category.categoryId);
            },
          ),
      ],
    );
  }
}
