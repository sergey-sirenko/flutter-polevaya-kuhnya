import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

/// Эталон UI для FL-01-17 (ADR-6). Вызывает только Controller: не строит
/// HTTP-запрос и не разбирает JSON напрямую. Пока не подключён к
/// `app/router.dart` — реальная бизнес-функция меню и её маршрут остаются
/// в этапе 4 дорожной карты вместе с утверждённым контрактом FL-04-04.
class MenuPage extends ConsumerWidget {
  const MenuPage({required this.isTest, required this.onHome, super.key});

  final bool isTest;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(menuControllerProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.menu, key: ValueKey('route-page-title')),
      ),
      body: SafeArea(
        child: switch (menu) {
          AsyncData(value: final weeks) when weeks.isNotEmpty => _MenuWeeksList(
            weeks: weeks,
            isTest: isTest,
          ),
          AsyncData() => _MenuStatus(
            message: AppStrings.menuEmptyMessage,
            isTest: isTest,
            onHome: onHome,
          ),
          AsyncError() => _MenuStatus(
            message: AppStrings.menuUnavailable,
            isTest: isTest,
            onHome: onHome,
            onRetry: () => ref.read(menuControllerProvider.notifier).reload(),
          ),
          _ => _MenuStatus(
            message: AppStrings.pleaseWait,
            isLoading: true,
            isTest: isTest,
            onHome: onHome,
          ),
        },
      ),
    );
  }
}

class _MenuWeeksList extends StatelessWidget {
  const _MenuWeeksList({required this.weeks, required this.isTest});

  final List<MenuWeek> weeks;
  final bool isTest;

  @override
  Widget build(BuildContext context) {
    final days = [for (final week in weeks) ...week.days];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isTest) const Text(AppStrings.testBuild),
        for (final day in days) _MenuDaySection(day: day),
      ],
    );
  }
}

class _MenuDaySection extends StatelessWidget {
  const _MenuDaySection({required this.day});

  final MenuDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isoDate(day.date), style: theme.textTheme.titleMedium),
          for (final category in day.categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                category.categoryName,
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final dish in category.dishes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(dish.dishName),
                trailing: Text('${dish.price.toStringAsFixed(0)} ₽'),
              ),
          ],
        ],
      ),
    );
  }

  static String _isoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _MenuStatus extends StatelessWidget {
  const _MenuStatus({
    required this.message,
    required this.isTest,
    required this.onHome,
    this.isLoading = false,
    this.onRetry,
  });

  final String message;
  final bool isTest;
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
            if (isTest) const Text(AppStrings.testBuild),
            if (isLoading) const CircularProgressIndicator(),
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
