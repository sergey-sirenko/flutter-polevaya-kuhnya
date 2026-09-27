import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/adaptive_app_shell.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required double width,
  String initialLocation = '/menu',
  SessionStatus status = SessionStatus.signedOut,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.parse(
            environment: 'test',
            apiBaseUrl: 'https://example.invalid/api/',
            dataBaseUrl: 'https://example.invalid/data/',
          ),
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
  for (final (width, expected) in <(double, String)>[
    (360, 'bottom'),
    (599, 'bottom'),
    (600, 'rail'),
    (1023, 'rail'),
    (1024, 'columns'),
    (1920, 'columns'),
  ]) {
    testWidgets('ширина $width выбирает $expected без переполнения', (
      tester,
    ) async {
      final container = await _mount(tester, width: width);
      expect(find.byType(AdaptiveAppShell), findsOneWidget);
      expect(
        find.byType(NavigationBar),
        expected == 'bottom' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationRail),
        expected == 'bottom' ? findsNothing : findsOneWidget,
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

  testWidgets('широкое меню показывает закрытую корзину гостю', (tester) async {
    await _mount(tester, width: 1024);
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
  });

  testWidgets('узкая навигация ведёт гостя с корзины на вход', (tester) async {
    final container = await _mount(tester, width: 360);
    await tester.tap(find.text(AppStrings.cart));
    await tester.pumpAndSettle();
    final uri = container
        .read(routerProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(uri.path, '/sign-in');
    expect(uri.queryParameters['from'], '/cart');
    expect(find.byType(AdaptiveAppShell), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('resize сохраняет адрес и выбор, перестраивая три режима', (
    tester,
  ) async {
    const target = '/cart?day=2026-09-28';
    final container = await _mount(
      tester,
      width: 1024,
      initialLocation: target,
      status: SessionStatus.signedIn,
    );
    final router = container.read(routerProvider);
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
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
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    tester.view.physicalSize = const Size(1920, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-cart-columns')), findsOneWidget);
    expect(container.read(routerProvider), same(router));
    expect(router.routeInformationProvider.value.uri.toString(), target);
    expect(tester.takeException(), isNull);
  });
}
