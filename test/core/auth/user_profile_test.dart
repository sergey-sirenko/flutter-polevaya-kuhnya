import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/auth/session_repository.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/cart/pricing_normalize.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fullJson = jsonDecode(
    File('test/fixtures/api/login_token_profile_full.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('UserProfile', () {
    test('разбирает условия, профиль и историю из полной фикстуры', () {
      final profile = UserProfile.fromUserJson(fullJson['user']);
      expect(profile.login, 'fixture-user');
      expect(profile.name, 'Fixture Org');
      expect(profile.employee, 'Fixture Employee');
      expect(profile.orders, hasLength(1));
      expect(profile.orders.single.sum, 171);
      expect(profile.orders.single.dishes.single.name, 'Тестовое блюдо');

      final conditions = clientPricingConditionsFromUser(profile.rawUser);
      expect(conditions.discountPercentage, 10);
      expect(conditions.discountClient, 50);
      expect(conditions.isDiscountPromotion, isTrue);
      expect(conditions.minimumPaymentAmount, 100);
      expect(conditions.minimumOrderAmount, 200);
      expect(conditions.limit, 500);
      expect(conditions.isWeekLimitPeriod, isFalse);
    });

    test('пустой user допустим для подтверждения сессии', () {
      final profile = UserProfile.fromUserJson(<String, Object?>{});
      expect(profile.login, isEmpty);
      expect(profile.orders, isEmpty);
    });
  });

  group('SessionRepository.verify', () {
    late SessionStorage storage;
    final config = AppConfig.parse(
      environment: 'test',
      apiBaseUrl: 'https://api.example.test/Obmen/',
      dataBaseUrl: 'https://data.example.test/data/',
    );

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storage = SessionStorage(config: config);
    });

    test('успешный token refresh возвращает профиль и сохраняет токен ответа', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/Obmen/V1/User/login');
        final body = jsonDecode(request.body) as Map;
        expect(body.keys, unorderedEquals(['token', 'deviceId']));
        return http.Response.bytes(
          utf8.encode(jsonEncode(fullJson)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repo = SessionRepository(
        api: ApiClient(config: config, client: client),
        storage: storage,
      );
      final verified = await repo.verify(
        const SessionCredentials(
          token: 'old-token',
          deviceId: '00000000-0000-4000-8000-000000000099',
        ),
      );
      expect(verified.credentials.token, 'FIXTURE_TOKEN_REFRESH_SAME');
      expect(verified.profile.login, 'fixture-user');
      expect(verified.profile.orders, hasLength(1));
    });

    test('неверный токен (HTTP 400) пробрасывает ApiException', () async {
      final body = File(
        'test/fixtures/api/login_token_invalid.json',
      ).readAsBytesSync();
      final client = MockClient(
        (_) async => http.Response.bytes(
          body,
          400,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final repo = SessionRepository(
        api: ApiClient(config: config, client: client),
        storage: storage,
      );
      await expectLater(
        repo.verify(
          const SessionCredentials(token: 'bad', deviceId: 'dev'),
        ),
        throwsA(isA<Object>()),
      );
    });

    test('отказ доступа (HTTP 400) пробрасывает ApiException', () async {
      final body = File(
        'test/fixtures/api/login_token_access_denied.json',
      ).readAsBytesSync();
      final client = MockClient(
        (_) async => http.Response.bytes(
          body,
          400,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final repo = SessionRepository(
        api: ApiClient(config: config, client: client),
        storage: storage,
      );
      await expectLater(
        repo.verify(
          const SessionCredentials(token: 'tok', deviceId: 'foreign-device'),
        ),
        throwsA(isA<Object>()),
      );
    });
  });
}
