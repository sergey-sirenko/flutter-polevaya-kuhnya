// Локальные превью FL-UX-19: обезличенные данные, без живого API.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/features/site/site_pages.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';

import '../../test/features/menu/menu_page_test.dart' as menu;

void _nothing() {}

Future<void> _capture(WidgetTester tester, String name, Finder target) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(target);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('docs/testing/FL-UX-19/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
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
  for (final width in [390.0, 650.0, 1440.0]) {
    testWidgets('Главная: равные категории, Arial, $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1100);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const names = [
        'ПЕРВЫЕ БЛЮДА',
        'ВТОРЫЕ БЛЮДА',
        'БЛЮДА ДЛЯ ДИЕТ (Без: соли, сахара, масла, специй...)',
        'САЛАТЫ ЗАПРАВЛЕННЫЕ И ЗАКУСКИ',
        'САЛАТЫ НЕ ЗАПРАВЛЕННЫЕ',
        'ЗАПРАВКИ К САЛАТАМ И СОУСЫ',
        'ВЫПЕЧКА И БЛИНЫ',
        'ПРОЧЕЕ',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(
            textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Arial'),
          ),
          home: RepaintBoundary(
            key: const ValueKey('categories-preview'),
            child: SiteHomePage(
              destinations: const SiteDestinations(
                onHome: _nothing,
                onMenu: _nothing,
                onAbout: _nothing,
                onDelivery: _nothing,
                onHowToOrder: _nothing,
                onContacts: _nothing,
                onOffer: _nothing,
                onPrivacy: _nothing,
                onAboutApp: _nothing,
              ),
              categories: [
                for (var i = 0; i < names.length; i++)
                  SiteHomeCategory(id: '$i', name: names[i]),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('site-category-0'));
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      final size = tester.getSize(first);
      for (var i = 1; i < names.length; i++) {
        final other = tester.getSize(find.byKey(ValueKey('site-category-$i')));
        expect(other.height, closeTo(size.height, 0.001));
        expect(other.width, closeTo(size.width, 0.001));
      }
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        'home-$width',
        find.byKey(const ValueKey('categories-preview')),
      );
    });
  }
  testWidgets('Меню 390: без верхних категорий, Arial', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final raw = jsonDecode(await menu.fixture(tester, 'menu_with_dishes'));
    raw['weeks'][0]['days'][0]['categories'][0]['dishes'][0]['imagePath'] =
        null;
    await menu.mountMenuPage(
      tester,
      menu.menuClient(jsonEncode(raw)),
      realFont: true,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(
      tester,
      'menu-390',
      find.byKey(const ValueKey('ux-menu-preview')),
    );
  });
}
