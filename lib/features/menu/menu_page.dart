import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/order_layout.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/shared/price_text.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/features/menu/order_sheets.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

/// Бизнес-экран меню (этап 4, ADR-6). UI → Controller; количества — cart draft.
class MenuPage extends ConsumerStatefulWidget {
  const MenuPage({required this.onHome, this.onSignIn, super.key});

  final VoidCallback onHome;
  final VoidCallback? onSignIn;

  @override
  ConsumerState<MenuPage> createState() => _MenuPageState();
}

class _PhotoRequest {
  const _PhotoRequest(this.dish, {required this.image});

  final MenuDish dish;
  final bool image;
}

class _PhotoOverlayController extends Notifier<_PhotoRequest?> {
  @override
  _PhotoRequest? build() => null;

  void open(MenuDish dish, {required bool image}) {
    state = _PhotoRequest(dish, image: image);
  }

  void close() => state = null;
}

final _photoOverlayProvider =
    NotifierProvider<_PhotoOverlayController, _PhotoRequest?>(
      _PhotoOverlayController.new,
    );

/// Интеграция Back: закрытие фото имеет приоритет перед переходом маршрута.
final menuHasPhotoOverlayProvider = Provider<bool>(
  (ref) => ref.watch(_photoOverlayProvider) != null,
);

