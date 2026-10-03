import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_repository.dart';

import 'app_version_policy_test.dart' show versionConfig, policyDocument;

void main() {
  test('single anonymous GET per check, independent origin, fresh query, no redirect', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      config: versionConfig,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(policyDocument()), 200);
      }),
    );
    final repo = HttpAppVersionRepository(client, versionConfig);
    await repo.fetch();
    await repo.fetch();
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.method, 'GET');
      expect(request.body, isEmpty);
      expect(request.url.origin, versionConfig.appVersionUri.origin);
      expect(request.url.path, '/version.json');
      expect(request.url.queryParameters.keys, ['check']);
      expect(request.headers.keys.map((e) => e.toLowerCase()), ['accept']);
      expect(request.headers['Accept'], 'application/json');
      expect(request.followRedirects, isFalse);
    }
    expect(requests[0].url.query, isNot(requests[1].url.query));
  });
  test(
    '404, redirect, HTML, bad JSON and legacy rejected without retry',
    () async {
      for (final response in [
        http.Response('{}', 404),
        http.Response('{}', 302),
        http.Response('<html>error</html>', 200),
        http.Response('{', 200),
        http.Response('{1.0:8}', 200),
        http.Response('{"version":"0.1.0","build":8}', 200),
      ]) {
        var calls = 0;
        final client = ApiClient(
          config: versionConfig,
          client: MockClient((_) async {
            calls++;
            return response;
          }),
        );
        await expectLater(
          HttpAppVersionRepository(client, versionConfig).fetch(),
          throwsA(isA<Exception>()),
        );
        expect(calls, 1);
      }
    },
  );
  test('one deadline covers response body; no background repeat', () async {
    var calls = 0;
    final client = ApiClient(
      config: versionConfig,
      versionTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        calls++;
        return Completer<http.Response>().future;
      }),
    );
    await expectLater(
      HttpAppVersionRepository(client, versionConfig).fetch(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.timeout),
      ),
    );
    expect(calls, 1);
    expect(client.timeout, const Duration(seconds: 15));
  });
  test(
    'JSON fractional or exponent integer lexemes rejected on all runtimes',
    () async {
      for (final bad in ['8.0', '8e0', '8.000000000000001', 'true', '"8"']) {
        final source = jsonEncode(policyDocument())
            .replaceAll('"build":8', '"build":$bad');
        final client = ApiClient(
          config: versionConfig,
          client: MockClient((_) async => http.Response(source, 200)),
        );
        await expectLater(
          HttpAppVersionRepository(client, versionConfig).fetch(),
          throwsFormatException,
        );
      }
      final source = jsonEncode(policyDocument())
          .replaceFirst('"schema":1', '"schema":1e0');
      final client = ApiClient(
        config: versionConfig,
        client: MockClient((_) async => http.Response(source, 200)),
      );
      await expectLater(
        HttpAppVersionRepository(client, versionConfig).fetch(),
        throwsFormatException,
      );
    },
  );
  test('prod source and environment independently configured', () async {
    final config = AppConfig.parse(
      environment: 'prod',
      apiBaseUrl: 'https://api.example.test/',
      dataBaseUrl: 'https://data.example.test/',
      appVersionUrl: 'https://new.obedmoscow.ru/version.json',
    );
    final doc = policyDocument();
    (doc['policy'] as Map)['environment'] = 'prod';
    ((((doc['policy'] as Map)['releases'] as Map)['web']) as Map)['url'] =
        'https://new.obedmoscow.ru/';
    final client = ApiClient(
      config: config,
      client: MockClient((request) async {
        expect(request.url.origin, 'https://new.obedmoscow.ru');
        return http.Response(jsonEncode(doc), 200);
      }),
    );
    expect(
      (await HttpAppVersionRepository(
        client,
        config,
      ).fetch()).minimum.toString(),
      '0.1.0+1',
    );
  });
  test('invalid configured endpoints fail before any request', () {
    for (final url in [
      '',
      '/version.json',
      'http://example.test/version.json',
      'https://u:p@example.test/version.json',
      'https://example.test/version.json#f',
      'https://example.test/version.json?a=1',
      'https://example.test/data/version.json',
    ]) {
      expect(
        () => AppConfig.parse(
          environment: 'test',
          apiBaseUrl: 'https://api.example.test/',
          dataBaseUrl: 'https://data.example.test/',
          appVersionUrl: url,
        ),
        throwsStateError,
      );
    }
  });
}
