import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/compatible_version.dart';

void main() {
  testWidgets(
    'главная листает фото/название/цену по кругу, resize и смена дня без записи API',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1080);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final requests = <http.Request>[];
      final menu = {
        'weeks': [
          {
            'weekType': 'current',
            'days': [
              for (final (date, name, price, path) in [
                ('2030-01-02', 'Говядина с кус-кусом', 190, 'beef'),
                ('2030-01-03', 'Запеканка «Болоньезе»', 290, 'bake'),
              ])
                {
                  'date': date,
                  'hasDelivery': true,
                  'categories': [
                    {
                      'categoryId': 'main',
                      'categoryName': 'Вторые блюда',
                      'dishes': [
                        {
                          'dishId': path,
                          'dishName': name,
                          'price': price,
                          'imagePath': path,
                          'photo_version': '7',
                        },
                        if (path == 'beef') ...[
                          {
                            'dishId': 'soup',
                            'dishName': 'Суп с овощами',
                            'price': 110,
                            'imagePath': 'soup',
                            'photo_version': '8',
                          },
                          {
                            'dishId': 'salad',
                            'dishName': 'Салат из свежих овощей',
                            'price': 95,
                            'imagePath': 'salad',
                            'photo_version': '9',
                          },
                          {
                            'dishId': 'no-photo',
                            'dishName': 'Блюдо без фото',
                            'price': 50,
                          },
                        ],
                      ],
                    },
                  ],
                },
            ],
          },
        ],
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionControllerProvider.overrideWith(
              CompatibleVersionController.new,
            ),
            sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
            initialLocationProvider.overrideWithValue('/'),
            appConfigProvider.overrideWithValue(
              AppConfig.parse(
                environment: 'test',
                apiBaseUrl: 'https://example.invalid/api/',
                dataBaseUrl: 'https://example.invalid/data/',
                appVersionUrl: 'https://example.invalid/version.json',
              ),
            ),
            httpClientProvider.overrideWithValue(
              MockClient((request) async {
                requests.add(request);
                return http.Response.bytes(
                  utf8.encode(jsonEncode(menu)),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }),
            ),
          ],
          child: const FieldKitchenApp(),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FieldKitchenApp)),
      );
      final hero = find.byKey(const ValueKey('site-hero-photo'));
      expect(
        find.descendant(of: hero, matching: find.text('Говядина с кус-кусом')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('190 ₽')),
        findsOneWidget,
      );
      var image = tester.widget<MenuNetworkImage>(
        find.descendant(of: hero, matching: find.byType(MenuNetworkImage)),
      );
      expect(image.imagePath, 'beef');
      expect(image.fit, BoxFit.contain);
      final previous = find.byKey(const ValueKey('site-hero-previous'));
      final next = find.byKey(const ValueKey('site-hero-next'));
      final requestCount = requests.length;
      final selectionBefore = container.read(menuSelectionProvider);
      final draftBefore = container.read(cartDraftProvider);
      Future<void> checkDish(String name, String price, String path) async {
        expect(
          find.descendant(of: hero, matching: find.text(name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: hero, matching: find.text(price)),
          findsOneWidget,
        );
        final image = tester.widget<MenuNetworkImage>(
          find.descendant(of: hero, matching: find.byType(MenuNetworkImage)),
        );
        expect(image.imagePath, path);
        expect(image.fit, BoxFit.contain);
      }

      // Назад с первого — последний; вперёд с последнего — первый.
      await tester.tap(previous);
      await tester.pumpAndSettle();
      await checkDish('Салат из свежих овощей', '95 ₽', 'salad');
      await tester.tap(next);
      await tester.pumpAndSettle();
      await checkDish('Говядина с кус-кусом', '190 ₽', 'beef');
      await tester.tap(next);
      await tester.pumpAndSettle();
      await checkDish('Суп с овощами', '110 ₽', 'soup');
      tester.view.physicalSize = const Size(390, 1080);
      await tester.pumpAndSettle();
      await checkDish('Суп с овощами', '110 ₽', 'soup');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      await checkDish('Салат из свежих овощей', '95 ₽', 'salad');
      await tester.tap(next);
      await tester.pumpAndSettle();
      await checkDish('Говядина с кус-кусом', '190 ₽', 'beef');
      expect(requests.length, requestCount);
      expect(container.read(menuSelectionProvider), selectionBefore);
      expect(container.read(cartDraftProvider), draftBefore);
      tester.view.physicalSize = const Size(1440, 1080);
      await tester.pumpAndSettle();
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      await checkDish('Суп с овощами', '110 ₽', 'soup');
      final weeks = container.read(menuControllerProvider).requireValue;
      await container
          .read(menuSelectionProvider.notifier)
          .openDate('2030-01-03', weeks);
      await tester.pumpAndSettle();
      image = tester.widget<MenuNetworkImage>(
        find.descendant(of: hero, matching: find.byType(MenuNetworkImage)),
      );
      expect(image.imagePath, 'bake');
      expect(
        find.descendant(of: hero, matching: find.text('290 ₽')),
        findsOneWidget,
      );
      expect(find.text('190 ₽'), findsNothing);
      expect(previous, findsNothing);
      expect(next, findsNothing);
      await container
          .read(menuSelectionProvider.notifier)
          .openDate('2030-01-02', weeks);
      await tester.pumpAndSettle();
      await checkDish('Говядина с кус-кусом', '190 ₽', 'beef');
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
