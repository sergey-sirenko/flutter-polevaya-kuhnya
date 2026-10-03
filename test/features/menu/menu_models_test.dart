import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/features/menu/menu_dates.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_normalize.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('коллекции меню сохраняют снимок независимо от исходных списков', () {
    const dish = MenuDish(
      dishId: 'fixture',
      dishName: 'Блюдо',
      price: 190.5,
      imagePath: 'fixture-image',
      servingWeight: '250',
      composition: 'овощи',
      menuOrder: 1,
    );
    final dishes = [dish];
    final category = MenuCategory(
      categoryId: 'category',
      categoryName: 'Категория',
      dishes: dishes,
      categoryImagePath: 'fixture-category',
      categoryOrder: 2,
    );
    final categories = [category];
    final day = MenuDay(
      dateKey: '2030-01-02',
      date: DateTime(2030, 1, 2),
      categories: categories,
    );
    final days = [day];
    final week = MenuWeek(weekType: 'current', days: days);

    dishes.clear();
    categories.clear();
    days.clear();
    expect(week.days.single.categories.single.dishes.single, same(dish));
    expect(() => week.days.clear(), throwsUnsupportedError);
    expect(() => day.categories.clear(), throwsUnsupportedError);
    expect(() => category.dishes.clear(), throwsUnsupportedError);
    expect(dish.price, 190.5);
    expect(dish.imagePath, 'fixture-image');
    expect(dish.servingWeight, '250');
    expect(dish.composition, 'овощи');
    expect(category.categoryImagePath, 'fixture-category');
  });

  Map<String, dynamic> validWeek() => {
    'weekType': 'current',
    'days': [
      {
        'date': '2030-01-02',
        'categories': [
          <String, dynamic>{
            'categoryId': 'fixture-category-soups',
            'categoryName': 'Супы',
            'dishes': [
              <String, dynamic>{
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
    expect(day.dateKey, '2030-01-02');
    expect(day.hasDelivery, isFalse);
    expect(day.date, DateTime(2030, 1, 2));
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

  test('явный null hasDelivery не делает день днём доставки', () {
    final json = validWeek();
    final day = Map<String, dynamic>.from(
      (json['days'] as List).first as Map,
    );
    day['hasDelivery'] = null;
    json['days'] = [day];
    final week = MenuWeek.fromJson(json);
    expect(week.days.single.hasDelivery, isFalse);
    expect(week.deliveryDays, isEmpty);
  });

  test('календарный ключ не смещается от ISO с временем', () {
    expect(menuCalendarDateKey('2030-01-02T00:00:00'), '2030-01-02');
    expect(menuCalendarDateKey('2030-01-02T23:00:00+14:00'), '2030-01-02');
    expect(() => menuCalendarDateKey('вчера'), throwsFormatException);
  });

  test('необязательные вес и состав разбираются; повреждённые отклоняются', () {
    final json = validWeek();
    final dishJson =
        ((((json['days'] as List)[0]['categories'] as List)[0]['dishes']
                as List)[0]
            as Map<String, dynamic>);
    dishJson['servingweight'] = 250;
    dishJson['ingredients'] = {'textDescription': 'морковь, капуста'};
    final dish = MenuWeek.fromJson(json)
        .days
        .single
        .categories
        .single
        .dishes
        .single;
    expect(dish.servingWeight, '250');
    expect(dish.composition, 'морковь, капуста');

    dishJson['servingweight'] = {'invalid': 250};
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
    dishJson['servingweight'] = 250;
    dishJson['ingredients'] = 'строка';
    expect(() => MenuWeek.fromJson(json), throwsFormatException);
  });

  test('пищевая ценность необязательна и отклоняет чужой тип', () {
    final json = validWeek();
    final dishJson =
        ((((json['days'] as List)[0]['categories'] as List)[0]['dishes']
                as List)[0]
            as Map<String, dynamic>);
    MenuDish dish() => MenuWeek.fromJson(json)
        .days
        .single
        .categories
        .single
        .dishes
        .single;

    expect(dish().nutrients, isNull);

    dishJson['nutrients'] = null;
    expect(dish().nutrients, isNull);

    dishJson['nutrients'] = {
      'proteins': 22,
      'fats': 20.5,
      'carbohydrates': 43,
      'calories': 436,
    };
    final nutrients = dish().nutrients!;
    expect(nutrients.proteins, 22);
    expect(nutrients.fats, 20.5);
    expect(nutrients.carbohydrates, 43);
    expect(nutrients.calories, 436);
    expect(nutrients.hasAny, isTrue);

    dishJson['nutrients'] = 'строка';
    expect(() => dish(), throwsFormatException);
    dishJson['nutrients'] = {'proteins': 'много'};
    expect(() => dish(), throwsFormatException);
  });

  test('рабочие строки веса не блокируют меню и сохраняются для показа', () {
    for (final entry in <Object?, String?>{
      '90': '90',
      '100/50/150': '100/50/150',
      '2 шт./150': '2 шт./150',
      ' 3шт/120/50 ': '3шт/120/50',
      '': null,
      '  ': null,
      null: null,
      250: '250',
      190.5: '190.5',
    }.entries) {
      final data = validWeek();
      final dishJson = data['days'][0]['categories'][0]['dishes'][0];
      dishJson['servingweight'] = entry.key;
      dishJson['imagePath'] = 'fixture-image';
      final weeks = parseMenuWeeksRoot({
        'weeks': [data],
      });
      final dish = weeks.single.days.single.categories.single.dishes.single;
      expect(dish.servingWeight, entry.value, reason: '${entry.key}');
      expect(dish.imagePath, 'fixture-image');
      expect(dish.price, 190);
    }
  });

  test('вес в виде bool, списка или объекта отклоняется', () {
    for (final value in <Object>[
      false,
      [90],
      {'value': 90},
    ]) {
      final data = validWeek();
      data['days'][0]['categories'][0]['dishes'][0]['servingweight'] = value;
      expect(
        () => parseMenuWeeksRoot({
          'weeks': [data],
        }),
        throwsFormatException,
      );
    }
  });

  test('пустой weeks — валидное пустое меню; отсутствие weeks — ошибка', () {
    expect(parseMenuWeeksRoot({'weeks': []}), isEmpty);
    expect(
      () => parseMenuWeeksRoot({'other': []}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('weeks'),
        ),
      ),
    );
  });

  test('нормализация оставляет две ранние недели как current/next', () {
    final weeks = parseMenuWeeksRoot({
      'weeks': [
        {
          'weekType': 'raw-b',
          'days': [
            {'date': '2030-01-10', 'categories': <Object>[]},
          ],
        },
        {
          'weekType': 'raw-a',
          'days': [
            {'date': '2030-01-02', 'categories': <Object>[]},
          ],
        },
        {
          'weekType': 'raw-c',
          'days': [
            {'date': '2030-01-20', 'categories': <Object>[]},
          ],
        },
      ],
    });
    expect(weeks.map((w) => w.weekType), ['current', 'next']);
    expect(weeks.first.days.single.dateKey, '2030-01-02');
    expect(weeks.last.days.single.dateKey, '2030-01-10');
  });

  test('menudates разбираются в календарные ключи', () {
    final keys = parseMenuDateKeys([
      '2030-01-02T00:00:00',
      '2030-01-03T00:00:00',
    ]);
    expect(keys, {'2030-01-02', '2030-01-03'});
    expect(isOrderDateAllowed(keys, '2030-01-02'), isTrue);
    expect(isOrderDateAllowed(keys, '2030-01-09'), isFalse);
    expect(isOrderDateAllowed(const {}, '2030-01-09'), isTrue);
    expect(isOrderDateAllowed(null, '2030-01-09'), isTrue);
  });

  test('день без категорий парсится с пустым списком', () {
    final json = validWeek();
    (json['days'] as List)[0]['categories'] = <Object?>[];
    final week = MenuWeek.fromJson(json);
    expect(week.days.single.categories, isEmpty);
  });

  test('JSON сохраняет ссылки изображений без преобразования в URL', () {
    final json = validWeek();
    final categoryJson = json['days'][0]['categories'][0];
    categoryJson['categoryimagePath'] = 'fixture-category';
    categoryJson['dishes'][0]['imagePath'] = 'fixture-dish';
    final week = MenuWeek.fromJson(json);
    final category = week.days.single.categories.single;
    expect(category.categoryImagePath, 'fixture-category');
    expect(category.dishes.single.imagePath, 'fixture-dish');
    categoryJson['dishes'].clear();
    expect(category.dishes, hasLength(1));
    expect(() => category.dishes.clear(), throwsUnsupportedError);
    expect(() => week.days.clear(), throwsUnsupportedError);
    expect(() => week.days.single.categories.clear(), throwsUnsupportedError);
  });

  for (final image in <Object?>[null, '', 42, <String>[]]) {
    test('необязательные изображения: ${image.runtimeType} "$image"', () {
      final json = validWeek();
      final categoryJson = json['days'][0]['categories'][0];
      categoryJson['categoryimagePath'] = image;
      categoryJson['dishes'][0]['imagePath'] = image;
      if (image == null || image == '') {
        final category = MenuWeek.fromJson(json).days.single.categories.single;
        expect(category.categoryImagePath, isNull);
        expect(category.dishes.single.imagePath, isNull);
      } else {
        expect(() => MenuWeek.fromJson(json), throwsFormatException);
        categoryJson.remove('categoryimagePath');
        expect(() => MenuWeek.fromJson(json), throwsFormatException);
      }
    });
  }

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

  test('уникальные категории сохраняют первое вхождение и порядок', () {
    MenuCategory category(String id, String name, int order, {String? image}) {
      return MenuCategory(
        categoryId: id,
        categoryName: name,
        dishes: const [],
        categoryOrder: order,
        categoryImagePath: image,
      );
    }

    final weeks = [
      MenuWeek(
        weekType: 'current',
        days: [
          MenuDay(
            dateKey: '2030-01-02',
            date: DateTime(2030, 1, 2),
            categories: [
              category('second', 'Вторые', 2),
              category('soup', 'Супы', 1, image: 'soup'),
            ],
          ),
          MenuDay(
            dateKey: '2030-01-03',
            date: DateTime(2030, 1, 3),
            categories: [category('soup', 'Супы позже', 9, image: 'other')],
          ),
        ],
      ),
    ];

    final unique = uniqueMenuCategories(weeks);
    expect(unique.map((item) => item.categoryId).toList(), ['soup', 'second']);
    expect(unique.first.categoryName, 'Супы');
    expect(unique.first.categoryImagePath, 'soup');
  });
}
