import '../../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

final _config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _mount(WidgetTester tester, MockClient client) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final storage = SessionStorage(config: _config);
  await storage.writeToken('synthetic-token');
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        appConfigProvider.overrideWithValue(_config),
        sessionStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(client),
        initialLocationProvider.overrideWithValue('/profile'),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const FieldKitchenApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

http.Response _json(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('профиль показывает ФИО, организацию, условия и пустые поля', (
    tester,
  ) async {
    await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {
              'name': 'Org Name',
              'employee': 'Employee Name',
              'login': '001.03',
              'phone': '',
              'email': 'a@b.c',
              'DiscountPercentage': 10,
              'DiscountClient': 50,
              'DiscountPromotion': 1,
              'MinimumPaymentAmount': 100,
              'MinimumOrderAmount': 0,
              'Limit': 0,
            },
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': 'a@b.c',
            'canChangeEmail': false,
          });
        }
        fail('Неожиданный запрос $path');
      }),
    );
    final profileTitle = find.byKey(const ValueKey('route-page-title'));
    final profileBar = find.ancestor(
      of: profileTitle,
      matching: find.byType(AppBar),
    );
    expect(
      tester.getCenter(profileTitle).dx,
      closeTo(tester.getCenter(profileBar).dx, 1),
    );
    expect(find.text('Employee Name'), findsOneWidget);
    expect(find.text('Org Name'), findsOneWidget);
    expect(find.text('001.03'), findsOneWidget);
    expect(find.text('10 %'), findsOneWidget);
    expect(find.text('50 ₽'), findsOneWidget);
    expect(find.text(AppStrings.profileDiscountPromotionOn), findsOneWidget);
    expect(find.text(AppStrings.profileLimitNone), findsNothing);
    expect(find.text(AppStrings.profileValueMissing), findsNothing);
    expect(find.text(AppStrings.profileDiscountPromotionOff), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-field-${AppStrings.profilePhone}')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('profile-field-${AppStrings.profileMinimumOrder}'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('profile-about')), findsNothing);
    expect(find.byKey(const ValueKey('profile-support')), findsNothing);
    expect(find.byKey(const ValueKey('profile-about-app')), findsNothing);
    expect(find.byKey(const ValueKey('profile-summary-title')), findsNothing);
    expect(find.text(AppStrings.profile), findsWidgets);
    final version = find.byKey(const ValueKey('profile-app-version'));
    expect(version, findsOneWidget);
    expect(
      tester.getTopLeft(version).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('profile-sign-out'))).dy,
      ),
    );
  });

  testWidgets('выход удаляет токен и уводит со страницы профиля', (
    tester,
  ) async {
    var logoutCalls = 0;
    late SessionStorage storage;
    final container = await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {'name': 'Org', 'employee': 'Emp'},
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': '',
            'canChangeEmail': false,
          });
        }
        if (path.endsWith('/logout')) {
          logoutCalls++;
          return _json({'success': true, 'code': 'logged_out'});
        }
        fail('Неожиданный запрос $path');
      }),
    );
    storage = container.read(sessionStorageProvider);
    expect(await storage.readToken(), 'synthetic-token');
    await _tapVisible(tester, find.byKey(const ValueKey('profile-sign-out')));
    expect(logoutCalls, 1);
    expect(await storage.readToken(), isNull);
    expect(container.read(sessionStatusProvider), SessionStatus.signedOut);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/sign-in',
    );
  });

  testWidgets('отключение устройства требует подтверждения и очищает сессию', (
    tester,
  ) async {
    var disconnects = 0;
    var logoutCalls = 0;
    late SessionStorage storage;
    final container = await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {'name': 'Org', 'employee': 'Emp'},
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': '',
            'canChangeEmail': false,
          });
        }
        if (path.endsWith('/devicedisconnect')) {
          disconnects++;
          expect(body.keys.toSet(), {'token', 'deviceId'});
          return _json({'success': true, 'code': 'device_disconnected'});
        }
        if (path.endsWith('/logout')) {
          logoutCalls++;
          return _json({'success': true});
        }
        fail('Неожиданный запрос $path');
      }),
    );
    storage = container.read(sessionStorageProvider);
    final deviceBeforeDisconnect = await storage.deviceId();
    await _tapVisible(tester, find.byKey(const ValueKey('device-disconnect')));
    expect(find.text(AppStrings.deviceDisconnectConfirmBody), findsOneWidget);
    await tester.tap(find.text(AppStrings.deviceDisconnectCancel));
    await tester.pumpAndSettle();
    expect(disconnects, 0);
    expect(await storage.readToken(), 'synthetic-token');

    await _tapVisible(tester, find.byKey(const ValueKey('device-disconnect')));
    await tester.tap(find.byKey(const ValueKey('device-disconnect-confirm')));
    await tester.pumpAndSettle();
    expect(disconnects, 1);
    expect(logoutCalls, 0);
    expect(await storage.readToken(), isNull);
    expect(await storage.deviceId(), deviceBeforeDisconnect);
    expect(container.read(sessionStatusProvider), SessionStatus.signedOut);
  });

  testWidgets('сетевой отказ отключения не выдаётся за успех', (tester) async {
    late SessionStorage storage;
    final container = await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({'success': true, 'user': {}});
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': '',
            'canChangeEmail': false,
          });
        }
        if (path.endsWith('/devicedisconnect')) {
          throw http.ClientException('offline');
        }
        fail('Неожиданный запрос $path');
      }),
    );
    storage = container.read(sessionStorageProvider);
    await _tapVisible(tester, find.byKey(const ValueKey('device-disconnect')));
    await tester.tap(find.byKey(const ValueKey('device-disconnect-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.signInConnectionError), findsOneWidget);
    expect(await storage.readToken(), 'synthetic-token');
    expect(container.read(sessionStatusProvider), SessionStatus.signedIn);
  });
}
