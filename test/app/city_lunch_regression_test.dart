import '../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/adaptive_app_shell.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _routes = <String>[
  AppRoutes.home,
  AppRoutes.about,
  AppRoutes.delivery,
  AppRoutes.howToOrder,
  AppRoutes.contacts,
  AppRoutes.offer,
  AppRoutes.privacy,
  AppRoutes.menu,
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.resetPassword,
];

const _menu = '''
{"weeks":[{"weekType":"current","days":[{"date":"2030-01-02","hasDelivery":true,"categories":[{"categoryId":"c1","categoryName":"Супы с очень длинным названием для переноса","categoryOrder":1,"dishes":[{"dishId":"d1","dishName":"Суп с очень длинным названием для проверки карточки","menuOrder":1,"price":190,"weight":"250 г"}]}]}]}]}
''';

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required Size size,
  double scale = 1,
  String initialLocation = AppRoutes.home,
  SessionStatus status = SessionStatus.signedOut,
  String dishesBody = '{"weeks":[]}',
  bool preparedDay = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (preparedDay)
          cartDayEditPermissionProvider.overrideWith((ref, dateKey) => true),
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        appConfigProvider.overrideWithValue(
          AppConfig.parse(
            appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
            environment: 'test',
            apiBaseUrl: 'https://example.invalid/api/',
            dataBaseUrl: 'https://example.invalid/data/',
          ),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.url.path.endsWith('/dishes.json')) {
              return http.Response.bytes(
                utf8.encode(dishesBody),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            return http.Response('missing', 404);
          }),
        ),
        initialLocationProvider.overrideWithValue(initialLocation),
        sessionStatusProvider.overrideWithValue(status),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(FieldKitchenApp)),
  );
}

void main() {
  for (final width in <double>[
    320,
    390,
    599,
    600,
    768,
    769,
    1024,
    1199,
    1200,
    1440,
  ]) {
    testWidgets('этап 10: $width и текст 1.6 без переполнения маршрутов', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        size: Size(width, 844),
        scale: 1.6,
      );
      final router = container.read(routerProvider);
      for (final route in _routes) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
        if (route == AppRoutes.home) {
          final photo = find.byKey(const ValueKey('site-hero-photo'));
          expect(photo, findsOneWidget);
          final image = tester.widget<Image>(
            find.descendant(of: photo, matching: find.byType(Image)),
          );
          expect(
            (image.image as AssetImage).assetName,
            endsWith('app-logo-cb1bbbb6c0df.png'),
          );
        }
        if (route == AppRoutes.menu) {
          expect(
            find.byKey(const ValueKey('order-bottom-bar')),
            width < 600 ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(NavigationRail),
            width >= 600 && width < 1200 ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('menu-cart-columns')),
            width >= 1200 ? findsOneWidget : findsNothing,
          );
        }
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          await tester.drag(scroll.first, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$route scroll');
        }
      }
    });
  }

  testWidgets('альбомное окно 844×390: главная и меню читаются', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      size: const Size(844, 390),
      scale: 1.6,
    );
    container.read(routerProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    container.read(routerProvider).go(AppRoutes.menu);
    await tester.pumpAndSettle();
    expect(find.byType(AdaptiveAppShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('клавиатура на узком меню оставляет количество доступным', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      size: const Size(390, 844),
      scale: 1.6,
      initialLocation: AppRoutes.menu,
      status: SessionStatus.signedIn,
      dishesBody: _menu,
      preparedDay: true,
    );
    container.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'d1': 1},
    });
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    final increase = find.byTooltip(AppStrings.menuIncreaseQuantity);
    expect(increase, findsOneWidget);
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    expect(increase.hitTestable(), findsOneWidget);
    expect(tester.getRect(increase).bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.takeException(), isNull);
  });
}
