import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() {
  final config = AppConfig.parse(
    environment: 'test',
    apiBaseUrl: 'https://api.example.test/Obmen/',
    dataBaseUrl: 'https://data.example.test/data/',
  );

  test(
    'POST отправляется один раз в API как JSON без автоматического токена',
    () async {
      var calls = 0;
      final client = ApiClient(
        config: config,
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(
            request.url.toString(),
            'https://api.example.test/Obmen/V1/User/login',
          );
          expect(request.headers['content-type'], contains('application/json'));
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.body, '{"login":"test-user"}');
          return http.Response('{"success":true,"user":{}}', 200);
        }),
      );

      final result = await client.postJson('V1/User/login', {
        'login': 'test-user',
      });
      expect(result['success'], isTrue);
      expect(calls, 1);
    },
  );

  test('публичный JSON идёт на отдельный origin без токена', () async {
    final client = ApiClient(
      config: config,
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.followRedirects, isFalse);
        expect(
          request.url.toString(),
          'https://data.example.test/data/dishes.json',
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.body, isEmpty);
        return http.Response('[{"id":1}]', 200);
      }),
    );

    expect(await client.getDataJson('dishes.json'), isA<List<dynamic>>());
  });

  test('старый HTTP 400 и новый code нормализуются как бизнес-отказ', () async {
    for (final fixture in <String>[
      '{"success":false,"error":"Неверный токен"}',
      '{"success":false,"code":"rate_limited","message":"Позже","error":""}',
    ]) {
      final client = ApiClient(
        config: config,
        client: MockClient((_) async => utf8Response(fixture, 400)),
      );
      await expectLater(
        client.postJson('V1/User/login', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.business)
              .having((e) => e.invalidSession, 'invalidSession', isFalse)
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    }
  });

  test(
    '401 означает недействительную сессию даже без JSON; 403 отделён',
    () async {
      for (final status in <int>[401, 403]) {
        final client = ApiClient(
          config: config,
          client: MockClient((_) async => http.Response('error', status)),
        );
        await expectLater(
          client.postJson('V1/User/login', {}),
          throwsA(
            isA<ApiException>()
                .having(
                  (e) => e.invalidSession,
                  'invalidSession',
                  status == 401,
                )
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
      }
    },
  );

  test('успех HTTP с success false не считается успешной записью', () async {
    final client = ApiClient(
      config: config,
      client: MockClient(
        (_) async => utf8Response(
          '{"success":false,"code":"invalid_code","message":"Код неверен"}',
          200,
        ),
      ),
    );
    await expectLater(
      client.postJson('V1/User/registrationconfirm', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.business)
            .having((e) => e.code, 'code', 'invalid_code'),
      ),
    );
  });

  test(
    'HTTP 500, невалидный JSON и отсутствующий success различаются',
    () async {
      for (final fixture in <(int, String, ApiErrorKind)>[
        (500, '<html>Ошибка</html>', ApiErrorKind.http),
        (200, '<html>Ошибка</html>', ApiErrorKind.format),
        (200, '{"message":"ok"}', ApiErrorKind.format),
      ]) {
        final client = ApiClient(
          config: config,
          client: MockClient((_) async => utf8Response(fixture.$2, fixture.$1)),
        );
        await expectLater(
          client.postJson('V1/User/login', {}),
          throwsA(
            isA<ApiException>().having((e) => e.kind, 'kind', fixture.$3),
          ),
        );
      }
    },
  );

  test('HTTP-сбой не маскируется неверным форматом тела', () async {
    final client = ApiClient(
      config: config,
      client: MockClient((_) async => http.Response('["gateway"]', 503)),
    );
    await expectLater(
      client.postJson('V1/User/login', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.http)
            .having((e) => e.statusCode, 'statusCode', 503),
      ),
    );
  });

  test(
    'ошибка публичных данных не получает признак неизвестной записи',
    () async {
      final client = ApiClient(
        config: config,
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      await expectLater(
        client.getDataJson('dishes.json'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.http)
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse),
        ),
      );
    },
  );

  test(
    'таймаут записи помечает неизвестный исход и не повторяет запрос',
    () async {
      var calls = 0;
      final client = ApiClient(
        config: config,
        timeout: const Duration(milliseconds: 5),
        client: MockClient((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{"success":true}', 200);
        }),
      );
      await expectLater(
        client.postJson('V1/Orders/basket', {'order': <Object>[]}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue),
        ),
      );
      expect(calls, 1);
    },
  );

  test('сетевая ошибка записи помечает неизвестный исход', () async {
    final client = ApiClient(
      config: config,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      client.postJson('V1/Orders/basket', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.network)
            .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue),
      ),
    );
  });

  test('путь нельзя подменить URL, параметрами или выходом из базы', () async {
    final client = ApiClient(
      config: config,
      client: MockClient((_) async => fail('Сеть не должна вызываться')),
    );
    for (final path in <String>[
      'https://other.example/path',
      '/V1/User/login',
      '../V1/User/login',
      'V1/User/login?token=secret',
      'V1//User/login',
      'V1/%2e%2e/login',
    ]) {
      await expectLater(client.postJson(path, {}), throwsArgumentError);
      await expectLater(client.getDataJson(path), throwsArgumentError);
    }
  });
}

http.Response utf8Response(String body, int statusCode) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
