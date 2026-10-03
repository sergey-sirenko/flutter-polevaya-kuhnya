import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_models.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/orders_page.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/compatible_version.dart';

import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';

const _a = '2030-01-02';
const _b = '2030-01-09';
const _dish = '11111111-1111-4111-8111-111111111111';
const _missing = '22222222-2222-4222-8222-222222222222';
const _device = '33333333-3333-4333-8333-333333333333';
const _scope =
    'repeat-v1:44444444-4444-4444-8444-444444444444:00000000-0000-0000-0000-000000000000';
final _config = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.example.invalid/Obmen/',
  dataBaseUrl: 'https://data.example.invalid/data/',
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
);
final _harness = Provider<_Harness>((ref) => throw UnimplementedError());
final _generation = NotifierProvider<_Generation, int>(_Generation.new);

class _Generation extends Notifier<int> {
  @override
  int build() => 0;
  void change() => state++;
}

class _Session extends SessionController {
  @override
  SessionState build() => const SessionState(SessionStatus.signedIn, 0);
  @override
  UserProfile? get profile => ref.read(sessionProfileProvider);
  @override
  Future<UserProfile> refreshProfile() async => profile!;
}

class _Menu extends MenuController {
  @override
  Future<List<MenuWeek>> build() async => ref.read(_harness).weeks;
  @override
  Future<void> reload() async => state = AsyncData(ref.read(_harness).weeks);
}

class _Dates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => ref.read(_harness).allowed;
  @override
  Future<void> reload() async => state = AsyncData(ref.read(_harness).allowed);
}

http.Response _json(Map<String, Object?> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);
Map<String, Object?> _day(
  String date, {
  String status = 'ready',
  String revision = 'none',
  int offset = 7,
  bool missing = false,
}) => {
  'date': '${date}T00:00:00',
  'revision': revision,
  'status': status,
  'sourceDate': status == 'ready'
      ? DateTime.parse('${date}T00:00:00Z')
            .subtract(Duration(days: offset))
            .toIso8601String()
            .substring(0, 19)
      : null,
  'dishes': status == 'ready'
      ? [
          {'dish': _dish, 'name': 'Суп раньше', 'quantity': 2},
          if (missing)
            {'dish': _missing, 'name': 'Исчезнувшее блюдо', 'quantity': 3},
        ]
      : [],
};

