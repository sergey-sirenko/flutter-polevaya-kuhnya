import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';

import '../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';
import 'package:polevaya_kuhnya/features/profile/profile_page.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreparedEdit extends CartEditController {
  @override
  CartEditState build() => const CartEditState(
    dateKey: '2030-01-02',
    owner: 'owner-a',
    revision: 'test-revision',
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required double width,
  double height = 800,
  String initialLocation = '/menu',
  SessionStatus status = SessionStatus.signedOut,
  String dishesBody = '{"weeks":[]}',
  bool prepared = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        if (prepared)
          cartEditControllerProvider.overrideWith(_PreparedEdit.new),
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
  testWidgets('полоса меню открывает корзину без изменения порций', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      width: 390,
      status: SessionStatus.signedIn,
      prepared: true,
    );
    container.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'d1': 2},
      '2030-01-03': {'d2': 3},
    });
    await tester.pumpAndSettle();
    expect(find.text('Порций: 2'), findsOneWidget);
    final draft = container.read(cartDraftProvider);
    await tester.tap(find.byKey(const ValueKey('cart-summary-open')));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/cart',
    );
    expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
    expect(container.read(cartDraftProvider), draft);
    expect(tester.takeException(), isNull);
  });

  for (final (width, expected) in <(double, String)>[
    (320, 'bottom'),
    (360, 'bottom'),
    (390, 'bottom'),
    (599, 'bottom'),
    (600, 'rail'),
    (768, 'rail'),
    (769, 'rail'),
    (1023, 'rail'),
    (1024, 'rail'),
    (1199, 'rail'),
    (1200, 'columns'),
    (1440, 'columns'),
    (1920, 'columns'),
  ]) {
    testWidgets('ширина $width выбирает $expected без переполнения', (
      tester,
    ) async {
      final container = await _mount(tester, width: width);
      expect(find.byType(AdaptiveAppShell), findsOneWidget);
      expect(
        find.byKey(const ValueKey('order-bottom-bar')),
        expected == 'bottom' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationRail),
        expected == 'rail' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('order-side-nav')),
        expected == 'columns' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('menu-cart-columns')),
        expected == 'columns' ? findsOneWidget : findsNothing,
      );
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/menu',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('правая колонка 400 px на широких экранах', (tester) async {
    await _mount(tester, width: 1440);
    expect(tester.getSize(find.byKey(const ValueKey('cart-panel'))).width, 400);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('cart-panel'))).width, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на широком экране профиль занимает место корзины', (
    tester,
  ) async {
    await _mount(
      tester,
      width: 1280,
      initialLocation: '/profile',
      status: SessionStatus.signedIn,
    );
    expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-panel')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('profile-panel'))).width,
      400,
    );
    expect(find.byKey(const ValueKey('profile-sign-out')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('заказы на широком экране стоят в правой панели', (tester) async {
    await _mount(
      tester,
      width: 1280,
      initialLocation: '/orders',
      status: SessionStatus.signedIn,
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('широкое меню показывает закрытую корзину гостю', (tester) async {
    await _mount(tester, width: 1440);
    final cartPanel = find.byKey(const ValueKey('cart-panel'));
    expect(
      find.descendant(
        of: cartPanel,
        matching: find.text(AppStrings.signInRequired),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cartPanel,
        matching: find.text(AppStrings.sectionUnavailable),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
    expect(
      find.descendant(
        of: cartPanel,
        matching: find.byKey(const ValueKey('guest-sign-in')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('гостевая панель корзины предлагает вход с возвратом from', (
    tester,
  ) async {
    final container = await _mount(tester, width: 1280);
    final cartPanel = find.byKey(const ValueKey('cart-panel'));
    await tester.tap(
      find.descendant(
        of: cartPanel,
        matching: find.byKey(const ValueKey('guest-sign-in')),
      ),
    );
    await tester.pumpAndSettle();
    final uri = container
        .read(routerProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(uri.path, '/sign-in');
    expect(uri.queryParameters['from'], '/cart');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'узкая кнопка Заказать ведёт гостя на вход с возвратом в заказы',
    (tester) async {
      final container = await _mount(tester, width: 360);
      await tester.tap(find.byKey(const ValueKey('order-bottom-order')));
      await tester.pumpAndSettle();
      final uri = container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri;
      expect(uri.path, '/sign-in');
      expect(uri.queryParameters['from'], '/orders');
      expect(find.byType(AdaptiveAppShell), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NavigationRail переключает разделы и выбранный индекс', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      width: 600,
      status: SessionStatus.signedIn,
    );
    await tester.tap(find.text(AppStrings.ordersTab));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/orders',
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
    );
    await tester.tap(find.text(AppStrings.profile));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/profile',
    );
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('клавиатура открывает раздел из NavigationRail', (tester) async {
    final container = await _mount(
      tester,
      width: 600,
      status: SessionStatus.signedIn,
    );
    final orderLabel = find.text(AppStrings.ordersTab);
    Focus.of(tester.element(orderLabel)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/orders',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize сохраняет State меню, прокрутку, дату и порции', (
    tester,
  ) async {
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
                  'categoryId': 'c1',
                  'categoryName': 'Супы',
                  'categoryOrder': 1,
                  'dishes': [
                    for (var i = 0; i < 20; i++)
                      {
                        'dishId': 'd$i',
                        'dishName': 'Суп $i',
                        'menuOrder': i + 1,
                        'price': 100,
                      },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });
    final container = await _mount(tester, width: 390, dishesBody: dishes);
    final state = tester.state(find.byType(MenuPage));
    final scrollFinder = find.byKey(const ValueKey('menu-dishes-scroll'));
    final controller = tester
        .widget<SingleChildScrollView>(scrollFinder)
        .controller!;
    controller.jumpTo(240);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(240, 1));
    final selectedDay = container.read(menuSelectionProvider);
    final selectedCategory = container.read(menuActiveCategoryProvider);
    container.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'d0': 2},
    });
    final draft = container.read(cartDraftProvider);
    for (final width in <double>[
      599,
      600,
      768,
      769,
      1024,
      1199,
      1200,
      1440,
      390,
    ]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(MenuPage)),
        same(state),
        reason: '$width',
      );
      expect(
        tester.widget<SingleChildScrollView>(scrollFinder).controller,
        same(controller),
      );
      expect(controller.offset, closeTo(240, 1), reason: '$width');
      expect(container.read(menuSelectionProvider), selectedDay);
      expect(container.read(menuActiveCategoryProvider), selectedCategory);
      expect(container.read(cartDraftProvider), draft);
      if (width == 1200 || width == 1440) {
        final first = tester.getTopLeft(
          find.byKey(const ValueKey('menu-dish-photo-d0')),
        );
        final lastInRow = tester.getTopLeft(
          find.byKey(ValueKey('menu-dish-photo-d${width == 1200 ? 1 : 2}')),
        );
        final nextRow = tester.getTopLeft(
          find.byKey(ValueKey('menu-dish-photo-d${width == 1200 ? 2 : 3}')),
        );
        expect(lastInRow.dy, closeTo(first.dy, 1));
        expect(nextRow.dy, greaterThan(first.dy));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('resize сохраняет адрес и выбор, перестраивая три режима', (
    tester,
  ) async {
    const target = '/cart?day=2026-09-28';
    final container = await _mount(
      tester,
      width: 1440,
      initialLocation: target,
      status: SessionStatus.signedIn,
    );
    final router = container.read(routerProvider);
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey('order-side-cart')), findsNothing);
    expect(find.byKey(const ValueKey('order-side-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-side-profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-panel')), findsOneWidget);

    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsNothing);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );

    tester.view.physicalSize = const Size(599, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-bottom-bar')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('order-bottom-bar'))).height,
      56,
    );
    final orderIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('order-bottom-order')),
        matching: find.byIcon(Icons.shopping_cart_outlined),
      ),
    );
    expect(
      orderIcon.color,
      Theme.of(tester.element(find.byKey(const ValueKey('order-bottom-bar'))))
          .colorScheme
          .onSurfaceVariant,
    );

    tester.view.physicalSize = const Size(1920, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
    expect(container.read(routerProvider), same(router));
    expect(router.routeInformationProvider.value.uri.toString(), target);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкая панель: день, меню, заказать и профиль над страницей', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      width: 360,
      initialLocation: '/profile',
      status: SessionStatus.signedIn,
    );
    expect(find.text(AppStrings.orderDay), findsOneWidget);
    expect(find.text(AppStrings.orderAction), findsOneWidget);
    expect(find.text(AppStrings.ordersTab), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('order-bottom-bar'))).height,
      56,
    );

    tester.view.viewPadding = const FakeViewPadding(bottom: 40);
    tester.view.padding = const FakeViewPadding(bottom: 40);
    await tester.pump();
    final bar = find.byKey(const ValueKey('order-bottom-bar'));
    expect(tester.getBottomLeft(bar).dy, closeTo(760, 1));
    expect(
      tester.getBottomLeft(find.byType(ProfilePage)).dy,
      lessThanOrEqualTo(tester.getTopLeft(bar).dy + 0.1),
    );

    await tester.tap(find.byKey(const ValueKey('order-bottom-day')));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/menu',
    );

    container.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'dish': 1},
    });
    await tester.pump();
    expect(find.text(AppStrings.orderAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'день и категории открываются над панелью и закрываются снаружи',
    (tester) async {
      const dishes = '''
{"weeks":[
  {"weekType":"current","days":[{"date":"2030-01-02","hasDelivery":true,"dayName":"Среда","categories":[{"categoryId":"c1","categoryName":"Супы","categoryOrder":1,"dishes":[{"dishId":"d1","dishName":"Суп","menuOrder":1,"price":10,"ingredients":{"textDescription":"вода"}}]}]}]},
  {"weekType":"next","days":[{"date":"2030-01-09","hasDelivery":true,"dayName":"Среда","categories":[{"categoryId":"c2","categoryName":"Салаты","categoryOrder":1,"dishes":[{"dishId":"d2","dishName":"Салат","menuOrder":1,"price":20}]}]}]}
]}
''';
      final container = await _mount(
        tester,
        width: 360,
        status: SessionStatus.signedIn,
        dishesBody: dishes,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-dish-photo-d1')),
      );
      await tester.tap(find.byKey(const ValueKey('menu-dish-photo-d1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-dish-card-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('order-bottom-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-dish-card-dialog')), findsNothing);
      final sheet = find.byKey(const ValueKey('order-day-sheet'));
      final bar = find.byKey(const ValueKey('order-bottom-bar'));
      expect(sheet, findsOneWidget);
      expect(
        tester.getBottomLeft(sheet).dy,
        closeTo(tester.getTopLeft(bar).dy, 1),
      );
      expect(find.byKey(const ValueKey('order-week-row')), findsOneWidget);

      container.read(cartDraftProvider.notifier).replaceAll({
        '2030-01-02': {'d1': 1},
      });
      await tester.pump();
      expect(
        find.byKey(const ValueKey('order-day-mark-2030-01-02')),
        findsNothing,
      );
      expect(find.text('✓'), findsNothing);
      for (final label in [
        AppStrings.menuCurrentWeek,
        AppStrings.menuNextWeek,
      ]) {
        final weekButton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, label),
        );
        expect(
          weekButton.style!.foregroundColor!.resolve({}),
          Theme.of(tester.element(find.text(label))).colorScheme.primary,
        );
      }

      tester.view.physicalSize = const Size(500, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-week-row')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('order-sheet-barrier')));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);

      await tester.tap(find.byKey(const ValueKey('order-bottom-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('order-category-sheet')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('order-sheet-barrier')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-category-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'расширение собирает день, категории, заказы и профиль в один заказ',
    (tester) async {
      const dishes = '''
{"weeks":[{"weekType":"current","days":[
  {"date":"2030-01-02","hasDelivery":true,"dayName":"Среда","categories":[
    {"categoryId":"c1","categoryName":"Супы","categoryOrder":1,"dishes":[
      {"dishId":"d1","dishName":"Суп","menuOrder":1,"price":10},
      {"dishId":"d3","dishName":"Суп 2","menuOrder":2,"price":10},
      {"dishId":"d4","dishName":"Суп 3","menuOrder":3,"price":10},
      {"dishId":"d5","dishName":"Суп 4","menuOrder":4,"price":10},
      {"dishId":"d6","dishName":"Суп 5","menuOrder":5,"price":10},
      {"dishId":"d7","dishName":"Суп 6","menuOrder":6,"price":10}
    ]},
    {"categoryId":"c2","categoryName":"Салаты","categoryOrder":2,"dishes":[
      {"dishId":"d2","dishName":"Салат","menuOrder":1,"price":20},
      {"dishId":"d8","dishName":"Салат 2","menuOrder":2,"price":20},
      {"dishId":"d9","dishName":"Салат 3","menuOrder":3,"price":20},
      {"dishId":"d10","dishName":"Салат 4","menuOrder":4,"price":20},
      {"dishId":"d11","dishName":"Салат 5","menuOrder":5,"price":20},
      {"dishId":"d12","dishName":"Салат 6","menuOrder":6,"price":20}
    ]}
  ]},
  {"date":"2030-01-03","hasDelivery":true,"dayName":"Четверг","categories":[
    {"categoryId":"c1","categoryName":"Супы","categoryOrder":1,"dishes":[
      {"dishId":"d1","dishName":"Суп","menuOrder":1,"price":10},
      {"dishId":"d3","dishName":"Суп 2","menuOrder":2,"price":10},
      {"dishId":"d4","dishName":"Суп 3","menuOrder":3,"price":10},
      {"dishId":"d5","dishName":"Суп 4","menuOrder":4,"price":10},
      {"dishId":"d6","dishName":"Суп 5","menuOrder":5,"price":10},
      {"dishId":"d7","dishName":"Суп 6","menuOrder":6,"price":10}
    ]},
    {"categoryId":"c2","categoryName":"Салаты","categoryOrder":2,"dishes":[
      {"dishId":"d2","dishName":"Салат","menuOrder":1,"price":20},
      {"dishId":"d8","dishName":"Салат 2","menuOrder":2,"price":20},
      {"dishId":"d9","dishName":"Салат 3","menuOrder":3,"price":20},
      {"dishId":"d10","dishName":"Салат 4","menuOrder":4,"price":20},
      {"dishId":"d11","dishName":"Салат 5","menuOrder":5,"price":20},
      {"dishId":"d12","dishName":"Салат 6","menuOrder":6,"price":20}
    ]}
  ]}
]}]}
''';
      final container = await _mount(
        tester,
        width: 360,
        status: SessionStatus.signedIn,
        dishesBody: dishes,
      );
      await tester.tap(find.byKey(const ValueKey('order-bottom-menu')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('order-category-sheet'));
      final saladThumb = find.descendant(
        of: sheet,
        matching: find.byKey(const ValueKey('menu-category-thumb-c2')),
      );
      expect(saladThumb, findsOneWidget);
      expect(tester.getSize(saladThumb), const Size(64, 64));
      expect(
        tester.getTopLeft(saladThumb).dx,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(of: sheet, matching: find.text('Салаты')),
              )
              .dx,
        ),
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Салаты')),
      );
      await tester.pumpAndSettle();
      expect(container.read(menuActiveCategoryProvider), 'c2');
      await tester.tap(find.byKey(const ValueKey('order-bottom-day')));
      await tester.pumpAndSettle();
      final thursday = find.descendant(
        of: find.byKey(const ValueKey('order-day-sheet')),
        matching: find.text('Четверг (03.01)'),
      );
      await tester.ensureVisible(thursday);
      await tester.tap(thursday);
      await tester.pumpAndSettle();
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('order-bottom-day')),
          matching: find.text('Чт 03.01'),
        ),
        findsOneWidget,
      );
      expect(container.read(menuActiveCategoryProvider), 'c2');
      await tester.tap(find.byKey(const ValueKey('order-bottom-day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-day-sheet')), findsOneWidget);

      tester.view.physicalSize = const Size(700, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-day-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('order-category-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('menu-cart-columns')), findsNothing);
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      expect(container.read(menuActiveCategoryProvider), 'c2');
      expect(find.byType(ChoiceChip), findsNothing);

      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-bottom-order')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1440, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/orders',
      );
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      expect(container.read(menuActiveCategoryProvider), 'c2');
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.widgetWithText(TextButton, 'Салаты'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('order-side-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-panel')), findsNothing);
      expect(find.byKey(const ValueKey('orders-panel')), findsNothing);
      expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.widgetWithText(TextButton, 'Салаты'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .selected,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('order-side-orders')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-panel')), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('верхнее меню заказа видно, пока окно не адаптивное', (
    tester,
  ) async {
    final container = await _mount(tester, width: 1440);
    expect(find.byKey(SiteFrame.navRowKey), findsOneWidget);
    expect(find.byKey(SiteFrame.navToggleKey), findsNothing);
    expect(find.text(AppStrings.about), findsOneWidget);
    expect(find.text(AppStrings.delivery), findsOneWidget);
    expect(find.text(AppStrings.howToOrder), findsOneWidget);
    expect(
      tester.widget<Row>(find.byKey(SiteFrame.navRowKey)).direction,
      Axis.horizontal,
    );

    tester.view.physicalSize = const Size(768, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(SiteFrame.navRowKey), findsNothing);
    expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
    await tester.tap(find.byKey(SiteFrame.navToggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SiteFrame.navPanelKey), findsOneWidget);
    expect(find.text(AppStrings.delivery), findsOneWidget);
    final panelBottom = tester
        .getRect(find.byKey(SiteFrame.navPanelKey))
        .bottom;
    await tester.tapAt(Offset(24, panelBottom + 12));
    await tester.pumpAndSettle();
    expect(find.byKey(SiteFrame.navPanelKey), findsNothing);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/menu',
    );

    tester.view.physicalSize = const Size(900, 400);
    await tester.pumpAndSettle();
    expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
    expect(find.byKey(SiteFrame.navRowKey), findsNothing);

    tester.view.physicalSize = const Size(1440, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.about));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/about',
    );
    expect(find.byKey(const ValueKey('order-bottom-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
