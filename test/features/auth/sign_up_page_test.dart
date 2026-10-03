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
import 'package:polevaya_kuhnya/features/auth/sign_up_page.dart';
import 'package:polevaya_kuhnya/features/auth/login_controller.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';

final _config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

Future<SessionStorage> _mount(
  WidgetTester tester,
  MockClient client, {
  DateTime Function()? now,
  String initialLocation = '/sign-up',
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
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.url.path.endsWith('/dishes.json')) {
              return http.Response('{"weeks":[]}', 200);
            }
            final forwarded = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = request.bodyBytes;
            return http.Response.fromStream(await client.send(forwarded));
          }),
        ),
        initialLocationProvider.overrideWithValue(initialLocation),
        if (now != null) registrationClockProvider.overrideWithValue(now),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  final checkbox = find.descendant(of: finder, matching: find.byType(Checkbox));
  final text = find.descendant(of: finder, matching: find.byType(Text));
  final target = checkbox.evaluate().isNotEmpty
      ? checkbox
      : text.evaluate().isNotEmpty
      ? text.first
      : finder;
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  await tester.tap(target);
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  bool giveConsent = true,
}) async {
  await tester.enterText(find.byKey(const ValueKey('sign-up-login')), 'demo');
  await tester.enterText(
    find.byKey(const ValueKey('sign-up-password')),
    'synthetic-password',
  );
  if (giveConsent &&
      !tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('sign-up-consent')),
          )
          .value!) {
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-consent')));
    await tester.pump();
  }
  await _tapVisible(tester, find.byKey(const ValueKey('sign-up-check')));
  await tester.pumpAndSettle();
}

Future<void> _startRegistration(WidgetTester tester) async {
  await _enterCredentials(tester);
  await tester.enterText(
    find.byKey(const ValueKey('sign-up-full-name')),
    'Тестовый Пользователь',
  );
  await tester.enterText(
    find.byKey(const ValueKey('sign-up-email')),
    'demo@example.test',
  );
  await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
  await tester.pumpAndSettle();
}

http.Response _codeSent(
  String id, {
  int retryAfter = 60,
  int expiresIn = 600,
}) => http.Response(
  jsonEncode({
    'success': true,
    'code': 'code_sent',
    'requestId': id,
    'retryAfter': retryAfter,
    'expiresIn': expiresIn,
  }),
  200,
);

