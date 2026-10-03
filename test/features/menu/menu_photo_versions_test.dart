import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_normalize.dart';
import 'package:polevaya_kuhnya/features/menu/menu_photo_versions.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppConfig configFor([String host = 'data.example.test']) => AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://$host/data/',
);

Map<String, dynamic> menu({Object? version, String path = 'soup'}) => {
  'weeks': [
    {
      'weekType': 'current',
      'days': [
        {
          'date': '2030-01-02',
          'hasDelivery': false,
          'dayName': 'Среда',
          'dayNumber': 3,
          'categories': [
            {
              'categoryId': 'soups',
              'categoryName': 'Супы',
              'categoryOrder': 2,
              'categoryimagePath': 'category',
              'photo_version': 'cat-1',
              'dishes': [
                <String, dynamic>{
                  'dishId': 'dish-1',
                  'dishName': 'Суп',
                  'price': 190.5,
                  'imagePath': path,
                  'photo_version': ?version,
                  'servingweight': '100/250',
                  'ingredients': {'textDescription': 'овощи'},
                  'menuOrder': 7,
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('photo_version необязательна, строковая или целочисленная', () {
    for (final entry in <Object?, String?>{
      null: null,
      '': null,
      '  ': null,
      ' rev/2 & дата ': 'rev/2 & дата',
      0: '0',
      42: '42',
    }.entries) {
      final dish = parseMenuWeeksRoot(menu(version: entry.key))
          .single
          .days
          .single
          .categories
          .single
          .dishes
          .single;
      expect(dish.photoVersion, entry.value);
    }
    for (final invalid in <Object>[true, 1.5, <Object>[], <String, Object>{}]) {
      expect(
        () => parseMenuWeeksRoot(menu(version: invalid)),
        throwsFormatException,
      );
    }
    final data = menu();
    data['weeks'][0]['days'][0]['categories'][0]['photo_version'] = false;
    expect(() => parseMenuWeeksRoot(data), throwsFormatException);
  });

  test(
    'смена версии меняет URL, перезапуск и отсутствие поля сохраняют последнюю',
    () async {
      final config = configFor();
      var body = menu();
      final requests = <http.Request>[];
      MenuRepository repository() => MenuRepository(
        photoVersions: MenuPhotoVersions(config: config),
        api: ApiClient(
          config: config,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      Future<MenuDish> load(MenuRepository repo) async =>
          (await repo.loadWeeks())
              .single
              .days
              .single
              .categories
              .single
              .dishes
              .single;
      Uri url(MenuDish dish) =>
          menuImageUri(config, dish.imagePath, version: dish.imageVersion)!;
      final repo = repository();
      final legacy = await load(repo);
      expect(legacy.photoVersion, isNull);
      expect(url(legacy).queryParameters['v'], 'legacy');
      expect(url(await load(repository())), url(legacy));

      body = menu(version: 'rev/1 & дата');
      final first = await load(repo);
      expect(first.photoVersion, 'rev/1 & дата');
      expect(url(first).queryParameters['v'], 'photo:rev/1 & дата');
      expect(url(first), isNot(url(legacy)));
      expect(url(await load(repository())), url(first));
      body = menu();
      expect(url(await load(repository())), url(first));
      body = menu(version: 'rev-2');
      final second = await load(repo);
      expect(url(second), isNot(url(first)));
      expect(url(await load(repository())), url(second));
      expect(
        requests.every(
          (r) => r.method == 'GET' && r.url.path.endsWith('/dishes.json'),
        ),
        isTrue,
      );
      expect(
        requests.every((r) => !r.headers.containsKey('authorization')),
        isTrue,
      );
      expect(second.price, 190.5);
      expect(second.servingWeight, '100/250');
      expect(second.composition, 'овощи');
      expect(second.menuOrder, 7);
      final day = (await repo.loadWeeks()).single.days.single;
      expect(day.hasDelivery, isFalse);
      expect(day.dayNumber, 3);
      expect(day.dayName, 'Среда');
      expect(day.categories.single.imageVersion, 'photo:cat-1');
      expect(day.categories.single.categoryOrder, 2);
    },
  );

  test('источники и новые имена не наследуют чужую версию', () async {
    final store = MenuPhotoVersions(config: configFor());
    await store.resolve(parseMenuWeeksRoot(menu(version: 'v1')));
    final other = MenuPhotoVersions(config: configFor('other.example.test'));
    expect((await other.resolve(parseMenuWeeksRoot(menu())))['soup'], 'legacy');
    expect(
      (await store.resolve(
        parseMenuWeeksRoot(menu(path: 'new-soup')),
      ))['new-soup'],
      'legacy',
    );
    expect(
      (await store.resolve(parseMenuWeeksRoot(menu())))['soup'],
      'photo:v1',
    );
  });

  test('явная версия применяется ко всем повторениям имени; конфликт не записывается', () async {
    final store = MenuPhotoVersions(config: configFor());
    final data = menu();
    final dishes =
        data['weeks'][0]['days'][0]['categories'][0]['dishes'] as List;
    dishes.add({
      ...dishes.first as Map<String, dynamic>,
      'photo_version': 'v1',
    });
    expect((await store.resolve(parseMenuWeeksRoot(data)))['soup'], 'photo:v1');
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(store.storageKey);
    dishes.first['photo_version'] = 'v2';
    await expectLater(
      store.resolve(parseMenuWeeksRoot(data)),
      throwsFormatException,
    );
    expect(prefs.getString(store.storageKey), before);
    expect(
      (await store.resolve(parseMenuWeeksRoot(menu())))['soup'],
      'photo:v1',
    );
  });

  test(
    'повреждённый реестр восстанавливается, отсутствие фото не создаёт запись',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = MenuPhotoVersions(config: configFor(), preferences: prefs);
      await prefs.setString(store.storageKey, '{broken');
      expect(
        (await store.resolve(parseMenuWeeksRoot(menu())))['soup'],
        'legacy',
      );
      final decoded = jsonDecode(prefs.getString(store.storageKey)!);
      expect(decoded, {'soup': 'legacy', 'category': 'photo:cat-1'});
      expect(await store.resolve(const []), isEmpty);
      final data = menu(path: '');
      data['weeks'][0]['days'][0]['categories'][0].remove('categoryimagePath');
      expect(await store.resolve(parseMenuWeeksRoot(data)), isEmpty);
      expect(prefs.getString(store.storageKey), jsonEncode(decoded));
    },
  );

  test('параллельные загрузки сохраняют версии разных фото', () async {
    final store = MenuPhotoVersions(config: configFor());
    await Future.wait([
      store.resolve(parseMenuWeeksRoot(menu(path: 'a', version: 'a1'))),
      store.resolve(parseMenuWeeksRoot(menu(path: 'b', version: 'b1'))),
    ]);
    final restored = MenuPhotoVersions(config: configFor());
    expect(
      (await restored.resolve(parseMenuWeeksRoot(menu(path: 'a'))))['a'],
      'photo:a1',
    );
    expect(
      (await restored.resolve(parseMenuWeeksRoot(menu(path: 'b'))))['b'],
      'photo:b1',
    );
  });

  test('Repository переводит конфликт версий в ошибку формата меню', () async {
    final data = menu(version: 'v1');
    final category = data['weeks'][0]['days'][0]['categories'][0];
    category['categoryimagePath'] = 'soup';
    final repo = MenuRepository(
      photoVersions: MenuPhotoVersions(config: configFor()),
      api: ApiClient(
        config: configFor(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
    await expectLater(
      repo.loadWeeks(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.format),
      ),
    );
  });
}
