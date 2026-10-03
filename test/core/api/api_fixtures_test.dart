import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() {
  final config = AppConfig.parse(
    appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
    environment: 'test',
    apiBaseUrl: 'https://api.example.test/Obmen/',
    dataBaseUrl: 'https://data.example.test/data/',
  );

  Future<String> fixture(String name) =>
      File('test/fixtures/api/$name.json').readAsString();

  Future<ApiClient> clientFor(String name, int status) async {
    final body = await fixture(name);
    return ApiClient(
      config: config,
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body),
          status,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
  }

  test('все локальные ответы являются JSON без реальных реквизитов', () async {
    final names = <String>[
      'login_success',
      'login_with_history',
      'menudates_available',
      'menudates_empty',
      'legacy_error_400',
      'coded_error_400',
      'session_expired_401',
      'server_error_500',
      'public_menu_empty',
    ];
    for (final name in names) {
      final body = await fixture(name);
      expect(jsonDecode(body), isA<Map<String, dynamic>>(), reason: name);
      expect(body, isNot(contains('password')), reason: name);
      expect(body, isNot(contains('deviceId')), reason: name);
    }
  });

  test('успех и пустые данные проходят через общий транспорт', () async {
    final login = await clientFor('login_success', 200);
    final response = await login.postJson('V1/User/login', {});
    expect(response['token'], 'FIXTURE_TOKEN_NOT_VALID');
    expect((response['user'] as Map<String, dynamic>)['order'], isEmpty);

    final history = await clientFor('login_with_history', 200);
    final profile = await history.postJson('V1/User/login', {});
    expect(profile.containsKey('token'), isFalse);
    expect(
      ((profile['user'] as Map<String, dynamic>)['order'] as List),
      hasLength(1),
    );

    for (final name in ['menudates_available', 'menudates_empty']) {
      final api = await clientFor(name, 200);
      final dates = (await api.postJson(
        'V1/Orders/menudates',
        {},
      ))['menudates'];
      expect(dates, isA<List<dynamic>>(), reason: name);
    }

    final menu = await clientFor('public_menu_empty', 200);
    final data = await menu.getDataJson('dishes.json');
    expect((data as Map<String, dynamic>)['weeks'], isEmpty);
  });

  test('старая ошибка, код и 500 различаются', () async {
    for (final case_ in <(String, int, ApiErrorKind, String?)>[
      ('legacy_error_400', 400, ApiErrorKind.business, null),
      ('coded_error_400', 400, ApiErrorKind.business, 'rate_limited'),
      ('server_error_500', 500, ApiErrorKind.http, null),
    ]) {
      final api = await clientFor(case_.$1, case_.$2);
      await expectLater(
        api.postJson('V1/User/login', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', case_.$3)
              .having((e) => e.code, 'code', case_.$4)
              .having((e) => e.invalidSession, 'invalidSession', isFalse),
        ),
      );
    }
  });

  test('только целевой HTTP 401 помечает сессию недействительной', () async {
    final api = await clientFor('session_expired_401', 401);
    await expectLater(
      api.postJson('V1/User/login', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)
            .having((e) => e.invalidSession, 'invalidSession', isTrue)
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });
}
