import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';

final config = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

Future<String> fixture(String name) =>
    File('test/fixtures/api/$name.json').readAsString();

ProviderContainer mount(http.Client client) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      httpClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Ждёт первый неотложный (не loading) результат, как `untilStatus` для
/// SessionController: избегает `.future`, который здесь ненадёжен при отказе.
Future<AsyncValue<List<MenuWeek>>> settled(ProviderContainer container) async {
  final current = container.read(menuControllerProvider);
  if (!current.isLoading) return current;
  final completer = Completer<AsyncValue<List<MenuWeek>>>();
  final subscription = container.listen(menuControllerProvider, (
    previous,
    next,
  ) {
    if (!next.isLoading && !completer.isCompleted) completer.complete(next);
  });
  try {
    return await completer.future.timeout(const Duration(seconds: 3));
  } finally {
    subscription.close();
  }
}

void main() {
  test('успешная загрузка переводит состояние в AsyncData с блюдами', () async {
    final body = await fixture('menu_with_dishes');
    final container = mount(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final value = await settled(container);
    expect(value.hasValue, isTrue);
    final weeks = value.requireValue;
    expect(weeks, hasLength(1));
    expect(
      weeks.single.days.single.categories.single.dishes.single.dishName,
      contains('Суп'),
    );
  });

  test('отказ сети переводит состояние в AsyncError', () async {
    final container = mount(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    final value = await settled(container);
    expect(value.hasError, isTrue);
    expect(value.hasValue, isFalse);
  });

  test('reload запрашивает данные снова и заменяет состояние', () async {
    var useEmpty = true;
    final emptyBody = await fixture('public_menu_empty');
    final dishesBody = await fixture('menu_with_dishes');
    final container = mount(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(useEmpty ? emptyBody : dishesBody),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final first = await settled(container);
    expect(first.requireValue, isEmpty);

    useEmpty = false;
    await container.read(menuControllerProvider.notifier).reload();
    final weeks = container.read(menuControllerProvider).requireValue;
    expect(weeks, hasLength(1));
  });
}
