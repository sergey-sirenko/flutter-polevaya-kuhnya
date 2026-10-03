import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_freshness.dart';
import 'package:polevaya_kuhnya/features/cart/cart_models.dart';
import 'package:polevaya_kuhnya/features/cart/cart_order_request.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_reorder.dart';
import 'package:polevaya_kuhnya/features/cart/pricing.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

MenuWeek _week() {
  return MenuWeek(
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
                dishId: 'd1',
                dishName: 'Борщ',
                price: 100,
                menuOrder: 1,
              ),
              const MenuDish(
                dishId: 'd2',
                dishName: 'Щи',
                price: 80,
                menuOrder: 2,
              ),
            ],
          ),
        ],
      ),
      MenuDay(
        dateKey: '2030-01-03',
        date: DateTime(2030, 1, 3),
        categories: [
          MenuCategory(
            categoryId: 'c1',
            categoryName: 'Супы',
            dishes: [
              const MenuDish(
                dishId: 'd1',
                dishName: 'Борщ',
                price: 110,
                menuOrder: 1,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('операции: add, remove, clearDay, clearAll', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final draft = container.read(cartDraftProvider.notifier);
    draft.addItem('2030-01-02', 'd1');
    draft.addItem('2030-01-02', 'd1');
    draft.addItem('2030-01-03', 'd2');
    expect(container.read(cartModelProvider).days, hasLength(2));
    draft.removeItem('2030-01-02', 'd1');
    expect(container.read(cartModelProvider).dayFor('2030-01-02'), isNull);
    draft.clearDay('2030-01-03');
    expect(container.read(cartModelProvider).isEmpty, isTrue);
    draft.replaceAll({
      '2030-01-02': {'d1': 2},
      '2030-01-03': {'d2': 1},
    });
    draft.clearAll();
    expect(container.read(cartDraftProvider), isEmpty);
  });

  test('расчёт корзины использует единый pricing-модуль', () {
    final cart = Cart.fromDraft({
      '2030-01-02': {'d1': 2, 'd2': 1},
    });
    final conditions = clientPricingConditionsFromUser({
      'DiscountPercentage': 10,
      'DiscountClient': 0,
      'DiscountPromotion': 0,
      'MinimumPayment': 0,
      'MinimumOrder': 0,
      'Limit': 0,
    });
    final view = buildCartPricingView(
      cart: cart,
      weeks: [_week()],
      conditions: conditions,
    );
    expect(view.days, hasLength(1));
    expect(view.days.single.totals.baseTotal, 280);
    expect(view.days.single.totals.finalTotal, 252);
    expect(view.missingDishCount, 0);
  });

  test('ограничения минимума и лимита видны в предпросмотре', () {
    final cart = Cart.fromDraft({
      '2030-01-02': {'d2': 1},
    });
    final conditions = clientPricingConditionsFromUser({
      'DiscountPercentage': 0,
      'DiscountClient': 0,
      'DiscountPromotion': 0,
      'MinimumPaymentAmount': 0,
      'MinimumOrderAmount': 200,
      'Limit': 50,
      'LimitPeriod': 'день',
    });
    final view = buildCartPricingView(
      cart: cart,
      weeks: [_week()],
      conditions: conditions,
    );
    expect(view.conditions.minimumOrderAmount, 200);
    expect(view.conditions.limit, 50);
    expect(view.days.single.totals.finalTotal, 80);
    expect(view.days.single.minimum.isBelowMinimum, isTrue);
    expect(view.days.single.limit.isExceeded, isTrue);
    expect(view.hasBlockingConstraint, isTrue);
  });

  test('CartDraftSnapshot сериализуется и отвергает чужую версию', () {
    final snapshot = CartDraftSnapshot(
      version: cartDraftFormatVersion,
      ownerKey: 'user-a',
      quantities: {
        '2030-01-02': {'d1': 2},
      },
    );
    final parsed = CartDraftSnapshot.tryParse(snapshot.toJson());
    expect(parsed?.ownerKey, 'user-a');
    expect(parsed?.quantities['2030-01-02']?['d1'], 2);
    expect(
      CartDraftSnapshot.tryParse({
        'version': 999,
        'ownerKey': 'user-a',
        'quantities': {},
      }),
      isNull,
    );
  });

  test('черновик сохраняется и читается по владельцу', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = CartDraftStore(
      config: AppConfig.parse(
        appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
        environment: 'test',
        apiBaseUrl: 'https://example.test/api/',
        dataBaseUrl: 'https://example.test/data/',
      ),
      prefs: prefs,
    );
    await store.save(
      const CartDraftSnapshot(
        version: cartDraftFormatVersion,
        ownerKey: 'alice',
        quantities: {
          '2030-01-02': {'d1': 3},
        },
      ),
    );
    expect((await store.load('alice'))?.quantities['2030-01-02']?['d1'], 3);
    expect(await store.load('bob'), isNull);
    await store.clear('alice');
    expect(await store.load('alice'), isNull);
  });

  test('пустая следующая неделя не затирает блюда текущей с той же датой', () {
    final cart = Cart.fromDraft({
      '2030-01-02': {'d1': 2},
    });
    final weeks = [
      _week(),
      MenuWeek(
        weekType: 'next',
        days: [
          MenuDay(
            dateKey: '2030-01-02',
            date: DateTime(2030, 1, 2),
            hasDelivery: false,
            categories: const [],
          ),
        ],
      ),
    ];
    final issues = checkCartFreshness(
      cart: cart,
      weeks: weeks,
      allowedDateKeys: {'2030-01-02'},
    );
    expect(issues, isEmpty);
    final view = buildCartPricingView(
      cart: cart,
      weeks: weeks,
      conditions: clientPricingConditionsFromUser(const {}),
    );
    expect(view.missingDishCount, 0);
    expect(view.days.single.weekType, 'current');
    expect(view.days.single.lines.single.dishName, 'Борщ');
    expect(view.days.single.lines.single.missingFromMenu, isFalse);
    expect(view.cartTotals.finalTotal, 200);
  });

  test('актуальность: закрытая дата и отсутствующее блюдо', () {
    final cart = Cart.fromDraft({
      '2030-01-02': {'d1': 1, 'gone': 1},
      '2030-01-09': {'d1': 1},
    });
    final issues = checkCartFreshness(
      cart: cart,
      weeks: [_week()],
      allowedDateKeys: {'2030-01-02'},
      knownPrices: {'2030-01-02|d1': 90},
    );
    expect(
      issues.map((i) => i.kind),
      containsAll([
        CartFreshnessKind.missingDish,
        CartFreshnessKind.closedDate,
        CartFreshnessKind.priceChanged,
      ]),
    );
  });

  test('запрос заказа включает пустые разрешённые дни и revision', () {
    final cart = Cart.fromDraft({
      '2030-01-02': {'d1': 1},
    });
    final pricing = buildCartPricingView(
      cart: cart,
      weeks: [_week()],
      conditions: clientPricingConditionsFromUser(const {}),
    );
    final order = buildBasketOrderDays(
      cart: cart,
      pricing: pricing,
      allowedDateKeys: {'2030-01-02', '2030-01-03'},
      revisionsByDate: {'2030-01-02': 'abc', '2030-01-03': 'none'},
      weeksForNames: [_week()],
    );
    expect(order, hasLength(2));
    expect(order[0]['date'], '2030-01-02T00:00:00');
    expect((order[0]['dishes'] as List), hasLength(1));
    expect(order[0]['revision'], 'abc');
    expect(order[1]['dishes'], isEmpty);
    expect(order[1]['revision'], 'none');
    final body = buildBasketRequestBody(
      submissionId: '11111111-1111-4111-8111-111111111111',
      orderDays: order,
    );
    expect(body['submissionId'], isNotEmpty);
    expect(body['order'], order);
  });

  test(
    'повтор заказа переносит доступные позиции и пропускает закрытый день',
    () {
      final orderDay = UserOrderDay.fromJson({
        'date': '2030-01-02T00:00:00',
        'weekType': 'current',
        'changes': true,
        'status': 'Доступен',
        'dishes': [
          {
            'dish': 'd1',
            'name': 'Борщ',
            'menunumber': 1,
            'quantity': 2,
            'sum': 200,
            'DiscountPercentage': 0,
            'DiscountClient': 0,
          },
          {
            'dish': 'missing',
            'name': 'Нет',
            'menunumber': 2,
            'quantity': 1,
            'sum': 10,
            'DiscountPercentage': 0,
            'DiscountClient': 0,
          },
        ],
        'discount': 0,
        'sum': 200,
      });
      final ok = reorderOrderDayToDraft(
        orderDay: orderDay,
        targetDateKey: '2030-01-02',
        weeks: [_week()],
        allowedDateKeys: {'2030-01-02'},
      );
      expect(ok.addedCount, 1);
      expect(ok.draft['2030-01-02']?['d1'], 2);
      expect(ok.skippedMissing, 1);
      expect(ok.currentPriceNotes.single, contains('100'));

      final closed = reorderOrderDayToDraft(
        orderDay: orderDay,
        targetDateKey: '2030-01-02',
        weeks: [_week()],
        allowedDateKeys: {'2030-01-03'},
        existingDraft: const {
          '2030-01-03': {'d1': 4},
        },
      );
      expect(closed.addedCount, 0);
      expect(closed.draft, {
        '2030-01-03': {'d1': 4},
      });
      expect(closed.skippedClosed, 2);
    },
  );

  test('прошлый день переносится на выбранный будущий с текущей ценой', () {
    final past = UserOrderDay.fromJson({
      'date': '2020-06-01T00:00:00',
      'weekType': 'current',
      'changes': false,
      'status': 'Закрыт',
      'dishes': [
        {
          'dish': 'd1',
          'name': 'Старый борщ',
          'menunumber': 1,
          'quantity': 2,
          'sum': 50,
          'DiscountPercentage': 0,
          'DiscountClient': 0,
        },
        {
          'dish': 'gone',
          'name': 'Нет в меню',
          'menunumber': 2,
          'quantity': 1,
          'sum': 10,
          'DiscountPercentage': 0,
          'DiscountClient': 0,
        },
      ],
      'discount': 0,
      'sum': 50,
    });
    final result = reorderOrderDayToDraft(
      orderDay: past,
      targetDateKey: '2030-01-03',
      weeks: [_week()],
      allowedDateKeys: {'2030-01-03'},
      existingDraft: const {
        '2030-01-02': {'d2': 3},
        '2030-01-03': {'d9': 1},
      },
    );
    expect(result.addedCount, 1);
    expect(result.skippedMissing, 1);
    expect(result.draft['2030-01-02'], {'d2': 3});
    expect(result.draft['2030-01-03'], {'d9': 1, 'd1': 2});
    expect(result.draft.containsKey('2020-06-01'), isFalse);
    expect(result.currentPriceNotes.single, contains('110'));
    expect(
      reorderTargetDays(
        weeks: [_week()],
        allowedDateKeys: {'2030-01-03'},
      ).map((day) => day.dateKey),
      ['2030-01-03'],
    );
  });
}
