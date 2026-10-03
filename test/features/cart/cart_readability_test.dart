import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/orders_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/profile/profile_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Menu extends MenuController {
  @override
  Future<List<MenuWeek>> build() async => [
    MenuWeek(
      weekType: 'current',
      days: [
        MenuDay(
          dateKey: '2030-01-02',
          date: DateTime(2030, 1, 2),
          categories: [
            MenuCategory(
              categoryId: 'c1',
              categoryName: 'Супы',
              dishes: [
                const MenuDish(
                  dishId: 'known-id',
                  dishName: 'Суп с овощами и зеленью',
                  price: 190.5,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}

class _Dates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => {'2030-01-02'};
}

class _PreparedEdit extends CartEditController {
  @override
  CartEditState build() => const CartEditState(
    dateKey: '2030-01-02',
    owner: 'owner-a',
    revision: 'test-revision',
  );
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  Widget page, {
  bool draft = false,
  double discount = 0,
  int subsidy = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(360, 1100);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.parse(
          appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
          environment: 'test',
          apiBaseUrl: 'https://example.invalid/api/',
          dataBaseUrl: 'https://example.invalid/data/',
        ),
      ),
      sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
      sessionProfileProvider.overrideWithValue(
        UserProfile.fromUserJson({
          'login': 'fixture-owner',
          'DiscountPercentage': discount,
          'DiscountClient': subsidy,
          'MinimumPaymentAmount': 0,
          'MinimumOrderAmount': 0,
          'Limit': 1234.56,
          'LimitPeriod': 'day',
          'order': [
            {
              'date': '2030-01-02T23:59:00-12:00',
              'status': 'Принят',
              'sum': 190.5,
              'dishes': [
                {
                  'dish': 'known-id',
                  'name': 'Суп',
                  'quantity': 1.0,
                  'sum': 190.5,
                },
              ],
            },
          ],
        }),
      ),
      menuControllerProvider.overrideWith(_Menu.new),
      menuAllowedDatesProvider.overrideWith(_Dates.new),
      if (draft) cartEditControllerProvider.overrideWith(_PreparedEdit.new),
      cartRepositoryProvider.overrideWithValue(null),
      cartDayEditPermissionProvider.overrideWith((ref, dateKey) => true),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    await container.read(menuControllerProvider.future);
    await container.read(menuAllowedDatesProvider.future);
    await container.read(cartPersistenceControllerProvider.notifier).ready;
    if (draft) {
      container.read(cartDraftProvider.notifier).replaceAll({
        '2030-01-02': {'known-id': 1, 'missing-technical-id': 1},
      });
      await container
          .read(cartPersistenceControllerProvider.notifier)
          .persistNow();
    }
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final conditions in [
    (discount: 5.0, subsidy: 0, total: 181),
    (discount: 5.0, subsidy: 50, total: 131),
    (discount: 100.0, subsidy: 0, total: 0),
  ]) {
    testWidgets('цена корзины после скидок $conditions', (tester) async {
      final container = await _mount(
        tester,
        const CartPage(),
        draft: true,
        discount: conditions.discount,
        subsidy: conditions.subsidy,
      );
      final price = find.text(
        '190,50 ₽ ${conditions.total} ₽ × 1 · Итого: ${conditions.total} ₽',
      );
      expect(price, findsOneWidget);
      final span = tester.widget<Text>(price).textSpan! as TextSpan;
      expect(
        (span.children!.first as TextSpan).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(find.text('Ср\n02.01'), findsWidgets);
      expect(find.textContaining(AppStrings.cartDayTotal), findsOneWidget);
      container
          .read(cartDraftProvider.notifier)
          .increment('2030-01-02', 'known-id');
      await tester.pumpAndSettle();
      final total = conditions.discount == 100 ? 0 : 362 - conditions.subsidy;
      final unit = total / 2;
      expect(
        find.text(
          '190,50 ₽ ${unit == unit.roundToDouble() ? unit.toInt() : unit.toStringAsFixed(2).replaceAll('.', ',')} ₽ × 2 · Итого: $total ₽',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'корзина: даты, копейки, недоступное блюдо и подписи количества на узком экране',
    (tester) async {
      final container = await _mount(tester, const CartPage(), draft: true);
      expect(find.text('Ср\n02.01'), findsOneWidget);
      expect(find.textContaining(AppStrings.cartDayTotal), findsOneWidget);
      final dayTitle = find.descendant(
        of: find.byType(Card),
        matching: find.text('Ср\n02.01'),
      );
      final clearDay = find.text(AppStrings.cartClearDay);
      final card = find.ancestor(of: dayTitle, matching: find.byType(Card));
      expect(
        tester.getRect(clearDay).left,
        greaterThan(tester.getRect(dayTitle).right),
      );
      expect(
        tester.getRect(clearDay).right,
        greaterThan(tester.getRect(card).right - 36),
      );
      expect(
        find.text('190,50 ₽ × 1 · ${AppStrings.cartTotal}: 191 ₽'),
        findsOneWidget,
      );
      expect(find.textContaining('missing-technical-id'), findsNothing);
      expect(find.textContaining('known-id'), findsNothing);
      expect(find.text(AppStrings.cartUnavailableDish), findsOneWidget);
      expect(find.byTooltip(AppStrings.menuIncreaseQuantity), findsNWidgets(2));
      expect(find.byTooltip(AppStrings.menuDecreaseQuantity), findsNWidgets(2));
      await tester.ensureVisible(
        find.byTooltip(AppStrings.menuIncreaseQuantity).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppStrings.menuIncreaseQuantity).first);
      await tester.pumpAndSettle();
      expect(container.read(cartDraftProvider)['2030-01-02']?['known-id'], 2);
      expect(
        find.text('190,50 ₽ × 2 · ${AppStrings.cartTotal}: 381 ₽'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('клик по дню корзины передаёт дату меню', (tester) async {
    String? opened;
    await _mount(
      tester,
      CartPage(onOpenDay: (dateKey) => opened = dateKey),
      draft: true,
    );
    final dayTitle = find.byKey(const ValueKey('cart-open-day-2030-01-02'));
    await tester.ensureVisible(dayTitle);
    await tester.tap(dayTitle);
    await tester.pump();
    expect(opened, '2030-01-02');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'общие действия корзины остаются на месте при прокрутке позиций',
    (tester) async {
      await _mount(tester, const CartPage(), draft: true);
      tester.view.physicalSize = const Size(360, 360);
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('cart-save-all'));
      expect(find.byKey(const ValueKey('cart-sticky-header')), findsNothing);
      expect(header, findsOneWidget);
      final top = tester.getTopLeft(header).dy;
      await tester.drag(
        find.byKey(const ValueKey('cart-items-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, top);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'история использует календарный день и копейки, количество без .0',
    (tester) async {
      await _mount(tester, const OrdersPage());
      expect(find.text('02.01.2030 · Принят'), findsNothing);
      expect(find.text('Принят'), findsOneWidget);
      expect(find.text('Ср 02.01.30'), findsOneWidget);
      expect(find.text('Суп × 1 — 190,50 ₽'), findsOneWidget);
      expect(find.textContaining('2030-01-02T'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'профиль сохраняет дробный лимит и прежнюю семантику отсутствующих условий',
    (tester) async {
      await _mount(
        tester,
        const Scaffold(body: SingleChildScrollView(child: ProfileSummary())),
      );
      expect(find.text('1\u00a0234,56 ₽'), findsOneWidget);
      expect(find.text(AppStrings.profileValueMissing), findsNothing);
      expect(find.text(AppStrings.profileLimitNone), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
