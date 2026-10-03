import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';

final config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

http.Response accepted() => http.Response('{"success":true,"user":{}}', 200);

Future<void> untilStatus(
  ProviderContainer container,
  SessionStatus status,
) async {
  final done = Completer<void>();
  final subscription = container.listen(sessionControllerProvider, (_, value) {
    if (value.status == status && !done.isCompleted) done.complete();
  }, fireImmediately: true);
  try {
    await done.future.timeout(const Duration(seconds: 3));
  } finally {
    subscription.close();
  }
}

ProviderContainer mount(SessionStorage storage, MockClient client) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      sessionStorageProvider.overrideWithValue(storage),
      httpClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SessionStorage storage;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = SessionStorage(config: config);
  });

  test('без токена гость определяется без обращения к API', () async {
    final container = mount(
      storage,
      MockClient((_) async => fail('Не должно быть запроса')),
    );
    await untilStatus(container, SessionStatus.signedOut);
    expect(container.read(sessionApiProvider), isNull);
  });

  test('сохранённый токен даёт вход только после подтверждения', () async {
    await storage.writeToken('test-token');
    final reply = Completer<http.Response>();
    final sent = Completer<http.Request>();
    final container = mount(
      storage,
      MockClient((request) {
        sent.complete(request);
        return reply.future;
      }),
    );
    container.read(sessionControllerProvider);
    final request = await sent.future;
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.restoring,
    );
    expect(container.read(sessionApiProvider), isNull);
    expect(container.read(sessionProfileProvider), isNull);
    final body = jsonDecode(request.body) as Map;
    expect(body.keys, unorderedEquals(['token', 'deviceId']));
    expect(body['deviceId'], await storage.deviceId());
    expect(request.url.path, '/Obmen/V1/User/login');
    reply.complete(
      http.Response.bytes(
        utf8.encode('{"success":true,"user":{"name":"Свежий профиль"}}'),
        200,
      ),
    );
    await untilStatus(container, SessionStatus.signedIn);
    expect(await storage.readToken(), 'test-token');
    expect(container.read(sessionProfileProvider)?.name, 'Свежий профиль');
  });

  test('повторный старт получает профиль заново только по токену', () async {
    await storage.writeToken('test-token');
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(jsonDecode(request.body), {
        'token': 'test-token',
        'deviceId': await storage.deviceId(),
      });
      return http.Response.bytes(
        utf8.encode('{"success":true,"user":{"name":"Версия $requests"}}'),
        200,
      );
    });
    final first = mount(storage, client);
    await untilStatus(first, SessionStatus.signedIn);
    expect(first.read(sessionProfileProvider)?.name, 'Версия 1');
    first.dispose();

    final second = mount(storage, client);
    expect(second.read(sessionProfileProvider), isNull);
    await untilStatus(second, SessionStatus.signedIn);
    expect(second.read(sessionProfileProvider)?.name, 'Версия 2');
    expect(requests, 2);
  });

  for (final status in [400, 401, 503]) {
    test('восстановление HTTP $status очищает токен только при 401', () async {
      await storage.writeToken('test-token');
      final container = mount(
        storage,
        MockClient(
          (_) async =>
              http.Response('{"success":false,"error":"rejected"}', status),
        ),
      );
      await untilStatus(
        container,
        status == 401 ? SessionStatus.signedOut : SessionStatus.unavailable,
      );
      expect(await storage.readToken(), status == 401 ? isNull : 'test-token');
      expect(container.read(sessionApiProvider), isNull);
      expect(container.read(sessionProfileProvider), isNull);
    });
  }

  for (final fixture in <(String, int, String)>[
    (
      '400 invalid_session',
      400,
      '{"success":false,"code":"invalid_session","message":"session","error":""}',
    ),
    (
      '403 device_mismatch',
      403,
      '{"success":false,"code":"device_mismatch","message":"device","error":""}',
    ),
  ]) {
    test('восстановление ${fixture.$1} очищает токен', () async {
      await storage.writeToken('test-token');
      final container = mount(
        storage,
        MockClient((_) async => http.Response(fixture.$3, fixture.$2)),
      );
      await untilStatus(container, SessionStatus.signedOut);
      expect(await storage.readToken(), isNull);
    });
  }

  test(
    'восстановление 403 access_denied сохраняет токен как unavailable',
    () async {
      await storage.writeToken('test-token');
      final container = mount(
        storage,
        MockClient(
          (_) async => http.Response(
            '{"success":false,"code":"access_denied","message":"denied","error":""}',
            403,
          ),
        ),
      );
      await untilStatus(container, SessionStatus.unavailable);
      expect(await storage.readToken(), 'test-token');
    },
  );

  test(
    'ошибка сети сохраняет токен и допускает явную повторную проверку',
    () async {
      await storage.writeToken('test-token');
      var online = false;
      var calls = 0;
      final container = mount(
        storage,
        MockClient((_) async {
          calls++;
          if (!online) throw http.ClientException('offline');
          return accepted();
        }),
      );
      await untilStatus(container, SessionStatus.unavailable);
      expect(calls, 1);
      expect(await storage.readToken(), 'test-token');
      online = true;
      await container.read(sessionControllerProvider.notifier).restore();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.signedIn,
      );
      expect(calls, 2);
    },
  );

  test('ответ без профиля не подтверждает сохранённый токен', () async {
    await storage.writeToken('test-token');
    final container = mount(
      storage,
      MockClient((_) async => http.Response('{"success":true}', 200)),
    );
    await untilStatus(container, SessionStatus.unavailable);
    expect(await storage.readToken(), 'test-token');
  });

  test('logout исключает поздний ответ восстановления', () async {
    await storage.writeToken('old-token');
    final id = await storage.deviceId();
    final reply = Completer<http.Response>();
    final sent = Completer<void>();
    final container = mount(
      storage,
      MockClient((_) {
        sent.complete();
        return reply.future;
      }),
    );
    container.read(sessionControllerProvider);
    await sent.future;
    await container.read(sessionControllerProvider.notifier).signOut();
    reply.complete(accepted());
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(container.read(sessionProfileProvider), isNull);
    expect(await storage.readToken(), isNull);
    expect(await storage.deviceId(), id);
  });

  test('выход удаляет локальный токен до ответа сервера', () async {
    final logoutRequest = Completer<http.Request>();
    final logoutResponse = Completer<http.Response>();
    final container = mount(
      storage,
      MockClient((request) {
        if (request.url.path.endsWith('/logout')) {
          logoutRequest.complete(request);
          return logoutResponse.future;
        }
        return Future.value(accepted());
      }),
    );
    await untilStatus(container, SessionStatus.signedOut);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.signIn((_) async => 'test-token');
    final deviceId = await storage.deviceId();
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedIn,
    );

    await controller.signOut();
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(await storage.readToken(), isNull);
    expect(await storage.deviceId(), deviceId);
    final request = await logoutRequest.future.timeout(
      const Duration(seconds: 3),
    );
    expect(request.url.path, '/Obmen/V1/User/logout');
    expect(jsonDecode(request.body), {
      'token': 'test-token',
      'deviceId': deviceId,
    });

    logoutResponse.complete(
      http.Response('{"success":false,"code":"server_error"}', 503),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
  });

  test('сбой сети при отзыве не возвращает локальную сессию', () async {
    final revokeSent = Completer<void>();
    final container = mount(
      storage,
      MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          revokeSent.complete();
          throw http.ClientException('offline');
        }
        return accepted();
      }),
    );
    await untilStatus(container, SessionStatus.signedOut);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.signIn((_) async => 'test-token');

    await controller.signOut();
    await revokeSent.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(await storage.readToken(), isNull);
  });

  test('поздний login A не заменяет подтверждённый вход B', () async {
    final container = mount(storage, MockClient((_) async => accepted()));
    await untilStatus(container, SessionStatus.signedOut);
    final controller = container.read(sessionControllerProvider.notifier);
    final tokenA = Completer<String>();
    final startedA = Completer<void>();
    final loginA = controller.signIn((_) {
      startedA.complete();
      return tokenA.future;
    });
    await startedA.future;
    await controller.signIn((_) async => 'token-B');
    tokenA.complete('token-A');
    await loginA;
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedIn,
    );
    expect(await storage.readToken(), 'token-B');
  });

  for (final oldStatus in [200, 401]) {
    test(
      'поздний ответ $oldStatus сессии A не раскрывает данные и не удаляет B',
      () async {
        final oldReply = Completer<http.Response>();
        final oldSent = Completer<void>();
        final container = mount(
          storage,
          MockClient((request) {
            if (request.url.path.endsWith('/basket')) {
              oldSent.complete();
              return oldReply.future;
            }
            return Future.value(accepted());
          }),
        );
        await untilStatus(container, SessionStatus.signedOut);
        final controller = container.read(sessionControllerProvider.notifier);
        await controller.signIn((_) async => 'token-A');
        final apiA = container.read(sessionApiProvider)!;
        final pending = apiA.postJson('V1/Orders/basket', {
          'order': <Object>[],
        });
        final assertion = expectLater(
          pending,
          throwsA(isA<StaleSessionException>()),
        );
        await oldSent.future;
        await controller.signIn((_) async => 'token-B');
        oldReply.complete(
          http.Response('{"success":${oldStatus == 200}}', oldStatus),
        );
        await assertion;
        expect(await storage.readToken(), 'token-B');
        expect(
          container.read(sessionControllerProvider).status,
          SessionStatus.signedIn,
        );
        await expectLater(
          apiA.postJson('V1/Orders/menudates', {}),
          throwsA(isA<StaleSessionException>()),
        );
      },
    );
  }

  test('401 защищённого запроса очищает текущую сессию', () async {
    var logoutCalls = 0;
    final container = mount(
      storage,
      MockClient((request) async {
        if (request.url.path.endsWith('/login')) return accepted();
        if (request.url.path.endsWith('/logout')) {
          logoutCalls++;
          return accepted();
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['token'], 'test-token');
        expect(body['deviceId'], await storage.deviceId());
        return http.Response('', 401);
      }),
    );
    await untilStatus(container, SessionStatus.signedOut);
    await container
        .read(sessionControllerProvider.notifier)
        .signIn((_) async => 'test-token');
    await expectLater(
      container.read(sessionApiProvider)!.postJson('V1/Orders/menudates', {}),
      throwsException,
    );
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(await storage.readToken(), isNull);
    expect(container.read(sessionProfileProvider), isNull);
    expect(logoutCalls, 0);
  });

  test('код invalid_session на HTTP 400 завершает сессию', () async {
    final container = mount(
      storage,
      MockClient(
        (request) async => request.url.path.endsWith('/login')
            ? accepted()
            : http.Response(
                '{"success":false,"code":"invalid_session","message":"session"}',
                400,
              ),
      ),
    );
    await untilStatus(container, SessionStatus.signedOut);
    await container
        .read(sessionControllerProvider.notifier)
        .signIn((_) async => 'test-token');
    await expectLater(
      container.read(sessionApiProvider)!.postJson('V1/Orders/menudates', {}),
      throwsException,
    );
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(await storage.readToken(), isNull);
    expect(container.read(sessionProfileProvider), isNull);
  });

  test('сбой сети защищённого запроса не считается истечением', () async {
    final container = mount(
      storage,
      MockClient((request) async {
        if (request.url.path.endsWith('/login')) return accepted();
        throw http.ClientException('offline');
      }),
    );
    await untilStatus(container, SessionStatus.signedOut);
    await container
        .read(sessionControllerProvider.notifier)
        .signIn((_) async => 'test-token');
    await expectLater(
      container.read(sessionApiProvider)!.postJson('V1/Orders/menudates', {}),
      throwsException,
    );
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedIn,
    );
    expect(await storage.readToken(), 'test-token');
    expect(container.read(sessionProfileProvider), isNotNull);
  });

  test('поздний успех после истечения не возвращает личные данные', () async {
    final firstSent = Completer<void>();
    final firstReply = Completer<http.Response>();
    var protectedCalls = 0;
    final container = mount(
      storage,
      MockClient((request) {
        if (request.url.path.endsWith('/login')) {
          return Future.value(accepted());
        }
        protectedCalls++;
        if (protectedCalls == 1) {
          firstSent.complete();
          return firstReply.future;
        }
        return Future.value(http.Response('', 401));
      }),
    );
    await untilStatus(container, SessionStatus.signedOut);
    await container
        .read(sessionControllerProvider.notifier)
        .signIn((_) async => 'test-token');
    final api = container.read(sessionApiProvider)!;
    final late = api.postJson('V1/Orders/menudates', {});
    final lateAssertion = expectLater(
      late,
      throwsA(isA<StaleSessionException>()),
    );
    await firstSent.future;
    await expectLater(api.postJson('V1/Orders/menudates', {}), throwsException);
    firstReply.complete(http.Response('{"success":true,"order":[]}', 200));
    await lateAssertion;
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.signedOut,
    );
    expect(container.read(sessionProfileProvider), isNull);
    expect(await storage.readToken(), isNull);
  });

  test('ошибка записи токена не объявляет вход успешным', () async {
    final failing = FailingStorage()..failWrite = true;
    final container = mount(failing, MockClient((_) async => accepted()));
    await untilStatus(container, SessionStatus.signedOut);
    await expectLater(
      container
          .read(sessionControllerProvider.notifier)
          .signIn((_) async => 'test-token'),
      throwsA(isA<SessionStorageException>()),
    );
    expect(
      container.read(sessionControllerProvider).status,
      SessionStatus.unavailable,
    );
    expect(container.read(sessionApiProvider), isNull);
  });

  test(
    'ошибка удаления закрывает доступ, но не выдаётся за успешный выход',
    () async {
      final failing = FailingStorage();
      final container = mount(failing, MockClient((_) async => accepted()));
      await untilStatus(container, SessionStatus.signedOut);
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.signIn((_) async => 'test-token');
      final oldApi = container.read(sessionApiProvider)!;
      failing.failDelete = true;
      await controller.signOut();
      expect(
        container.read(sessionControllerProvider).status,
        SessionStatus.unavailable,
      );
      expect(container.read(sessionApiProvider), isNull);
      expect(await failing.readToken(), 'test-token');
      await expectLater(
        oldApi.postJson('V1/Orders/menudates', {}),
        throwsA(isA<StaleSessionException>()),
      );
    },
  );
}

class FailingStorage extends SessionStorage {
  FailingStorage() : super(config: config);

  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<void> writeToken(String token) {
    if (failWrite) return Future.error(const SessionStorageException());
    return super.writeToken(token);
  }

  @override
  Future<void> deleteToken() {
    if (failDelete) return Future.error(const SessionStorageException());
    return super.deleteToken();
  }
}
