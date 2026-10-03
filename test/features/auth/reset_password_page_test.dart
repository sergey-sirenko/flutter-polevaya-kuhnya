import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../support/compatible_version.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
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

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required String route,
  MockClient? client,
}) async {
  final storage = SessionStorage(config: _config);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        appConfigProvider.overrideWithValue(_config),
        sessionStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(
          client ??
              MockClient((_) async {
                fail(
                  'Открытие страницы не должно вызывать API',
                );
              }),
        ),
        initialLocationProvider.overrideWithValue(route),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'страница показывает форму, открытие не отправляет письмо',
    (tester) async {
      var requests = 0;
      await _mount(
        tester,
        route: '/reset-password',
        client: MockClient((_) async {
          requests++;
          fail('Неожиданный запрос');
        }),
      );
      expect(find.text(AppStrings.passwordRecoveryDescription), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(requests, 0);
    },
  );

  testWidgets(
    'неизвестные параметры адреса не отображаются',
    (tester) async {
      await _mount(
        tester,
        route: '/reset-password?code=secret-token&token=another',
      );
      expect(find.textContaining('secret-token'), findsNothing);
      expect(find.textContaining('another'), findsNothing);
      expect(find.textContaining('code='), findsNothing);
      expect(find.textContaining('token='), findsNothing);
      expect(find.text(AppStrings.passwordRecoveryDescription), findsOneWidget);
    },
  );

  testWidgets('возврат ведёт ко входу', (tester) async {
    final container = await _mount(tester, route: '/reset-password');
    await tester.tap(find.byKey(const ValueKey('reset-password-sign-in')));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/sign-in',
    );
  });

  testWidgets(
    'ссылка из входа открывает восстановление',
    (tester) async {
      final container = await _mount(tester, route: '/sign-in');
      await tester.tap(find.byKey(const ValueKey('sign-in-reset-password')));
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/reset-password',
      );
      expect(find.text(AppStrings.passwordRecoveryDescription), findsOneWidget);
    },
  );
  testWidgets('ошибочная почта не вызывает API', (tester) async {
    await _mount(tester, route: '/reset-password');
    await tester.enterText(
      find.byKey(const ValueKey('reset-password-email')),
      'wrong',
    );
    await tester.tap(find.byKey(const ValueKey('reset-password-send')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.passwordRecoveryInvalidEmail), findsOneWidget);
  });

  testWidgets(
    'POST содержит только нормализованную почту, успех означает очередь',
    (tester) async {
      var requests = 0;
      await _mount(
        tester,
        route: '/reset-password',
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.path, '/Obmen/V1/User/passwordrecovery');
          expect(jsonDecode(request.body), {'email': 'employee@example.org'});
          return http.Response(
            jsonEncode({'success': true, 'code': 'credentials_queued'}),
            200,
          );
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-password-email')),
        ' Employee@Example.org ',
      );
      await tester.tap(find.byKey(const ValueKey('reset-password-send')));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text(AppStrings.passwordRecoveryQueued), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('reset-password-email')),
        'other@example.org',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reset-password-success')),
        findsNothing,
      );
    },
  );

  for (final entry in {
    'invalid_email': AppStrings.passwordRecoveryInvalidEmail,
    'email_not_found': AppStrings.passwordRecoveryNotFound,
    'access_denied': AppStrings.passwordRecoveryDenied,
    'credentials_unavailable': AppStrings.passwordRecoveryUnavailable,
    'rate_limited': AppStrings.passwordRecoveryRateLimited,
    'recovery_unavailable': AppStrings.passwordRecoveryFailed,
    'unknown': AppStrings.passwordRecoveryFailed,
  }.entries) {
    testWidgets('безопасное сообщение ${entry.key}', (tester) async {
      await _mount(
        tester,
        route: '/reset-password',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'success': false,
              'code': entry.key,
              'error': 'secret server password',
              'message': 'secret server password',
            }),
            400,
          );
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-password-email')),
        'employee@example.org',
      );
      await tester.tap(find.byKey(const ValueKey('reset-password-send')));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('secret server password'), findsNothing);
      expect(
        find.byKey(const ValueKey('reset-password-success')),
        findsNothing,
      );
    });
  }

  testWidgets('повторное нажатие во время запроса не создаёт второе письмо', (
    tester,
  ) async {
    var requests = 0;
    final pending = Completer<http.Response>();
    await _mount(
      tester,
      route: '/reset-password',
      client: MockClient((_) {
        requests++;
        return pending.future;
      }),
    );
    await tester.enterText(
      find.byKey(const ValueKey('reset-password-email')),
      'employee@example.org',
    );
    await tester.tap(find.byKey(const ValueKey('reset-password-send')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reset-password-send')));
    await tester.pump();
    expect(requests, 1);
    pending.complete(
      http.Response('{"success":true,"code":"credentials_queued"}', 200),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.passwordRecoveryQueued), findsOneWidget);
  });

  testWidgets(
    'сбой сети не показывает успешную отправку и позволяет повторить',
    (tester) async {
      await _mount(
        tester,
        route: '/reset-password',
        client: MockClient((_) async {
          throw Exception('secret network detail');
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-password-email')),
        'employee@example.org',
      );
      await tester.tap(find.byKey(const ValueKey('reset-password-send')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.passwordRecoveryFailed), findsOneWidget);
      expect(find.textContaining('secret network detail'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('reset-password-send')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
