import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

final config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/Obmen/',
  dataBaseUrl: 'https://data.example.test/data/',
);

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

Future<void> mountMenuPage(
  WidgetTester tester,
  http.Client client, {
  VoidCallback onHome = _doNothing,
  SessionStatus sessionStatus = SessionStatus.signedIn,
  VoidCallback? onSignIn,
  double discount = 0,
  bool realFont = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(client),
        sessionStatusProvider.overrideWithValue(sessionStatus),
        sessionProfileProvider.overrideWithValue(
          UserProfile.fromUserJson({'DiscountPercentage': discount}),
        ),
        cartDayEditPermissionProvider.overrideWith(
          (ref, dateKey) => sessionStatus == SessionStatus.signedIn,
        ),
      ],
      child: RepaintBoundary(
        key: const ValueKey('ux-menu-preview'),
        child: MaterialApp(
          theme: realFont
              ? AppTheme.light.copyWith(
                  textTheme: AppTheme.light.textTheme.apply(
                    fontFamily: 'Arial',
                  ),
                )
              : AppTheme.light,
          home: MenuPage(onHome: onHome, onSignIn: onSignIn),
        ),
      ),
    ),
  );
  await settleMenu(tester);
}

Future<void> settleMenu(WidgetTester tester) async {
  await tester.pump();
  for (
    var attempt = 0;
    attempt < 40 &&
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
}

void _doNothing() {}

MockClient menuClient(String dishesBody) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/dishes.json')) {
      return jsonResponse(dishesBody);
    }
    return http.Response('missing', 404);
  });
}