class _MenuPageState extends ConsumerState<MenuPage> {
  final _scrollController = ScrollController();
  final _dishesKey = GlobalKey();
  final _categoryKeys = <String, GlobalKey>{};
  String? _activeCategoryId;
  bool _programmaticScroll = false;
  bool _categoryRestoreScheduled = false;
  bool _sheetCloseScheduled = false;
  bool _selectionSyncScheduled = false;
  Timer? _categorySyncLock;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _categorySyncLock?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_programmaticScroll || !_scrollController.hasClients) return;
    final viewport = _dishViewport();
    if (viewport == null) return;
    final anchor = viewport.localToGlobal(Offset.zero).dy + 8;
    String? active;
    for (final entry in _categoryKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy <= anchor) {
        active = entry.key;
      }
    }
    active ??= _categoryKeys.keys.firstOrNull;
    if (active != null && active != _activeCategoryId) {
      _rememberCategory(active);
      setState(() => _activeCategoryId = active);
    }
  }

  void _rememberCategory(String categoryId) {
    ref.read(menuActiveCategoryProvider.notifier).select(categoryId);
  }

  /// Главная уже читает меню, поэтому слушатель страницы не получает первое
  /// значение и день остаётся невыбранным.
  void _scheduleSelectionSync(List<MenuWeek> weeks) {
    if (_selectionSyncScheduled) return;
    if (!menuSelectionNeedsSync(weeks, ref.read(menuSelectionProvider))) {
      return;
    }
    _selectionSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _selectionSyncScheduled = false;
      if (!mounted) return;
      final latest = ref.read(menuControllerProvider).asData?.value;
      if (latest == null || latest.isEmpty) return;
      if (!menuSelectionNeedsSync(latest, ref.read(menuSelectionProvider))) {
        return;
      }
      await ref.read(menuSelectionProvider.notifier).syncWithWeeks(latest);
    });
  }

  void _scheduleCategoryRestore(List<MenuCategory> categories) {
    // Восстановление выполняется только при первом доступном меню.
    // Последующая ручная прокрутка не должна запускать его заново.
    if (_categoryRestoreScheduled) return;
    _categoryRestoreScheduled = true;
    final saved = ref.read(menuActiveCategoryProvider);
    if (saved == null || !categories.any((item) => item.categoryId == saved)) {
      return;
    }
    _programmaticScroll = true;
    _restoreSavedCategory(saved);
  }

  void _restoreSavedCategory(String categoryId, [int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final weeks = ref.read(menuControllerProvider).asData?.value;
      final day = selectedMenuDay(
        weeks ?? const <MenuWeek>[],
        ref.read(menuSelectionProvider),
      );
      final categories = day?.categoriesSorted ?? const <MenuCategory>[];
      if (!categories.any((item) => item.categoryId == categoryId)) {
        _programmaticScroll = false;
        return;
      }
      final ready =
          _categoryKeys[categoryId]?.currentContext != null &&
          _scrollController.hasClients;
      if (!ready && attempt < 8) {
        _restoreSavedCategory(categoryId, attempt + 1);
        return;
      }
      _scrollToCategory(categoryId);
    });
  }

  RenderBox? _dishViewport() {
    final box =
        _scrollController.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box;
  }

  Future<void> _scrollToCategory(String categoryId) async {
    _rememberCategory(categoryId);
    if (_activeCategoryId != categoryId) {
      setState(() => _activeCategoryId = categoryId);
    }
    final target = _categoryKeys[categoryId]?.currentContext;
    if (target == null || !_scrollController.hasClients) return;
    final targetBox = target.findRenderObject() as RenderBox?;
    final viewport = _dishViewport();
    if (targetBox == null || !targetBox.hasSize || viewport == null) return;
    // На телефоне название уже закреплено над списком: открываем блюда
    // сразу после заголовка раздела, чтобы не показывать его второй раз.
    final headingOffset = _phoneDishGrid(context) ? targetBox.size.height : 0.0;
    final delta =
        targetBox.localToGlobal(Offset.zero, ancestor: viewport).dy +
        headingOffset;
    final position = _scrollController.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    setState(() {
      _activeCategoryId = categoryId;
      _programmaticScroll = true;
    });
    await _scrollController.animateTo(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
    _armCategorySyncLock();
  }

  void _armCategorySyncLock() {
    _categorySyncLock?.cancel();
    if (!mounted) return;
    _categorySyncLock = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _programmaticScroll = false);
    });
  }

  void _keepDishScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    _categorySyncLock?.cancel();
    _programmaticScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final restored = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - restored).abs() > 0.5) {
        position.jumpTo(restored);
      }
      _armCategorySyncLock();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cartPersistenceControllerProvider);
    final menu = ref.watch(menuControllerProvider);
    final dates = ref.watch(menuAllowedDatesProvider);
    final sheet = ref.watch(orderSheetProvider);
    final photo = ref.watch(_photoOverlayProvider);
    final compactOrder = MediaQuery.sizeOf(context).width < 600;
    if (photo != null && photo.image == compactOrder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(ref.read(_photoOverlayProvider), photo)) {
          ref.read(_photoOverlayProvider.notifier).close();
        }
      });
    }
    final menuData = menu.asData?.value;
    if (menuData != null && menuData.isNotEmpty) {
      _scheduleSelectionSync(menuData);
      final day = selectedMenuDay(menuData, ref.read(menuSelectionProvider));
      final categories = day?.categoriesSorted ?? const <MenuCategory>[];
      if (categories.isNotEmpty) _scheduleCategoryRestore(categories);
    }
    if (!compactOrder && sheet != null && !_sheetCloseScheduled) {
      _sheetCloseScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetCloseScheduled = false;
        if (!mounted || MediaQuery.sizeOf(context).width < 600) return;
        ref.read(orderSheetProvider.notifier).close();
      });
    }

    ref.listen(orderSheetProvider, (previous, next) {
      if (next != null) ref.read(_photoOverlayProvider.notifier).close();
    });

    ref.listen(menuSelectionProvider, (previous, next) {
      if (previous?.dateKey == next?.dateKey) return;
      final saved = ref.read(menuActiveCategoryProvider);
      if (saved == null) return;
      _programmaticScroll = true;
      _restoreSavedCategory(saved);
    });

    ref.listen(menuControllerProvider, (previous, next) {
      next.whenData((weeks) {
        ref.read(menuSelectionProvider.notifier).syncWithWeeks(weeks);
      });
    });

    return PopScope(
      canPop: photo == null && sheet == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (photo != null) {
          ref.read(_photoOverlayProvider.notifier).close();
        } else if (sheet != null) {
          ref.read(orderSheetProvider.notifier).close();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: switch (menu) {
                AsyncData(value: final weeks) when weeks.isNotEmpty =>
                  _MenuBody(
                    dishesKey: _dishesKey,
                    weeks: weeks,
                    onSignIn: widget.onSignIn,
                    allowedDates: dates.asData?.value,
                    datesError: dates.hasError,
                    scrollController: _scrollController,
                    categoryKeys: _categoryKeys,
                    activeCategoryId: _activeCategoryId,
                    onCategoryTap: _scrollToCategory,
                    onKeepScroll: _keepDishScroll,
                  ),
                AsyncData() => _MenuStatus(
                  message: AppStrings.menuEmptyMessage,
                  onHome: widget.onHome,
                ),
                AsyncError(:final error) => _MenuStatus(
                  message: _errorMessage(error),
                  onHome: widget.onHome,
                  onRetry: () {
                    ref.read(menuControllerProvider.notifier).reload();
                    ref.read(menuAllowedDatesProvider.notifier).reload();
                  },
                ),
                _ => _MenuStatus(
                  message: AppStrings.pleaseWait,
                  isLoading: true,
                  onHome: widget.onHome,
                ),
              },
            ),
            if (photo != null && sheet == null)
              _PhotoOverlay(
                request: photo,
                onClose: () => ref.read(_photoOverlayProvider.notifier).close(),
              ),
            if (compactOrder &&
                sheet != null &&
                menu.asData?.value.isNotEmpty == true)
              OrderSheetLayer(
                kind: sheet,
                weeks: menu.asData!.value,
                onCategory: (categoryId) => _scrollToCategory(categoryId),
              ),
          ],
        ),
      ),
    );
  }

  static String _errorMessage(Object error) {
    if (error is ApiException) {
      return switch (error.kind) {
        ApiErrorKind.network ||
        ApiErrorKind.timeout => AppStrings.menuNetworkError,
        ApiErrorKind.format => AppStrings.menuFormatError,
        _ => AppStrings.menuUnavailable,
      };
    }
    return AppStrings.menuUnavailable;
  }
}

