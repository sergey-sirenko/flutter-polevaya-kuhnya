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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'повтор проверки восстанавливает доступ; logout сохраняет router и ведёт ко входу',
    (tester) async {
      final config = AppConfig.parse(
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
            appConfigProvider.overrideWithValue(config),
            sessionStorageProvider.overrideWithValue(storage),
            initialLocationProvider.overrideWithValue('/orders'),
            httpClientProvider.overrideWithValue(
              MockClient((_) async {
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
}
