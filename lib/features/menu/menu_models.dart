// Модели меню: контракт v0.3 (FL-04-16). Источник полей — FL-00-10 и
// сверка live dishes.json (FL-04-13). Живой JSON — источник имён; единицы
// веса сервером не зафиксированы.

/// Календарный ключ YYYY-MM-DD без смещения часового пояса.
String menuCalendarDateKey(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (match == null) {
    throw const FormatException(
      'date не является календарной датой YYYY-MM-DD.',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final probed = DateTime(year, month, day);
  if (probed.year != year || probed.month != month || probed.day != day) {
    throw const FormatException(
      'date содержит несуществующий календарный день.',
    );
  }
  return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
}

DateTime menuCalendarDate(String dateKey) {
  final key = menuCalendarDateKey(dateKey);
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Одно блюдо категории дня.
final class MenuDish {
  const MenuDish({
    required this.dishId,
    required this.dishName,
    required this.price,
    this.imagePath,
    this.photoVersion,
    this.imageVersion,
    this.servingWeight,
    this.composition,
    this.nutrients,
    this.menuOrder,
  });

  final String dishId;
  final String dishName;
  final num price;

  /// Имя изображения из источника, без построения URL и загрузки файла.
  final String? imagePath;

  /// Необязательный серверный сигнал `photo_version`.
  final String? photoVersion;

  /// Эффективная версия URL после восстановления реестра Repository.
  final String? imageVersion;

  MenuDish withImageVersion(String? version) => MenuDish(
    dishId: dishId,
    dishName: dishName,
    price: price,
    imagePath: imagePath,
    photoVersion: photoVersion,
    imageVersion: version,
    servingWeight: servingWeight,
    composition: composition,
    nutrients: nutrients,
    menuOrder: menuOrder,
  );

  /// Текст `servingweight`, включая составной вес и обозначение штук.
  /// Единицы не дописываются клиентом; значение не участвует в расчётах.
  final String? servingWeight;

  /// Текст `ingredients.textDescription`, если есть.
  final String? composition;

  /// `nutrients`: белки, жиры, углеводы и калории. Нет объекта — не показывать.
  final MenuDishNutrients? nutrients;

  /// Порядок в категории; null — без явного порядка.
  final int? menuOrder;

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
    return MenuDish(
      dishId: dishId,
      dishName: dishName,
      price: price,
      imagePath: _optionalImagePath(json, 'imagePath'),
      photoVersion: _optionalPhotoVersion(json),
      servingWeight: _optionalServingWeight(json),
      composition: _optionalComposition(json),
      nutrients: MenuDishNutrients.fromJson(json),
      menuOrder: _optionalInt(json, 'menuOrder'),
    );
  }
}

/// Категория блюд внутри одного дня меню.
final class MenuCategory {
  MenuCategory({
    required this.categoryId,
    required this.categoryName,
    required List<MenuDish> dishes,
    this.categoryImagePath,
    this.photoVersion,
    this.imageVersion,
    this.categoryOrder,
  }) : dishes = List.unmodifiable(dishes);

  final String categoryId;
  final String categoryName;
  final List<MenuDish> dishes;

  /// JSON-поле `categoryimagePath`, включая регистр букв источника.
  final String? categoryImagePath;

  /// Версия фото категории; правила те же, что у блюда.
  final String? photoVersion;
  final String? imageVersion;

  /// Порядок категории; null — без явного порядка.
  final int? categoryOrder;

  List<MenuDish> get dishesSorted {
    final copy = [...dishes];
    copy.sort((a, b) {
      final ao = a.menuOrder ?? 1 << 30;
      final bo = b.menuOrder ?? 1 << 30;
      return ao.compareTo(bo);
    });
    return List.unmodifiable(copy);
  }

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
      categoryImagePath: _optionalImagePath(json, 'categoryimagePath'),
      photoVersion: _optionalPhotoVersion(json),
      categoryOrder: _optionalInt(json, 'categoryOrder'),
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

/// Один день меню с календарной датой и доступными категориями.
final class MenuDay {
  MenuDay({
    required this.dateKey,
    required this.date,
    required List<MenuCategory> categories,
    this.hasDelivery = true,
    this.dayNumber,
    this.dayName,
  }) : categories = List.unmodifiable(categories);

  /// Календарный ключ YYYY-MM-DD из JSON, без timezone-сдвига.
  final String dateKey;
  final DateTime date;
  final List<MenuCategory> categories;
  final bool hasDelivery;
  final int? dayNumber;
  final String? dayName;

  List<MenuCategory> get categoriesSorted {
    final copy = [...categories];
    copy.sort((a, b) {
      final ao = a.categoryOrder ?? 1 << 30;
      final bo = b.categoryOrder ?? 1 << 30;
      return ao.compareTo(bo);
    });
    return List.unmodifiable(copy);
  }

  static MenuDay fromJson(Map<String, dynamic> json) {
    final dateRaw = json['date'];
    final categoriesJson = json['categories'];
    if (dateRaw is! String || dateRaw.isEmpty) {
      throw const FormatException('date отсутствует или не строка.');
    }
    final dateKey = menuCalendarDateKey(dateRaw);
    if (categoriesJson is! List) {
      throw const FormatException('categories отсутствует или не список.');
    }
    return MenuDay(
      dateKey: dateKey,
      date: menuCalendarDate(dateKey),
      hasDelivery: _hasDeliveryFlag(json),
      dayNumber: _optionalInt(json, 'dayNumber'),
      dayName: _optionalNonEmptyString(json, 'dayName'),
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

/// Неделя меню (`current`/`next` после нормализации, FL-00-10).
final class MenuWeek {
  MenuWeek({
    required this.weekType,
    required List<MenuDay> days,
    this.weekNumber,
  }) : days = List.unmodifiable(days);

  final String weekType;
  final List<MenuDay> days;
  final int? weekNumber;

  List<MenuDay> get deliveryDays => [
    for (final day in days)
      if (day.hasDelivery) day,
  ];

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
      weekNumber: _optionalInt(json, 'weekNumber'),
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

/// Уникальные категории всех дней: первое вхождение каждого id, затем порядок.
List<MenuCategory> uniqueMenuCategories(List<MenuWeek> weeks) {
  final byId = <String, MenuCategory>{};
  for (final week in weeks) {
    for (final day in week.days) {
      for (final category in day.categoriesSorted) {
        byId.putIfAbsent(category.categoryId, () => category);
      }
    }
  }
  final categories = byId.values.toList();
  categories.sort((a, b) {
    final ao = a.categoryOrder ?? 1 << 30;
    final bo = b.categoryOrder ?? 1 << 30;
    final byOrder = ao.compareTo(bo);
    if (byOrder != 0) return byOrder;
    return a.categoryName.compareTo(b.categoryName);
  });
  return categories;
}

/// Блюда и тип недели по календарной дате.
///
/// Один и тот же день может встретиться в двух неделях. Пустой день не
/// затирает день, в котором блюда уже есть: живая следующая неделя повторяет
/// даты текущей без блюд и без `hasDelivery`.
final class MenuDateIndex {
  const MenuDateIndex({
    required this.dishesByDate,
    required this.weekTypeByDate,
  });

  final Map<String, Map<String, MenuDish>> dishesByDate;
  final Map<String, String> weekTypeByDate;
}

MenuDateIndex indexMenuByDate(List<MenuWeek> weeks) {
  final dishesByDate = <String, Map<String, MenuDish>>{};
  final weekTypeByDate = <String, String>{};
  for (final week in weeks) {
    for (final day in week.days) {
      final incoming = <String, MenuDish>{
        for (final category in day.categories)
          for (final dish in category.dishes) dish.dishId: dish,
      };
      final existing = dishesByDate[day.dateKey];
      if (existing != null && existing.isNotEmpty && incoming.isEmpty) {
        continue;
      }
      dishesByDate[day.dateKey] = incoming;
      weekTypeByDate[day.dateKey] = week.weekType;
    }
  }
  return MenuDateIndex(
    dishesByDate: dishesByDate,
    weekTypeByDate: weekTypeByDate,
  );
}

String? _optionalImagePath(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$key не является строкой.');
  }
  return value.isEmpty ? null : value;
}

String? _optionalPhotoVersion(Map<String, dynamic> json) {
  final value = json['photo_version'];
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is int) return value.toString();
  throw const FormatException(
    'photo_version не является строкой или целым числом.',
  );
}

String? _optionalServingWeight(Map<String, dynamic> json) {
  final value = json['servingweight'];
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num) return value.toString();
  throw const FormatException('servingweight не является строкой или числом.');
}

num? _optionalNum(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! num) {
    throw FormatException('$key не является числом.');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = _optionalNum(json, key);
  if (value == null) return null;
  if (value is int) return value;
  if (value == value.roundToDouble()) return value.toInt();
  throw FormatException('$key не является целым числом.');
}

/// Рабочий сайт показывает день только при `hasDelivery: true`.
/// Нет поля или null — неделя ещё без меню, день в полосе не показывается.
bool _hasDeliveryFlag(Map<String, dynamic> json) {
  if (!json.containsKey('hasDelivery') || json['hasDelivery'] == null) {
    return false;
  }
  final value = json['hasDelivery'];
  if (value is! bool) {
    throw const FormatException(
      'hasDelivery не является логическим значением.',
    );
  }
  return value;
}

String? _optionalNonEmptyString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key не является строкой.');
  }
  return value.isEmpty ? null : value;
}

/// Пищевая ценность блюда из `nutrients`. Единицы дописывает только показ.
final class MenuDishNutrients {
  const MenuDishNutrients({
    this.proteins,
    this.fats,
    this.carbohydrates,
    this.calories,
  });

  final num? proteins;
  final num? fats;
  final num? carbohydrates;
  final num? calories;

  bool get hasAny =>
      proteins != null ||
      fats != null ||
      carbohydrates != null ||
      calories != null;

  static MenuDishNutrients? fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('nutrients') || json['nutrients'] == null) {
      return null;
    }
    final value = json['nutrients'];
    if (value is! Map) {
      throw const FormatException('nutrients не является объектом.');
    }
    final map = Map<String, dynamic>.from(value);
    return MenuDishNutrients(
      proteins: _optionalNum(map, 'proteins'),
      fats: _optionalNum(map, 'fats'),
      carbohydrates: _optionalNum(map, 'carbohydrates'),
      calories: _optionalNum(map, 'calories'),
    );
  }
}

String? _optionalComposition(Map<String, dynamic> json) {
  if (!json.containsKey('ingredients') || json['ingredients'] == null) {
    return null;
  }
  final ingredients = json['ingredients'];
  if (ingredients is! Map) {
    throw const FormatException('ingredients не является объектом.');
  }
  final map = Map<String, dynamic>.from(ingredients);
  if (!map.containsKey('textDescription') || map['textDescription'] == null) {
    return null;
  }
  final text = map['textDescription'];
  if (text is! String) {
    throw const FormatException(
      'ingredients.textDescription не является строкой.',
    );
  }
  return text.isEmpty ? null : text;
}
