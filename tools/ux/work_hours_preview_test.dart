// Локальные превью FL-UX-20 из ранее сохранённого снимка меню, без живого API.
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

void _nothing() {}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('home-dish-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory =
        Platform.environment['UX_PREVIEW_DIR'] ?? 'docs/testing/FL-UX-20';
    final output = File('$directory/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late List<SiteHomeDish> dishes;
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
    final menu = jsonDecode(
      File('docs/design/FL-DESIGN-01/menu-snapshot.json').readAsStringSync(),
    );
    final day = (menu['weeks'] as List)
        .expand((week) => week['days'] as List)
        .firstWhere((day) => day['date'] == '2026-10-05');
    final categories = (day['categories'] as List).where(
      (category) => (category['categoryName'] as String).contains('ВТОРЫЕ'),
    );
    final records = categories
        .expand((category) => category['dishes'] as List)
        .take(3);
    dishes = [
      for (final dish in records)
        SiteHomeDish(
          id: dish['dishId'],
          name: dish['dishName'],
          price: dish['price'],
          image: Image.memory(
            File('docs/design/FL-DESIGN-01/images/${dish['imagePath']}.jpg')
                .readAsBytesSync(),
            fit: BoxFit.contain,
          ),
        ),
    ];
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('Главная: стрелки и реальные фото, Arial, $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light.copyWith(
            textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Arial'),
          ),
          home: RepaintBoundary(
            key: const ValueKey('home-dish-preview'),
            child: SiteHomePage(
              heroDayKey: '2026-10-05',
              heroDishes: dishes,
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
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(SiteHomePage));
      await tester.runAsync(() async {
        for (final dish in dishes) {
          await precacheImage((dish.image as Image).image, context);
        }
      });
      await tester.pumpAndSettle();
      await _capture(tester, 'home-$width-top');
      final next = find.byKey(const ValueKey('site-hero-next'));
      await tester.ensureVisible(find.byKey(const ValueKey('site-hero-photo')));
      await tester.pumpAndSettle();
      expect(find.text(dishes.first.name), findsOneWidget);
      await _capture(tester, 'home-$width-first');
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text(dishes[1].name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'home-$width-next');
    });
  }
}
