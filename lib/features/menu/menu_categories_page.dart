import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

/// Категории выбранного дня; переходы связывает router, корзина не меняется.
class MenuCategoriesPage extends ConsumerWidget {
  const MenuCategoriesPage({
    required this.onCategory,
    this.onRootBack,
    super.key,
  });

  final ValueChanged<String> onCategory;
  final VoidCallback? onRootBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuControllerProvider);
    final selection = ref.watch(menuSelectionProvider);
    final day = selectedMenuDay(menu.asData?.value ?? const [], selection);
    return PopScope(
      canPop: onRootBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onRootBack?.call();
      },
      child: Scaffold(
        key: const ValueKey('menu-categories-page'),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            day == null ? 'Категории' : formatCalendarDate(day.dateKey),
          ),
        ),
        body: menu.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(AppStrings.ordersMenuError),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(menuControllerProvider.notifier).reload(),
                  child: const Text(AppStrings.ordersRetryMenu),
                ),
              ],
            ),
          ),
          data: (weeks) {
            if (menuSelectionNeedsSync(weeks, selection)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted &&
                    menuSelectionNeedsSync(
                      weeks,
                      ref.read(menuSelectionProvider),
                    )) {
                  ref.read(menuSelectionProvider.notifier).syncWithWeeks(weeks);
                }
              });
            }
            final categories = day?.categoriesSorted ?? const [];
            if (categories.isEmpty) {
              return const Center(child: Text(AppStrings.menuNoDishesForDay));
            }
            return MenuCategoryList(
              categories: categories,
              activeCategoryId: ref.watch(menuActiveCategoryProvider),
              onTap: onCategory,
              vertical: true,
            );
          },
        ),
      ),
    );
  }
}
