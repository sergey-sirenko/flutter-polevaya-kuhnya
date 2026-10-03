import '../../support/compatible_version.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/app_version.dart';
import 'package:polevaya_kuhnya/features/menu/menu_excel.dart';
import 'package:polevaya_kuhnya/features/site/site_content.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _pageTitle(String title) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.key == const ValueKey('route-page-title') &&
      widget.data == title,
);

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required double width,
  double height = 900,
  double textScale = 1,
  String initialLocation = '/',
  String? versionLabel,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        if (versionLabel != null)
          appVersionLabelProvider.overrideWithValue(versionLabel),
        appConfigProvider.overrideWithValue(
          AppConfig.parse(
            appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
            environment: 'test',
            apiBaseUrl: 'https://example.invalid/api/',
            dataBaseUrl: 'https://example.invalid/data/',
          ),
        ),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.url.path.endsWith('/dishes.json')) {
              return http.Response.bytes(
                utf8.encode('{"weeks":[]}'),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            return http.Response('missing', 404);
          }),
        ),
        initialLocationProvider.overrideWithValue(
          initialLocation == '/' ? '/about' : initialLocation,
        ),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
      ],
      child: const FieldKitchenApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FieldKitchenApp)),
  );
  // Проверяем рамку главной после явного перехода: узкий холодный старт теперь заказы.
  if (initialLocation == '/') {
    container.read(routerProvider).go('/');
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  testWidgets(
    'скачивание меню открывается под строкой и не закрывает Контакты',
    (tester) async {
      await _mount(tester, width: 1440, initialLocation: '/menu');
      final contacts = find.byKey(SiteFrame.navItemKey(AppStrings.contacts));
      expect(contacts, findsOneWidget);
      await tester.tap(find.byKey(MenuDownloadButton.buttonKey));
      await tester.pumpAndSettle();
      final popup = find.text(
        'Текущая неделя (${AppStrings.menuExcelMissing})',
      );
      expect(popup, findsOneWidget);
      final item = find.ancestor(
        of: popup,
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(item, findsOneWidget);
      expect(tester.getRect(item).overlaps(tester.getRect(contacts)), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('увеличенный текст сворачивает полную шапку без переполнения', (
    tester,
  ) async {
    for (final route in ['/', '/menu']) {
      await _mount(tester, width: 1440, textScale: 1.6, initialLocation: route);
      expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
      expect(find.byKey(SiteFrame.navRowKey), findsNothing);
      await tester.tap(find.byKey(SiteFrame.navToggleKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(SiteFrame.navItemKey(AppStrings.delivery)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('документы доступны гостю по прямому адресу на узком экране', (
    tester,
  ) async {
    for (final document in [
      (AppRoutes.privacy, AppStrings.privacy, SiteContent.privacyParagraphs),
      (
        AppRoutes.personalDataConsent,
        AppStrings.personalDataConsent,
        SiteContent.personalDataConsentParagraphs,
      ),
    ]) {
      await _mount(
        tester,
        width: 360,
        textScale: 1.6,
        initialLocation: document.$1,
      );
      expect(_pageTitle(document.$2), findsOneWidget);
      for (final paragraph in document.$3) {
        expect(find.text(paragraph), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('data-document-back')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('/about-app показывает текущую версию из provider', (
    tester,
  ) async {
    await _mount(
      tester,
      width: 360,
      initialLocation: '/about-app',
      versionLabel: '2.3.4+42',
    );
    expect(
      find.text('${AppStrings.aboutAppVersion}: 2.3.4+42'),
      findsOneWidget,
    );
    expect(find.textContaining('0.1.0+1'), findsNothing);
    expect(find.text(SiteContent.email), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('/about-app без версии сохраняет контакты и ссылку политики', (
    tester,
  ) async {
    await _mount(
      tester,
      width: 360,
      initialLocation: '/about-app',
      versionLabel: AppStrings.aboutAppVersionUnavailable,
    );
    expect(
      find.text(
        '${AppStrings.aboutAppVersion}: ${AppStrings.aboutAppVersionUnavailable}',
      ),
      findsOneWidget,
    );
    expect(find.text(SiteContent.email), findsWidgets);
    expect(find.text(AppStrings.privacy), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  for (final width in <double>[
    320,
    360,
    390,
    599,
    600,
    768,
    769,
    1024,
    1199,
    1200,
    1440,
    1920,
  ]) {
    testWidgets('рамка $width ограничивает текст и не переполняется', (
      tester,
    ) async {
      final compact = siteNavIsCompact(Size(width, 900));
      await _mount(tester, width: width, textScale: width <= 360 ? 1.6 : 1);
      final box = tester.renderObject<RenderConstrainedBox>(
        find.byKey(SiteFrame.contentKey),
      );
      expect(box.additionalConstraints.maxWidth, siteContentMaxWidth);
      expect(box.size.width, lessThanOrEqualTo(siteContentMaxWidth));
      expect(box.size.width, lessThanOrEqualTo(width));
      expect(find.byKey(const ValueKey('site-footer')), findsOneWidget);
      expect(find.text(AppStrings.privacy), findsWidgets);
      if (compact ||
          (width == 1200 &&
              find.byKey(SiteFrame.navToggleKey).evaluate().isNotEmpty)) {
        expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
        expect(find.byKey(SiteFrame.navRowKey), findsNothing);
        expect(find.text(AppStrings.about), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('site-hero-copy')),
            matching: find.text(AppStrings.delivery),
          ),
          findsOneWidget,
        );
        expect(find.text(AppStrings.howToOrder), findsNothing);
      } else {
        expect(find.byKey(SiteFrame.navToggleKey), findsNothing);
        final row = tester.renderObject<RenderFlex>(
          find.byKey(SiteFrame.navRowKey),
        );
        expect(row.direction, Axis.horizontal);
        expect(find.text(AppStrings.about), findsWidgets);
        expect(find.text(AppStrings.delivery), findsWidgets);
        expect(find.text(AppStrings.howToOrder), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('низкое альбомное окно сворачивает меню разделов', (
    tester,
  ) async {
    await _mount(tester, width: 900, height: 400, initialLocation: '/about');
    expect(find.byKey(SiteFrame.navToggleKey), findsOneWidget);
    expect(find.byKey(SiteFrame.navRowKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('меню разделов стоит выше названия страницы', (tester) async {
    await _mount(tester, width: 1440, initialLocation: '/delivery');
    final menu = tester.getTopLeft(find.byKey(SiteFrame.navRowKey));
    final title = tester.getTopLeft(_pageTitle(AppStrings.delivery));
    expect(menu.dy, lessThan(title.dy));

    await _mount(tester, width: 390, initialLocation: '/delivery');
    final toggle = tester.getTopLeft(find.byKey(SiteFrame.navToggleKey));
    final compactTitle = tester.getTopLeft(_pageTitle(AppStrings.delivery));
    expect(toggle.dy, lessThan(compactTitle.dy));
    await tester.tap(find.byKey(SiteFrame.navToggleKey));
    await tester.pumpAndSettle();
    final panel = tester.getTopLeft(find.byKey(SiteFrame.navPanelKey));
    final openTitle = tester.getTopLeft(_pageTitle(AppStrings.delivery));
    expect(panel.dy, lessThan(openTitle.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('верхнее меню заказа на той же высоте, что у раздела', (
    tester,
  ) async {
    await _mount(tester, width: 1440, initialLocation: '/about');
    final aboutLogo = tester.getTopLeft(
      find.byKey(const ValueKey('site-brand-logo')),
    );
    final aboutItem = tester.getTopLeft(
      find.byKey(SiteFrame.navItemKey(AppStrings.menu)),
    );

    await _mount(tester, width: 1440, initialLocation: '/menu');
    final menuLogo = tester.getTopLeft(
      find.byKey(const ValueKey('site-brand-logo')),
    );
    final menuItem = tester.getTopLeft(
      find.byKey(SiteFrame.navItemKey(AppStrings.menu)),
    );
    expect(menuLogo.dy, aboutLogo.dy);
    expect(menuItem.dy, aboutItem.dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('логотип слева от названия, служебные разделы не в меню', (
    tester,
  ) async {
    await _mount(tester, width: 1440, initialLocation: '/menu');
    final logoFinder = find.byKey(const ValueKey('site-brand-logo'));
    final logo = tester.getTopLeft(logoFinder);
    final name = tester.getTopLeft(find.text('Полевая\nкухня'));
    final label = tester.widget<Text>(find.text('Полевая\nкухня'));
    expect(label.maxLines, 2);
    expect(label.semanticsLabel, AppStrings.appTitle);
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.text('Полевая\nкухня'),
              matching: find.byType(RichText),
            ),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(logo.dx, lessThan(name.dx));
    expect(tester.getSize(logoFinder), const Size(56, 56));
    expect(
      find.ancestor(of: logoFinder, matching: find.byType(ClipOval)),
      findsWidgets,
    );
    expect(find.byKey(SiteFrame.navItemKey(AppStrings.privacy)), findsNothing);
    expect(find.byKey(SiteFrame.navItemKey(AppStrings.aboutApp)), findsNothing);
    expect(find.byKey(SiteFrame.navItemKey(AppStrings.install)), findsNothing);
    expect(find.text(AppStrings.testBuild), findsNothing);

    await _mount(tester, width: 1440, initialLocation: '/');
    expect(find.text(AppStrings.install), findsNothing);
    expect(find.text(AppStrings.testBuild), findsNothing);
    expect(find.byKey(const ValueKey('site-brand-logo')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'заголовок страницы по центру, скачивание только в широком меню',
    (tester) async {
      await _mount(tester, width: 1440, initialLocation: '/about');
      final title = tester.getRect(_pageTitle(AppStrings.about));
      expect(title.center.dx, closeTo(1440 / 2, 24));
      expect(find.text(AppStrings.home), findsNothing);
      final download = tester.getTopLeft(find.text(AppStrings.menuDownload));
      final contacts = tester.getTopLeft(
        find.byKey(SiteFrame.navItemKey(AppStrings.contacts)),
      );
      final offer = tester.getTopLeft(
        find.byKey(SiteFrame.navItemKey(AppStrings.offer)),
      );
      expect(offer.dx, greaterThan(contacts.dx));
      expect(download.dx, greaterThan(offer.dx));

      await _mount(tester, width: 390, initialLocation: '/about');
      expect(find.text(AppStrings.menuDownload), findsNothing);
      await tester.tap(find.byKey(SiteFrame.navToggleKey));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.menuDownload), findsNothing);

      await _mount(tester, width: 1440, initialLocation: '/menu');
      expect(_pageTitle(AppStrings.menu), findsNothing);
      expect(find.text(AppStrings.menuDownload), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'компактное меню показывает те же разделы и закрывается снаружи',
    (tester) async {
      await _mount(tester, width: 768, initialLocation: '/about');
      final scroll = tester.widget<Scrollable>(
        find.descendant(
          of: find.byKey(SiteFrame.pageScrollKey),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.physics, isNull);

      await tester.tap(find.byKey(SiteFrame.navToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SiteFrame.navPanelKey), findsOneWidget);
      expect(
        find.byKey(SiteFrame.navItemKey(AppStrings.about)),
        findsOneWidget,
      );
      expect(
        find.byKey(SiteFrame.navItemKey(AppStrings.delivery)),
        findsOneWidget,
      );
      expect(
        find.byKey(SiteFrame.navItemKey(AppStrings.privacy)),
        findsNothing,
      );
      expect(
        find.byKey(SiteFrame.navItemKey(AppStrings.install)),
        findsNothing,
      );
      final locked = tester.widget<Scrollable>(
        find.descendant(
          of: find.byKey(SiteFrame.pageScrollKey),
          matching: find.byType(Scrollable),
        ),
      );
      expect(locked.physics, isA<NeverScrollableScrollPhysics>());
      final about = tester.widget<TextButton>(
        find.byKey(SiteFrame.navItemKey(AppStrings.about)),
      );
      final theme = Theme.of(tester.element(find.byKey(SiteFrame.navPanelKey)));
      expect(
        about.style?.foregroundColor?.resolve(const <WidgetState>{}),
        theme.colorScheme.primary,
      );

      await tester.tap(find.byKey(SiteFrame.navBarrierKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SiteFrame.navPanelKey), findsNothing);
      expect(find.byKey(SiteFrame.navItemKey(AppStrings.about)), findsNothing);
      expect(_pageTitle(AppStrings.about), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('выбор раздела закрывает компактное меню', (tester) async {
    final container = await _mount(tester, width: 390);
    await tester.tap(find.byKey(SiteFrame.navToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SiteFrame.navItemKey(AppStrings.contacts)));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/contacts',
    );
    expect(find.byKey(SiteFrame.navPanelKey), findsNothing);
    expect(_pageTitle(AppStrings.contacts), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('навигация открывает информационные разделы', (tester) async {
    final container = await _mount(tester, width: 1440);
    Future<void> open(String label, String path, String title) async {
      container.read(routerProvider).go('/');
      await tester.pumpAndSettle();
      final target = find.byKey(SiteFrame.navItemKey(label));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        path,
      );
      expect(_pageTitle(title), findsOneWidget);
    }

    await open(AppStrings.about, '/about', AppStrings.about);
    await open(AppStrings.delivery, '/delivery', AppStrings.delivery);
    await open(AppStrings.howToOrder, '/how-to-order', AppStrings.howToOrder);
    await open(AppStrings.offer, '/offer', AppStrings.offer);
    expect(find.text(AppStrings.offerHeading), findsOneWidget);
    expect(
      find.textContaining(SiteContent.offerLawPoints.first),
      findsOneWidget,
    );

    Future<void> openFooter(String label, String path, String title) async {
      container.read(routerProvider).go('/');
      await tester.pumpAndSettle();
      final target = find.descendant(
        of: find.byKey(const ValueKey('site-footer')),
        matching: find.widgetWithText(TextButton, label),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        path,
      );
      expect(_pageTitle(title), findsOneWidget);
    }

    await openFooter(AppStrings.privacy, '/privacy', AppStrings.privacy);
    await openFooter(AppStrings.aboutApp, '/about-app', AppStrings.aboutApp);
    expect(tester.takeException(), isNull);
  });

  testWidgets('установка продолжает в браузере и не ведёт в прежние магазины', (
    tester,
  ) async {
    final container = await _mount(
      tester,
      width: 800,
      initialLocation: '/install',
    );
    expect(find.text(AppStrings.installStoresPending), findsOneWidget);
    expect(find.text(AppStrings.installApkLater), findsOneWidget);
    expect(find.text(SiteContent.phoneDisplay), findsWidgets);
    expect(find.text('Google Play'), findsNothing);
    expect(find.text('RuStore'), findsNothing);
    expect(find.text('App Store'), findsNothing);
    expect(find.textContaining('ru.ssn.hlebsol'), findsNothing);
    final button = find.byKey(const ValueKey('install-continue-browser'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/menu',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('подвал открывает оферту', (tester) async {
    final container = await _mount(tester, width: 800);
    expect(find.widgetWithText(TextButton, AppStrings.support), findsNothing);
    final offer = find.descendant(
      of: find.byKey(const ValueKey('site-footer')),
      matching: find.widgetWithText(TextButton, AppStrings.offer),
    );
    await tester.ensureVisible(offer);
    await tester.pumpAndSettle();
    await tester.tap(offer);
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      '/offer',
    );
    expect(_pageTitle(AppStrings.offer), findsOneWidget);
    expect(find.text(SiteContent.offerNotice), findsOneWidget);
  });
}