void main() {
  for (final width in [390.0, 1200.0, 1440.0]) {
    testWidgets('FL-UX-04: компактная карточка и сравнимое превью $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final font = File('C:/Windows/Fonts/arial.ttf');
      if (font.existsSync()) {
        final loader = FontLoader('Arial')
          ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      }
      final raw = jsonDecode(await fixture(tester, 'menu_with_dishes'));
      raw['weeks'][0]['days'][0]['categories'][0]['dishes'][0]['imagePath'] =
          null;
      await mountMenuPage(
        tester,
        menuClient(jsonEncode(raw)),
        realFont: font.existsSync(),
      );
      final photo = find.byKey(
        const ValueKey('menu-dish-photo-FIXTURE-DISH-0001'),
      );
      final price = find.byKey(
        const ValueKey('menu-dish-price-FIXTURE-DISH-0001'),
      );
      if (Platform.environment['FL_UX_MENU_BASELINE'] != '1') {
        expect(
          tester.getSize(photo).height,
          lessThanOrEqualTo(width < 600 ? 160 : 220),
        );
        // Старое квадратное фото: выигрыш превышает добавленную строку цены.
        expect(
          tester.getSize(photo).width - tester.getSize(photo).height,
          greaterThan(tester.getSize(price).height + 4),
        );
        expect(
          tester.getTopLeft(price).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(photo).dy),
        );
      }
      if (Platform.environment['FL_UX_MENU_PREVIEW'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('ux-menu-preview')),
        );

        final suffix = Platform.environment['FL_UX_MENU_BASELINE'] == '1'
            ? 'before'
            : 'after';
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('docs/testing/FL-UX-04/menu-$width-$suffix.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final percent in [5.0, 100.0]) {
    testWidgets('карточка и полный состав показывают скидку $percent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final raw = jsonDecode(await fixture(tester, 'menu_with_dishes'));
      raw['weeks'][0]['days'][0]['categories'][0]['dishes'][0]['price'] = 115;
      await mountMenuPage(
        tester,
        menuClient(jsonEncode(raw)),
        discount: percent,
      );
      final label = percent == 5 ? '109 ₽\n115 ₽' : '0 ₽\n115 ₽';
      expect(find.text(label), findsOneWidget);
      final text = tester.widget<Text>(find.text(label));
      final old = (text.textSpan! as TextSpan).children!.last as TextSpan;
      expect(old.style!.decoration, TextDecoration.lineThrough);
      expect(old.style!.fontSize, lessThan(text.style!.fontSize!));
      expect(old.style!.color, AppTheme.light.colorScheme.onSurfaceVariant);
      await tester.tap(
        find.byKey(const ValueKey('menu-dish-photo-FIXTURE-DISH-0001')),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

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
        'карточки $width / $scale: название, цена и 44 px без переполнения',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final raw = jsonDecode(await fixture(tester, 'menu_with_dishes'));
          final dish = raw['weeks'][0]['days'][0]['categories'][0]['dishes'][0];
          const name =
              'Суп овощной с цветной капустой и зеленью (вегетарианский)';
          dish['dishName'] = name;
          dish['imagePath'] = null;
          await mountMenuPage(tester, menuClient(jsonEncode(raw)));
          final title = find.text(name);
          final photo = find.byKey(
            const ValueKey('menu-dish-photo-FIXTURE-DISH-0001'),
          );
          final price = find.byKey(
            const ValueKey('menu-dish-price-FIXTURE-DISH-0001'),
          );
          final control = find.byKey(
            const ValueKey('menu-dish-quantity-FIXTURE-DISH-0001'),
          );
          final nutrients = find.byKey(
            const ValueKey('menu-dish-nutrients-FIXTURE-DISH-0001'),
          );
          expect(tester.widget<Text>(title).maxLines, isNull);
          expect(
            tester.getRect(price).top,
            greaterThanOrEqualTo(tester.getRect(photo).bottom),
          );
          expect(
            tester.getRect(price).top,
            greaterThan(tester.getRect(title).bottom),
          );
          expect(
            tester.getSize(photo).height,
            lessThanOrEqualTo(width < 600 ? 160 : 220),
          );
          final image = tester.widget<MenuNetworkImage>(
            find.descendant(of: photo, matching: find.byType(MenuNetworkImage)),
          );
          expect(image.fit, BoxFit.contain);
          expect(find.descendant(of: photo, matching: price), findsNothing);
          expect(find.textContaining('Бел', findRichText: true), findsWidgets);
          expect(find.textContaining('Жир', findRichText: true), findsWidgets);
          expect(find.textContaining('Угл', findRichText: true), findsWidgets);
          expect(find.textContaining('Ккал', findRichText: true), findsWidgets);
          expect(find.textContaining('22г', findRichText: true), findsWidgets);
          expect(find.textContaining('436', findRichText: true), findsWidgets);
          expect(
            tester.getRect(nutrients).top,
            greaterThan(tester.getRect(title).bottom),
          );
          expect(
            tester.getRect(control).top,
            greaterThanOrEqualTo(tester.getRect(nutrients).bottom),
          );
          expect(
            tester.getSize(photo).width,
            greaterThanOrEqualTo(width < 600 ? 156 : 248),
          );
          if (width < 600 && (scale > 1 || width == 320)) {
            expect(tester.getSize(photo).width, closeTo(width - 32, 1));
          }
          final increase = find.descendant(
            of: control,
            matching: find.byTooltip(AppStrings.menuIncreaseQuantity),
          );
          await tester.ensureVisible(increase);
          await tester.pumpAndSettle();
          expect(tester.getSize(increase).width, greaterThanOrEqualTo(44));
          expect(tester.getSize(increase).height, greaterThanOrEqualTo(44));
          expect(increase.hitTestable(), findsOneWidget);
          await tester.tap(increase);
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(tester.element(title));
          expect(
            container.read(
              cartDraftProvider,
            )['2030-01-02']?['FIXTURE-DISH-0001'],
            1,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Back закрывает полную карточку и панели; resize закрывает несовместимое фото',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final raw = jsonDecode(await fixture(tester, 'menu_with_dishes'));
      raw['weeks'][0]['days'][0]['categories'][0]['dishes'][0]['imagePath'] =
          null;
      await mountMenuPage(tester, menuClient(jsonEncode(raw)));
      final photo = find.byKey(
        const ValueKey('menu-dish-photo-FIXTURE-DISH-0001'),
      );
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-dish-card-dialog')),
        findsOneWidget,
      );
      await Navigator.of(tester.element(find.byType(MenuPage))).maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-dish-card-dialog')), findsNothing);
      ProviderScope.containerOf(tester.element(find.byType(MenuPage)))
          .read(orderSheetProvider.notifier)
          .toggle(OrderSheet.categories);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('order-category-sheet')),
        findsOneWidget,
      );
      await Navigator.of(tester.element(find.byType(MenuPage))).maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-category-sheet')), findsNothing);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(900, 390);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-dish-card-dialog')), findsNothing);
      await tester.tap(photo);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-dish-image-dialog')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'узкая карточка сохраняет копейки и раскрывает длинный состав с Esc',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1);
      final body = jsonDecode(await fixture(tester, 'menu_with_dishes'));
      final dish = body['weeks'][0]['days'][0]['categories'][0]['dishes'][0];
      final composition = List.filled(30, 'овощи, крупа, зелень').join(', ');
      dish['ingredients'] = {'textDescription': composition};
      dish['price'] = 190.5;
      await mountMenuPage(tester, menuClient(jsonEncode(body)));
      expect(find.text('190,50 ₽'), findsOneWidget);
      expect(find.text(AppStrings.menuShowComposition), findsNothing);
      expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
      expect(find.text('${AppStrings.menuWeightLabel}: 250'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('menu-dish-photo-FIXTURE-DISH-0001')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-dish-card-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('menu-dish-image-dialog')),
        findsNothing,
      );
      final fullText = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(fullText.data, composition);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-dish-card-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('широкая карточка открывает полный состав и изображение', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final body = jsonDecode(await fixture(tester, 'menu_with_dishes'));
    final dish = body['weeks'][0]['days'][0]['categories'][0]['dishes'][0];
    dish['ingredients'] = {'textDescription': 'овощи, вода'};
    await mountMenuPage(tester, menuClient(jsonEncode(body)));
    final name = tester.widget<Text>(find.text('Суп овощной (фикстура)'));
    expect(name.maxLines, isNull);
    expect(find.text(AppStrings.menuShowComposition), findsOneWidget);
    final weight = find.byKey(
      const ValueKey('menu-dish-weight-FIXTURE-DISH-0001'),
    );
    final price = find.byKey(
      const ValueKey('menu-dish-price-FIXTURE-DISH-0001'),
    );
    expect(
      tester.getRect(weight).center.dy,
      closeTo(tester.getRect(price).center.dy, 1),
    );
    expect(
      tester.getRect(weight).right,
      greaterThan(tester.getRect(price).right),
    );
    expect(
      tester.getRect(find.text(AppStrings.menuShowComposition)).left,
      closeTo(
        tester
            .getRect(
              find.byKey(const ValueKey('menu-dish-price-FIXTURE-DISH-0001')),
            )
            .left,
        1,
      ),
    );
    expect(find.text('овощи, вода'), findsNothing);
    await tester.tap(find.text(AppStrings.menuShowComposition));
    await tester.pumpAndSettle();
    expect(find.text('овощи, вода'), findsOneWidget);
    await tester.tap(find.text(AppStrings.close));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('menu-dish-photo-FIXTURE-DISH-0001')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('menu-dish-image-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('menu-dish-card-dialog')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-dish-image-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('непустое меню показывает категорию, блюдо, вес и цену', (
    tester,
  ) async {
    final body = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(tester, menuClient(body));
    expect(find.text(AppStrings.menuCurrentWeek), findsOneWidget);
    final weekButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, AppStrings.menuCurrentWeek),
    );
    expect(
      weekButton.style!.foregroundColor!.resolve({}),
      Theme.of(tester.element(find.text(AppStrings.menuCurrentWeek)))
          .colorScheme
          .primary,
    );
    expect(find.textContaining('Для добавления блюд нажмите'), findsNothing);
    expect(find.text('02.01'), findsOneWidget);
    expect(find.text('Супы'), findsWidgets);
    expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
    expect(find.text('190 ₽'), findsOneWidget);
    expect(find.textContaining(AppStrings.menuWeightLabel), findsOneWidget);
    expect(find.text(AppStrings.testBuild), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкое меню оставляет сверху выбранные день и категорию', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final body = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(tester, menuClient(body));
    expect(
      find.byKey(const ValueKey('menu-adaptive-selection')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('menu-week-day-bar')), findsNothing);
    expect(find.text(AppStrings.menuCurrentWeek), findsNothing);
    expect(find.text(AppStrings.menuNextWeek), findsNothing);
    expect(find.byKey(const ValueKey('menu-selected-day')), findsOneWidget);
    expect(find.text('Ср 02.01'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('menu-selected-category')))
          .dx,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('menu-selected-day'))).dx,
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('menu-selected-category')))
          .data,
      'Супы',
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('верхние категории скрыты до 1200, широкая колонка 224 px', (
    tester,
  ) async {
    final body = await fixture(tester, 'menu_with_dishes');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(body));
    expect(find.byKey(const ValueKey('menu-category-column')), findsNothing);
    expect(find.byType(MenuCategoryList), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    for (final width in [390.0, 600.0, 768.0, 1199.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();
      expect(find.byType(MenuCategoryList), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('menu-category-column'))).width,
      224,
    );
    final bar = tester.getRect(find.byKey(const ValueKey('menu-week-day-bar')));
    final weekChip = tester.getRect(
      find.widgetWithText(TextButton, AppStrings.menuCurrentWeek),
    );
    final dayChip = tester.getRect(find.widgetWithText(TextButton, '02.01'));
    expect(weekChip.center.dx, closeTo(bar.center.dx, 16));
    expect(dayChip.center.dx, closeTo(bar.center.dx, 16));
    final thumb = find.byKey(
      const ValueKey('menu-category-thumb-fixture-category-soups'),
    );
    expect(thumb, findsOneWidget);
    expect(tester.getSize(thumb), const Size(40, 40));
    final categoryName = find.descendant(
      of: find.byKey(const ValueKey('menu-category-column')),
      matching: find.text('Супы'),
    );
    expect(
      tester.getTopLeft(thumb).dx,
      lessThan(tester.getTopLeft(categoryName).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('длинное название категории переносится по словам', (
    tester,
  ) async {
    final raw = jsonDecode(await fixture(tester, 'menu_with_dishes'));
    const name = 'Салаты заправленные и закуски';
    raw['weeks'][0]['days'][0]['categories'][0]['categoryName'] = name;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(jsonEncode(raw)));
    final text = find.descendant(
      of: find.byKey(const ValueKey('menu-category-column')),
      matching: find.text(name),
    );
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.getSize(text).height, greaterThan(24));
    expect(tester.getSize(text).width, lessThan(208 * 1.2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('страница меню не держит второе меню разделов', (tester) async {
    final body = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(tester, menuClient(body));
    expect(find.byKey(const ValueKey('menu-site-links')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('строковый составной вес показывает блюдо и его изображение', (
    tester,
  ) async {
    final body = jsonDecode(await fixture(tester, 'menu_with_dishes'));
    final dish = body['weeks'][0]['days'][0]['categories'][0]['dishes'][0];
    dish['servingweight'] = '2 шт./150';
    dish['imagePath'] = 'fixture-image';
    dish['photo_version'] = '2';
    await mountMenuPage(tester, menuClient(jsonEncode(body)));
    expect(find.text('Суп овощной (фикстура)'), findsOneWidget);
    expect(
      find.text('${AppStrings.menuWeightLabel}: 2 шт./150'),
      findsOneWidget,
    );
    expect(
      tester.widget<MenuNetworkImage>(find.byType(MenuNetworkImage)).imagePath,
      'fixture-image',
    );
    expect(
      tester.widget<MenuNetworkImage>(find.byType(MenuNetworkImage)).version,
      'photo:2',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('количество сохраняется в cart draft при смене раскладки', (
    tester,
  ) async {
    final body = await fixture(tester, 'menu_with_dishes');
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(menuClient(body)),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
        cartDayEditPermissionProvider.overrideWith((ref, dateKey) => true),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: MenuPage(onHome: _doNothing)),
      ),
    );
    await settleMenu(tester);
    final increase = find.byTooltip(AppStrings.menuIncreaseQuantity);
    await tester.ensureVisible(increase);
    await tester.tap(increase);
    await tester.pump();
    expect(
      container.read(cartDraftProvider)['2030-01-02']?['FIXTURE-DISH-0001'],
      1,
    );
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    expect(
      container.read(cartDraftProvider)['2030-01-02']?['FIXTURE-DISH-0001'],
      1,
    );
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('пустое опубликованное меню показывает понятное сообщение', (
    tester,
  ) async {
    final body = await fixture(tester, 'public_menu_empty');
    await mountMenuPage(tester, menuClient(body));
    expect(find.text(AppStrings.menuEmptyMessage), findsOneWidget);
  });

  testWidgets('сетевой отказ показывает ошибку, повтор загружает данные', (
    tester,
  ) async {
    var offline = true;
    final dishesBody = await fixture(tester, 'menu_with_dishes');
    await mountMenuPage(
      tester,
      MockClient((request) async {
        if (offline) throw http.ClientException('offline');
        if (request.url.path.endsWith('/dishes.json')) {
          return jsonResponse(dishesBody);
        }
        return http.Response('missing', 404);
      }),
    );
    expect(find.text(AppStrings.menuNetworkError), findsOneWidget);
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
      menuClient(body),
      onHome: () => homeTapped = true,
    );
    expect(homeTapped, isFalse);
    await tester.tap(find.text(AppStrings.home));
    await tester.pumpAndSettle();
    expect(homeTapped, isTrue);
  });

  testWidgets('гость не выбирает блюда и видит приглашение войти', (
    tester,
  ) async {
    final body = await fixture(tester, 'menu_with_dishes');
    var signInTapped = false;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(menuClient(body)),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MenuPage(
            onHome: _doNothing,
            onSignIn: () => signInTapped = true,
          ),
        ),
      ),
    );
    await settleMenu(tester);
    expect(find.text(AppStrings.menuSignInToChoose), findsOneWidget);
    expect(find.byTooltip(AppStrings.menuIncreaseQuantity), findsNothing);
    expect(find.byTooltip(AppStrings.menuDecreaseQuantity), findsNothing);
    expect(container.read(cartDraftProvider), isEmpty);
    final signIn = find.byKey(const ValueKey('menu-guest-sign-in'));
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pump();
    expect(signInTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('полоса недель остаётся на месте, категория садится под неё', (
    tester,
  ) async {
    final raw = jsonDecode(
      await fixture(tester, 'menu_with_dishes'),
    ) as Map<String, dynamic>;
    final day =
        (((raw['weeks'] as List).first as Map)['days'] as List).first as Map;
    final categories = day['categories'] as List;
    final dish = Map<String, dynamic>.from(
      ((categories.first as Map)['dishes'] as List).first as Map,
    );
    List<Map<String, dynamic>> copies(String prefix) => [
      for (var i = 0; i < 8; i++)
        {...dish, 'dishId': '$prefix-$i', 'dishName': '$prefix $i'},
    ];
    (categories.first as Map)['dishes'] = copies('Суп');
    categories.add({
      'categoryId': 'fixture-category-salads',
      'categoryName': 'Салаты',
      'categoryOrder': 2,
      'dishes': copies('Салат'),
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(jsonEncode(raw)));

    final bar = find.byKey(const ValueKey('menu-week-day-bar'));
    final barTop = tester.getTopLeft(bar).dy;
    await tester.drag(
      find.byKey(const ValueKey('menu-dishes-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(bar).dy, barTop);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('menu-category-column')),
        matching: find.widgetWithText(TextButton, 'Салаты'),
      ),
    );
    await tester.pumpAndSettle();
    final listTop = tester
        .getTopLeft(find.byKey(const ValueKey('menu-dishes-scroll')))
        .dy;
    final section = find.descendant(
      of: find.byKey(const ValueKey('menu-dishes-scroll')),
      matching: find.text('Салаты'),
    );
    expect(tester.getTopLeft(section).dy, lessThan(listTop + 20));
    expect(tester.getTopLeft(bar).dy, barTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('прокрутка сохраняет активную категорию без верхней полосы', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(await _twoCategoryMenu(tester)));
    final dishes = find.byKey(const ValueKey('menu-dishes-scroll'));
    final listTop = tester.getTopLeft(dishes).dy;
    final saladTop = tester
        .getTopLeft(find.descendant(of: dishes, matching: find.text('Салаты')))
        .dy;
    await tester.drag(dishes, Offset(0, -(saladTop - listTop + 24)));
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MenuPage)))
          .read(menuActiveCategoryProvider),
      'fixture-category-salads',
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('после нажатия автоподсветка коротко не перебивает выбор', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(await _twoCategoryMenu(tester)));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MenuPage)),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('menu-category-column')),
        matching: find.widgetWithText(TextButton, 'Салаты'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 280));
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('menu-dishes-scroll')),
    );
    scroll.controller!.jumpTo(0);
    await tester.pump();
    expect(
      container.read(menuActiveCategoryProvider),
      'fixture-category-salads',
    );
    await tester.pump(const Duration(milliseconds: 200));
    scroll.controller!.jumpTo(1);
    await tester.pump();
    scroll.controller!.jumpTo(0);
    await tester.pump();
    expect(
      container.read(menuActiveCategoryProvider),
      'fixture-category-soups',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('смена количества оставляет блюдо на месте', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(await _twoCategoryMenu(tester)));

    final title = find.text('Суп 2');
    final card = find.ancestor(of: title, matching: find.byType(Card));
    final increase = find.descendant(
      of: card,
      matching: find.byTooltip(AppStrings.menuIncreaseQuantity),
    );
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(title));
    final beforeDraft = container.read(cartDraftProvider);
    expect(increase.hitTestable(), findsOneWidget);
    final before = tester.getTopLeft(title).dy;
    await tester.tap(increase);
    await tester.pump();
    expect(container.read(cartDraftProvider), isNot(equals(beforeDraft)));
    expect(tester.getTopLeft(title).dy, closeTo(before, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('смартфон ставит две колонки, широкий экран — карточку от 248', (
    tester,
  ) async {
    final raw = jsonDecode(
      await fixture(tester, 'menu_with_dishes'),
    ) as Map<String, dynamic>;
    final day =
        (((raw['weeks'] as List).first as Map)['days'] as List).first as Map;
    final dishes = (day['categories'] as List).first as Map;
    final source = Map<String, dynamic>.from(
      (dishes['dishes'] as List).first as Map,
    );
    dishes['dishes'] = [
      for (var i = 0; i < 3; i++)
        {
          ...source,
          'dishId': 'grid-$i',
          'dishName': 'Блюдо $i',
          'menuOrder': i + 1,
          'price': 190,
        },
    ];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountMenuPage(tester, menuClient(jsonEncode(raw)));

    final left = find.byKey(const ValueKey('menu-dish-photo-grid-0'));
    final right = find.byKey(const ValueKey('menu-dish-photo-grid-1'));
    final leftSize = tester.getSize(left);
    expect(leftSize.height, lessThanOrEqualTo(160));
    expect(
      tester.getTopLeft(right).dx,
      greaterThan(tester.getTopLeft(left).dx + leftSize.width - 1),
    );
    expect(find.descendant(of: left, matching: find.text('1')), findsOneWidget);
    final priceOnPhoto = find.descendant(
      of: left,
      matching: find.text('190 ₽'),
    );
    expect(priceOnPhoto, findsNothing);
    final priceBelow = find.byKey(const ValueKey('menu-dish-price-grid-0'));
    expect(
      tester.getTopLeft(priceBelow).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(left).dy),
    );
    final quantity = find.byKey(const ValueKey('menu-dish-quantity-grid-0'));
    expect(tester.getSize(quantity).width, greaterThanOrEqualTo(110));
    expect(
      tester.getTopLeft(quantity).dy,
      greaterThan(tester.getBottomLeft(left).dy - 1),
    );

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    final wideCard = find.ancestor(
      of: find.byKey(const ValueKey('menu-dish-photo-grid-0')),
      matching: find.byType(Card),
    );
    expect(tester.getSize(wideCard).width, greaterThanOrEqualTo(248));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('menu-dish-quantity-grid-0')))
          .width,
      greaterThanOrEqualTo(130),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('закрытый день можно смотреть, кнопки количества скрыты', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          httpClientProvider.overrideWithValue(menuClient(_closedDayMenu)),
          sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
          cartDayEditPermissionProvider.overrideWith((ref, dateKey) => true),
          menuAllowedDatesProvider.overrideWith(_OnlyOpenDay.new),
        ],
        child: const MaterialApp(home: MenuPage(onHome: _doNothing)),
      ),
    );
    await settleMenu(tester);
    expect(find.text('Открытое блюдо'), findsOneWidget);
    expect(find.text(AppStrings.menuDayClosed), findsNothing);
    expect(
      _quantityButton(tester, AppStrings.menuIncreaseQuantity).onPressed,
      isNotNull,
    );

    final closedChip = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '03.01'),
    );
    expect(closedChip.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, '03.01'));
    await tester.pumpAndSettle();
    expect(find.text('Закрытое блюдо'), findsOneWidget);
    expect(find.text(AppStrings.menuDayClosed), findsOneWidget);
    expect(find.byTooltip(AppStrings.menuIncreaseQuantity), findsNothing);
    expect(find.byTooltip(AppStrings.menuDecreaseQuantity), findsNothing);

    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(MenuPage)))
        .read(orderSheetProvider.notifier)
        .toggle(OrderSheet.day);
    await tester.pumpAndSettle();
    final sheetChip = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const ValueKey('order-day-sheet')),
        matching: find.widgetWithText(TextButton, '03.01'),
      ),
    );
    expect(sheetChip.onPressed, isNotNull);
    final openDay = find.descendant(
      of: find.byKey(const ValueKey('order-day-sheet')),
      matching: find.widgetWithText(TextButton, '02.01'),
    );
    await tester.ensureVisible(openDay);
    await tester.tap(openDay);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MenuPage)))
          .read(menuSelectionProvider)
          ?.dateKey,
      '2030-01-02',
    );
    expect(find.byKey(const ValueKey('order-day-sheet')), findsNothing);
    expect(find.textContaining('Открытое блюдо'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('следующая неделя без меню не оставляет дни текущей', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const body = '''
{"weeks":[
  {"weekType":"current","days":[{"date":"2030-01-02","hasDelivery":true,"dayName":"Среда","categories":[{"categoryId":"c1","categoryName":"Супы","dishes":[{"dishId":"d1","dishName":"Суп","price":10}]}]}]},
  {"weekType":"next","days":[
    {"date":"2030-01-02","dayName":"Среда","categories":[]},
    {"date":"2030-01-03","dayName":"Четверг","categories":[]}
  ]}
]}
''';
    await mountMenuPage(tester, menuClient(body));
    expect(find.text('Среда (02.01)'), findsOneWidget);
    expect(find.text(AppStrings.menuNextWeek), findsNothing);
    expect(find.text('Суп'), findsOneWidget);
    expect(find.text(AppStrings.menuNoDeliveryDays), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('без блюд в обеих неделях остаётся текущая', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const body = '''
{"weeks":[
  {"weekType":"current","days":[{"date":"2030-01-02","categories":[]}]},
  {"weekType":"next","days":[{"date":"2030-01-09","categories":[]}]}
]}
''';
    await mountMenuPage(tester, menuClient(body));
    expect(find.text(AppStrings.menuCurrentWeek), findsOneWidget);
    expect(find.text(AppStrings.menuNextWeek), findsNothing);
    expect(find.text(AppStrings.menuNoDeliveryDays), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('уже загруженное меню сразу показывает блюда текущей недели', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    const body = '''
{"weeks":[
  {"weekType":"current","days":[{"date":"2030-01-02","hasDelivery":true,"dayName":"Среда","categories":[{"categoryId":"c1","categoryName":"Супы","dishes":[{"dishId":"d1","dishName":"Суп","price":10}]}]}]},
  {"weekType":"next","days":[
    {"date":"2030-10-05","dayName":"Понедельник","categories":[]},
    {"date":"2030-10-06","dayName":"Вторник","categories":[]}
  ]}
]}
''';
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(menuClient(body)),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
        cartDayEditPermissionProvider.overrideWith((ref, dateKey) => true),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(menuControllerProvider.future));
    expect(container.read(menuSelectionProvider), isNull);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: MenuPage(onHome: _doNothing),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.menuCurrentWeek), findsOneWidget);
    expect(find.text(AppStrings.menuNextWeek), findsNothing);
    expect(find.text('Среда (02.01)'), findsOneWidget);
    expect(find.text('Суп'), findsOneWidget);
    expect(find.text(AppStrings.menuNoDeliveryDays), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

IconButton _quantityButton(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

class _OnlyOpenDay extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => const {'2030-01-02'};
}

const _closedDayMenu = '''
{
  "weeks": [
    {
      "weekType": "current",
      "weekNumber": 1,
      "days": [
        {
          "date": "2030-01-02",
          "hasDelivery": true,
          "categories": [
            {
              "categoryId": "open-day",
              "categoryName": "Супы",
              "categoryOrder": 1,
              "dishes": [
                {
                  "dishId": "open-dish",
                  "dishName": "Открытое блюдо",
                  "menuOrder": 1,
                  "price": 100,
                  "servingweight": 100
                }
              ]
            }
          ]
        },
        {
          "date": "2030-01-03",
          "hasDelivery": true,
          "categories": [
            {
              "categoryId": "closed-day",
              "categoryName": "Супы",
              "categoryOrder": 1,
              "dishes": [
                {
                  "dishId": "closed-dish",
                  "dishName": "Закрытое блюдо",
                  "menuOrder": 1,
                  "price": 120,
                  "servingweight": 100
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
''';

Future<String> _twoCategoryMenu(WidgetTester tester) async {
  final raw = jsonDecode(
    await fixture(tester, 'menu_with_dishes'),
  ) as Map<String, dynamic>;
  final day =
      (((raw['weeks'] as List).first as Map)['days'] as List).first as Map;
  final categories = day['categories'] as List;
  final dish = Map<String, dynamic>.from(
    ((categories.first as Map)['dishes'] as List).first as Map,
  );
  List<Map<String, dynamic>> copies(String prefix, int count) => [
    for (var i = 0; i < count; i++)
      {...dish, 'dishId': '$prefix-$i', 'dishName': '$prefix $i'},
  ];
  (categories.first as Map)['dishes'] = copies('Суп', 8);
  categories.add({
    'categoryId': 'fixture-category-salads',
    'categoryName': 'Салаты',
    'categoryOrder': 2,
    'dishes': copies('Салат', 8),
  });
  return jsonEncode(raw);
}
