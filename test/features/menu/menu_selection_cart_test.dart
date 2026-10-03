import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('cart draft хранит количества по дате и блюду', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final draft = container.read(cartDraftProvider.notifier);
    draft.increment('2030-01-02', 'd1');
    draft.increment('2030-01-02', 'd1');
    draft.increment('2030-01-03', 'd2');
    expect(container.read(cartDraftProvider)['2030-01-02']?['d1'], 2);
    expect(container.read(cartDraftProvider)['2030-01-03']?['d2'], 1);
    draft.decrement('2030-01-02', 'd1');
    expect(container.read(cartDraftProvider)['2030-01-02']?['d1'], 1);
    draft.decrement('2030-01-02', 'd1');
    expect(
      container.read(cartDraftProvider).containsKey('2030-01-02'),
      isFalse,
    );
  });

  test('выбор недели/дня сохраняется и заменяет недоступный день', () async {
    MenuDay day(String dateKey, int monthDay) => MenuDay(
      dateKey: dateKey,
      date: DateTime(2030, 1, monthDay),
      categories: [
        MenuCategory(
          categoryId: 'c',
          categoryName: 'Супы',
          dishes: const [MenuDish(dishId: 'd', dishName: 'Суп', price: 1)],
        ),
      ],
    );
    final weeks = [
      MenuWeek(
        weekType: 'current',
        days: [day('2030-01-02', 2), day('2030-01-03', 3)],
      ),
      MenuWeek(
        weekType: 'next',
        days: [day('2030-01-09', 9)],
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final selection = container.read(menuSelectionProvider.notifier);
    await selection.syncWithWeeks(weeks);
    expect(
      container.read(menuSelectionProvider),
      isA<MenuSelection>()
          .having((s) => s.weekType, 'week', 'current')
          .having((s) => s.dateKey, 'day', '2030-01-02'),
    );

    SharedPreferences.setMockInitialValues({
      'menu.currentWeekType': 'next',
      'menu.currentDateKey': 'missing-day',
    });
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    await container2.read(menuSelectionProvider.notifier).syncWithWeeks(weeks);
    expect(
      container2.read(menuSelectionProvider),
      isA<MenuSelection>()
          .having((s) => s.weekType, 'week', 'next')
          .having((s) => s.dateKey, 'day', '2030-01-09'),
    );
  });

  test('категория открывает день, где она есть, и сохраняет текущий', () async {
    MenuCategory category(String id) => MenuCategory(
      categoryId: id,
      categoryName: id,
      dishes: const [],
    );
    final weeks = [
      MenuWeek(
        weekType: 'current',
        days: [
          MenuDay(
            dateKey: '2030-01-02',
            date: DateTime(2030, 1, 2),
            categories: [category('soup')],
          ),
          MenuDay(
            dateKey: '2030-01-03',
            date: DateTime(2030, 1, 3),
            categories: [category('salad')],
          ),
        ],
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final selection = container.read(menuSelectionProvider.notifier);
    await selection.syncWithWeeks(weeks);
    await selection.showCategory('salad', weeks);
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
    await selection.showCategory('soup', weeks);
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
    await selection.showCategory('soup', weeks);
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
  });

  test('день корзины открывает неделю, где эта дата с блюдами', () async {
    MenuDay day(String dateKey, {required bool dishes}) => MenuDay(
      dateKey: dateKey,
      date: DateTime(2030, 1, int.parse(dateKey.substring(8))),
      categories: [
        MenuCategory(
          categoryId: 'c',
          categoryName: 'Супы',
          dishes: dishes
              ? const [MenuDish(dishId: 'd', dishName: 'Суп', price: 1)]
              : const [],
        ),
      ],
    );
    final weeks = [
      MenuWeek(
        weekType: 'current',
        days: [day('2030-01-02', dishes: true)],
      ),
      MenuWeek(
        weekType: 'next',
        days: [
          day('2030-01-02', dishes: false),
          day('2030-01-09', dishes: true),
        ],
      ),
    ];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final selection = container.read(menuSelectionProvider.notifier);
    await selection.syncWithWeeks(weeks);
    expect(await selection.openDate('2030-01-09', weeks), isTrue);
    expect(container.read(menuSelectionProvider)?.weekType, 'next');
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-09');
    expect(await selection.openDate('2030-01-02', weeks), isTrue);
    expect(container.read(menuSelectionProvider)?.weekType, 'current');
    expect(await selection.openDate('2030-02-01', weeks), isFalse);
  });

  test('первая неделя без блюд не выбирается, обе пустые оставляют текущую', () async {
    MenuWeek week(String type, {required bool dishes}) => MenuWeek(
      weekType: type,
      days: [
        MenuDay(
          dateKey: type == 'current' ? '2030-01-02' : '2030-01-09',
          date: DateTime(2030, 1, type == 'current' ? 2 : 9),
          categories: [
            MenuCategory(
              categoryId: 'c',
              categoryName: 'Супы',
              dishes: dishes
                  ? const [MenuDish(dishId: 'd', dishName: 'Суп', price: 1)]
                  : const [],
            ),
          ],
        ),
      ],
    );
    final onlyNext = [week('current', dishes: false), week('next', dishes: true)];
    expect(menuWeeksForDisplay(onlyNext).map((item) => item.weekType), ['next']);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(menuSelectionProvider.notifier).syncWithWeeks(onlyNext);
    expect(container.read(menuSelectionProvider)?.weekType, 'next');

    final none = [week('current', dishes: false), week('next', dishes: false)];
    expect(menuWeeksForDisplay(none).map((item) => item.weekType), ['current']);
    SharedPreferences.setMockInitialValues({
      'menu.currentWeekType': 'next',
      'menu.currentDateKey': '2030-01-09',
    });
    final savedEmpty = ProviderContainer();
    addTearDown(savedEmpty.dispose);
    await savedEmpty.read(menuSelectionProvider.notifier).syncWithWeeks(none);
    expect(savedEmpty.read(menuSelectionProvider)?.weekType, 'current');
  });

  test('текущая неделя без доставки уступает следующей с блюдами', () async {
    MenuDay day(
      String dateKey, {
      required bool delivery,
      required bool dishes,
    }) => MenuDay(
      dateKey: dateKey,
      date: DateTime.parse(dateKey),
      hasDelivery: delivery,
      categories: [
        MenuCategory(
          categoryId: 'c',
          categoryName: 'Супы',
          dishes: dishes
              ? const [MenuDish(dishId: 'd', dishName: 'Суп', price: 1)]
              : const [],
        ),
      ],
    );
    final weeks = [
      MenuWeek(
        weekType: 'current',
        days: [day('2030-01-02', delivery: false, dishes: true)],
      ),
      MenuWeek(
        weekType: 'next',
        days: [day('2030-01-09', delivery: true, dishes: true)],
      ),
    ];
    expect(menuSelectionNeedsSync(weeks, null), isTrue);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(menuSelectionProvider.notifier).syncWithWeeks(weeks);
    expect(container.read(menuSelectionProvider)?.weekType, 'next');
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-09');
  });
}
