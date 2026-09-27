// Эталон Model для FL-01-17 (ADR-6). Поля соответствуют подтверждённой
// части черновой карты FL-00-10 (`weeks/days/categories/dishes`, dishId,
// dishName, price). Модель не расширяется предположениями о полях, чьё
// значение или обязательность не подтверждены (например, состав/вес);
// такие поля добавит бизнес-задача меню в этапе 4 вместе с её контрактом.

/// Одно блюдо категории дня.
final class MenuDish {
  const MenuDish({
    required this.dishId,
    required this.dishName,
    required this.price,
  });

  final String dishId;
  final String dishName;
  final num price;

  static MenuDish fromJson(Map<String, dynamic> json) {
    final dishId = json['dishId'];
    final dishName = json['dishName'];
    final price = json['price'];
    if (dishId is! String || dishId.isEmpty) {
      throw const FormatException('dishId отсутствует или не строка.');
    }
    if (dishName is! String || dishName.isEmpty) {
      throw const FormatException('dishName отсутствует или не строка.');
    }
    if (price is! num) {
      throw const FormatException('price отсутствует или не число.');
    }
    return MenuDish(dishId: dishId, dishName: dishName, price: price);
  }
}

/// Категория блюд внутри одного дня меню.
final class MenuCategory {
  const MenuCategory({
    required this.categoryId,
    required this.categoryName,
    required this.dishes,
  });

  final String categoryId;
  final String categoryName;
  final List<MenuDish> dishes;

  static MenuCategory fromJson(Map<String, dynamic> json) {
    final categoryId = json['categoryId'];
    final categoryName = json['categoryName'];
    final dishesJson = json['dishes'];
    if (categoryId is! String || categoryId.isEmpty) {
      throw const FormatException('categoryId отсутствует или не строка.');
    }
    if (categoryName is! String || categoryName.isEmpty) {
      throw const FormatException('categoryName отсутствует или не строка.');
    }
    if (dishesJson is! List) {
      throw const FormatException('dishes отсутствует или не список.');
    }
    return MenuCategory(
      categoryId: categoryId,
      categoryName: categoryName,
      dishes: [
        for (final item in dishesJson)
          MenuDish.fromJson(
            item is Map<String, dynamic>
                ? item
                : throw const FormatException(
                    'Элемент dishes не является объектом.',
                  ),
          ),
      ],
    );
  }
}

/// Один день меню с датой и доступными категориями.
final class MenuDay {
  const MenuDay({required this.date, required this.categories});

  final DateTime date;
  final List<MenuCategory> categories;

  static MenuDay fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final categoriesJson = json['categories'];
    if (date is! String || date.isEmpty) {
      throw const FormatException('date отсутствует или не строка.');
    }
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) {
      throw const FormatException('date не является датой ISO-8601.');
    }
    if (categoriesJson is! List) {
      throw const FormatException('categories отсутствует или не список.');
    }
    return MenuDay(
      date: parsedDate,
      categories: [
        for (final item in categoriesJson)
          MenuCategory.fromJson(
            item is Map<String, dynamic>
                ? item
                : throw const FormatException(
                    'Элемент categories не является объектом.',
                  ),
          ),
      ],
    );
  }
}

/// Неделя меню (`current`/`next` по нормализации сайта, FL-00-10).
final class MenuWeek {
  const MenuWeek({required this.weekType, required this.days});

  final String weekType;
  final List<MenuDay> days;

  static MenuWeek fromJson(Map<String, dynamic> json) {
    final weekType = json['weekType'];
    final daysJson = json['days'];
    if (weekType is! String || weekType.isEmpty) {
      throw const FormatException('weekType отсутствует или не строка.');
    }
    if (daysJson is! List) {
      throw const FormatException('days отсутствует или не список.');
    }
    return MenuWeek(
      weekType: weekType,
      days: [
        for (final item in daysJson)
          MenuDay.fromJson(
            item is Map<String, dynamic>
                ? item
                : throw const FormatException(
                    'Элемент days не является объектом.',
                  ),
          ),
      ],
    );
  }
}
