import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

final _testSessionProvider = NotifierProvider<_TestSession, SessionStatus>(
  () => _TestSession(SessionStatus.signedOut),
);

class _TestSession extends Notifier<SessionStatus> {
  _TestSession(this.initial);
  final SessionStatus initial;

  @override
  SessionStatus build() => initial;

  void setStatus(SessionStatus value) => state = value;
}

Finder _pageTitle(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.key == const ValueKey('route-page-title') &&
      widget.data == title,
);

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  String initialLocation = '/',
  String platformLocation = '/',
  SessionStatus status = SessionStatus.signedOut,
}) async {
  tester.platformDispatcher.defaultRouteNameTestValue = platformLocation;
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
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
        _testSessionProvider.overrideWith(() => _TestSession(status)),
        sessionStatusProvider.overrideWith(
          (ref) => ref.watch(_testSessionProvider),
        ),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  // У restoring есть анимированный индикатор, поэтому не ждём его остановки.
  await tester.pump();
  if (status != SessionStatus.restoring) await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(FieldKitchenApp)),
  );
}

void main() {
  test('ADR-8: любой Web стартует с /, Android и iOS с /menu', () {
    for (final platform in TargetPlatform.values) {
      expect(initialLocationFor(isWeb: true, platform: platform), '/');
    }
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(initialLocationFor(isWeb: false, platform: platform), '/menu');
    }
  });

  const publicPages = {
    '/': AppStrings.appTitle,
    '/about': AppStrings.about,
    '/delivery': AppStrings.delivery,
    '/how-to-order': AppStrings.howToOrder,
    '/contacts': AppStrings.contacts,
    '/install': AppStrings.install,
    '/sign-in': AppStrings.signIn,
    '/sign-up': AppStrings.signUp,
    '/reset-password': AppStrings.resetPassword,
    '/menu': AppStrings.menu,
  };
  for (final entry in publicPages.entries) {
    testWidgets('гость может открыть ${entry.key}', (tester) async {
      final container = await _mount(tester, initialLocation: entry.key);
      expect(
        entry.key == '/' ? find.text(entry.value) : _pageTitle(entry.value),
        findsOneWidget,
      );
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        entry.key,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('обычный старт $platform открывает меню гостю', (tester) async {
      await _mount(
        tester,
        initialLocation: initialLocationFor(isWeb: false, platform: platform),
      );
      expect(_pageTitle(AppStrings.menu), findsOneWidget);
      expect(find.text(AppStrings.signIn), findsNothing);
    });
  }

  testWidgets('явный адрес платформы с query и fragment сохраняется', (
    tester,
  ) async {
    const target = '/contacts?source=test#office';
    final container = await _mount(
      tester,
      initialLocation: '/menu',
      platformLocation: target,
    );
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      target,
    );
    expect(_pageTitle(AppStrings.contacts), findsOneWidget);
  });

  const protectedPages = {
    '/cart': AppStrings.cart,
    '/orders': AppStrings.orders,
    '/profile': AppStrings.profile,
  };
  for (final entry in protectedPages.entries) {
    testWidgets('${entry.key}: вход, возврат и выход без пересоздания router', (
      tester,
    ) async {
      final target = '${entry.key}?day=2026-09-28#details';
      final container = await _mount(tester, platformLocation: target);
      final router = container.read(routerProvider);
      final loginUri = router.routeInformationProvider.value.uri;
      expect(loginUri.path, '/sign-in');
      expect(loginUri.queryParameters['from'], target);
      expect(_pageTitle(entry.value), findsNothing);

      container
          .read(_testSessionProvider.notifier)
          .setStatus(SessionStatus.signedIn);
      await tester.pumpAndSettle();
      expect(container.read(routerProvider), same(router));
      expect(router.routeInformationProvider.value.uri.toString(), target);
      expect(_pageTitle(entry.value), findsOneWidget);

      container
          .read(_testSessionProvider.notifier)
          .setStatus(SessionStatus.signedOut);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/sign-in');
      expect(_pageTitle(entry.value), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'восстановление и ошибка связи скрывают защищённую страницу, сохраняя URL',
    (tester) async {
      const target = '/orders?day=2026-09-28';
      final container = await _mount(
        tester,
        initialLocation: target,
        status: SessionStatus.restoring,
      );
      final router = container.read(routerProvider);
      final session = container.read(_testSessionProvider.notifier);
      expect(_pageTitle(AppStrings.checkingSession), findsOneWidget);
      expect(_pageTitle(AppStrings.orders), findsNothing);
      expect(router.routeInformationProvider.value.uri.toString(), target);

      session.setStatus(SessionStatus.unavailable);
      await tester.pumpAndSettle();
      expect(_pageTitle(AppStrings.sessionUnavailable), findsOneWidget);
      expect(_pageTitle(AppStrings.orders), findsNothing);
      expect(router.routeInformationProvider.value.uri.toString(), target);

      session.setStatus(SessionStatus.signedIn);
      await tester.pumpAndSettle();
      expect(_pageTitle(AppStrings.orders), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.toString(), target);

      session.setStatus(SessionStatus.restoring);
      await tester.pump();
      expect(_pageTitle(AppStrings.orders), findsNothing);
      expect(_pageTitle(AppStrings.checkingSession), findsOneWidget);
      expect(container.read(routerProvider), same(router));
    },
  );

  testWidgets('ошибка проверки сессии не закрывает публичное меню', (
    tester,
  ) async {
    await _mount(
      tester,
      initialLocation: '/menu',
      status: SessionStatus.unavailable,
    );
    expect(_pageTitle(AppStrings.menu), findsOneWidget);
  });

  testWidgets('внешние, неизвестные и циклические from заменяются на меню', (
    tester,
  ) async {
    final container = await _mount(tester, status: SessionStatus.signedIn);
    final router = container.read(routerProvider);
    for (final target in [
      'https://example.invalid/orders',
      '//example.invalid/orders',
      '/sign-in?from=/orders',
      '/sign-up',
      '/reset-password',
      '/unknown',
      'orders',
      r'/\example.invalid',
      '%2F%2Fexample.invalid',
      '',
    ]) {
      router.go(
        Uri(path: '/sign-in', queryParameters: {'from': target}).toString(),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/menu',
        reason: target,
      );
      expect(tester.takeException(), isNull);
    }
    router.go('/sign-in?from=/orders&from=/profile');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/menu');
  });

  testWidgets('ссылка восстановления доступна при подтверждённой сессии', (
    tester,
  ) async {
    const target = '/reset-password?code=example-only';
    final container = await _mount(
      tester,
      platformLocation: target,
      status: SessionStatus.signedIn,
    );
    expect(
      container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .toString(),
      target,
    );
    expect(_pageTitle(AppStrings.resetPassword), findsOneWidget);
  });

  testWidgets('завершающий / не обходит защиту и нормализуется router', (
    tester,
  ) async {
    final container = await _mount(tester, initialLocation: '/orders/');
    final router = container.read(routerProvider);
    expect(router.routeInformationProvider.value.uri.path, '/sign-in');
    container
        .read(_testSessionProvider.notifier)
        .setStatus(SessionStatus.signedIn);
    await tester.pumpAndSettle();
    expect(_pageTitle(AppStrings.orders), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/orders');
  });

  testWidgets('выход закрывает защищённый стек, Back не раскрывает его', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      initialLocation: '/orders',
      status: SessionStatus.signedIn,
    );
    final router = container.read(routerProvider);
    router.push<void>('/about');
    await tester.pumpAndSettle();
    expect(_pageTitle(AppStrings.about), findsOneWidget);
    container
        .read(_testSessionProvider.notifier)
        .setStatus(SessionStatus.signedOut);
    await tester.pumpAndSettle();
    expect(_pageTitle(AppStrings.signIn), findsOneWidget);
    expect(router.canPop(), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_pageTitle(AppStrings.orders), findsNothing);
    expect(_pageTitle(AppStrings.signIn), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/sign-in');
  });

  for (final target in ['/unknown?from=/orders', '/ORDERS']) {
    testWidgets('неизвестный адрес $target не превращается в защищённый', (
      tester,
    ) async {
      final container = await _mount(tester, initialLocation: target);
      expect(_pageTitle(AppStrings.pageNotFound), findsOneWidget);
      expect(_pageTitle(AppStrings.orders), findsNothing);
      expect(
        container
            .read(routerProvider)
            .routeInformationProvider
            .value
            .uri
            .toString(),
        target,
      );
      await tester.tap(find.text(AppStrings.home));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.appTitle), findsOneWidget);
    });
  }

  testWidgets(
    'кнопка заказа открывает меню, системный Back возвращает предыдущий адрес',
    (tester) async {
      final container = await _mount(tester);
      await tester.tap(find.text(AppStrings.orderLunch));
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/menu');
      router.push<void>('/about');
      await tester.pumpAndSettle();
      expect(_pageTitle(AppStrings.about), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_pageTitle(AppStrings.menu), findsOneWidget);
      expect(router.canPop(), isFalse);
    },
  );
}
