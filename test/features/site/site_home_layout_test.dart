import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';
import 'package:polevaya_kuhnya/features/site/site_pages.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:polevaya_kuhnya/shared/external_link.dart';

SiteDestinations _destinations({
  VoidCallback? onMenu,
  VoidCallback? onDelivery,
}) {
  return SiteDestinations(
    onHome: () {},
    onMenu: onMenu ?? () {},
    onAbout: () {},
    onDelivery: onDelivery ?? () {},
    onHowToOrder: () {},
    onContacts: () {},
    onOffer: () {},
    onPrivacy: () {},
    onAboutApp: () {},
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required double width,
  List<SiteHomeCategory> categories = const [],
  VoidCallback? onMenu,
  VoidCallback? onDelivery,
  ValueChanged<SiteHomeCategory>? onCategory,
  ExternalUrlLauncher? storeLauncher,
  double scale = 1,
  List<SiteHomeDish> dishes = const [],
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: SiteHomePage(
        destinations: _destinations(onMenu: onMenu, onDelivery: onDelivery),
        categories: categories,
        heroDishes: dishes,
        onCategory: onCategory,
        storeLauncher: storeLauncher,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _sameRow(WidgetTester tester, Finder a, Finder b) {
  return (tester.getTopLeft(a).dy - tester.getTopLeft(b).dy).abs() < 8;
}

void main() {
  testWidgets('контакты справа от режима и кнопка открывает доставку', (
    tester,
  ) async {
    var deliveries = 0;
    await _pumpHome(tester, width: 1440, onDelivery: () => deliveries++);
    final hours = find.byKey(const ValueKey('site-home-hours'));
    final contacts = find.byKey(const ValueKey('site-home-contacts'));
    expect(_sameRow(tester, hours, contacts), isTrue);
    expect(
      tester.getTopLeft(contacts).dx,
      greaterThan(tester.getTopRight(hours).dx),
    );
    final copy = find.byKey(const ValueKey('site-hero-copy'));
    final button = find.descendant(
      of: copy,
      matching: find.widgetWithText(OutlinedButton, AppStrings.delivery),
    );
    await tester.tap(button);
    expect(deliveries, 1);
    expect(
      find.descendant(of: contacts, matching: find.byType(ContactLines)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 650.0, 1440.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'стрелки главной $width / текст $scale: переключение и полный текст',
        (tester) async {
          const longName =
              'Говядина отварная с кус-кусом и морковью (Мини порция)';
          await _pumpHome(
            tester,
            width: width,
            scale: scale,
            dishes: const [
              SiteHomeDish(
                id: 'one',
                name: longName,
                price: 190,
                image: ColoredBox(color: Colors.white),
              ),
              SiteHomeDish(
                id: 'two',
                name: 'Суп с овощами',
                price: 110,
                image: ColoredBox(color: Colors.white),
              ),
            ],
          );
          final next = find.byKey(const ValueKey('site-hero-next'));
          final previous = find.byKey(const ValueKey('site-hero-previous'));
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          expect(tester.getSize(next).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(previous).height, greaterThanOrEqualTo(44));
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(longName))
                .didExceedMaxLines,
            isFalse,
          );
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(find.text('Суп с овощами'), findsOneWidget);
          expect(find.text('110 ₽'), findsOneWidget);
          await tester.tap(previous);
          await tester.pumpAndSettle();
          expect(find.text(longName), findsOneWidget);
          expect(find.text('190 ₽'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('нет стрелок для пустой и одиночной витрины', (tester) async {
    await _pumpHome(tester, width: 390);
    expect(find.byKey(const ValueKey('site-hero-next')), findsNothing);
    expect(find.byKey(const ValueKey('site-hero-previous')), findsNothing);
    await _pumpHome(
      tester,
      width: 390,
      dishes: const [
        SiteHomeDish(
          id: 'one',
          name: 'Суп',
          price: 110,
          image: ColoredBox(color: Colors.white),
        ),
      ],
    );
    expect(find.byKey(const ValueKey('site-hero-next')), findsNothing);
    expect(find.byKey(const ValueKey('site-hero-previous')), findsNothing);
    expect(find.text('Суп'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('герой: текст слева от фото на компьютере, сверху на телефоне', (
    tester,
  ) async {
    await _pumpHome(tester, width: 1440);
    final copy = find.byKey(const ValueKey('site-hero-copy'));
    final photo = find.byKey(const ValueKey('site-hero-photo'));
    final hero = find.byKey(const ValueKey('site-home-hero'));
    final copyRect = tester.getRect(copy);
    final photoRect = tester.getRect(photo);
    final heroRect = tester.getRect(hero);
    final leftCenter = heroRect.left + (heroRect.width - 32) / 4;
    expect(copyRect.right, lessThan(photoRect.left));
    expect(copyRect.center.dx, closeTo(leftCenter, 2));
    expect(copyRect.center.dy, closeTo(photoRect.center.dy, 1));
    expect(photoRect.width, 440);
    await _pumpHome(tester, width: 390);
    expect(tester.getRect(copy).bottom, lessThan(tester.getRect(photo).top));
    final image = tester.widget<Image>(
      find.descendant(of: photo, matching: find.byType(Image)),
    );
    expect(
      (image.image as AssetImage).assetName,
      endsWith('app-logo-cb1bbbb6c0df.png'),
    );
    expect(image.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[
    320,
    390,
    599,
    600,
    768,
    769,
    1024,
    1199,
    1200,
    1440,
  ]) {
    for (final scale in <double>[1, 1.6]) {
      testWidgets(
        'главная $width / текст $scale: длинные категории и полный текст',
        (tester) async {
          const longName = 'Блюда для диет (без соли, сахара, масла и специй)';
          await _pumpHome(
            tester,
            width: width,
            scale: scale,
            categories: const [
              SiteHomeCategory(id: 'one', name: longName),
              SiteHomeCategory(id: 'two', name: 'Вторые блюда'),
              SiteHomeCategory(id: 'three', name: 'Салаты'),
              SiteHomeCategory(id: 'four', name: 'Выпечка и блины'),
              SiteHomeCategory(id: 'five', name: '$longName без добавок'),
              SiteHomeCategory(id: 'six', name: 'Заправки к салатам и соусы'),
              SiteHomeCategory(id: 'seven', name: 'Прочее'),
            ],
          );
          final title = find.text(longName);
          final paragraph = tester.renderObject<RenderParagraph>(title);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.widget<Text>(title).maxLines, isNull);
          final first = tester.getRect(
            find.byKey(const ValueKey('site-category-one')),
          );
          final second = tester.getRect(
            find.byKey(const ValueKey('site-category-two')),
          );
          if (width == 390 && scale == 1) {
            expect(first.top, second.top);
            expect(second.left, greaterThan(first.right));
          }
          if (width >= 1200 && scale == 1) {
            expect(
              first.top,
              tester
                  .getRect(find.byKey(const ValueKey('site-category-four')))
                  .top,
            );
          }
          if (width < 600 && scale > 1) {
            expect(second.top, greaterThan(first.bottom));
          }
          expect(first.width, greaterThanOrEqualTo(44));
          for (final id in ['two', 'three', 'four', 'five', 'six', 'seven']) {
            final size = tester.getSize(
              find.byKey(ValueKey('site-category-$id')),
            );
            expect(
              size.width,
              closeTo(first.width, 0.001),
              reason: 'Все строки и последняя неполная строка: $id',
            );
            expect(size.height, closeTo(first.height, 0.001));
          }
          for (final feature in SiteContent.features) {
            expect(tester.widget<Text>(find.text(feature.$2)).maxLines, isNull);
          }
          await tester.ensureVisible(find.byKey(const ValueKey('site-footer')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('преимущества: одна, две и свободные колонки', (tester) async {
    final fresh = find.text(SiteContent.features[0].$1);
    final fast = find.text(SiteContent.features[1].$1);
    final varied = find.text(SiteContent.features[2].$1);

    await _pumpHome(tester, width: 360);
    expect(
      tester.getTopLeft(fast).dy,
      greaterThan(tester.getTopLeft(fresh).dy),
    );
    expect(
      tester.getTopLeft(varied).dy,
      greaterThan(tester.getTopLeft(fast).dy),
    );

    await _pumpHome(tester, width: 768);
    expect(_sameRow(tester, fresh, fast), isTrue);
    expect(
      tester.getTopLeft(varied).dy,
      greaterThan(tester.getTopLeft(fresh).dy),
    );

    await _pumpHome(tester, width: 1200);
    expect(_sameRow(tester, fresh, fast), isTrue);
    expect(_sameRow(tester, fast, varied), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('подвал на узкой ширине стоит столбиком, на широкой рядом', (
    tester,
  ) async {
    final identity = find.byKey(const ValueKey('site-footer-identity'));
    final links = find.byKey(const ValueKey('site-footer-links'));

    await _pumpHome(tester, width: 768);
    expect(
      tester.getTopLeft(links).dy,
      greaterThan(tester.getTopLeft(identity).dy),
    );

    expect(
      tester.getTopLeft(find.text(AppStrings.offer)).dx,
      closeTo(tester.getTopLeft(identity).dx, 1),
    );
    await _pumpHome(tester, width: 769);
    expect(
      tester.getTopLeft(links).dx,
      greaterThan(tester.getTopLeft(identity).dx),
    );
    expect(_sameRow(tester, identity, links), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('карточка категории круглая и открывает меню', (tester) async {
    SiteHomeCategory? selected;
    await _pumpHome(
      tester,
      width: 800,
      onCategory: (category) => selected = category,
      categories: const [SiteHomeCategory(id: 'soup', name: 'Супы')],
    );
    expect(find.text(AppStrings.siteDishCategories), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('site-category-soup')),
        matching: find.byType(ClipOval),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('site-category-soup')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('site-category-soup')));
    await tester.pumpAndSettle();
    expect(selected?.id, 'soup');
    expect(tester.takeException(), isNull);
  });

  testWidgets('без категорий витрина не показывается', (tester) async {
    await _pumpHome(tester, width: 800);
    expect(find.text(AppStrings.siteDishCategories), findsNothing);
    expect(find.text(SiteContent.features[0].$1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('справка сайта: отдельные блоки цвета категорий главной', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final destinations = _destinations();
    final pages = [
      AboutPage(destinations: destinations),
      DeliveryPage(destinations: destinations),
      HowToOrderPage(destinations: destinations),
      ContactsPage(destinations: destinations),
      OfferPage(destinations: destinations),
    ];
    for (final page in pages) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              AppConfig.parse(
                environment: 'test',
                apiBaseUrl: 'https://example.invalid/api/',
                dataBaseUrl: 'https://example.invalid/data/',
                appVersionUrl: 'https://example.invalid/version.json',
              ),
            ),
            httpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{}', 500)),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light, home: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(Card),
        findsNothing,
        reason: page.runtimeType.toString(),
      );
      final block = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SiteSection).first,
          matching: find.byType(DecoratedBox),
        ),
      );
      final homeBlock = AppTheme.light.colorScheme.surfaceContainer;
      expect((block.decoration as BoxDecoration).color, homeBlock);
      expect((block.decoration as BoxDecoration).borderRadius, AppTheme.radius);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DeliveryPage(destinations: destinations),
      ),
    );
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text(AppStrings.siteDeliveryTerms));
    expect(title.style?.color, AppTheme.light.colorScheme.primary);
    final lead = tester.widget<Text>(find.text(SiteContent.deliveryLead));
    expect(lead.style?.fontWeight, FontWeight.w700);
    expect(
      find.textContaining(SiteContent.paymentPoints.first),
      findsOneWidget,
    );
  });

  testWidgets('под преимуществами стоят значки магазинов рабочего сайта', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pumpHome(
      tester,
      width: 1100,
      storeLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    final features = find.byKey(const ValueKey('site-features'));
    final download = find.byKey(const ValueKey('site-app-download'));
    expect(download, findsOneWidget);
    expect(
      tester.getTopLeft(download).dy,
      greaterThan(tester.getBottomLeft(features).dy),
    );
    expect(find.text(AppStrings.siteAppDownload.toUpperCase()), findsOneWidget);
    expect(find.text(AppStrings.siteAppDownloadSubtitle), findsOneWidget);
    for (final badge in SiteContent.appBadges) {
      await tester.ensureVisible(
        find.byKey(ValueKey('site-badge-${badge.id}')),
      );
      await tester.tap(find.byKey(ValueKey('site-badge-${badge.id}')));
      await tester.pump();
    }
    expect(opened.map((uri) => uri.toString()), [
      for (final badge in SiteContent.appBadges) badge.url,
    ]);
    expect(tester.takeException(), isNull);

    await _pumpHome(tester, width: 320, storeLauncher: (_) async => true);
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('site-badge-app-store')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('site-badge-google-play')),
    );
    expect(second.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });
}
