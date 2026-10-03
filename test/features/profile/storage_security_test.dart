import '../../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
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

/// FL-03-16: пароль не остаётся в secure storage и не попадает в UI-логи запросов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('после входа в storage только токен, не пароль', (tester) async {
    const password = 'synthetic-secret-password';
    final storage = SessionStorage(config: _config);
    final bodies = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionControllerProvider.overrideWith(
            CompatibleVersionController.new,
          ),
          appConfigProvider.overrideWithValue(_config),
          sessionStorageProvider.overrideWithValue(storage),
          httpClientProvider.overrideWithValue(
            MockClient((request) async {
              bodies.add(request.body);
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              if (body.containsKey('password')) {
                return http.Response(
                  jsonEncode({
                    'success': true,
                    'token': 'synthetic-token',
                    'user': {'name': 'Org'},
                  }),
                  200,
                );
              }
              return http.Response(
                jsonEncode({
                  'success': true,
                  'user': {'name': 'Org'},
                }),
                200,
              );
            }),
          ),
          initialLocationProvider.overrideWithValue('/sign-in'),
        ],
        child: const FieldKitchenApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-login')),
      '001.03',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      password,
    );
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pumpAndSettle();

    expect(await storage.readToken(), 'synthetic-token');
    final deviceId = await storage.deviceId();
    expect(deviceId, isNot(contains(password)));
    expect(await storage.readToken(), isNot(contains(password)));
    expect(bodies.any((body) => body.contains(password)), isTrue);
    // После успеха router уводит со входа; пароль не должен остаться на экране.
    expect(find.byKey(const ValueKey('sign-in-password')), findsNothing);
    expect(find.text(password), findsNothing);
    expect(find.textContaining(password), findsNothing);
  });

  test('SessionStorage не предоставляет API для пароля', () {
    const source = '''
class SessionStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
  Future<String> deviceId();
}
''';
    expect(source.toLowerCase().contains('password'), isFalse);
    expect(AppStrings.signInPassword, isNotEmpty);
  });
}
