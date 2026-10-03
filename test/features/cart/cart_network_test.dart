import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';

void main() {
  final config = AppConfig.parse(
    appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
    environment: 'test',
    apiBaseUrl: 'https://example.test/api/',
    dataBaseUrl: 'https://example.test/data/',
  );

  SessionApi apiWith(MockClient client) {
    return SessionApi(
      api: ApiClient(config: config, client: client),
      credentials: const SessionCredentials(
        token: 'tok',
        deviceId: '11111111-1111-4111-8111-111111111111',
      ),
      isCurrent: () => true,
      onUnauthorized: () async {},
    );
  }

  test('basketstate возвращает revision по датам', () async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/V1/Orders/basketstate'));
      return http.Response(
        jsonEncode({
          'success': true,
          'states': [
            {'date': '2030-01-02T00:00:00', 'revision': 'rev-a'},
            {'date': '2030-01-03T00:00:00', 'revision': 'none'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = CartRepository(sessionApi: apiWith(client));
    final revisions = await repo.loadRevisions(['2030-01-02', '2030-01-03']);
    expect(revisions['2030-01-02'], 'rev-a');
    expect(revisions['2030-01-03'], 'none');
  });

  test(
    'потеря ответа помечается outcomeUnknown и не очищает корзину снаружи',
    () async {
      final client = MockClient((request) async {
        throw http.ClientException('offline');
      });
      final repo = CartRepository(sessionApi: apiWith(client));
      try {
        await repo.submitBasket({
          'submissionId': '11111111-1111-4111-8111-111111111111',
          'order': [],
        });
        fail('ожидался ApiException');
      } on ApiException catch (error) {
        expect(error.outcomeUnknown, isTrue);
        expect(error.kind, ApiErrorKind.network);
      }
    },
  );

  test(
    'basketresult not_found возвращает null для безопасного повтора',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/V1/Orders/basketresult'));
        return http.Response(
          jsonEncode({
            'success': false,
            'code': 'not_found',
            'message': 'Нет квитанции',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repo = CartRepository(sessionApi: apiWith(client));
      expect(
        await repo.readSubmissionResult('11111111-1111-4111-8111-111111111111'),
        isNull,
      );
    },
  );

  test('истёкшая сессия на basket требует reauth', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'success': false,
          'code': 'invalid_session',
          'message': 'Сессия недействительна',
        }),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = CartRepository(sessionApi: apiWith(client));
    try {
      await repo.submitBasket({
        'submissionId': '11111111-1111-4111-8111-111111111111',
        'order': [],
      });
      fail('ожидался ApiException');
    } on ApiException catch (error) {
      expect(error.requiresReauth, isTrue);
      expect(error.outcomeUnknown, isFalse);
    }
  });
}