class _Harness {
  _Harness({CartRepeatStore? repeatStore}) {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/Orders/repeat')) {
        repeatCalls++;
        final dates = (body['dates'] as List).cast<String>();
        requested.add(dates);
        expect(body['token'], 'synthetic-token');
        expect(body['deviceId'], _device);
        await held?.future;
        if (failRepeat) return http.Response('failure', 500);
        return _json({
          'success': true,
          'ownerScope': scope,
          'days': [
            for (final iso in dates)
              responses[iso.substring(0, 10)] ?? _day(iso.substring(0, 10)),
          ],
        });
      }
      if (request.url.path.endsWith('/basketstate')) {
        return _json({
          'success': true,
          'states': [
            for (final d in body['dates'] as List)
              {
                'date': (d as String).substring(0, 10),
                'revision': revisions[d.substring(0, 10)] ?? 'none',
              },
          ],
        });
      }
      if (request.url.path.endsWith('/basket')) {
        sent.add(Map<String, dynamic>.from(body));
        if (loseBasket) return http.Response('lost response', 500);
        return accepted(body['submissionId'] as String);
      }
      if (request.url.path.endsWith('/basketresult')) {
        resultIds.add(body['submissionId'] as String);
        if (resultNotFound) {
          return _json({
            'success': true,
            'submission': {'id': body['submissionId'], 'status': 'not_found'},
          });
        }
        return accepted(body['submissionId'] as String);
      }
      throw StateError('Unexpected endpoint ${request.url.path}');
    });
    container = ProviderContainer(
      overrides: [
        _harness.overrideWithValue(this),
        appConfigProvider.overrideWithValue(_config),
        appVersionControllerProvider.overrideWith(_Version.new),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
        sessionControllerProvider.overrideWith(_Session.new),
        sessionProfileProvider.overrideWith((ref) {
          ref.watch(_generation);
          return UserProfile.fromUserJson({
            'login': 'alpha',
            'name': 'Тест',
            ...profileFields,
          });
        }),
        sessionApiProvider.overrideWith((ref) {
          ref.watch(_generation);
          var current = true;
          ref.onDispose(() => current = false);
          return SessionApi(
            api: ApiClient(config: _config, client: client),
            credentials: SessionCredentials(
              token: 'synthetic-token',
              deviceId: _device,
            ),
            isCurrent: () => current,
            onUnauthorized: () async {},
          );
        }),
        if (repeatStore != null)
          cartRepeatStoreProvider.overrideWithValue(repeatStore),
        menuControllerProvider.overrideWith(_Menu.new),
        menuAllowedDatesProvider.overrideWith(_Dates.new),
      ],
    );
    container.listen(cartSubmitControllerProvider, (_, _) {});
    container.listen(cartRepeatControllerProvider, (_, _) {});
    container.listen(cartPersistenceControllerProvider, (_, _) {});
  }
  late final ProviderContainer container;
  String scope = _scope;
  bool failRepeat = false;
  bool loseBasket = false;
  bool resultNotFound = false;
  bool removeDish = false;
  int price = 200;
  int repeatCalls = 0;
  Completer<void>? held;
  Set<String> allowed = {_a, _b};
  Map<String, Object?> profileFields = {};
  final responses = <String, Map<String, Object?>>{};
  final revisions = <String, String>{};
  final sent = <Map<String, dynamic>>[];
  final resultIds = <String>[];
  final requested = <List<String>>[];
  List<MenuWeek> get weeks => [
    for (final date in [_a, _b])
      MenuWeek(
        weekType: date == _a ? 'current' : 'next',
        days: [
          MenuDay(
            dateKey: date,
            date: DateTime.parse(date),
            categories: [
              MenuCategory(
                categoryId: 'soup',
                categoryName: 'Супы',
                dishes: [
                  if (!removeDish)
                    MenuDish(
                      dishId: _dish,
                      dishName: 'Суп сейчас',
                      price: price,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
  ];
  http.Response accepted(String id) => _json({
    'success': true,
    'submission': {'id': id, 'status': 'accepted'},
    'order': [
      for (final day in sent.last['order'] as List)
        {
          'date': (day as Map)['date'],
          'finalPayable': 400,
          'finalPayableScope': 'employee_dishes',
        },
    ],
  });
  CartRepeatController get repeat =>
      container.read(cartRepeatControllerProvider.notifier);
  CartEditState get edit => container.read(cartEditControllerProvider);
  Map<String, Map<String, int>> get draft => container.read(cartDraftProvider);
  CartDraftController get selection =>
      container.read(cartDraftProvider.notifier);
  Future<void> settle() async {
    await container.read(menuControllerProvider.future);
    await container.read(menuAllowedDatesProvider.future);
    await container.read(cartPersistenceControllerProvider.notifier).ready;
    await repeat.ready;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<RepeatSnapshot?> saved() =>
      container.read(cartRepeatStoreProvider).load('alpha', _device);
  void dispose() => container.dispose();
}

class _FailingStore extends CartRepeatStore {
  _FailingStore() : super(_config);
  @override
  Future<void> save(
    String login,
    String device,
    RepeatSnapshot snapshot,
  ) async => throw StateError('disk full');
}

class _DelayedStore extends CartRepeatStore {
  _DelayedStore() : super(_config);
  final entered = Completer<void>();
  final release = Completer<void>();
  bool pause = true;
  @override
  Future<void> save(
    String login,
    String device,
    RepeatSnapshot snapshot,
  ) async {
    if (pause) {
      entered.complete();
      await release.future;
      pause = false;
    }
    await super.save(login, device, snapshot);
  }
}

class _Version extends CompatibleVersionController {
  void requireUpdate() =>
      state = const AppVersionCheck(AppVersionStatus.required);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('FL-UX-28 общая отмена удаляет повтор всех дней', (tester) async {
    late _Harness h;
    await tester.runAsync(() async {
      h = _Harness();
      await h.settle();
      expect(await h.repeat.repeat([_a, _b]), isTrue);
      await h.repeat.persistNow();
    });
    addTearDown(h.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: CartPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('cart-cancel-all')));
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    expect(h.draft, isEmpty);
    expect(h.edit.active, isFalse);
    expect(await tester.runAsync(h.saved), isNull);
    expect(h.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('повтор недоступен при блокировке версии', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    expect(await h.repeat.repeat([_a, _b]), true);
    (h.container.read(appVersionControllerProvider.notifier) as _Version)
        .requireUpdate();
    expect(await h.repeat.repeat([_a]), false);
    expect(h.repeatCalls, 1);
    expect(
      await h.container.read(cartEditControllerProvider.notifier).begin(_b),
      false,
    );
    expect(h.draft.length, 2);
  });

  test('скидка/дотация и ограничения берутся из текущего профиля', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    h.profileFields = {'DiscountPercentage': 20, 'DiscountClient': 50};
    h.container.invalidate(sessionProfileProvider);
    expect(await h.repeat.repeat([_a, _b]), true);
    expect(h.container.read(cartPricingProvider)!.cartTotals.finalTotal, 540);
    h.profileFields = {'MinimumOrderAmount': 1000};
    h.container.invalidate(sessionProfileProvider);
    await h.container.read(cartSubmitControllerProvider.notifier).submit();
    expect(h.sent, isEmpty);
    expect(h.draft.length, 2);
    h.profileFields = {'Limit': 100};
    h.container.invalidate(sessionProfileProvider);
    await h.container.read(cartSubmitControllerProvider.notifier).submit();
    expect(h.sent, isEmpty);
    expect(h.container.read(cartPricingProvider)!.hasBlockingConstraint, true);
  });

  testWidgets('навигация корзина → каталог → заказы сохраняет все дни', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _Harness h;
    await tester.runAsync(() async {
      h = _Harness();
      await h.settle();
      await h.repeat.repeat([_a, _b]);
    });
    addTearDown(h.dispose);
    final router = h.container.read(routerProvider);
    router.go('/cart');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const FieldKitchenApp(),
      ),
    );
    await tester.pumpAndSettle();
    for (final route in ['/menu', '/orders', '/cart']) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(h.edit.revisions.keys, containsAll([_a, _b]));
      expect(h.container.read(editingCartProvider).days.length, 2);
      expect(h.container.read(cartDayEditableProvider(_b)), true);
    }
    expect(tester.takeException(), null);
  });

  test(
    'черновик изменён во время записи снимка: состав и изменения сохранены',
    () async {
      final store = _DelayedStore();
      final h = _Harness(repeatStore: store);
      addTearDown(h.dispose);
      await h.settle();
      final loading = h.repeat.repeat([_a, _b]);
      await store.entered.future;
      h.selection.setQuantity(_a, _dish, 5);
      store.release.complete();
      expect(await loading, false);
      expect(h.draft, {
        _a: {_dish: 5},
      });
      expect(h.edit.active, false);
      expect(await h.saved(), null);
    },
  );

  test('найденный источник без доступных блюд не вызывает fallback', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    h.responses[_a] = _day(_a)
      ..['dishes'] = [
        {'dish': _missing, 'name': 'Нет в меню', 'quantity': 2},
      ];
    expect(await h.repeat.repeat([_a]), false);
    expect(h.repeatCalls, 1);
    expect(h.draft, isEmpty);
    expect(
      h.container.read(cartRepeatControllerProvider).message,
      contains('доступных блюд'),
    );
  });

  test('откат неуспешного добавления дня сохраняет последние правки старого повтора', () async {
    final store = _DelayedStore()..pause = false;
    final h = _Harness(repeatStore: store);
    addTearDown(h.dispose);
    await h.settle();
    expect(await h.repeat.repeat([_a]), true);
    await h.repeat.persistNow();
    store.pause = true;
    final loading = h.repeat.repeat([_b]);
    await store.entered.future;
    h.selection.setQuantity(_a, _dish, 5);
    store.release.complete();
    expect(await loading, false);
    expect(h.draft, {
      _a: {_dish: 5},
    });
    final saved = await h.saved();
    expect(saved!.quantities, {
      _a: {_dish: 5},
    });
    expect(saved.revisions.keys, [_a]);
  });

  test(
    'not_found разрешает неизменный повтор basket с тем же submissionId',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.settle();
      await h.repeat.repeat([_a, _b]);
      h.loseBasket = true;
      final submit = h.container.read(cartSubmitControllerProvider.notifier);
      await submit.submit();
      expect(h.sent.length, 1);
      h.loseBasket = false;
      h.resultNotFound = true;
      await submit.resolveUnknownOutcome();
      expect(h.sent.length, 2);
      expect(h.sent.last, h.sent.first);
      expect(h.resultIds.single, h.sent.first['submissionId']);
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.succeeded,
      );
    },
  );

  test(
    'две недели: прежнее количество, текущие цены и пропуск блюда без fallback',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.settle();
      h.responses[_a] = _day(_a, missing: true);
      h.responses[_b] = _day(_b, offset: 14);
      h.selection.setQuantity('2030-01-03', _dish, 9);
      expect(await h.repeat.repeat([_a, _b], selected: _a), true);
      expect(h.draft[_a], {_dish: 2});
      expect(h.draft[_b], {_dish: 2});
      expect(h.draft['2030-01-03'], {_dish: 9});
      expect(h.container.read(editingCartProvider).days.map((d) => d.dateKey), [
        _a,
        _b,
      ]);
      expect(h.container.read(cartPricingProvider)!.cartTotals.finalTotal, 800);
      expect(
        h.container.read(cartRepeatControllerProvider).message,
        contains('Исчезнувшее блюдо'),
      );
      expect(h.repeatCalls, 1);
      expect(await h.repeat.repeat([_a, _b]), false);
      expect(h.draft[_a]![_dish], 2);
      h.container.read(cartEditControllerProvider.notifier).selectRepeatDay(_b);
      h.container.read(cartEditControllerProvider.notifier).end();
      expect(h.edit.dateKey, _b);
      expect(h.edit.revisions.length, 2);
    },
  );

  test(
    'неперезапись local draft после сети, occupied/closed/no_history/ambiguous',
    () async {
      for (final status in ['occupied', 'closed', 'no_history', 'ambiguous']) {
        final h = _Harness();
        await h.settle();
        h.responses[_a] = _day(_a, status: status);
        h.held = Completer<void>();
        final loading = h.repeat.repeat([_a, _b]);
        while (h.repeatCalls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(await h.repeat.repeat([_a]), false);
        h.selection.setQuantity(_b, _dish, 7);
        h.held!.complete();
        expect(await loading, false);
        expect(h.draft, {
          _b: {_dish: 7},
        });
        expect(h.edit.active, false);
        h.dispose();
      }
    },
  );

  test(
    'ошибка сети, хранилища и устаревший экран не изменяют корзину',
    () async {
      for (final mode in ['network', 'store', 'view']) {
        final h = _Harness(
          repeatStore: mode == 'store' ? _FailingStore() : null,
        );
        await h.settle();
        h.failRepeat = mode == 'network';
        h.selection.setQuantity('2030-01-03', _dish, 5);
        expect(
          await h.repeat.repeat([_a], viewCurrent: () => mode != 'view'),
          false,
        );
        expect(h.draft, {
          '2030-01-03': {_dish: 5},
        });
        expect(h.edit.active, false);
        h.dispose();
      }
    },
  );

  test('смена сессии во время сети игнорирует поздний ответ', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    h.held = Completer<void>();
    final loading = h.repeat.repeat([_a]);
    while (h.repeatCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    h.container.read(_generation.notifier).change();
    h.held!.complete();
    expect(await loading, false);
    await h.settle();
    expect(h.edit.active, false);
    expect(h.draft, isEmpty);
    expect(await h.saved(), null);
  });

  test('очищенный день не отменяет заказ; пакет одним submissionId, success очищает снимки', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    expect(await h.repeat.repeat([_a, _b]), true);
    h.selection.clearDay(_a);
    await h.container.read(cartSubmitControllerProvider.notifier).submit();
    expect(h.sent.length, 1);
    expect((h.sent.single['order'] as List).length, 1);
    expect(h.sent.single['order'][0]['date'], '${_b}T00:00:00');
    expect(h.sent.single['order'][0]['dishes'], isNotEmpty);
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.succeeded,
    );
    expect(h.draft, isEmpty);
    expect(await h.saved(), null);
    expect(
      await h.container.read(cartRepositoryProvider)!.loadPending('alpha'),
      null,
    );
  });

  test(
    'две даты отправлены одной basket; потеря ответа сохраняет тот же пакет',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.settle();
      await h.repeat.repeat([_a, _b]);
      h.loseBasket = true;
      final submit = h.container.read(cartSubmitControllerProvider.notifier);
      await submit.submit();
      expect(h.sent.length, 1);
      expect((h.sent.single['order'] as List).length, 2);
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.outcomeUnknown,
      );
      final id = h.sent.single['submissionId'];
      expect(h.draft.length, 2);
      expect(await h.repeat.repeat([_a]), false);
      expect(
        await h.container.read(cartEditControllerProvider.notifier).begin(_b),
        false,
      );
      await submit.resolveUnknownOutcome();
      expect(h.sent.length, 1);
      expect(
        h.container.read(cartSubmitControllerProvider).submissionId,
        isNull,
      );
      expect(id, isNotEmpty);
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.succeeded,
      );
      expect(await h.saved(), null);
    },
  );

  test(
    'конфликт одной revision останавливает весь пакет, состав остаётся',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.settle();
      await h.repeat.repeat([_a, _b]);
      h.revisions[_b] = 'changed';
      await h.container.read(cartSubmitControllerProvider.notifier).submit();
      expect(h.sent, isEmpty);
      expect(h.draft.length, 2);
      expect(h.edit.blocked, true);
      expect((await h.saved())!.quantities[_a]![_dish], 2);
    },
  );

  test(
    'перезагрузка предлагает продолжение и сохраняет правки, цены пересчитаны',
    () async {
      final first = _Harness();
      await first.settle();
      await first.repeat.repeat([_a, _b]);
      first.selection.setQuantity(_a, _dish, 6);
      first.container
          .read(cartEditControllerProvider.notifier)
          .selectRepeatDay(_b);
      await first.repeat.persistNow();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs
          .getKeys()
          .where((k) => k.startsWith('field_kitchen.repeat.'))
          .map(prefs.getString)
          .join();
      expect(raw, contains(_scope));
      expect(raw, contains('"version":1'));
      expect(raw, isNot(contains('synthetic-token')));
      first.dispose();
      final h = _Harness();
      addTearDown(h.dispose);
      await h.settle();
      expect(h.edit.active, false);
      expect(h.container.read(cartRepeatControllerProvider).saved, isNotNull);
      expect(
        await h.container.read(cartEditControllerProvider.notifier).begin(_a),
        false,
      );
      h.price = 250;
      h.responses[_a] = _day(_a, status: 'no_history');
      expect(await h.repeat.resume(), true);
      expect(h.draft[_a]![_dish], 6);
      expect(h.edit.dateKey, _b);
      expect(
        h.container.read(cartPricingProvider)!.cartTotals.finalTotal,
        2000,
      );
    },
  );

  test('восстановление: чужой сотрудник, закрытие, revision, меню не перезаписывают снимок', () async {
    for (final mode in ['owner', 'closed', 'revision', 'menu']) {
      SharedPreferences.setMockInitialValues({});
      final first = _Harness();
      await first.settle();
      await first.repeat.repeat([_a]);
      first.selection.setQuantity(_a, _dish, 8);
      await first.repeat.persistNow();
      first.dispose();
      final h = _Harness();
      await h.settle();
      if (mode == 'owner') {
        h.scope = _scope.replaceFirst(
          '00000000-0000-0000-0000-000000000000',
          _device,
        );
      }
      if (mode == 'closed') {
        h.allowed = {_b};
      }
      if (mode == 'revision') {
        h.responses[_a] = _day(_a, revision: 'changed');
      }
      if (mode == 'menu') {
        h.removeDish = true;
      }
      expect(await h.repeat.resume(), false, reason: mode);
      expect(h.edit.active, false);
      expect((await h.saved())!.quantities[_a]![_dish], 8);
      expect(h.container.read(cartRepeatControllerProvider).saved, isNotNull);
      h.dispose();
    }
  });

  test('снимок изолирован окружением, API, устройством и login; повреждённый удаляется', () async {
    final store = CartRepeatStore(_config);
    final snapshot = RepeatSnapshot(
      ownerScope: _scope,
      selectedDateKey: _a,
      revisions: {_a: 'none'},
      quantities: {
        _a: {_dish: 2},
      },
    );
    await store.save('alpha', _device, snapshot);
    expect(await store.load('beta', _device), null);
    expect(await store.load('alpha', 'other-device'), null);
    final other = AppConfig.parse(
      environment: 'test',
      apiBaseUrl: 'https://other.example.invalid/Obmen/',
      dataBaseUrl: 'https://data.example.invalid/data/',
      appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
    );
    expect(await CartRepeatStore(other).load('alpha', _device), null);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    await prefs.setString(key, 'broken');
    final h = _Harness();
    addTearDown(h.dispose);
    await h.settle();
    expect(
      h.container.read(cartRepeatControllerProvider).recoveryBlocked,
      true,
    );
    expect(await h.repeat.repeat([_a]), false);
    await h.repeat.discard();
    expect(await h.saved(), null);
    expect(await h.repeat.repeat([_a]), true);
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('диалог Один/Все и общая корзина на $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _Harness h;
      await tester.runAsync(() async {
        h = _Harness();
        await h.settle();
      });
      addTearDown(h.dispose);
      var cart = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => cart
                  ? const CartPage()
                  : OrdersPage(
                      selectedDateKey: _a,
                      onRepeatReady: () => setState(() => cart = true),
                    ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Обновить историю'), findsNothing);
      await tester.tap(find.byTooltip('Повторить заказ'));
      await tester.pumpAndSettle();
      expect(find.text('Один'), findsOneWidget);
      expect(find.text('Все'), findsOneWidget);
      await tester.tap(find.text('Все'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(
        h.edit.revisions.length,
        2,
        reason: h.container.read(cartRepeatControllerProvider).message,
      );
      expect(find.byKey(const ValueKey('repeat-report')), findsNothing);
      expect(tester.takeException(), null);
      // Сам состав и права каждого дня сохраняются при смене ширины.
      tester.view.physicalSize = Size(width == 320 ? 1440 : 320, 1000);
      await tester.pumpAndSettle();
      expect(h.draft.length, 2);
      expect(h.container.read(cartDayEditableProvider(_a)), true);
      expect(h.container.read(cartDayEditableProvider(_b)), true);
      expect(tester.takeException(), null);
    });
  }

  testWidgets(
    'Один отключён для черновика; Все сохраняет черновик и загружает другой день',
    (tester) async {
      late _Harness h;
      await tester.runAsync(() async {
        h = _Harness();
        await h.settle();
        h.selection.setQuantity(_a, _dish, 9);
      });
      addTearDown(h.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(home: OrdersPage(selectedDateKey: _a)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Повторить заказ'));
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Один'),
      );
      expect(tile.enabled, false);
      expect(tile.onTap, null);
      await tester.tap(find.text('Все'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pumpAndSettle();
      expect(h.draft[_a]![_dish], 9);
      expect(h.draft[_b]![_dish], 2);
      expect(h.edit.revisions.keys, [_b]);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('повтор отключён при отсутствии пустых доступных дней', (
    tester,
  ) async {
    late _Harness h;
    await tester.runAsync(() async {
      h = _Harness();
      await h.settle();
      h.selection.setQuantity(_a, _dish, 1);
      h.selection.setQuantity(_b, _dish, 1);
    });
    addTearDown(h.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: OrdersPage(selectedDateKey: _a)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('orders-repeat')))
          .onPressed,
      null,
    );
    expect(h.repeatCalls, 0);
  });

  testWidgets('восстановление из правой корзины широкого каталога /menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _Harness h;
    await tester.runAsync(() async {
      final first = _Harness();
      await first.settle();
      await first.repeat.repeat([_a, _b]);
      first.selection.setQuantity(_b, _dish, 5);
      await first.repeat.persistNow();
      first.dispose();
      h = _Harness();
      await h.settle();
    });
    addTearDown(h.dispose);
    final router = h.container.read(routerProvider);
    router.go('/menu');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const FieldKitchenApp(),
      ),
    );
    await tester.pumpAndSettle();
    final resume = find.byKey(const ValueKey('repeat-resume'));
    expect(resume, findsOneWidget);
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    expect(h.edit.isRepeat, true);
    expect(h.edit.revisions.length, 2);
    expect(h.draft[_b]![_dish], 5);
    expect(router.routeInformationProvider.value.uri.path, '/menu');
    expect(tester.takeException(), null);
  });

  test('контракт: границы года 7/14 и отказ от неоднозначного/повреждённого ответа', () {
    for (final offset in [7, 14]) {
      final raw = {
        'success': true,
        'ownerScope': _scope,
        'days': [_day(_a, offset: offset)],
      };
      expect(
        RepeatResponse.parse(raw, [_a]).days.single.sourceDateKey,
        offset == 7 ? '2029-12-26' : '2029-12-19',
      );
    }
    for (final corrupt in [
      'date',
      'qty',
      'duplicate',
      'source',
      'empty',
      'scope',
    ]) {
      final day = _day(_a);
      final raw = <String, dynamic>{
        'ownerScope': _scope,
        'days': [day],
      };
      if (corrupt == 'date') {
        day['date'] = '2030-02-30T00:00:00';
      }
      if (corrupt == 'qty') {
        ((day['dishes'] as List).first as Map)['quantity'] = 1.5;
      }
      if (corrupt == 'duplicate') {
        raw['days'] = [day, day];
      }
      if (corrupt == 'source') {
        day['sourceDate'] = '2030-01-01T00:00:00';
      }
      if (corrupt == 'empty') {
        day['dishes'] = [];
      }
      if (corrupt == 'scope') {
        raw['ownerScope'] = 'alpha';
      }
      expect(
        () => RepeatResponse.parse(raw, [_a]),
        throwsFormatException,
        reason: corrupt,
      );
    }
  });
}
