import '../../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  const api = 'https://hleb-sol.su/Zakaz_http/hs/Obmen/';
  const data = 'https://flutter-test.obedmoscow.ru/data/';

  for (final environment in <String>['test', 'prod']) {
    testWidgets('главная site открывается в $environment', (tester) async {
      final config = AppConfig.parse(
        appVersionUrl: environment == 'prod'
            ? 'https://new.obedmoscow.ru/version.json'
            : 'https://flutter-test.obedmoscow.ru/version.json',
        environment: environment,
        apiBaseUrl: api,
        dataBaseUrl: data,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionControllerProvider.overrideWith(
              CompatibleVersionController.new,
            ),
            sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
            appConfigProvider.overrideWithValue(config),
            httpClientProvider.overrideWithValue(
              MockClient(
                (request) async => http.Response.bytes(
                  utf8.encode('{"weeks":[]}'),
                  200,
                  headers: const {
                    'content-type': 'application/json; charset=utf-8',
                  },
                ),
              ),
            ),
            initialLocationProvider.overrideWithValue('/about'),
          ],
          child: const FieldKitchenApp(),
        ),
      );
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(FieldKitchenApp)))
          .read(routerProvider)
          .go('/');
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text('Полевая\nкухня'), findsOneWidget);
      expect(find.text(AppStrings.testBuild), findsNothing);
      expect(find.text(AppStrings.install), findsNothing);
      final theme = Theme.of(tester.element(find.text('Полевая\nкухня')));
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppTheme.link);
      expect(theme.scaffoldBackgroundColor, AppTheme.background);
      expect(theme.textTheme.titleLarge?.fontFamily, 'Arial');
    });
  }

  testWidgets('категория главной открывает меню на этой категории', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dishes = jsonEncode({
      'weeks': [
        {
          'weekType': 'current',
          'days': [
            {
              'date': '2030-01-02',
              'hasDelivery': true,
              'categories': [
                {
                  'categoryId': 'soups',
                  'categoryName': 'Супы',
                  'categoryOrder': 1,
                  'dishes': [
                    for (var i = 0; i < 12; i++)
                      {
                        'dishId': 'soup-$i',
                        'dishName': 'Суп $i',
                        'menuOrder': i + 1,
                        'price': 100,
                      },
                  ],
                },
                {
                  'categoryId': 'salads',
                  'categoryName': 'Салаты',
                  'categoryOrder': 2,
                  'dishes': [
                    {
                      'dishId': 'salad-1',
                      'dishName': 'Салат овощной',
                      'menuOrder': 1,
                      'price': 120,
                    },
                  ],
                },
                {
                  'categoryId': 'bakery',
                  'categoryName': 'Выпечка',
                  'categoryOrder': 3,
                  'dishes': [
                    for (var i = 0; i < 8; i++)
                      {
                        'dishId': 'bake-$i',
                        'dishName': 'Выпечка $i',
                        'menuOrder': i + 1,
                        'price': 80,
                      },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionControllerProvider.overrideWith(
            CompatibleVersionController.new,
          ),
          sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
          appConfigProvider.overrideWithValue(
            AppConfig.parse(
              environment: 'test',
              apiBaseUrl: api,
              dataBaseUrl: data,
              appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
            ),
          ),
          httpClientProvider.overrideWithValue(
            MockClient((request) async {
              if (request.url.path.endsWith('/dishes.json')) {
                return http.Response.bytes(
                  utf8.encode(dishes),
                  200,
                  headers: const {
                    'content-type': 'application/json; charset=utf-8',
                  },
                );
              }
              return http.Response('missing', 404);
            }),
          ),
          initialLocationProvider.overrideWithValue('/about'),
        ],
        child: const FieldKitchenApp(),
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(FieldKitchenApp)))
        .read(routerProvider)
        .go('/');
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('site-category-salads'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FieldKitchenApp)),
    );
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/menu',
    );
    expect(container.read(menuActiveCategoryProvider), 'salads');
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
    final scroll = find.byKey(const ValueKey('menu-dishes-scroll'));
    final salad = find.descendant(of: scroll, matching: find.text('Салаты'));
    expect(salad, findsOneWidget);
    expect(tester.getRect(salad).top, closeTo(tester.getRect(scroll).top, 24));
    expect(tester.takeException(), isNull);
  });
}
