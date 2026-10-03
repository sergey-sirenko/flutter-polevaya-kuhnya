import 'package:polevaya_kuhnya/features/site/site_widgets.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/orders_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/compatible_version.dart';

MenuDay _day(String key, {bool delivery = true}) => MenuDay(
  dateKey: key,
  date: menuCalendarDate(key),
  hasDelivery: delivery,
  categories: [
    MenuCategory(
      categoryId: 'c1',
      categoryName: 'Супы',
      dishes: [
        const MenuDish(dishId: 'd1', dishName: 'Суп с овощами', price: 190.5),
      ],
    ),
  ],
);

final _weeks = [
  MenuWeek(
    weekType: 'current',
    days: [
      _day('2030-01-02'),
      _day('2030-01-03'),
      _day('2030-01-05', delivery: false),
    ],
  ),
  MenuWeek(weekType: 'next', days: [_day('2030-01-07')]),
];

UserProfile _profile({
  String name = 'Тестовый пользователь',
  num sum = 190.5,
}) => UserProfile.fromUserJson({
  'name': name,
  'login': name,
  'order': [
    {
      'date': '2030-01-02T23:59:00-12:00',
      'weekType': 'next',
      'status': 'Принят',
      'sum': sum,
      'dishes': [
        {'dish': 'd1', 'name': 'Суп', 'quantity': 1, 'sum': sum},
      ],
    },
    {
      'date': '2030-01-07',
      'sum': 0,
      'dishes': [
        {'dish': 'd1', 'name': 'Суп бесплатно', 'quantity': 1, 'sum': 0},
      ],
    },
    {
      'date': '2020-06-01',
      'sum': 999,
      'dishes': [
        {'dish': 'old', 'name': 'Старый заказ', 'quantity': 1, 'sum': 999},
      ],
    },
  ],
});

final _menuSource = Provider<Future<List<MenuWeek>>>((ref) async => _weeks);
final _datesSource = Provider<Future<Set<String>?>>(
  (ref) async => {'2030-01-03', '2030-01-07'},
);

class _Menu extends MenuController {
  int retries = 0;
  @override
  Future<List<MenuWeek>> build() => ref.watch(_menuSource);
  @override
  Future<void> reload() async {
    retries++;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(_menuSource));
  }

  void replace(List<MenuWeek> value) => state = AsyncData(value);
  void fail() => state = AsyncError(StateError("offline"), StackTrace.current);
}

class _Dates extends MenuAllowedDatesController {
  int retries = 0;
  @override
  Future<Set<String>?> build() => ref.watch(_datesSource);
  @override
  Future<void> reload() async {
    retries++;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(_datesSource));
  }

  void replace(Set<String>? value) => state = AsyncData(value);
  void fail() => state = AsyncError(StateError('offline'), StackTrace.current);
}

final _profileState = NotifierProvider<_Profile, UserProfile?>(_Profile.new);

class _Profile extends Notifier<UserProfile?> {
  @override
  UserProfile? build() => _profile();
  void replace(UserProfile? value) => state = value;
}

final _statusState = NotifierProvider<_Status, SessionStatus>(_Status.new);

class _Version extends CompatibleVersionController {
  void block() => state = const AppVersionCheck(AppVersionStatus.checking);
  void allow() => state = const AppVersionCheck(AppVersionStatus.current);
}

class _Status extends Notifier<SessionStatus> {
  @override
  SessionStatus build() => SessionStatus.signedIn;
  void replace(SessionStatus value) => state = value;
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  double width = 320,
  double scale = 1,
  bool app = false,
  String initialLocation = '/orders',
  Future<List<MenuWeek>>? menu,
  Future<Set<String>?>? dates,
  String? selected,
  ValueChanged<String>? onSelect,
  ValueChanged<String>? onStart,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1100);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(
    overrides: [
      appVersionControllerProvider.overrideWith(_Version.new),
      appConfigProvider.overrideWithValue(
        AppConfig.parse(
          appVersionUrl: 'https://example.invalid/version.json',
          environment: 'test',
          apiBaseUrl: 'https://example.invalid/api/',
          dataBaseUrl: 'https://example.invalid/data/',
        ),
      ),
      initialLocationProvider.overrideWithValue(initialLocation),
      sessionStatusProvider.overrideWith((ref) => ref.watch(_statusState)),
      sessionProfileProvider.overrideWith((ref) => ref.watch(_profileState)),
      menuControllerProvider.overrideWith(_Menu.new),
      menuAllowedDatesProvider.overrideWith(_Dates.new),
      if (menu != null) _menuSource.overrideWithValue(menu),
      if (dates != null) _datesSource.overrideWithValue(dates),
      cartRepositoryProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: app
          ? const FieldKitchenApp()
          : MaterialApp(
              theme: AppTheme.light,
              home: RepaintBoundary(
                key: const ValueKey('orders-preview'),
                child: OrdersPage(
                  selectedDateKey: selected,
                  onSelectDay: onSelect,
                  onStartOrder: onStart,
                ),
              ),
            ),
    ),
  );
  await tester.pump();
  // Незавершённые futures оставляют анимированный индикатор загрузки.
  if (!container.read(menuControllerProvider).isLoading &&
      !container.read(menuAllowedDatesProvider).isLoading) {
    await tester.pumpAndSettle();
  }
  return container;
}

