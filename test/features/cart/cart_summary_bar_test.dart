import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/adaptive_app_shell.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_summary_bar.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Owner extends Notifier<UserProfile?> {
  @override
  UserProfile? build() =>
      UserProfile.fromUserJson({'login': 'owner-a', 'DiscountPercentage': 10});
  void change(String? login) =>
      state = login == null ? null : UserProfile.fromUserJson({'login': login});
}

final _owner = NotifierProvider<_Owner, UserProfile?>(_Owner.new);

class _Menu extends MenuController {
  @override
  Future<List<MenuWeek>> build() async => [
    MenuWeek(
      weekType: 'current',
      days: [
        for (final n in [2, 3])
          MenuDay(
            dateKey: '2030-01-0$n',
            date: DateTime(2030, 1, n),
            categories: [
              MenuCategory(
                categoryId: 'c',
                categoryName: 'Супы',
                dishes: [
                  MenuDish(
                    dishId: 'd',
                    dishName: 'Суп',
                    price: n == 2 ? 100 : 200,
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
  ];
  void removeMenu() => state = const AsyncData([]);
}

class _Dates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => {'2030-01-02', '2030-01-03'};
  void closeDays() => state = const AsyncData(<String>{'2030-01-09'});
}

class _PreparedEdit extends CartEditController {
  @override
  CartEditState build() => ref.watch(_owner)?.login != 'owner-a'
      ? const CartEditState()
      : const CartEditState(
          dateKey: '2030-01-02',
          owner: 'owner-a',
          revision: 'test-revision',
        );
}

Future<ProviderContainer> mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool pending = false,
  VoidCallback? open,
  int selected = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig.parse(
          environment: 'test',
          apiBaseUrl: 'https://example.invalid/api/',
          dataBaseUrl: 'https://example.invalid/data/',
          appVersionUrl: 'https://example.invalid/version.json',
        ),
      ),
      sessionProfileProvider.overrideWith((ref) => ref.watch(_owner)),
      sessionStatusProvider.overrideWith(
        (ref) => ref.watch(_owner) == null
            ? SessionStatus.signedOut
            : SessionStatus.signedIn,
      ),
      cartEditControllerProvider.overrideWith(_PreparedEdit.new),
      menuControllerProvider.overrideWith(_Menu.new),
      menuAllowedDatesProvider.overrideWith(_Dates.new),
      if (pending) cartSubmissionPricingProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    await container.read(menuControllerProvider.future);
    await container.read(menuAllowedDatesProvider.future);
    await container.read(cartPersistenceControllerProvider.notifier).ready;
    container.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'d': 2},
      '2030-01-03': {'d': 3},
    });
    await container
        .read(cartPersistenceControllerProvider.notifier)
        .persistNow();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: AdaptiveAppShell(
          selectedIndex: selected,
          menuPanel: const SizedBox(),
          cartPanel: const SizedBox(),
          onDaySelected: () {},
          onMenuSelected: () {},
          onDestinationSelected: (_) {},
          bottomSummary: CartSummaryBar(onOpenCart: open ?? () {}),
          child: const SizedBox.expand(key: ValueKey('content')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'итог выбранного дня учитывает скидку; действие только вызывает переход',
    (tester) async {
      var opened = 0;
      final c = await mount(tester, open: () => opened++);
      expect(find.text('Порций: 2'), findsOneWidget);
      expect(find.text('180 ₽'), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-summary-warning')), findsNothing);
      final before = c.read(cartDraftProvider);
      await tester.tap(find.byKey(const ValueKey('cart-summary-open')));
      await tester.pump();
      expect(opened, 1);
      expect(c.read(cartDraftProvider), before);
      final bar = tester.getRect(
        find.byKey(const ValueKey('cart-summary-bar')),
      );
      final nav = tester.getRect(
        find.byKey(const ValueKey('order-bottom-bar')),
      );
      expect(bar.bottom, lessThanOrEqualTo(nav.top));
      expect(
        tester.getRect(find.byKey(const ValueKey('content'))).bottom,
        lessThanOrEqualTo(bar.top),
      );
    },
  );
  testWidgets('без расчёта вместо нуля — сумма уточняется', (tester) async {
    await mount(tester, pending: true);
    expect(find.text(AppStrings.cartAmountPending), findsOneWidget);
    expect(find.text('0 ₽'), findsNothing);
  });
  testWidgets(
    'закрытые дни предупреждают; пропавшее меню не показывает частичную сумму',
    (tester) async {
      final c = await mount(tester);
      (c.read(menuAllowedDatesProvider.notifier) as _Dates).closeDays();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.cartReviewFreshness), findsOneWidget);
      expect(find.text('180 ₽'), findsOneWidget);
      (c.read(menuControllerProvider.notifier) as _Menu).removeMenu();
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.cartAmountPending), findsOneWidget);
      expect(find.text('180 ₽'), findsNothing);
    },
  );
  testWidgets('смена владельца и выход скрывают прежний итог', (tester) async {
    final c = await mount(tester);
    c.read(_owner.notifier).change('owner-b');
    c.read(sessionProfileProvider);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
    expect(c.read(cartDraftProvider), isEmpty);
    c.read(cartDraftProvider.notifier).replaceAll({
      '2030-01-02': {'d': 1},
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
    c.read(_owner.notifier).change(null);
    c.read(sessionProfileProvider);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
  });
  for (final width in <double>[320, 390, 599, 600, 1199, 1200, 1440]) {
    testWidgets(
      'полоса $width и текст 1,6: только мобильное меню без перекрытий',
      (tester) async {
        await mount(tester, width: width, scale: 1.6);
        expect(
          find.byKey(const ValueKey('cart-summary-bar')),
          width < 600 ? findsOneWidget : findsNothing,
        );
        if (width < 600) {
          expect(
            find.byKey(const ValueKey('cart-summary-open')).hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final selected in [1, 2, 3]) {
    testWidgets('полоса отсутствует в разделе $selected', (tester) async {
      await mount(tester, selected: selected);
      expect(find.byKey(const ValueKey('cart-summary-bar')), findsNothing);
    });
  }
}
