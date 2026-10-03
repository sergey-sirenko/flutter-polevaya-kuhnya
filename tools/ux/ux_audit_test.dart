// Диагностический UX-набор: запускается явно, отдельно от регрессии test/.
// Проверяет целевые критерии, поэтому найденные нарушения дают красный тест.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/compatible_version.dart';

const _menu = {
  'weeks': [
    {
      'weekType': 'current',
      'days': [
        {
          'date': '2030-01-02',
          'hasDelivery': true,
          'categories': [
            {
              'categoryId': 'soup',
              'categoryName': 'Первые блюда с длинным названием категории',
              'dishes': [
                {
                  'dishId': 'soup-1',
                  'dishName': 'Суп овощной с цветной капустой (вегетарианский)',
                  'price': 110,
                  'weight': '350',
                },
              ],
            },
          ],
        },
      ],
    },
  ],
};

Future<void> _mount(
  WidgetTester tester, {
  required double width,
  double scale = 1,
  String route = '/menu',
}) async {
  // Диагностический flutter_test вне общего набора test/.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        appConfigProvider.overrideWithValue(
          AppConfig.parse(
            appVersionUrl: 'https://example.invalid/version.json',
            environment: 'test',
            apiBaseUrl: 'https://example.invalid/api/',
            dataBaseUrl: 'https://example.invalid/data/',
          ),
        ),
        httpClientProvider.overrideWithValue(
          MockClient(
            (request) async => http.Response.bytes(
              utf8.encode(
                request.url.path.endsWith('/dishes.json')
                    ? jsonEncode(_menu)
                    : '{}',
              ),
              request.url.path.endsWith('/dishes.json') ? 200 : 404,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        ),
        initialLocationProvider.overrideWithValue(route),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [
    320.0,
    360.0,
    390.0,
    430.0,
    768.0,
    1199.0,
    1200.0,
    1440.0,
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('UX: меню и вход без переполнения $width / $scale', (
        tester,
      ) async {
        await _mount(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FieldKitchenApp)),
        );
        container.read(routerProvider).go('/sign-in');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('sign-in-login')), findsOneWidget);
      });
    }
  }

  for (final width in [390.0, 1440.0]) {
    for (final route in ['/menu', '/sign-in']) {
      testWidgets('UX: семантические подписи $route $width', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          await _mount(tester, width: width, route: route);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        } finally {
          handle.dispose();
        }
      });
      testWidgets('UX: области нажатия минимум 44 px $route $width', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        try {
          await _mount(tester, width: width, route: route);
          // Геометрический критерий проекта; не запуск и не приёмка iOS.
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        } finally {
          handle.dispose();
        }
      });
    }
  }
}
