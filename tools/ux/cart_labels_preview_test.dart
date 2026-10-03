// Локальное превью FL-UX-29. Все HTTP-ответы синтетические, записи в 1С нет.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/features/cart/cart_edit_flow_test.dart'
    show Harness, date, other;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Arial')..addFont(
          Future.value(
            ByteData.sublistView(
              File('C:/Windows/Fonts/arial.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [390.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('FL-UX-29 $width текст $scale', (tester) async {
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        // ignore: invalid_use_of_visible_for_testing_member
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1100);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = Harness();
        await tester.runAsync(() async {
          await h.init();
          await h.edit.begin(date);
          h.draft.clearDay(date);
          h.draft.increment(other, 'dish');
          await h.edit.begin(other);
          await h.edit.persistNow();
        });
        final boundaryKey = GlobalKey();
        h.container.read(routerProvider).go('/cart');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp.router(
                theme: AppTheme.light.copyWith(
                  textTheme: AppTheme.light.textTheme.apply(
                    fontFamily: 'Arial',
                  ),
                  primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
                    fontFamily: 'Arial',
                  ),
                ),
                routerConfig: h.container.read(routerProvider),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('cart-tab-$other')),
        );
        await tester.tap(find.byKey(const ValueKey('cart-tab-$other')));
        await tester.pumpAndSettle();
        expect(h.container.read(menuSelectionProvider)?.dateKey, other);
        expect(find.byKey(const ValueKey('cart-day-tabs')), findsOneWidget);
        expect(find.text('Ср!\n02.01'), findsOneWidget);
        expect(find.byKey(const ValueKey('cart-save-all')), findsOneWidget);
        expect(find.byKey(const ValueKey('cart-cancel-all')), findsOneWidget);
        expect(find.textContaining('К сохранению'), findsNothing);
        expect(find.byKey(ValueKey('cart-day-total-$other')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 1);
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory('docs/testing/FL-UX-29')
            ..createSync(recursive: true);
          File(
            '${directory.path}/cart-${width.toInt()}-${(scale * 100).toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      });
    }
  }
}