Finder _button(String date) => find.byKey(ValueKey('orders-day-$date'));

Future<void> _tapDay(WidgetTester tester, Finder day) async {
  final heading = find.descendant(of: day, matching: find.byType(Text)).first;
  await tester.ensureVisible(heading);
  await tester.pump();
  await tester.tap(heading);
}

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('скидки истории в двух колонках $scale', (tester) async {
      final container = await _mount(
        tester,
        width: 1200,
        scale: scale,
        app: true,
      );
      container
          .read(_profileState.notifier)
          .replace(
            UserProfile.fromUserJson({
              'name': 'Тест',
              'DiscountPercentage': 50,
              'order': [
                {
                  'date': '2030-01-02',
                  'sum': 115,
                  'discount': 6,
                  'dishes': [
                    {'dish': 'd', 'name': 'Суп', 'quantity': 1, 'sum': 115},
                  ],
                },
                {
                  'date': '2030-01-07',
                  'sum': 200,
                  'discount': 10,
                  'finalPayable': 175,
                  'finalPayableScope': 'document',
                  'dishes': [
                    {'dish': 'd', 'name': 'Суп', 'quantity': 1, 'sum': 200},
                  ],
                },
              ],
            }),
          );
      await tester.pumpAndSettle();
      expect(find.text('109 ₽\n115 ₽'), findsWidgets);
      expect(find.text('175 ₽\n200 ₽'), findsOneWidget);
      expect(find.text('Итого: 109 ₽'), findsOneWidget);
      expect(find.text('Итого: 175 ₽'), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-weeks-row')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1440.0, 1920.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('FL-10-15: широкие недели рядом $width/$scale', (
        tester,
      ) async {
        await _mount(tester, width: width, scale: scale, app: true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('orders-weeks-row')), findsOneWidget);
        expect(find.byKey(const ValueKey('orders-weeks-column')), findsNothing);
        expect(find.byKey(const ValueKey('app-history-back')), findsNothing);
        expect(
          tester.getSize(find.byKey(const ValueKey('orders-panel'))).width,
          400,
        );
        final current = find.text(AppStrings.menuCurrentWeek);
        final next = find.text(AppStrings.menuNextWeek);
        expect(
          tester.getTopLeft(current).dy,
          closeTo(tester.getTopLeft(next).dy, 1),
        );
        expect(
          tester.getTopLeft(current).dx,
          lessThan(tester.getTopLeft(next).dx),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 390.0, 599.0, 600.0, 1199.0, 1200.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('FL-10-13: высота дней и положение действия $width/$scale', (
        tester,
      ) async {
        var starts = 0;
        await _mount(
          tester,
          width: width,
          scale: scale,
          onStart: (_) => starts++,
        );
        await tester.pumpAndSettle();
        final closed = _button('2030-01-02');
        final open = _button('2030-01-03');
        final closedSize = tester.getSize(closed);
        final openSize = tester.getSize(open);
        expect(openSize, closedSize);
        final start = find.byKey(const ValueKey('orders-start-2030-01-03'));
        await tester.ensureVisible(start);
        await tester.pump();
        final sum = find.descendant(
          of: open,
          matching: find.text(AppStrings.ordersNoOrder),
        );
        final status = find.descendant(
          of: open,
          matching: find.text(AppStrings.ordersNoOrder),
        );
        expect(
          tester.getRect(open).bottom - tester.getRect(start).bottom,
          closeTo(8, 2),
        );
        if (tester.getRect(start).top >= tester.getRect(status).bottom) {
          expect(
            tester.getRect(start).bottom,
            lessThanOrEqualTo(tester.getRect(open).bottom),
          );
        } else {
          expect(
            tester.getRect(start).left,
            greaterThan(tester.getRect(sum).right),
          );
        }
        expect(find.byKey(const ValueKey('orders-weeks-row')), findsOneWidget);
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('orders-week-current')))
              .dy,
          tester.getTopLeft(find.byKey(const ValueKey('orders-week-next'))).dy,
        );
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(starts, 1);
        expect(tester.getSize(closed), closedSize);
        expect(tester.takeException(), isNull);
      });

      testWidgets('FL-10-13: Назад в общей строке $width/$scale', (
        tester,
      ) async {
        final container = await _mount(
          tester,
          width: width,
          scale: scale,
          app: true,
        );
        await tester.pumpAndSettle();
        final back = find.byKey(const ValueKey('app-history-back'));
        final logo = find.byKey(const ValueKey('site-brand-logo'));
        if (width >= 1200) {
          expect(back, findsNothing);
          expect(
            find.byKey(const ValueKey('orders-weeks-row')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('orders-weeks-column')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          return;
        }
        expect(
          tester.getCenter(back).dy,
          closeTo(tester.getCenter(logo).dy, 1),
        );
        expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
        final toggle = find.byKey(SiteFrame.navToggleKey);
        if (toggle.evaluate().isNotEmpty) {
          expect(
            tester.getRect(back).right,
            lessThanOrEqualTo(tester.getRect(toggle).left),
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            container.read(routerProvider).routerDelegate.state.uri.path,
            '/orders',
          );
          expect(find.byKey(SiteFrame.navPanelKey), findsNothing);
        }
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(
          container.read(routerProvider).routerDelegate.state.uri.path,
          '/',
        );
        expect(find.byKey(const ValueKey('app-history-back')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final status in [SessionStatus.signedOut, SessionStatus.restoring]) {
    testWidgets(
      'FL-10-11: главная, вход/восстановление и видимые заказы $status',
      (tester) async {
        final container = await _mount(
          tester,
          width: 390,
          app: true,
          initialLocation: '/about',
        );
        await tester.pumpAndSettle();
        container.read(_statusState.notifier).replace(status);
        await tester.pump();
        final router = container.read(routerProvider);
        router.push('/');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-history-back')), findsNothing);
        await tester.tap(find.text(AppStrings.orderLunch));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        if (status == SessionStatus.signedOut) {
          expect(router.routeInformationProvider.value.uri.path, '/sign-in');
          expect(
            router.routeInformationProvider.value.uri.queryParameters['from'],
            '/orders',
          );
          expect(
            find.byKey(const ValueKey('sign-in-login')).hitTestable(),
            findsOneWidget,
          );
        } else {
          expect(router.routeInformationProvider.value.uri.path, '/orders');
          expect(
            find.text(AppStrings.checkingSession).hitTestable(),
            findsOneWidget,
          );
          expect(_button('2030-01-02'), findsNothing);
        }
        container.read(_statusState.notifier).replace(SessionStatus.signedIn);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/orders',
          reason:
              'status=${container.read(sessionStatusProvider)}, delegate=${router.routerDelegate.state.uri}, base=${router.routerDelegate.currentConfiguration.uri}',
        );
        expect(_button('2030-01-02').hitTestable(), findsOneWidget);
        expect(container.read(routerProvider), same(router));
        if (status == SessionStatus.signedOut) {
          // После входа через push форма не должна остаться в истории возврата.
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          await tester.tap(find.text(AppStrings.orderLunch));
          await tester.pumpAndSettle();
          container
              .read(_statusState.notifier)
              .replace(SessionStatus.signedOut);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/sign-in');
          expect(router.canPop(), isTrue);
          expect(_button('2030-01-02'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'FL-10-11: resize после главной сохраняет Navigator, день и корзину',
    (tester) async {
      final container = await _mount(tester, width: 390, app: true);
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      container.read(cartDraftProvider.notifier).replaceAll({
        '2030-01-03': {'d1': 2},
      });
      await _tapDay(tester, _button('2030-01-03'));
      await tester.pumpAndSettle();
      router.push('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.orderLunch));
      await tester.pumpAndSettle();
      for (final width in [1200.0, 599.0, 600.0, 1199.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpAndSettle();
        expect(_button('2030-01-03').hitTestable(), findsOneWidget);
        expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
        expect(container.read(cartDraftProvider), {
          '2030-01-03': {'d1': 2},
        });
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).last),
          same(navigator),
        );
        expect(router.routeInformationProvider.value.uri.path, '/orders');
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final filled in [false, true]) {
    testWidgets(
      'FL-10-11: Заказать открывает заказы, корзина заполнена $filled',
      (tester) async {
        final container = await _mount(
          tester,
          width: 390,
          app: true,
          initialLocation: '/menu',
        );
        await tester.pumpAndSettle();
        if (filled) {
          container.read(cartDraftProvider.notifier).replaceAll({
            '2030-01-03': {'d1': 2},
          });
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('cart-summary-open')), findsNothing);
        }
        final draft = container.read(cartDraftProvider);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('order-bottom-order')),
            matching: find.text(AppStrings.orderAction),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('order-bottom-order')));
        await tester.pumpAndSettle();
        expect(
          container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/orders',
        );
        expect(_button('2030-01-02').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('order-bottom-order')));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/',
        );
        expect(container.read(cartDraftProvider), draft);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0, 599.0, 600.0, 1199.0, 1200.0]) {
    testWidgets('FL-10-11: заказы через главную без reload $width', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        width: width,
        scale: 1.6,
        app: true,
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      router.push('/');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('app-history-back')), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator).last),
        same(navigator),
      );
      expect(find.text(AppStrings.orderLunch).hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text(AppStrings.orderLunch));
      await tester.tap(find.text(AppStrings.orderLunch));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(router.routeInformationProvider.value.uri.path, '/orders');
      expect(_button('2030-01-02').hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-week-current')), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator).last),
        same(navigator),
      );
      if (width < 1200) {
        if (width < 600) {
          final button = find.byKey(const ValueKey('order-bottom-order'));
          expect(
            find.descendant(
              of: button,
              matching: find.text(AppStrings.orderAction),
            ),
            findsOneWidget,
          );
          final icon = tester.widget<Icon>(
            find.descendant(
              of: button,
              matching: find.byIcon(Icons.shopping_cart),
            ),
          );
          expect(
            icon.color,
            Theme.of(tester.element(button)).colorScheme.primary,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
        // Проверяем видимое содержимое и возврат, без создания нового приложения.
        final profileNav = width < 600
            ? find.byKey(const ValueKey('order-bottom-profile'))
            : find.descendant(
                of: find.byType(NavigationRail),
                matching: find.text(AppStrings.profile),
              );
        await tester.tap(profileNav);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/profile');
        expect(
          find.text(AppStrings.profileOrganization).hitTestable(),
          findsOneWidget,
        );
        final orderNav = width < 600
            ? find.byKey(const ValueKey('order-bottom-order'))
            : find.descendant(
                of: find.byType(NavigationRail),
                matching: find.text(AppStrings.ordersTab),
              );
        await tester.tap(orderNav);
        await tester.pumpAndSettle();
        expect(_button('2030-01-02').hitTestable(), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/');
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.byKey(const ValueKey('app-history-back')), findsNothing);
      expect(find.text(AppStrings.orderLunch).hitTestable(), findsOneWidget);
      expect(container.read(routerProvider), same(router));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 599.0, 600.0, 1199.0, 1200.0]) {
    testWidgets('FL-10-12: повтор дня не переходит, история просмотра $width', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        width: width,
        scale: 1.6,
        app: true,
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      String path() => router.routeInformationProvider.value.uri.path;
      expect(path(), '/orders');
      expect(
        find.byKey(const ValueKey('app-history-back')),
        width >= 1200 ? findsNothing : findsOneWidget,
      );
      final draft = {
        '2030-01-03': {'d1': 2},
      };
      container.read(cartDraftProvider.notifier).replaceAll(draft);
      await tester.ensureVisible(_button('2030-01-03'));
      await _tapDay(tester, _button('2030-01-03'));
      await tester.pumpAndSettle();
      expect(path(), '/orders');
      await _tapDay(tester, _button('2030-01-03'));
      await tester.pumpAndSettle();
      if (width >= 1200) {
        expect(path(), '/orders');
        expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
        return;
      }
      expect(path(), '/orders');
      router.push('/orders/categories');
      await tester.pumpAndSettle();
      expect(path(), '/orders/categories');
      expect(
        find.byKey(const ValueKey('menu-categories-page')),
        findsOneWidget,
      );
      await tester.tap(find.text('Супы'));
      await tester.pumpAndSettle();
      expect(path(), '/menu');
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      expect(container.read(menuActiveCategoryProvider), 'c1');
      // Кнопка и системный Back закрывают сначала временные слои.
      if (width < 600) {
        container.read(orderSheetProvider.notifier).toggle(OrderSheet.day);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(path(), '/menu');
        expect(container.read(orderSheetProvider), isNull);
        await tester.tap(find.byKey(const ValueKey('menu-dish-photo-d1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('menu-dish-card-dialog')),
          findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(path(), '/menu');
        expect(
          find.byKey(const ValueKey('menu-dish-card-dialog')),
          findsNothing,
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(path(), '/orders/categories');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(path(), '/orders');
      expect(container.read(cartDraftProvider), draft);
      expect(
        find.byKey(const ValueKey('app-history-back')),
        width >= 1200 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('FL-10-10: ФИО, организация, пустые поля и состав', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersTab), findsNothing);
    expect(find.text(AppStrings.ordersReorder), findsNothing);
    for (final values in [
      ('Иван Иванов', 'Организация', 'Иван Иванов'),
      ('  ', 'Организация', 'Организация'),
      ('', '', ''),
    ]) {
      container
          .read(_profileState.notifier)
          .replace(
            UserProfile.fromUserJson({
              'employee': values.$1,
              'name': values.$2,
              'order': [],
            }),
          );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('route-page-title')))
            .data,
        values.$3,
      );
      expect(find.byKey(const ValueKey('orders-user-name')), findsNothing);
    }
  });

  for (final signedIn in [true, false]) {
    testWidgets('FL-UX-12: узкий холодный старт показывает главную $signedIn', (
      tester,
    ) async {
      final container = await _mount(tester, app: true, initialLocation: '/');
      if (!signedIn) {
        container.read(_statusState.notifier).replace(SessionStatus.signedOut);
      }
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/');
      await tester.tap(find.byKey(SiteFrame.navToggleKey));
      await tester.pumpAndSettle();
      final profile = find.byKey(SiteFrame.navItemKey(AppStrings.profile));
      expect(profile, findsOneWidget);
      await tester.ensureVisible(profile);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        signedIn ? '/profile' : '/sign-in',
      );
      if (!signedIn) {
        expect(
          router.routeInformationProvider.value.uri.queryParameters['from'],
          '/profile',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final systemBack in [false, true]) {
    testWidgets('FL-10-10: прямые категории, возврат $systemBack', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        app: true,
        initialLocation: '/orders/categories',
      );
      await tester.pumpAndSettle();
      expect(find.text('Супы'), findsOneWidget);
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byKey(const ValueKey('app-history-back')));
      }
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/orders',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'FL-10-10: resize категорий, корзина/профиль и блокировка версии',
    (tester) async {
      final container = await _mount(tester, app: true);
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      await _tapDay(tester, _button('2030-01-02'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/orders');
      router.push('/orders/categories');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/orders/categories',
      );
      tester.view.physicalSize = const Size(1200, 1100);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
      tester.view.physicalSize = const Size(390, 1100);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-categories-page')),
        findsOneWidget,
      );
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
      container.read(routerProvider).push('/cart');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/cart');
      await tester.tap(find.byKey(const ValueKey('order-bottom-profile')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/profile');
      await tester.tap(find.byKey(const ValueKey('order-bottom-profile')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      router.go('/cart');
      await tester.pumpAndSettle();
      (container.read(appVersionControllerProvider.notifier) as _Version)
          .block();
      await tester.pump();
      await tester.binding.handlePopRoute();
      router.push('/menu');
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/cart');
      (container.read(appVersionControllerProvider.notifier) as _Version)
          .allow();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-history-back')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FL-10-10: загрузка категорий, ошибка, повтор и пустые данные', (
    tester,
  ) async {
    final pending = Completer<List<MenuWeek>>();
    final container = await _mount(
      tester,
      app: true,
      initialLocation: '/orders/categories',
      menu: pending.future,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(_weeks);
    await tester.pumpAndSettle();
    expect(find.text('Супы'), findsOneWidget);
    final controller = container.read(menuControllerProvider.notifier) as _Menu;
    controller.fail();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersMenuError), findsOneWidget);
    await tester.tap(find.text(AppStrings.ordersRetryMenu));
    await tester.pumpAndSettle();
    expect(controller.retries, 1);
    expect(find.text('Супы'), findsOneWidget);
    controller.replace([]);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.menuNoDishesForDay), findsOneWidget);
    expect(find.text('Супы'), findsNothing);
    controller.replace([
      MenuWeek(weekType: 'next', days: [_day('2030-01-07')]),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Супы'), findsOneWidget);
    expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-07');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'календарь 320 px: недели вертикально, закрытые/пустые дни, серверные итоги',
    (tester) async {
      final container = await _mount(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orders-weeks-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-week-current')), findsOneWidget);
      expect(_button('2030-01-05'), findsNothing);
      expect(find.text('Старый заказ'), findsNothing);
      expect(find.text(AppStrings.repeatOrder), findsOneWidget);
      expect(
        find.descendant(
          of: _button('2030-01-02'),
          matching: find.text(AppStrings.ordersClosed),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _button('2030-01-03'),
          matching: find.text(AppStrings.ordersAvailable),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _button('2030-01-02'),
          matching: find.text('02.01 Среда'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _button('2030-01-03'),
          matching: find.text(AppStrings.ordersNoOrder),
        ),
        findsOneWidget,
      );
      expect(find.text('Итого: 190,50 ₽'), findsOneWidget);
      expect(find.text('Итого: 0 ₽'), findsOneWidget);
      container.read(cartDraftProvider.notifier).replaceAll({
        '2030-01-03': {'d1': 5},
      });
      await _tapDay(tester, _button('2030-01-03'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('orders-selected-empty')),
        findsOneWidget,
      );
      expect(container.read(cartDraftProvider)['2030-01-03'], {'d1': 5});
      await _tapDay(tester, _button('2030-01-07'));
      await tester.pumpAndSettle();
      expect(find.text('Суп бесплатно × 1 — 0 ₽'), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-selected-empty')), findsNothing);
      await _tapDay(tester, _button('2030-01-02'));
      await tester.pumpAndSettle();
      expect(find.text('Суп × 1 — 190,50 ₽'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ожидание доступности нейтрально, закрытый день остаётся кликабельным',
    (tester) async {
      final reply = Completer<Set<String>?>();
      final selected = <String>[];
      await _mount(tester, dates: reply.future, onSelect: selected.add);
      await tester.pump();
      expect(find.text(AppStrings.ordersChecking), findsNWidgets(3));
      expect(find.text(AppStrings.ordersAvailable), findsNothing);
      await _tapDay(tester, _button('2030-01-02'));
      await tester.pump();
      expect(selected.last, '2030-01-02');
      reply.complete({'2030-01-03'});
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.ordersClosed), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ошибка дат и повтор; пустой успешный набор открывает даты', (
    tester,
  ) async {
    final container = await _mount(tester);
    final dates = container.read(menuAllowedDatesProvider.notifier) as _Dates;
    dates.fail();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersAvailable), findsNothing);
    expect(find.text(AppStrings.ordersAvailabilityUnknown), findsNWidgets(4));
    await tester.tap(find.text(AppStrings.ordersRetryDates));
    await tester.pumpAndSettle();
    expect(dates.retries, 1);
    expect(find.text(AppStrings.ordersAvailabilityUnknown), findsNothing);
    dates.replace({});
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersAvailable), findsNothing);
    expect(find.text(AppStrings.ordersClosed), findsNothing);
  });

  testWidgets('загрузка и ошибка меню с повтором, без ложного пустого заказа', (
    tester,
  ) async {
    final reply = Completer<List<MenuWeek>>();
    final container = await _mount(tester, menu: reply.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('orders-selected-empty')), findsNothing);
    reply.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersMenuError), findsOneWidget);
    await tester.tap(find.text(AppStrings.ordersRetryMenu));
    await tester.pumpAndSettle();
    expect(
      (container.read(menuControllerProvider.notifier) as _Menu).retries,
      1,
    );
    expect(find.text(AppStrings.ordersMenuError), findsOneWidget);
  });

  testWidgets('пустая следующая неделя и обновление профиля/меню', (
    tester,
  ) async {
    final container = await _mount(tester);
    (container.read(menuControllerProvider.notifier) as _Menu).replace([
      _weeks.first,
    ]);
    container.read(_profileState.notifier).replace(_profile(sum: 250));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersNextWeekEmpty), findsOneWidget);
    expect(_button('2030-01-07'), findsNothing);
    expect(find.text('Итого: 250 ₽'), findsOneWidget);
    expect(find.text('Суп × 1 — 250 ₽'), findsOneWidget);
    (container.read(menuControllerProvider.notifier) as _Menu).replace([]);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ordersNoDeliveryDays), findsOneWidget);
    expect(find.text('Суп × 1 — 250 ₽'), findsNothing);
  });

  testWidgets('смена пользователя и выход скрывают прежние заказы и выбор', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.pumpAndSettle();
    await _tapDay(tester, _button('2030-01-07'));
    await tester.pumpAndSettle();
    container
        .read(_profileState.notifier)
        .replace(
          UserProfile.fromUserJson({
            'name': 'Другой',
            'login': 'other',
            'order': [],
          }),
        );
    await tester.pumpAndSettle();
    expect(find.text('Тестовый пользователь'), findsNothing);
    expect(find.text('Суп бесплатно × 1 — 0 ₽'), findsNothing);
    expect(find.text('Ср 02.01.30'), findsOneWidget);
    expect(find.byKey(const ValueKey('orders-selected-empty')), findsOneWidget);
    container.read(_statusState.notifier).replace(SessionStatus.signedOut);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orders-user-name')), findsNothing);
    expect(_button('2030-01-02'), findsNothing);
  });

  testWidgets('выбор доступен с клавиатуры', (tester) async {
    await _mount(tester);
    await tester.pumpAndSettle();
    // Фокусируем внутренний Focus кнопки.
    final label = find.descendant(
      of: _button('2030-01-03'),
      matching: find.text(AppStrings.ordersNoOrder),
    );
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('orders-selected-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('первый показ сохраняет выбранный день меню', (tester) async {
    await _mount(tester, selected: '2030-01-07');
    await tester.pumpAndSettle();
    expect(find.text('Пн 07.01.30'), findsOneWidget);
    expect(find.text('Суп бесплатно × 1 — 0 ₽'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 1199.0, 1200.0]) {
    testWidgets('router: выбор закрытого дня и resize $width, текст 1.6', (
      tester,
    ) async {
      final container = await _mount(
        tester,
        width: width,
        scale: 1.6,
        app: true,
      );
      await tester.pumpAndSettle();
      container.read(cartDraftProvider.notifier).replaceAll({
        '2030-01-03': {'d1': 2},
      });
      await tester.ensureVisible(_button('2030-01-03'));
      await _tapDay(tester, _button('2030-01-03'));
      await tester.pumpAndSettle();
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-03');
      await tester.ensureVisible(_button('2030-01-02'));
      await _tapDay(tester, _button('2030-01-02'));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/orders',
      );
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
      expect(container.read(cartDraftProvider)['2030-01-03'], {'d1': 2});
      if (width >= 1200) {
        expect(find.byKey(const ValueKey('orders-panel')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('orders-panel'))).width,
          400,
        );
        expect(find.text(AppStrings.menuDayClosed), findsOneWidget);
      }
      tester.view.physicalSize = Size(width >= 1200 ? 390 : 1200, 1100);
      await tester.pumpAndSettle();
      expect(container.read(menuSelectionProvider)?.dateKey, '2030-01-02');
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/orders',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'увеличенный текст сохраняет две колонки недель; синтетическое превью',
    (tester) async {
      final container = await _mount(tester, scale: 1.6);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orders-weeks-row')), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpAndSettle();
      if (Platform.environment['FL_ORDERS_PREVIEW'] == '1') {
        await tester.runAsync(() async {
          final font = FontLoader('Arial');
          font.addFont(
            File('C:/Windows/Fonts/arial.ttf')
                .readAsBytes()
                .then(ByteData.sublistView),
          );
          await font.load();
          final icons = FontLoader('MaterialIcons');
          icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
        (container.read(menuControllerProvider.notifier) as _Menu).replace([
          for (final (type, start) in [
            ('current', DateTime(2026, 9, 28)),
            ('next', DateTime(2026, 10, 5)),
          ])
            MenuWeek(
              weekType: type,
              days: [
                for (var index = 0; index < 5; index++)
                  _day(
                    start
                        .add(Duration(days: index))
                        .toIso8601String()
                        .substring(0, 10),
                  ),
              ],
            ),
        ]);
        (container.read(menuAllowedDatesProvider.notifier) as _Dates).replace({
          '2026-10-01',
          '2026-10-02',
          '2026-10-05',
          '2026-10-06',
          '2026-10-07',
          '2026-10-08',
          '2026-10-09',
        });
        container
            .read(_profileState.notifier)
            .replace(
              UserProfile.fromUserJson({
                'name': 'Тестовый пользователь',
                'login': 'fixture-owner',
                'order': [
                  {
                    'date': '2026-09-29',
                    'sum': 189,
                    'status': 'Принят',
                    'dishes': [
                      {'dish': 'd1', 'name': 'Суп', 'quantity': 1, 'sum': 189},
                    ],
                  },
                ],
              }),
            );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('orders-preview')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File('build/fl-10-09/orders-panel.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    },
  );

  final fontCandidates = [
    ?Platform.environment['FL_UX_TEST_FONT'],
    'C:/Windows/Fonts/arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  final fontPath = fontCandidates
      .where((path) => File(path).existsSync())
      .firstOrNull;
  group(
    'FL-UX-02: реальные метрики шрифта',
    () {
      setUpAll(() async {
        final font = FontLoader('Arial');
        font.addFont(File(fontPath!).readAsBytes().then(ByteData.sublistView));
        await font.load();
      });
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.6]) {
          testWidgets('слова календаря целиком $width/$scale', (tester) async {
            var starts = 0;
            await _mount(
              tester,
              width: width,
              scale: scale,
              onStart: (_) => starts++,
            );
            final cards = find.byWidgetPredicate(
              (widget) =>
                  widget is TextButton &&
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'orders-day-',
                  ),
            );
            final heights = <double>[];
            for (final card in cards.evaluate()) {
              final finder = find.byWidget(card.widget);
              heights.add(tester.getSize(finder).height);
              for (final element
                  in find
                      .descendant(of: finder, matching: find.byType(RichText))
                      .evaluate()) {
                final paragraph = element.renderObject! as RenderParagraph;
                final label = paragraph.text.toPlainText();
                // У кнопки допустим перенос подписи при крупном тексте;
                // слова статуса, суммы и даты должны оставаться целыми.
                if (label == 'Заказать') continue;
                for (final word in RegExp(r'\S+').allMatches(label)) {
                  final boxes = paragraph.getBoxesForSelection(
                    TextSelection(
                      baseOffset: word.start,
                      extentOffset: word.end,
                    ),
                  );
                  expect(boxes, isNotEmpty, reason: label);
                  expect(
                    boxes.every((box) => (box.top - boxes.first.top).abs() < 1),
                    isTrue,
                    reason:
                        'Слово "${word.group(0)}" разорвано: $label ($width/$scale)',
                  );
                }
              }
            }
            expect(heights.every((height) => height == heights.first), isTrue);
            final open = _button('2030-01-03');
            final action = find.byKey(
              const ValueKey('orders-start-2030-01-03'),
            );
            final status = find.descendant(
              of: open,
              matching: find.text(AppStrings.ordersNoOrder),
            );
            final actionRect = tester.getRect(action);
            final statusRect = tester.getRect(status);
            expect(actionRect.overlaps(statusRect), isFalse);
            expect(
              actionRect.bottom,
              lessThanOrEqualTo(tester.getRect(open).bottom),
            );
            await tester.ensureVisible(action);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(starts, 1);
            expect(
              find.byKey(const ValueKey('orders-weeks-row')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
      testWidgets('закрытый день использует всю ширину текста', (tester) async {
        await _mount(tester, width: 1440, onStart: (_) {});
        final closed = _button('2030-01-02');
        final open = _button('2030-01-03');
        final closedText = find.descendant(
          of: closed,
          matching: find.text('02.01 Среда'),
        );
        final openText = find.descendant(
          of: open,
          matching: find.text(AppStrings.ordersNoOrder),
        );
        expect(
          tester.getTopLeft(closedText).dx,
          closeTo(tester.getTopLeft(closed).dx + 8, 1),
        );
        expect(
          tester.getTopLeft(openText).dx,
          closeTo(tester.getTopLeft(open).dx + 8, 1),
        );
        expect(tester.getSize(closed).height, tester.getSize(open).height);
        expect(tester.takeException(), isNull);
      });
    },
    skip: fontPath == null
        ? 'Нужен системный шрифт или FL_UX_TEST_FONT для проверки переносов'
        : false,
  );
}
