import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

void main() {
  Map<String, dynamic> validWeek() => {
    'weekType': 'current',
    'days': [
      {
        'date': '2030-01-02',
        'categories': [
          {
            'categoryId': 'fixture-category-soups',
            'categoryName': 'Супы',
            'dishes': [
              {
                'dishId': 'FIXTURE-DISH-0001',
                'dishName': 'Суп овощной (фикстура)',
                'price': 190,
              },
            ],
          },
        ],
      },
    ],
  };

  test('разбирает неделю, день, категорию и блюдо из подтверждённых полей', () {
    final week = MenuWeek.fromJson(validWeek());
    expect(week.weekType, 'current');
    expect(week.days, hasLength(1));
    final day = week.days.single;
    expect(day.date, DateTime.parse('2030-01-02'));
    expect(day.categories, hasLength(1));
    final category = day.categories.single;
    expect(category.categoryId, 'fixture-category-soups');
    expect(category.categoryName, 'Супы');
    expect(category.dishes, hasLength(1));
    final dish = category.dishes.single;
    expect(dish.dishId, 'FIXTURE-DISH-0001');
    expect(dish.dishName, 'Суп овощной (фикстура)');
    expect(dish.price, 190);
  });

  test('день без категорий парсится с пустым списком', () {
    final json = validWeek();
    (json['days'] as List)[0]['categories'] = <Object?>[];
    final week = MenuWeek.fromJson(json);
    expect(week.days.single.categories, isEmpty);
  });

  for (final field in ['weekType', 'days']) {
    test('неделя без $field отклоняется', () {
      final json = validWeek()..remove(field);
      expect(() => MenuWeek.fromJson(json), throwsFormatException);
    });
  }

  test('days не список отклоняется', () {
    final json = validWeek();
    json['days'] = 'не список';
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
  });

  test('элемент days не объект отклоняется', () {
    final json = validWeek();
    json['days'] = ['не объект'];
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
  });

  test('date не ISO-8601 отклоняется', () {
    final json = validWeek();
    (json['days'] as List)[0]['date'] = 'вчера';
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
  });

  for (final field in ['categoryId', 'categoryName', 'dishes']) {
    test('категория без $field отклоняется', () {
      final json = validWeek();
      ((json['days'] as List)[0]['categories'] as List)[0].remove(field);
      expect(() => MenuWeek.fromJson(json), throwsFormatException);
    });
  }

  for (final field in ['dishId', 'dishName', 'price']) {
    test('блюдо без $field отклоняется', () {
      final json = validWeek();
      ((((json['days'] as List)[0]['categories'] as List)[0]['dishes']
                  as List)[0]
              as Map<String, dynamic>)
          .remove(field);
      expect(() => MenuWeek.fromJson(json), throwsFormatException);
    });
  }

  test('price не число отклоняется', () {
    final json = validWeek();
    ((((json['days'] as List)[0]['categories'] as List)[0]['dishes'] as List)[0]
            as Map<String, dynamic>)['price'] =
        'бесплатно';
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
  });
}
