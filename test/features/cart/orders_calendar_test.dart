import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/features/cart/orders_calendar.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

MenuDay day(String key, {bool delivery = true, bool dishes = true}) => MenuDay(
  dateKey: key,
  date: menuCalendarDate(key),
  hasDelivery: delivery,
  categories: [
    MenuCategory(
      categoryId: 'c',
      categoryName: 'Супы',
      dishes: [
        if (dishes) const MenuDish(dishId: 'd', dishName: 'Суп', price: 100),
      ],
    ),
  ],
);

UserOrderDay order(String date, num sum, {bool empty = false}) =>
    UserOrderDay.fromJson({
      'date': date,
      'weekType': 'next',
      'sum': sum,
      'dishes': [
        if (!empty) {'dish': 'd', 'name': 'Суп', 'quantity': 1, 'sum': sum},
      ],
    });

void main() {
  final weeks = [
    MenuWeek(
      weekType: 'current',
      days: [
        day('2030-01-03'),
        day('2030-01-02'),
        day('2030-01-05', delivery: false),
      ],
    ),
    MenuWeek(weekType: 'next', days: [day('2030-01-07')]),
  ];

  test(
    'все дни доставки, календарное совпадение, серверные итоги и нулевая сумма',
    () {
      final result = buildOrderCalendar(weeks, [
        order('2030-01-02T23:59:00-12:00', 190.5),
        order('2030-01-07', 0),
        order('2020-06-01', 999),
        order('broken', 50),
      ]);
      expect(result[0].days.map((d) => d.menuDay.dateKey), [
        '2030-01-02',
        '2030-01-03',
      ]);
      expect(result[0].days[0].order!.weekType, 'next');
      expect(result[0].days[1].order, isNull);
      expect(result[0].total, 190.5);
      expect(result[1].days.single.order, isNotNull);
      expect(result[1].total, 0);
    },
  );

  test('пустая запись истории не создаёт заказ; реальные даты без блюд сохраняются', () {
    final result = buildOrderCalendar(
      [
        MenuWeek(weekType: 'current', days: [day('2030-01-02', dishes: false)]),
      ],
      [order('2030-01-02', 0, empty: true)],
    );
    expect(result[0].days.single.order, isNull);
    expect(result[1].days, isEmpty);
    expect(result[1].total, 0);
  });

  test('пустой повтор следующей недели не дублирует день и итог', () {
    final result = buildOrderCalendar(
      [
        weeks[0],
        MenuWeek(
          weekType: 'next',
          days: [
            day('2030-01-02', dishes: false),
            day('2030-01-03', delivery: false, dishes: false),
          ],
        ),
      ],
      [order('2030-01-02', 100)],
    );
    expect(result[0].total, 100);
    expect(result[1].days, isEmpty);
    expect(result[1].total, 0);
  });

  test('начальный выбор: меню, сегодня, первый день, пустое меню', () {
    final calendar = buildOrderCalendar(weeks, []);
    expect(
      initialOrderCalendarDate(
        calendar,
        selectedDateKey: '2030-01-07',
        today: DateTime(2030, 1, 3),
      ),
      '2030-01-07',
    );
    expect(
      initialOrderCalendarDate(
        calendar,
        selectedDateKey: 'missing',
        today: DateTime(2030, 1, 3),
      ),
      '2030-01-03',
    );
    expect(
      initialOrderCalendarDate(calendar, today: DateTime(2026, 9, 30)),
      '2030-01-02',
    );
    expect(
      initialOrderCalendarDate(
        buildOrderCalendar([], []),
        today: DateTime(2026, 9, 30),
      ),
      isNull,
    );
  });
}
