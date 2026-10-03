import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_photo_versions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final config = AppConfig.parse(
    appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
    environment: 'test',
    apiBaseUrl: 'https://api.example.test/Obmen/',
    dataBaseUrl: 'https://data.example.test/data/',
  );

  Future<String> fixture(String name) =>
      File('test/fixtures/api/$name.json').readAsString();

  MenuRepository repositoryFor(String body, int status) {
    return MenuRepository(
      photoVersions: MenuPhotoVersions(config: config),
      api: ApiClient(
        config: config,
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(body),
            status,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );
  }

  test('непустое опубликованное меню разбирается в модели', () async {
    final repository = repositoryFor(await fixture('menu_with_dishes'), 200);
    final weeks = await repository.loadWeeks();
    expect(weeks, hasLength(1));
    final day = weeks.single.days.single;
    expect(day.categories.single.categoryName, 'Супы');
    expect(day.categories.single.dishes.single.dishName, contains('Суп'));
    expect(day.categories.single.dishes.single.price, 190);
  });

  test('пустой файл меню (FL-00-10) возвращает пустой список', () async {
    final repository = repositoryFor(await fixture('public_menu_empty'), 200);
    expect(await repository.loadWeeks(), isEmpty);
  });

  test('отсутствие weeks в ответе даёт ApiException(format)', () async {
    final repository = repositoryFor('{"other": []}', 200);
    await expectLater(
      repository.loadWeeks(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.format),
      ),
    );
  });

  test('корень не объект даёт ApiException(format)', () async {
    final repository = repositoryFor('[]', 200);
    await expectLater(
      repository.loadWeeks(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.format),
      ),
    );
  });

  test('некорректное блюдо оборачивается в ApiException(format)', () async {
    final repository = repositoryFor(
      jsonEncode({
        'weeks': [
          {
            'weekType': 'current',
            'days': [
              {
                'date': '2030-01-02',
                'categories': [
                  {
                    'categoryId': 'c1',
                    'categoryName': 'Категория',
                    'dishes': [
                      {'dishId': 'd1', 'price': 100},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      }),
      200,
    );
    await expectLater(
      repository.loadWeeks(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.format)
            .having((e) => e.message, 'message', contains('dishName')),
      ),
    );
  });

  test('сетевой отказ транспорта передаётся без изменений', () async {
    final repository = MenuRepository(
      photoVersions: MenuPhotoVersions(config: config),
      api: ApiClient(
        config: config,
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
    );
    await expectLater(
      repository.loadWeeks(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
  });
}
