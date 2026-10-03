// Только локальное визуальное превью. API полностью подменён, реальные записи отсутствуют.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/profile/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreviewEdit extends CartEditController {
  @override
  CartEditState build() => const CartEditState(
    dateKey: '2026-10-05',
    owner: 'synthetic-preview',
    revision: 'preview',
  );
}

class _PreviewDates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => {'2026-10-05'};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Arial')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('C:/Windows/Fonts/arial.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final page in ['profile', 'cart']) {
    for (final width in [390.0, 400.0]) {
      testWidgets('Белая кухня: $page $width, синтетический профиль', (
        tester,
      ) async {
        // Диагностический flutter_test вне общего каталога test/.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        // ignore: invalid_use_of_visible_for_testing_member
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final menu = File('docs/design/FL-DESIGN-01/menu-snapshot.json')
            .readAsStringSync();
        final container = ProviderContainer(
          overrides: [
            sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
            sessionProfileProvider.overrideWithValue(
              UserProfile.fromUserJson({
                'name': 'Пример организации',
                'employee': 'Пример сотрудника',
                'login': '000',
                'email': 'example@example.invalid',
                'DiscountPercentage': 0,
                'DiscountClient': 0,
                'DiscountPromotion': 0,
                'MinimumPaymentAmount': 0,
                'MinimumOrderAmount': 0,
                'Limit': 0,
              }),
            ),
            appConfigProvider.overrideWithValue(
              AppConfig.parse(
                environment: 'test',
                apiBaseUrl: 'https://example.invalid/api/',
                dataBaseUrl: 'https://example.invalid/data/',
                appVersionUrl: 'https://example.invalid/version.json',
              ),
            ),
            menuAllowedDatesProvider.overrideWith(_PreviewDates.new),
            cartEditControllerProvider.overrideWith(_PreviewEdit.new),
            httpClientProvider.overrideWithValue(
              MockClient((request) async {
                if (request.url.path.endsWith('/dishes.json')) {
                  return http.Response.bytes(
                    utf8.encode(menu),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }
                if (request.url.path.endsWith('/emailchangestatus')) {
                  return http.Response(
                    jsonEncode({
                      'success': true,
                      'code': 'email_change_status',
                      'email': 'example@example.invalid',
                      'canChangeEmail': false,
                    }),
                    200,
                  );
                }
                return http.Response('{}', 404);
              }),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              home: RepaintBoundary(
                key: const ValueKey('preview'),
                child: page == 'profile'
                    ? const ProfilePage()
                    : const CartPage(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (page == 'cart') {
          final day = container
              .read(menuControllerProvider)
              .requireValue
              .expand((week) => week.days)
              .firstWhere((day) => day.dateKey == '2026-10-05');
          final dishes = day.categoriesSorted.first.dishesSorted;
          container.read(cartDraftProvider.notifier).replaceAll({
            day.dateKey: {dishes.first.dishId: 2, dishes[1].dishId: 1},
          });
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final output = File(
            'docs/testing/FL-DESIGN-02/$page-${width.toInt()}-synthetic.png',
          );
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