class _MenuBody extends ConsumerWidget {
  const _MenuBody({
    required this.dishesKey,
    required this.weeks,
    required this.allowedDates,
    required this.onSignIn,
    required this.datesError,
    required this.scrollController,
    required this.categoryKeys,
    required this.activeCategoryId,
    required this.onCategoryTap,
    required this.onKeepScroll,
  });

  final GlobalKey dishesKey;
  final List<MenuWeek> weeks;
  final Set<String>? allowedDates;
  final VoidCallback? onSignIn;
  final bool datesError;
  final ScrollController scrollController;
  final Map<String, GlobalKey> categoryKeys;
  final String? activeCategoryId;
  final ValueChanged<String> onCategoryTap;
  final VoidCallback onKeepScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(menuSelectionProvider);
    final day = selectedMenuDay(weeks, selection);
    final categories = day?.categoriesSorted ?? const <MenuCategory>[];
    for (final category in categories) {
      categoryKeys.putIfAbsent(category.categoryId, GlobalKey.new);
    }
    final effectiveActive =
        activeCategoryId ??
        (categories.isEmpty ? null : categories.first.categoryId);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context).width;
        final compactOrder = viewport < 600;
        final categoryColumn = viewport >= orderColumnsMinWidth;
        final activeCategory = categories
            .where((category) => category.categoryId == effectiveActive)
            .firstOrNull;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (datesError)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(AppStrings.menuDatesUnavailable),
              ),
            if (compactOrder)
              _AdaptiveSelectionBar(day: day, category: activeCategory)
            else
              Material(
                key: const ValueKey('menu-week-day-bar'),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WeekTabs(weeks: weeks, selection: selection),
                    if (selection != null)
                      _DayTabs(weeks: weeks, selection: selection),
                    const Divider(height: 1),
                  ],
                ),
              ),
            if (day == null)
              const Expanded(
                child: Center(child: Text(AppStrings.menuNoDeliveryDays)),
              )
            else if (categories.isEmpty)
              const Expanded(
                child: Center(child: Text(AppStrings.menuNoDishesForDay)),
              )
            else
              Expanded(
                child: categoryColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            key: const ValueKey('menu-category-column'),
                            width: orderCategoryWidth(viewport),
                            child: MenuCategoryList(
                              categories: categories,
                              activeCategoryId: effectiveActive,
                              onTap: onCategoryTap,
                              vertical: true,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _DishesScroll(
                              key: dishesKey,
                              day: day,
                              categories: categories,
                              allowedDates: allowedDates,
                              onSignIn: onSignIn,
                              scrollController: scrollController,
                              categoryKeys: categoryKeys,
                              onKeepScroll: onKeepScroll,
                            ),
                          ),
                        ],
                      )
                    : _DishesScroll(
                        key: dishesKey,
                        day: day,
                        categories: categories,
                        allowedDates: allowedDates,
                        onSignIn: onSignIn,
                        scrollController: scrollController,
                        categoryKeys: categoryKeys,
                        onKeepScroll: onKeepScroll,
                      ),
              ),
          ],
        );
        return content;
      },
    );
  }
}

