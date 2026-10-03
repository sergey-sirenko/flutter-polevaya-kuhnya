import '../support/compatible_version.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _emptyMenu() => http.Response.bytes(
  utf8.encode('{"weeks":[]}'),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _emptyDates() => http.Response.bytes(
  utf8.encode('{"success":true,"message":"ok","menudates":[]}'),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

bool _isMenuData(http.BaseRequest request) =>
    request.url.path.endsWith('/dishes.json') ||
    request.url.path.contains('/download/');

bool _isMenuDates(http.BaseRequest request) =>
    request.url.path.endsWith('/menudates');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('холодный старт держит личный маршрут закрытым до профиля 1С', (
    tester,
  ) async {
    final config = AppConfig.parse(
      appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
      environment: 'test',
      apiBaseUrl: 'https://api.example.test/Obmen/',
      dataBaseUrl: 'https://data.example.test/data/',
    );
    final storage = SessionStorage(config: config);
    await storage.writeToken('test-token');
    final deviceId = await storage.deviceId();
    final sent = Completer<void>();
    final reply = Completer<http.Response>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionControllerProvider.overrideWith(
            CompatibleVersionController.new,
          ),
          appConfigProvider.overrideWithValue(config),
          sessionStorageProvider.overrideWithValue(storage),
          initialLocationProvider.overrideWithValue('/orders'),
          httpClientProvider.overrideWithValue(
            MockClient((request) {
              if (_isMenuData(request)) return Future.value(_emptyMenu());
              if (_isMenuDates(request)) return Future.value(_emptyDates());
              expect(jsonDecode(request.body), {
                'token': 'test-token',
                'deviceId': deviceId,
              });
              sent.complete();
              return reply.future;
            }),
          ),
        ],
        child: const FieldKitchenApp(),
      ),
    );
    await sent.future;
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FieldKitchenApp)),
    );
    expect(container.read(sessionProfileProvider), isNull);
    expect(container.read(sessionApiProvider), isNull);
    expect(find.text(AppStrings.checkingSession), findsWidgets);
    reply.complete(
      http.Response.bytes(
        utf8.encode('{"success":true,"user":{"name":"Тест"}}'),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(sessionProfileProvider)?.name, 'Тест');
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/orders',
    );
  });

  testWidgets(
    'повтор проверки восстанавливает доступ; logout сохраняет router и ведёт ко входу',
    (tester) async {
      final config = AppConfig.parse(
        appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
        environment: 'test',
        apiBaseUrl: 'https://api.example.test/Obmen/',
        dataBaseUrl: 'https://data.example.test/data/',
      );
      final storage = SessionStorage(config: config);
      await storage.writeToken('test-token');
      var online = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionControllerProvider.overrideWith(
              CompatibleVersionController.new,
            ),
            appConfigProvider.overrideWithValue(config),
            sessionStorageProvider.overrideWithValue(storage),
            initialLocationProvider.overrideWithValue('/orders'),
            httpClientProvider.overrideWithValue(
              MockClient((request) async {
                if (_isMenuData(request)) return _emptyMenu();
                if (_isMenuDates(request)) return _emptyDates();
                if (!online) throw http.ClientException('offline');
                return http.Response('{"success":true,"user":{}}', 200);
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
      final router = container.read(routerProvider);
      expect(router.routeInformationProvider.value.uri.path, '/orders');
      expect(find.text(AppStrings.sessionUnavailable), findsOneWidget);
      expect(container.read(sessionApiProvider), isNull);
      online = true;
      await tester.tap(find.text(AppStrings.retrySession));
      await tester.pumpAndSettle();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedIn,
      );
      expect(router.routeInformationProvider.value.uri.path, '/orders');
      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(identical(container.read(routerProvider), router), isTrue);
      expect(router.routeInformationProvider.value.uri.path, '/sign-in');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['from'],
        '/orders',
      );
      expect(await storage.readToken(), isNull);
    },
  );

  testWidgets('истечение токена закрывает личный маршрут и профиль', (
    tester,
  ) async {
    var expired = false;
    final config = AppConfig.parse(
      appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
      environment: 'test',
      apiBaseUrl: 'https://api.example.test/Obmen/',
      dataBaseUrl: 'https://data.example.test/data/',
    );
    final storage = SessionStorage(config: config);
    await storage.writeToken('test-token');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionControllerProvider.overrideWith(
            CompatibleVersionController.new,
          ),
          appConfigProvider.overrideWithValue(config),
          sessionStorageProvider.overrideWithValue(storage),
          initialLocationProvider.overrideWithValue('/orders'),
          httpClientProvider.overrideWithValue(
            MockClient((request) async {
              if (_isMenuData(request)) return _emptyMenu();
              if (request.url.path.endsWith('/login')) {
                return http.Response.bytes(
                  utf8.encode('{"success":true,"user":{"name":"Тест"}}'),
                  200,
                );
              }
              if (request.url.path.endsWith('/menudates') && !expired) {
                return http.Response('{"success":true,"menudates":[]}', 200);
              }
              return http.Response('', 401);
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
    expect(container.read(sessionProfileProvider)?.name, 'Тест');
    expired = true;
    await expectLater(
      container.read(sessionApiProvider)!.postJson('V1/Orders/menudates', {}),
      throwsException,
    );
    await tester.pumpAndSettle();
    final uri = container
        .read(routerProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(uri.path, '/sign-in');
    expect(uri.queryParameters['from'], '/orders');
    expect(container.read(sessionProfileProvider), isNull);
    expect(await storage.readToken(), isNull);
  });
}
