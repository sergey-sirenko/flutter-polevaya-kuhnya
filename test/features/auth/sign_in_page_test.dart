import '../../support/compatible_version.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

final _config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

Future<SessionStorage> _mount(
  WidgetTester tester,
  MockClient client, {
  String route = '/sign-in',
}) async {
  final storage = SessionStorage(config: _config);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        appConfigProvider.overrideWithValue(_config),
        sessionStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(client),
        initialLocationProvider.overrideWithValue(route),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  List<bool> autofillDecisions(WidgetTester tester) => tester.testTextInput.log
      .where((call) => call.method == 'TextInput.finishAutofillContext')
      .map((call) => call.arguments as bool)
      .toList();

  testWidgets('валидация и переключение скрытия пароля без запроса', (
    tester,
  ) async {
    var requests = 0;
    await _mount(
      tester,
      MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pump();
    expect(find.text(AppStrings.signInLoginRequired), findsOneWidget);
    expect(find.text(AppStrings.signInPasswordRequired), findsOneWidget);
    expect(requests, 0);

    final field = find.byKey(const ValueKey('sign-in-password'));
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
    expect(tester.widget<EditableText>(editable).autofillHints, [
      AutofillHints.password,
    ]);
    final loginEditable = find.descendant(
      of: find.byKey(const ValueKey('sign-in-login')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(loginEditable).autofillHints, [
      AutofillHints.username,
    ]);
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(
      tester.widget<AutofillGroup>(find.byType(AutofillGroup)).onDisposeAction,
      AutofillContextAction.cancel,
    );
    await tester.tap(find.byTooltip(AppStrings.showPassword));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).obscureText, isFalse);
    await tester.tap(find.byTooltip(AppStrings.hidePassword));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).obscureText, isTrue);
  });

  testWidgets('один вход, сохранение после успеха и возврат к from', (
    tester,
  ) async {
    final loginRequest = Completer<http.Request>();
    final loginResponse = Completer<http.Response>();
    var loginCount = 0;
    final storage = await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body.containsKey('password')) {
            loginCount++;
            loginRequest.complete(request);
            return loginResponse.future;
          }
          expect(body.keys.toSet(), {'token', 'deviceId'});
          return http.Response('{"success":true,"user":{}}', 200);
        }
        fail('Неожиданный запрос ${request.url.path}');
      }),
      route: '/sign-in?from=%2Forders',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-login')),
      ' 001.03 ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      'synthetic-password',
    );
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pump();
    final request = await loginRequest.future.timeout(
      const Duration(seconds: 3),
    );
    expect(request.url.path, '/Obmen/V1/User/login');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['login'], '001.03');
    expect(body['password'], 'synthetic-password');
    expect(body['selfRegistration'], isTrue);
    expect(body['deviceId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sign-in-password')))
          .controller!
          .text,
      'synthetic-password',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sign-in-submit')))
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    expect(loginCount, 1);

    loginResponse.complete(
      http.Response('{"success":true,"token":"synthetic-token"}', 200),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FieldKitchenApp)),
    );
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/orders',
    );
    expect(await storage.readToken(), 'synthetic-token');
    expect(
      autofillDecisions(tester).where((decision) => decision),
      hasLength(1),
    );
  });

  testWidgets(
    'отказ показывает безопасную ошибку и оставляет повтор доступным',
    (tester) async {
      var requests = 0;
      final storage = await _mount(
        tester,
        MockClient((request) async {
          requests++;
          return http.Response(
            '{"success":false,"code":"invalid_credentials",'
            '"error":"server detail with synthetic-password"}',
            400,
          );
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-login')),
        '001.03',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-in-password')),
        'synthetic-password',
      );
      await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.signInInvalidCredentials), findsOneWidget);
      expect(find.textContaining('server detail'), findsNothing);
      expect(await storage.readToken(), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FieldKitchenApp)),
      );
      expect(container.read(sessionStatusProvider), SessionStatus.signedOut);
      expect(requests, 1);
      expect(autofillDecisions(tester), contains(false));
      expect(autofillDecisions(tester), isNot(contains(true)));
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sign-in-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sign-in-submit')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('уход с формы отменяет сохранение', (tester) async {
    await _mount(tester, MockClient((_) async => http.Response('{}', 500)));
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-login')),
      'synthetic-user',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      'synthetic-password',
    );
    await tester.tap(find.text(AppStrings.home));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(autofillDecisions(tester), contains(false));
    expect(autofillDecisions(tester), isNot(contains(true)));
  });
}