const _firstId = '12345678-1234-4123-8123-123456789abc';
const _secondId = '87654321-4321-4321-8321-cba987654321';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'FL-UX-03: registered сбрасывает старую ошибку, новая попытка показывает новую',
    (tester) async {
      var attempts = 0;
      await _mount(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/registrationstart')) {
            return _codeSent(_firstId);
          }
          if (request.url.path.endsWith('/registrationconfirm')) {
            return http.Response('{"success":true,"code":"registered"}', 200);
          }
          if (request.url.path.endsWith('/login') && ++attempts > 1) {
            return http.Response(
              '{"success":false,"code":"invalid_credentials"}',
              400,
            );
          }
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FieldKitchenApp)),
      );
      await container
          .read(loginControllerProvider.notifier)
          .submit(login: 'demo', password: 'synthetic-password');
      expect(
        container.read(loginControllerProvider).error,
        AppStrings.signInRegistrationRequired,
      );
      await _startRegistration(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-code')),
        '123456',
      );
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.registrationCompleted), findsOneWidget);
      expect(find.text(AppStrings.signInRegistrationRequired), findsNothing);
      expect(container.read(loginControllerProvider).error, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-password')),
        'synthetic-password',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('sign-up-login-submit')),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.signInInvalidCredentials), findsOneWidget);
    },
  );

  testWidgets(
    'без согласия check/start не отправляют данные, отзыв перед start учитывается',
    (tester) async {
      var checks = 0;
      var starts = 0;
      await _mount(
        tester,
        MockClient((request) async {
          if (request.url.path.endsWith('/registrationstatus')) {
            checks++;
            return http.Response(
              '{"success":false,"code":"registration_required"}',
              400,
            );
          }
          starts++;
          return _codeSent(_firstId);
        }),
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('sign-up-consent')),
            )
            .value,
        isFalse,
      );
      await _enterCredentials(tester, giveConsent: false);
      expect(checks, 0);
      expect(find.text(AppStrings.registrationConsentRequired), findsOneWidget);
      await _enterCredentials(tester);
      expect(checks, 1);
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-full-name')),
        'Тестовый Пользователь',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-email')),
        'demo@example.test',
      );
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-consent')));
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(find.text(AppStrings.registrationConsentRequired), findsOneWidget);
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-consent')));
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
      await tester.pumpAndSettle();
      expect(starts, 1);
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-cancel')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('sign-up-consent')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('sign-up-password')),
            )
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'политика и отдельное согласие доступны без запроса, Back сохраняет форму на 360 px',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1);
      var calls = 0;
      await _mount(
        tester,
        MockClient((request) async {
          calls++;
          return http.Response('unexpected', 500);
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-login')),
        'demo',
      );
      await tester.enterText(
        find.byKey(const ValueKey('sign-up-password')),
        'synthetic-password',
      );
      await _tapVisible(tester, find.byKey(const ValueKey('sign-up-consent')));
      await tester.pump();
      final router = ProviderScope.containerOf(
        tester.element(find.byType(SignUpPage)),
      ).read(routerProvider);
      for (final document in [
        (
          'sign-up-consent-link',
          AppRoutes.personalDataConsent,
          SiteContent.personalDataConsentParagraphs,
        ),
        (
          'sign-up-privacy-link',
          AppRoutes.privacy,
          SiteContent.privacyParagraphs,
        ),
      ]) {
        await _tapVisible(tester, find.byKey(ValueKey(document.$1)));
        await tester.pumpAndSettle();
        expect(find.text(document.$3.first), findsOneWidget);
        for (final paragraph in document.$3) {
          expect(find.text(paragraph), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (document.$2 == AppRoutes.personalDataConsent) {
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('data-document-back')),
          );
        } else {
          router.pop();
        }
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.signUp,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('sign-up-login')),
              )
              .controller!
              .text,
          'demo',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('sign-up-password')),
              )
              .controller!
              .text,
          'synthetic-password',
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('sign-up-consent')),
              )
              .value,
          isTrue,
        );
      }
      router.go(AppRoutes.signIn);
      await tester.pumpAndSettle();
      router.go(AppRoutes.signUp);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('sign-up-consent')),
            )
            .value,
        isFalse,
      );
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ФИО/email открываются только после registration_required', (
    tester,
  ) async {
    var calls = 0;
    final storage = await _mount(
      tester,
      MockClient((request) async {
        calls++;
        expect(request.url.path, '/Obmen/V1/User/registrationstatus');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, unorderedEquals(['login', 'password', 'deviceId']));
        expect(body['login'], 'demo');
        expect(body['password'], 'synthetic-password');
        expect(body['deviceId'], isA<String>());
        return http.Response(
          '{"success":false,"code":"registration_required"}',
          400,
        );
      }),
    );
    expect(find.byKey(const ValueKey('sign-up-full-name')), findsNothing);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-check')));
    await tester.pump();
    expect(find.text(AppStrings.signInLoginRequired), findsOneWidget);
    expect(calls, 0);
    await _enterCredentials(tester);
    expect(find.byKey(const ValueKey('sign-up-full-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-email')), findsOneWidget);
    expect(calls, 1);
    expect(await storage.readToken(), isNull);
  });

  testWidgets('start передаёт context_v1 и сохраняет ключ только в форме', (
    tester,
  ) async {
    var starts = 0;
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        starts++;
        expect(request.url.path, '/Obmen/V1/User/registrationstart');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['login'], 'demo');
        expect(body['password'], 'synthetic-password');
        expect(body['deviceId'], isA<String>());
        expect(body['fullName'], 'Тестовый Пользователь');
        expect(body['email'], 'demo@example.test');
        expect(body['registrationMode'], 'context_v1');
        return http.Response(
          '{"success":true,"code":"code_sent","requestId":"12345678-1234-4123-8123-123456789abc","retryAfter":60,"expiresIn":600}',
          200,
        );
      }),
    );
    await _enterCredentials(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
    await tester.pump();
    expect(find.text(AppStrings.registrationFullNameRequired), findsOneWidget);
    expect(find.text(AppStrings.registrationEmailRequired), findsOneWidget);
    expect(starts, 0);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-full-name')),
      'Тестовый Пользователь',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-email')),
      'demo@example.test',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text(AppStrings.registrationCodeSent), findsOneWidget);
    expect(find.text('12345678-1234-4123-8123-123456789abc'), findsNothing);
  });

  testWidgets('блокировка не открывает профиль, ready ведёт ко входу', (
    tester,
  ) async {
    var blocked = true;
    await _mount(
      tester,
      MockClient(
        (_) async => blocked
            ? http.Response('{"success":false,"code":"access_denied"}', 403)
            : http.Response('{"success":true,"code":"ready"}', 200),
      ),
    );
    await _enterCredentials(tester);
    expect(find.text(AppStrings.registrationAccessDenied), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-full-name')), findsNothing);
    blocked = false;
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-check')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.registrationAlreadyReady), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-full-name')), findsNothing);
    expect(find.byKey(const ValueKey('sign-up-login-submit')), findsOneWidget);
  });

  testWidgets('после ошибки start пароль вводится заново', (tester) async {
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        return http.Response('{"success":false,"code":"rate_limited"}', 400);
      }),
    );
    await _enterCredentials(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-full-name')),
      'Тест',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-email')),
      'demo@example.test',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-start')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.registrationRateLimited), findsOneWidget);
    final password = tester.widget<TextFormField>(
      find.byKey(const ValueKey('sign-up-password')),
    );
    expect(password.controller?.text, isEmpty);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('sign-up-consent')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('код с нулями подтверждается строкой без пароля', (tester) async {
    var confirms = 0;
    late SessionStorage storage;
    storage = await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId);
        }
        confirms++;
        expect(request.url.path, '/Obmen/V1/User/registrationconfirm');
        expect(jsonDecode(request.body), {
          'requestId': _firstId,
          'deviceId': await storage.deviceId(),
          'verificationCode': '001234',
        });
        return http.Response('{"success":true,"code":"registered"}', 200);
      }),
    );
    await _startRegistration(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pump();
    expect(find.text(AppStrings.registrationCodeRequired), findsOneWidget);
    expect(confirms, 0);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '001234',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(confirms, 1);
    expect(find.text(AppStrings.registrationCompleted), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-login-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-code')), findsNothing);
    expect(find.byKey(const ValueKey('sign-up-full-name')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sign-up-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(await storage.readToken(), isNull);
  });

  testWidgets('после registered вход создаёт сессию и очищает временные поля', (
    tester,
  ) async {
    var logins = 0;
    late SessionStorage storage;
    storage = await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId);
        }
        if (request.url.path.endsWith('/registrationconfirm')) {
          return http.Response('{"success":true,"code":"registered"}', 200);
        }
        if (request.url.path.endsWith('/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body.containsKey('password')) {
            logins++;
            expect(body['login'], 'demo');
            expect(body['password'], 'synthetic-password');
            expect(body['selfRegistration'], isTrue);
            expect(body.containsKey('requestId'), isFalse);
            return http.Response(
              '{"success":true,"token":"synthetic-token"}',
              200,
            );
          }
          expect(body.keys.toSet(), {'token', 'deviceId'});
          return http.Response('{"success":true,"user":{}}', 200);
        }
        fail('Неожиданный запрос ${request.url.path}');
      }),
    );
    await _startRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '123456',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(await storage.readToken(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-password')),
      'synthetic-password',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sign-up-login-submit')),
    );
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(await storage.readToken(), 'synthetic-token');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FieldKitchenApp)),
    );
    expect(container.read(sessionStatusProvider), SessionStatus.signedIn);
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/orders',
    );
  });

  testWidgets('отказ входа после registered оставляет гостя', (tester) async {
    final storage = await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId);
        }
        if (request.url.path.endsWith('/registrationconfirm')) {
          return http.Response('{"success":true,"code":"registered"}', 200);
        }
        return http.Response(
          '{"success":false,"code":"invalid_credentials"}',
          400,
        );
      }),
    );
    await _startRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '123456',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-password')),
      'wrong-password',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sign-up-login-submit')),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.signInInvalidCredentials), findsOneWidget);
    expect(await storage.readToken(), isNull);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('sign-up-password')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('sign-up-login-submit')), findsOneWidget);
  });

  testWidgets('повтор заменяет requestId без пароля и не продлевает срок', (
    tester,
  ) async {
    var resends = 0;
    var confirms = 0;
    var now = DateTime(2026, 9, 27);
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId, retryAfter: 2, expiresIn: 10);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/registrationresend')) {
          resends++;
          expect(body.keys, unorderedEquals(['requestId', 'deviceId']));
          expect(body['requestId'], _firstId);
          return _codeSent(_secondId, retryAfter: 2, expiresIn: 8);
        }
        confirms++;
        expect(
          body.keys,
          unorderedEquals(['requestId', 'deviceId', 'verificationCode']),
        );
        expect(body['requestId'], _secondId);
        return http.Response('{"success":true,"code":"registered"}', 200);
      }),
      now: () => now,
    );
    await _startRegistration(tester);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('sign-up-resend')))
          .onPressed,
      isNull,
    );
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-resend')));
    await tester.pumpAndSettle();
    expect(resends, 1);
    expect(find.text('Осталось секунд: 8'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '123456',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(confirms, 1);
  });

  testWidgets('истечение и code_expired возвращают к реквизитам', (
    tester,
  ) async {
    var expiredByServer = false;
    var now = DateTime(2026, 9, 27);
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId, retryAfter: 0, expiresIn: 2);
        }
        expiredByServer = true;
        return http.Response('{"success":false,"code":"code_expired"}', 400);
      }),
      now: () => now,
    );
    await _startRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '123456',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(expiredByServer, isTrue);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('sign-up-consent')),
          )
          .value,
      isFalse,
    );
    expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
    expect(find.text(AppStrings.registrationExpired), findsOneWidget);
    await _startRegistration(tester);
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
    expect(find.text(AppStrings.registrationExpired), findsOneWidget);
  });

  testWidgets('поздний resend не возвращает отменённый контекст', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final sent = Completer<void>();
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId, retryAfter: 0);
        }
        sent.complete();
        return pending.future;
      }),
    );
    await _startRegistration(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-resend')));
    await tester.pump();
    await sent.future;
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-cancel')));
    await tester.pump();
    pending.complete(_codeSent(_secondId));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-code')), findsNothing);
    expect(find.text(AppStrings.registrationCanceled), findsOneWidget);
  });

  for (final refusal in [
    (
      code: 'ambiguous_employee',
      message: 'Для этой почты найдено несколько сотрудников. Обратитесь к ответственному.',
      expected: AppStrings.registrationDuplicateEmail,
    ),
    (
      code: 'ambiguous_employee',
      message:
          'У устройства несколько сотрудников. Обратитесь к ответственному.',
      expected: AppStrings.registrationAmbiguousDevice,
    ),
    (
      code: 'access_denied',
      message: 'Доступ запрещён. Обратитесь к ответственному.',
      expected: AppStrings.registrationOrganizationDenied,
    ),
    (
      code: 'access_denied',
      message: 'Доступ устройства запрещён. Обратитесь к ответственному.',
      expected: AppStrings.registrationDeviceDenied,
    ),
    (
      code: 'access_denied',
      message: 'Доступ сотрудника ограничен. Обратитесь к ответственному.',
      expected: AppStrings.registrationEmployeeDenied,
    ),
    (
      code: 'access_denied',
      message: 'Сотрудник недоступен. Обратитесь к ответственному.',
      expected: AppStrings.registrationEmployeeUnavailable,
    ),
    (
      code: 'access_denied',
      message: 'Привязка устройства изменена. Обратитесь к ответственному.',
      expected: AppStrings.registrationBindingChanged,
    ),
    (
      code: 'device_mismatch',
      message: 'Устройство не соответствует сеансу.',
      expected: AppStrings.registrationDeviceMismatch,
    ),
    (
      code: 'access_denied',
      message: 'Internal detail must not be displayed',
      expected: AppStrings.registrationAccessDenied,
    ),
  ]) {
    for (final action in ['registrationconfirm', 'registrationresend']) {
      testWidgets('отказ $action: ${refusal.expected}', (tester) async {
        var refusals = 0;
        final storage = await _mount(
          tester,
          MockClient((request) async {
            if (request.url.path.endsWith('/registrationstatus')) {
              return http.Response(
                '{"success":false,"code":"registration_required"}',
                400,
              );
            }
            if (request.url.path.endsWith('/registrationstart')) {
              return _codeSent(_firstId, retryAfter: 0);
            }
            expect(request.url.path.endsWith('/$action'), isTrue);
            refusals++;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'success': false,
                  'code': refusal.code,
                  'message': refusal.message,
                }),
              ),
              403,
            );
          }),
        );
        await _startRegistration(tester);
        if (action == 'registrationconfirm') {
          await tester.enterText(
            find.byKey(const ValueKey('sign-up-code')),
            '000001',
          );
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('sign-up-confirm')),
          );
        } else {
          await _tapVisible(tester, find.text(AppStrings.registrationResend));
        }
        await tester.pumpAndSettle();
        expect(find.text(refusal.expected), findsOneWidget);
        expect(
          find.text('Internal detail must not be displayed'),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('sign-up-code')), findsNothing);
        expect(find.text(AppStrings.registrationResend), findsNothing);
        expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
        expect(await storage.readToken(), isNull);
        await tester.pump(const Duration(seconds: 1));
        expect(refusals, 1);
      });
    }
  }

  testWidgets('неверный код допускает повтор, лимит попыток сбрасывает поток', (
    tester,
  ) async {
    var confirms = 0;
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId);
        }
        confirms++;
        return confirms == 1
            ? http.Response('{"success":false,"code":"invalid_code"}', 400)
            : http.Response(
                '{"success":false,"code":"attempts_exhausted"}',
                400,
              );
      }),
    );
    await _startRegistration(tester);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '000001',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.registrationInvalidCode), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-code')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('sign-up-code')),
      '000002',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.registrationAttemptsExhausted), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
  });

  testWidgets('неизвестный итог resend не повторяет запись вслепую', (
    tester,
  ) async {
    var resends = 0;
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId, retryAfter: 0);
        }
        resends++;
        throw http.ClientException('offline');
      }),
    );
    await _startRegistration(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-resend')));
    await tester.pumpAndSettle();
    expect(resends, 1);
    expect(find.text(AppStrings.registrationResendUnknown), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-login')), findsOneWidget);
  });

  testWidgets('rate_limited сохраняет контекст и задерживает повтор', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 27);
    var resends = 0;
    await _mount(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/registrationstatus')) {
          return http.Response(
            '{"success":false,"code":"registration_required"}',
            400,
          );
        }
        if (request.url.path.endsWith('/registrationstart')) {
          return _codeSent(_firstId, retryAfter: 0);
        }
        resends++;
        return http.Response(
          '{"success":false,"code":"rate_limited","retryAfter":4}',
          400,
        );
      }),
      now: () => now,
    );
    await _startRegistration(tester);
    await _tapVisible(tester, find.byKey(const ValueKey('sign-up-resend')));
    await tester.pumpAndSettle();
    expect(resends, 1);
    expect(find.text(AppStrings.registrationRateLimited), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-up-code')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('sign-up-resend')))
          .onPressed,
      isNull,
    );
    now = now.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('sign-up-resend')))
          .onPressed,
      isNotNull,
    );
  });
}
