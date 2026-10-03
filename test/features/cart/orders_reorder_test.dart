import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/orders_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart' as menu;
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

MenuWeek _week({required bool includeOrderedDish}) {
  return MenuWeek(
    weekType: 'current',
    days: [
      MenuDay(
        dateKey: '2030-01-02',
        date: DateTime(2030, 1, 2),
        categories: [],
      ),
      MenuDay(
        dateKey: '2030-01-03',
        date: DateTime(2030, 1, 3),
        dayName: 'Четверг',
        categories: [
          MenuCategory(
            categoryId: 'c1',
            categoryName: 'Супы',
            dishes: [
              if (includeOrderedDish)
                const MenuDish(dishId: 'd1', dishName: 'Борщ', price: 110),
            ],
          ),
        ],
      ),
    ],
  );
}

final _menuWeeks = Provider<List<MenuWeek>>((ref) => const []);

final _allowedDates = Provider<Set<String>>((ref) => const {});

class _FixedMenu extends menu.MenuController {
  @override
  Future<List<MenuWeek>> build() async => ref.watch(_menuWeeks);
}

class _FixedDates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => ref.watch(_allowedDates);
}

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  required bool includeOrderedDish,
}) async {
  SharedPreferences.setMockInitialValues({});
  final profile = UserProfile.fromUserJson({
    'name': 'Org',
    'employee': 'Emp',
    'login': '',
    'order': [
      {
        'date': '2030-01-02T00:00:00',
        'status': 'Закрыт',
        'dishes': [
          {'dish': 'd1', 'name': 'Борщ', 'quantity': 2, 'sum': 50},
        ],
        'sum': 50,
      },
    ],
  });
  late ProviderContainer container;
  final router = GoRouter(
    initialLocation: '/orders',
    routes: [
      GoRoute(path: '/orders', builder: (context, state) => const OrdersPage()),
      GoRoute(
        path: '/cart',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('cart-opened'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
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
        sessionProfileProvider.overrideWithValue(profile),
        _menuWeeks.overrideWithValue([
          _week(includeOrderedDish: includeOrderedDish),
        ]),
        _allowedDates.overrideWithValue({'2030-01-03'}),
        menu.menuControllerProvider.overrideWith(_FixedMenu.new),
        menuAllowedDatesProvider.overrideWith(_FixedDates.new),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(routerConfig: router);
        },
      ),
    ),
  );
  await tester.pump();
  await container.read(menu.menuControllerProvider.future);
  await container.read(menuAllowedDatesProvider.future);
  await tester.pumpAndSettle();
  container.read(cartDraftProvider.notifier).replaceAll({
    '2030-01-02': {'d2': 3},
  });
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final includeDish in [true, false]) {
    testWidgets('состав без повторения не меняет корзину: $includeDish', (
      tester,
    ) async {
      final container = await _mount(tester, includeOrderedDish: includeDish);
      expect(find.text(AppStrings.ordersReorder), findsNothing);
      expect(find.text('Emp'), findsOneWidget);
      expect(find.text('Org'), findsNothing);
      expect(find.text('Борщ × 2 — 50 ₽'), findsOneWidget);
      expect(container.read(cartDraftProvider), {
        '2030-01-02': {'d2': 3},
      });
      expect(tester.takeException(), isNull);
    });
  }
}
