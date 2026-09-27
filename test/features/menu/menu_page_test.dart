import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';

final config = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

// `testWidgets` блокирует настоящий асинхронный ввод-вывод вне
// `runAsync` (в отличие от `test()` в menu_repository/controller_test.dart,
// где чтение файла работает напрямую): читаем фикстуру только так.
Future<String> fixture(WidgetTester tester, String name) async {
  final body = await tester.runAsync(
    () => File('test/fixtures/api/$name.json').readAsString(),
  );
  return body!;
}

http.Response jsonResponse(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

// Индикатор загрузки анимирован бесконечно, поэтому pumpAndSettle() здесь не
// применяется (тот же приём, что и для восстановления сессии в
// test/app/router_test.dart): по кадру дожидаемся ухода спиннера.
Future<void> mountMenuPage(
  WidgetTester tester,
  http.Client client, {
  bool isTest = true,
  VoidCallback onHome = _doNothing,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        home: MenuPage(isTest: isTest, onHome: onHome),
      ),
    ),
  );
  await settleMenu(tester);
}

Future<void> settleMenu(WidgetTester tester) async {
  await tester.pump();
  for (
    var attempt = 0;
    attempt < 20 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void _doNothing() {}

void main() {
  testWidgets('непустое меню показывает дату, категорию, блюдо и цену', (
    tester,
  ) async {
    final body = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(tester, MockClient((_) async => jsonResponse(body)));
    expect(find.text('2030-01-02'), findsOneWidget);
    expect(find.text('Супы'), findsOneWidget);
    expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
    expect(find.text('190 ₽'), findsOneWidget);
    expect(find.text(AppStrings.testBuild), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пустое опубликованное меню показывает понятное сообщение', (
    tester,
  ) async {
    final body = await fixture(tester, 'public_menu_empty');
    await mountMenuPage(tester, MockClient((_) async => jsonResponse(body)));
    expect(find.text(AppStrings.menuEmptyMessage), findsOneWidget);
  });

  testWidgets('сетевой отказ показывает ошибку, повтор загружает данные', (
    tester,
  ) async {
    var offline = true;
    final dishesBody = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(
      tester,
      MockClient((_) async {
        if (offline) throw http.ClientException('offline');
        return jsonResponse(dishesBody);
      }),
    );
    expect(find.text(AppStrings.menuUnavailable), findsOneWidget);
    expect(find.text(AppStrings.retryLoadMenu), findsOneWidget);

    offline = false;
    await tester.tap(find.text(AppStrings.retryLoadMenu));
    await settleMenu(tester);
    expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопка «На главную» вызывает переданный обработчик', (
    tester,
  ) async {
    final body = await fixture(tester, 'public_menu_empty');
    var homeTapped = false;
    await mountMenuPage(
      tester,
      MockClient((_) async => jsonResponse(body)),
      onHome: () => homeTapped = true,
    );
    expect(homeTapped, isFalse);
    await tester.tap(find.text(AppStrings.home));
    await tester.pumpAndSettle();
    expect(homeTapped, isTrue);
  });
}
