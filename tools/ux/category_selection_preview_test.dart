// FL-UX-29: синтетические HTTP-ответы, без живых действий.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';

import '../../test/features/menu/menu_page_test.dart' as menu;

void main() {
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
      testWidgets('Выбор длинной категории $width / $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1100);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final raw = jsonDecode(await menu.fixture(tester, 'menu_with_dishes'));
        final categories = raw['weeks'][0]['days'][0]['categories'] as List;
        final dish = Map<String, dynamic>.from(categories[0]['dishes'][0]);
        List<Map<String, dynamic>> copies(String prefix) => [
          for (var i = 0; i < 12; i++)
            {
              ...dish,
              'dishId': '$prefix-$i',
              'dishName': '$prefix $i',
              'imagePath': null,
            },
        ];
        categories[0]['dishes'] = copies('Суп');
        const name = 'БЛЮДА ДЛЯ ДИЕТ (Без: соли, сахара, масла, специй...)';
        categories.add({
          'categoryId': 'diet',
          'categoryName': name,
          'categoryOrder': 2,
          'dishes': copies('Диетическое блюдо'),
        });
        await menu.mountMenuPage(
          tester,
          menu.menuClient(jsonEncode(raw)),
          realFont: true,
        );
        if (width < 600) {
          ProviderScope.containerOf(tester.element(find.byType(MenuPage)))
              .read(orderSheetProvider.notifier)
              .toggle(OrderSheet.categories);
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.descendant(
            of: find.byKey(
              ValueKey(
                width < 600 ? 'order-category-sheet' : 'menu-category-column',
              ),
            ),
            matching: find.widgetWithText(TextButton, name),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byKey(const ValueKey('menu-dishes-scroll'));
        final heading = find.descendant(of: scroll, matching: find.text(name));
        if (width < 600) {
          expect(
            tester.getBottomLeft(heading).dy,
            lessThanOrEqualTo(tester.getTopLeft(scroll).dy + 0.1),
          );
          expect(
            find.byKey(const ValueKey('menu-selected-category')),
            findsOneWidget,
          );
        } else {
          expect(
            tester.getTopLeft(heading).dy,
            lessThan(tester.getTopLeft(scroll).dy + 20),
          );
        }
        expect(find.textContaining('К сохранению'), findsNothing);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('ux-menu-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            'docs/testing/FL-UX-29/menu-${width.toInt()}-${(scale * 100).toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
