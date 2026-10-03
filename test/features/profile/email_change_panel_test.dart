import '../../support/compatible_version.dart';

import 'dart:async';
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
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/features/profile/email_change_panel.dart';

final _config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

const _requestId = '12345678-1234-4123-8123-123456789abc';
const _requestId2 = '87654321-4321-4321-8321-cba987654321';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  MockClient client, {
  DateTime Function()? now,
}) async {
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
        if (now != null) emailChangeClockProvider.overrideWithValue(now),
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

http.Response _json(Map<String, Object?> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('подтверждение обновляет профиль без потери сессии', (
    tester,
  ) async {
    var statusCalls = 0;
    var confirms = 0;
    late SessionStorage storage;
    final container = await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {'name': 'Test', 'email': 'old@example.test'},
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          statusCalls++;
          expect(body.keys.toSet(), {'token', 'deviceId'});
          expect(body['token'], 'synthetic-token');
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': 'old@example.test',
            'canChangeEmail': true,
          });
        }
        if (path.endsWith('/emailchangestart')) {
          expect(body['email'], 'new@example.test');
          expect(body.containsKey('password'), isFalse);
          return _json({
            'success': true,
            'code': 'code_sent',
            'requestId': _requestId,
            'retryAfter': 60,
            'expiresIn': 600,
          });
        }
        if (path.endsWith('/emailchangeconfirm')) {
          confirms++;
          expect(body['requestId'], _requestId);
          expect(body['verificationCode'], '001234');
          return _json({
            'success': true,
            'code': 'email_changed',
            'email': 'new@example.test',
          });
        }
        fail('Неожиданный запрос $path');
      }),
    );
    storage = container.read(sessionStorageProvider);
    expect(container.read(sessionStatusProvider), SessionStatus.signedIn);
    expect(statusCalls, 1);
    expect(find.textContaining('old@example.test'), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('email-change-open')));
    await tester.enterText(
      find.byKey(const ValueKey('email-change-new')),
      'new@example.test',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('email-change-start')));
    expect(find.text(AppStrings.emailChangeCodeSent), findsOneWidget);
    expect(find.text(_requestId), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('email-change-code')),
      '001234',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('email-change-confirm')),
    );

    expect(confirms, 1);
    expect(find.text(AppStrings.emailChangeSuccess), findsOneWidget);
    expect(find.textContaining('new@example.test'), findsOneWidget);
    expect(container.read(sessionProfileProvider)?.email, 'new@example.test');
    expect(container.read(sessionStatusProvider), SessionStatus.signedIn);
    expect(await storage.readToken(), 'synthetic-token');
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/profile',
    );
  });

  testWidgets('email_unchanged не создаёт код и сохраняет сессию', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {'email': 'same@example.test'},
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': 'same@example.test',
            'canChangeEmail': true,
          });
        }
        if (path.endsWith('/emailchangestart')) {
          return _json({
            'success': true,
            'code': 'email_unchanged',
            'email': 'same@example.test',
          });
        }
        fail('Неожиданный запрос $path');
      }),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('email-change-open')));
    await tester.enterText(
      find.byKey(const ValueKey('email-change-new')),
      'same@example.test',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('email-change-start')));
    expect(find.text(AppStrings.emailChangeUnchanged), findsOneWidget);
    expect(find.byKey(const ValueKey('email-change-code')), findsNothing);
    expect(container.read(sessionStatusProvider), SessionStatus.signedIn);
  });

  testWidgets('повтор заменяет requestId; отмена игнорирует поздний ответ', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final sent = Completer<void>();
    var now = DateTime(2026, 9, 27);
    await _mount(
      tester,
      MockClient((request) async {
        final path = request.url.path;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (path.endsWith('/login') && !body.containsKey('password')) {
          return _json({
            'success': true,
            'user': {'email': 'a@b.c'},
          });
        }
        if (path.endsWith('/emailchangestatus')) {
          return _json({
            'success': true,
            'code': 'email_change_status',
            'email': 'a@b.c',
            'canChangeEmail': true,
          });
        }
        if (path.endsWith('/emailchangestart')) {
          return _json({
            'success': true,
            'code': 'code_sent',
            'requestId': _requestId,
            'retryAfter': 0,
            'expiresIn': 600,
          });
        }
        if (path.endsWith('/emailchangeresend')) {
          expect(body['requestId'], _requestId);
          sent.complete();
          return pending.future;
        }
        fail('Неожиданный запрос $path');
      }),
      now: () => now,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('email-change-open')));
    await tester.enterText(
      find.byKey(const ValueKey('email-change-new')),
      'new@example.test',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('email-change-start')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('email-change-resend')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('email-change-resend')));
    await tester.pump();
    await sent.future;
    await tester.tap(find.byKey(const ValueKey('email-change-cancel')));
    await tester.pump();
    pending.complete(
      _json({
        'success': true,
        'code': 'code_sent',
        'requestId': _requestId2,
        'retryAfter': 60,
        'expiresIn': 500,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.emailChangeCanceled), findsOneWidget);
    expect(find.byKey(const ValueKey('email-change-code')), findsNothing);
    expect(find.text(_requestId2), findsNothing);
  });

  testWidgets('canChangeEmail false скрывает форму', (tester) async {
    await _mount(
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
        fail('Неожиданный запрос $path');
      }),
    );
    expect(find.text(AppStrings.emailChangeNotAllowed), findsOneWidget);
    expect(find.byKey(const ValueKey('email-change-open')), findsNothing);
  });
}