/// В узком окне день и категория выбираются нижней панелью.
/// Сверху остаются только текущие значения.
class _AdaptiveSelectionBar extends StatelessWidget {
  const _AdaptiveSelectionBar({required this.day, required this.category});
  final MenuDay? day;
  final MenuCategory? category;
  @override
  Widget build(BuildContext context) {
    if (category == null) return const SizedBox.shrink();
    return Material(
      key: const ValueKey('menu-adaptive-selection'),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                category!.categoryName,
                key: const ValueKey('menu-selected-category'),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (day != null) ...[
              const SizedBox(width: 12),
              Text(
                formatMenuDayLabel(day!.dateKey),
                key: const ValueKey('menu-selected-day'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String dayChipLabel(MenuDay day) {
  final name = day.dayName;
  final date = formatCalendarDate(day.dateKey, includeYear: false);
  if (name != null && name.isNotEmpty) return '$name ($date)';
  return date;
}

class _WeekTabs extends ConsumerWidget {
  const _WeekTabs({required this.weeks, required this.selection});

  final List<MenuWeek> weeks;
  final MenuSelection? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CenteredChipRow(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      children: [
        for (final week in menuWeeksForDisplay(weeks))
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              selected: selection?.weekType == week.weekType,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Colors.transparent,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () => ref
                    .read(menuSelectionProvider.notifier)
                    .selectWeek(week.weekType, weeks),
                child: Text(
                  week.weekType == 'current'
                      ? AppStrings.menuCurrentWeek
                      : AppStrings.menuNextWeek,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selection?.weekType == week.weekType
                        ? FontWeight.bold
                        : FontWeight.normal,
                    decoration: selection?.weekType == week.weekType
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayTabs extends ConsumerWidget {
  const _DayTabs({required this.weeks, required this.selection});

  final List<MenuWeek> weeks;
  final MenuSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowedDates = ref.watch(menuAllowedDatesProvider).asData?.value;
    final week = menuWeekByType(weeks, selection.weekType);
    if (week == null) return const SizedBox.shrink();
    return _CenteredChipRow(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      children: [
        for (final day in week.deliveryDays)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              selected: selection.dateKey == day.dateKey,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  backgroundColor: Colors.transparent,
                  minimumSize: const Size(0, 48),
                ),
                onPressed: () => ref
                    .read(menuSelectionProvider.notifier)
                    .selectDay(day.dateKey, weeks),
                child: Text(
                  dayChipLabel(day),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: selection.dateKey == day.dateKey
                        ? FontWeight.bold
                        : FontWeight.normal,
                    decoration: selection.dateKey == day.dateKey
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    color:
                        allowedDates != null &&
                            isOrderDateAllowed(allowedDates, day.dateKey)
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Короткая полоса кнопок стоит по центру ширины и прокручивается, если не влезает.
class _CenteredChipRow extends StatelessWidget {
  const _CenteredChipRow({required this.padding, required this.children});

  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: width.isFinite ? width : 0),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}

class MenuCategoryList extends StatelessWidget {
  const MenuCategoryList({
    super.key,
    required this.categories,
    required this.activeCategoryId,
    required this.onTap,
    required this.vertical,
  });

  final List<MenuCategory> categories;
  final String? activeCategoryId;
  final ValueChanged<String> onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      final mobile = MediaQuery.sizeOf(context).width < orderColumnsMinWidth;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: Semantics(
                  selected: activeCategoryId == category.categoryId,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: activeCategoryId == category.categoryId
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      backgroundColor: activeCategoryId == category.categoryId
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Colors.transparent,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => onTap(category.categoryId),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            MenuCategoryThumb(
                              category: category,
                              dimension: mobile ? 64 : 40,
                            ),
                            if (activeCategoryId == category.categoryId)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            category.categoryName,
                            style: TextStyle(
                              fontSize: mobile ? 18 : 14,
                              fontWeight:
                                  activeCategoryId == category.categoryId
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            softWrap: true,
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
    final chips = [
      for (final category in categories)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(category.categoryName),
            selected: activeCategoryId == category.categoryId,
            onSelected: (_) => onTap(category.categoryId),
          ),
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: chips),
    );
  }
}

class _DishesScroll extends ConsumerWidget {
  const _DishesScroll({
    super.key,
    required this.day,
    required this.categories,
    required this.allowedDates,
    required this.onSignIn,
    required this.scrollController,
    required this.categoryKeys,
    required this.onKeepScroll,
  });

  final MenuDay day;
  final List<MenuCategory> categories;
  final Set<String>? allowedDates;
  final VoidCallback? onSignIn;
  final ScrollController scrollController;
  final Map<String, GlobalKey> categoryKeys;
  final VoidCallback onKeepScroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionStatusProvider);
    final signedIn = status == SessionStatus.signedIn;
    final orderAllowed =
        ref.watch(cartDayEditableProvider(day.dateKey)) &&
        signedIn &&
        isOrderDateAllowed(allowedDates, day.dateKey);
    return SingleChildScrollView(
      key: const ValueKey('menu-dishes-scroll'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!signedIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (status == SessionStatus.restoring)
                    const LinearProgressIndicator()
                  else
                    const Text(AppStrings.menuSignInToChoose),
                  if (status != SessionStatus.restoring && onSignIn != null)
                    TextButton(
                      key: const ValueKey('menu-guest-sign-in'),
                      onPressed: onSignIn,
                      child: const Text(AppStrings.signInSubmit),
                    ),
                ],
              ),
            )
          else if (!isOrderDateAllowed(allowedDates, day.dateKey))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: const Text(AppStrings.menuDayClosed),
            ),
          for (final category in categories) ...[
            KeyedSubtree(
              key: categoryKeys[category.categoryId],
              child: _phoneDishGrid(context) && category == categories.first
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Text(
                        category.categoryName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
            ),
            _DishGrid(
              dishes: category.dishesSorted,
              dateKey: day.dateKey,
              orderAllowed: orderAllowed,
              onKeepScroll: onKeepScroll,
            ),
          ],
        ],
      ),
    );
  }
}

const _dishCardMinWidth = 248.0;
const _dishPhoneCardMinWidth = 156.0;

bool _phoneDishGrid(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

int _dishColumnCount(double width, bool phone, double textScale) {
  if (phone && textScale >= 1.3) return 1;
  const gap = 12.0;
  final minWidth = phone
      ? _dishPhoneCardMinWidth
      : _dishCardMinWidth * (textScale >= 1.3 ? textScale : 1);
  final count = ((width + gap) / (minWidth + gap)).floor();
  return phone ? count.clamp(1, 2) : count.clamp(1, 12);
}

String _weightText(MenuDish dish) {
  final weight = dish.servingWeight;
  if (weight == null || weight.isEmpty) return AppStrings.menuWeightUnknown;
  return weight;
}

class _DishGrid extends StatelessWidget {
  const _DishGrid({
    required this.dishes,
    required this.dateKey,
    required this.orderAllowed,
    required this.onKeepScroll,
  });

  final List<MenuDish> dishes;
  final String dateKey;
  final bool orderAllowed;
  final VoidCallback onKeepScroll;

  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = _phoneDishGrid(context);
        final columns = _dishColumnCount(
          constraints.maxWidth,
          phone,
          MediaQuery.textScalerOf(context).scale(16) / 16,
        );
        return Column(
          children: [
            for (var start = 0; start < dishes.length; start += columns) ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: 12),
                      Expanded(
                        child: start + column < dishes.length
                            ? _DishCard(
                                dish: dishes[start + column],
                                dateKey: dateKey,
                                orderAllowed: orderAllowed,
                                onKeepScroll: onKeepScroll,
                                compactQuantity: phone,
                                contentWidth:
                                    (constraints.maxWidth -
                                            12 * (columns - 1)) /
                                        columns -
                                    24,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _DishCard extends ConsumerWidget {
  const _DishCard({
    required this.dish,
    required this.dateKey,
    required this.orderAllowed,
    required this.onKeepScroll,
    required this.compactQuantity,
    required this.contentWidth,
  });

  final MenuDish dish;
  final String dateKey;
  final bool orderAllowed;
  final VoidCallback onKeepScroll;
  final bool compactQuantity;
  final double contentWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final qty = ref.watch(
      cartDraftProvider.select((value) => value[dateKey]?[dish.dishId] ?? 0),
    );
    final theme = Theme.of(context);
    final locked = ref.watch(
      cartSubmitControllerProvider.select((s) => s.editingLocked),
    );
    final editable = ref.watch(cartDayEditableProvider(dateKey));
    final showQuantity =
        orderAllowed && ref.watch(cartDayEditPermissionProvider(dateKey));
    final price = ref.watch(menuDiscountedPriceProvider(dish.price));
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radius,
        side: BorderSide(
          color: qty > 0
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => ref
                .read(_photoOverlayProvider.notifier)
                .open(dish, image: !compactQuantity),
            child: SizedBox(
              key: ValueKey('menu-dish-photo-${dish.dishId}'),
              height: compactQuantity ? 140 : 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: MenuNetworkImage(
                      config: config,
                      imagePath: dish.imagePath,
                      version: dish.imageVersion,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (dish.menuOrder != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _PhotoBadge(
                        key: ValueKey('menu-dish-number-${dish.dishId}'),
                        text: '${dish.menuOrder}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dish.dishName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (!compactQuantity &&
                      dish.composition != null &&
                      dish.composition!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: ValueKey('menu-dish-composition-${dish.dishId}'),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text(
                                AppStrings.menuCompositionTitle,
                              ),
                              content: SingleChildScrollView(
                                child: SelectableText(dish.composition!),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: const Text(AppStrings.close),
                                ),
                              ],
                            ),
                          ),
                          child: const Text(AppStrings.menuShowComposition),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: PriceText(
                          key: ValueKey('menu-dish-price-${dish.dishId}'),
                          original: dish.price,
                          current: price,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${AppStrings.menuWeightLabel}: ${_weightText(dish)}',
                          key: ValueKey('menu-dish-weight-${dish.dishId}'),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (dish.nutrients != null && dish.nutrients!.hasAny) ...[
                    const SizedBox(height: 12),
                    _DishNutrients(
                      dishId: dish.dishId,
                      nutrients: dish.nutrients!,
                      width: contentWidth,
                    ),
                  ],
                  if (showQuantity) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _QuantityControl(
                        key: ValueKey('menu-dish-quantity-${dish.dishId}'),
                        quantity: qty,
                        decreaseEnabled:
                            !locked && editable && orderAllowed && qty > 0,
                        increaseEnabled: !locked && editable && orderAllowed,
                        onDecrease: () {
                          onKeepScroll();
                          ref
                              .read(cartDraftProvider.notifier)
                              .decrement(dateKey, dish.dishId);
                        },
                        onIncrease: () {
                          onKeepScroll();
                          ref
                              .read(cartDraftProvider.notifier)
                              .increment(dateKey, dish.dishId);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoOverlay extends ConsumerWidget {
  const _PhotoOverlay({required this.request, required this.onClose});

  final _PhotoRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final dish = request.dish;
    final composition = dish.composition;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: const ColoredBox(color: Color(0x80000000)),
            ),
          ),
          Center(
            child: request.image
                ? Dialog(
                    key: const ValueKey('menu-dish-image-dialog'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: MenuNetworkImage(
                                config: config,
                                imagePath: dish.imagePath,
                                version: dish.imageVersion,
                                fit: BoxFit.contain,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Text(dish.dishName),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: onClose,
                                child: const Text(AppStrings.close),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : AlertDialog(
                    key: const ValueKey('menu-dish-card-dialog'),
                    scrollable: true,
                    title: Text(dish.dishName),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: MenuNetworkImage(
                              config: config,
                              imagePath: dish.imagePath,
                              version: dish.imageVersion,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${AppStrings.menuWeightLabel}: ${_weightText(dish)}',
                          ),
                          if (composition != null &&
                              composition.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(AppStrings.menuCompositionTitle),
                            const SizedBox(height: 4),
                            SelectableText(composition),
                          ],
                          const SizedBox(height: 8),
                          PriceText(
                            original: dish.price,
                            current: ref.watch(
                              menuDiscountedPriceProvider(dish.price),
                            ),
                          ),
                          if (dish.nutrients != null &&
                              dish.nutrients!.hasAny) ...[
                            const SizedBox(height: 12),
                            _DishNutrients(
                              dishId: dish.dishId,
                              nutrients: dish.nutrients!,
                            ),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: onClose,
                        child: const Text(AppStrings.close),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({required this.text, super.key});
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class _DishNutrients extends StatelessWidget {
  const _DishNutrients({
    required this.dishId,
    required this.nutrients,
    this.width,
  });

  final String dishId;
  final MenuDishNutrients nutrients;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final items = <(String, String)>[
      (AppStrings.menuProteins, formatNutrientGrams(nutrients.proteins)),
      (AppStrings.menuFats, formatNutrientGrams(nutrients.fats)),
      (AppStrings.menuCarbs, formatNutrientGrams(nutrients.carbohydrates)),
      (AppStrings.menuCalories, formatNutrientCalories(nutrients.calories)),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = (width ?? 0) >= 330 * scale ? 4 : 2;
    return Wrap(
      key: ValueKey('menu-dish-nutrients-$dishId'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          SizedBox(
            width: width == null
                ? null
                : (width! - 8 * (columns - 1)) / columns,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${item.$1}: ', style: titleStyle),
                  TextSpan(text: item.$2, style: valueStyle),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.decreaseEnabled,
    required this.increaseEnabled,
    required this.onDecrease,
    required this.onIncrease,
    super.key,
  });

  final int quantity;
  final bool decreaseEnabled;
  final bool increaseEnabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppTheme.radius,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: decreaseEnabled ? onDecrease : null,
            icon: const Icon(Icons.remove),
            tooltip: AppStrings.menuDecreaseQuantity,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              maximumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          IconButton(
            onPressed: increaseEnabled ? onIncrease : null,
            icon: const Icon(Icons.add),
            tooltip: AppStrings.menuIncreaseQuantity,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              maximumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuStatus extends StatelessWidget {
  const _MenuStatus({
    required this.message,
    required this.onHome,
    this.isLoading = false,
    this.onRetry,
  });

  final String message;
  final VoidCallback onHome;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
            ] else ...[
              Icon(
                onRetry != null ? Icons.error_outline : Icons.restaurant_menu,
                color: Theme.of(context).colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 16),
            ],
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (onRetry != null)
              FilledButton(
                onPressed: onRetry,
                child: const Text(AppStrings.retryLoadMenu),
              ),
            TextButton(onPressed: onHome, child: const Text(AppStrings.home)),
          ],
        ),
      ),
    );
  }
}
