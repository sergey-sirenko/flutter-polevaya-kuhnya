import 'package:polevaya_kuhnya/app/navigation.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submission_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_store.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/order_sheet.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:polevaya_kuhnya/features/menu/menu_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/compatible_version.dart';

const date = '2030-01-02';
const other = '2030-01-03';
final config = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.example.invalid/Obmen/',
  dataBaseUrl: 'https://data.example.invalid/data/',
  appVersionUrl: 'https://version.example.invalid/version.json',
);

class _Menu extends MenuController {
  @override
  Future<void> reload() async => state = AsyncData(await build());
  @override
  Future<List<MenuWeek>> build() async => [
    MenuWeek(
      weekType: 'current',
      days: [
        for (final key in [date, other])
          MenuDay(
            dateKey: key,
            date: menuCalendarDate(key),
            categories: [
              MenuCategory(
                categoryId: 'soup',
                categoryName: 'Супы',
                dishes: const [
                  MenuDish(
                    dishId: 'dish',
                    dishName: 'Тестовый суп',
                    price: 100,
                  ),
                ],
              ),
            ],
          ),
      ],
    ),
    MenuWeek(weekType: 'next', days: const []),
  ];
}

class _Version extends CompatibleVersionController {
  void block() => state = const AppVersionCheck(AppVersionStatus.checking);
  void allow() => state = const AppVersionCheck(AppVersionStatus.current);
}

class Harness {
  late ProviderContainer container;
  Map<String, Object?> user = {
    'login': 'alice',
    'name': 'Организация',
    'employee': 'Иван Иванов',
    'order': [
      {
        'date': date,
        'changes': 'Открыт',
        'status': 'Принят',
        'sum': 200,
        'dishes': [
          {'dish': 'dish', 'name': 'Тестовый суп', 'quantity': 2, 'sum': 200},
        ],
      },
    ],
  };
  String revision = 'rev-a';
  Set<String> allowed = {date, other};
  bool datesFail = false;
  bool profileFail = false;
  final requests = <Map<String, Object?>>[];
  final calls = <String>[];
  List<String> revisionReplies = [];
  Completer<http.Response>? heldSnapshot;
  Completer<http.Response>? heldDates;
  Map<String, Object?>? snapshotOverride;
  String? basketError;
  bool loseResponse = false;
  Map<String, Object?>? accepted;
  Map<String, Object?>? acceptedSnapshotOverride;
  bool omitAcceptedSnapshot = false;
  Completer<http.Response>? heldBasket;
  bool resultNotFound = false;

  http.Response json(Map<String, Object?> body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object?> snapshotBody({List<Map<String, Object?>>? states}) => {
    'success': true,
    'schemaVersion': 1,
    'ownerScope': 'snapshot-v1:11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222',
    'user': {
      'email': '',
      'phone': '',
      'LimitPeriod': '',
      'DiscountPercentage': null,
      'DiscountClient': 0,
      'DiscountPromotion': 0,
      'Limit': 0,
      'MinimumOrderAmount': 0,
      'MinimumPaymentAmount': 0,
      ...user,
      'order': [
        for (final raw in user['order'] as List)
          {
            ...Map<String, Object?>.from(raw as Map),
            'date': '${raw['date'].toString().substring(0, 10)}T00:00:00',
            'weekType': raw['weekType'] ?? 'current',
            'discount': raw['discount'] ?? 0,
          },
      ],
    },
    'menudates': [for (final key in allowed) '${key}T00:00:00'],
    'states': states == null
        ? [
            {'date': '${date}T00:00:00', 'revision': revision},
            {'date': '${other}T00:00:00', 'revision': 'none'},
          ]
        : [
            for (final state in states)
              {
                ...state,
                'date': '${state['date'].toString().substring(0, 10)}T00:00:00',
              },
          ],
  };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.split('/').last;
    calls.add(path);
    final body = jsonDecode(request.body) as Map;
    if (path == 'login') {
      if (profileFail) throw http.ClientException('offline');
      return json({'success': true, 'user': user});
    }
    if (path == 'menudates') {
      if (heldDates case final Completer<http.Response> held) {
        heldDates = null;
        return held.future;
      }
      if (datesFail) throw http.ClientException('offline');
      return json({'success': true, 'menudates': allowed.toList()});
    }
    if (path == 'snapshot') {
      if (heldSnapshot case final Completer<http.Response> held) {
        heldSnapshot = null;
        return held.future;
      }
      if (profileFail || datesFail) throw http.ClientException('offline');
      return json(
        snapshotOverride ??
            snapshotBody(
              states: [
                for (final raw in body['dates'] as List)
                  {
                    'date': raw,
                    'revision': raw.toString().startsWith(date)
                        ? revision
                        : 'none',
                  },
              ],
            ),
      );
    }
    if (path == 'basketstate') {
      final rev = revisionReplies.isEmpty
          ? revision
          : revisionReplies.removeAt(0);
      return json({
        'success': true,
        'states': [
          for (final raw in body['dates'] as List)
            {
              'date': raw,
              'revision': raw.toString().startsWith(date) ? rev : 'none',
            },
        ],
      });
    }
    if (path == 'basket') {
      final sent = Map<String, Object?>.from(body)
        ..remove('token')
        ..remove('deviceId');
      requests.add(sent);
      final order = body['order'] as List;
      if (order.any(
        (raw) =>
            raw['revision'] !=
            (raw['date'].toString().startsWith(date) ? revision : 'none'),
      )) {
        return json({
          'success': false,
          'code': 'order_changed',
          'message': 'Заказ изменился',
        }, 409);
      }
      if (order.any(
        (raw) => !allowed.contains(raw['date'].toString().substring(0, 10)),
      )) {
        return json({
          'success': false,
          'code': 'order_day_closed',
          'message': 'День закрыт',
        }, 409);
      }
      if (basketError != null) {
        return json({
          'success': false,
          'code': basketError,
          'message': 'Заказ изменился или день закрыт',
        }, 409);
      }
      accepted = {
        'success': true,
        'submission': {'id': body['submissionId'], 'status': 'accepted'},
        'order': [
          {
            'date': date,
            'finalPayable': 200,
            'finalPayableScope': 'employee_dishes',
          },
        ],
        if (body['includeSnapshot'] == true && !omitAcceptedSnapshot)
          'snapshot':
              acceptedSnapshotOverride ??
              snapshotBody(
                states: [
                  for (final day in order)
                    {'date': day['date'], 'revision': 'rev-after'},
                ],
              ),
      };
      if (heldBasket case final Completer<http.Response> held) {
        heldBasket = null;
        return held.future;
      }
      if (loseResponse) throw http.ClientException('response lost');
      return json(accepted!);
    }
    if (path == 'basketresult') {
      if (resultNotFound) {
        return json({
          'success': true,
          'submission': {'id': body['submissionId'], 'status': 'not_found'},
        });
      }
      if (body['includeSnapshot'] == true) {
        expect(body['deviceId'], isNotNull);
        expect(body['token'], isNotNull);
      }
      return json(
        accepted ??
            {
              'success': true,
              'submission': {'id': body['submissionId'], 'status': 'accepted'},
            },
      );
    }
    throw StateError('Unexpected synthetic request $path');
  }

  Future<void> init({
    CartSubmitPhase expectedPhase = CartSubmitPhase.idle,
    CartWorkStore? workStore,
    MenuController Function()? menuFactory,
  }) async {
    final storage = SessionStorage(config: config);
    await storage.writeToken('synthetic-token');
    container = ProviderContainer(
      overrides: [
        if (workStore != null)
          cartWorkStoreProvider.overrideWithValue(workStore),
        appConfigProvider.overrideWithValue(config),
        httpClientProvider.overrideWithValue(MockClient(handle)),
        sessionStorageProvider.overrideWithValue(storage),
        menuControllerProvider.overrideWith(menuFactory ?? _Menu.new),
        appVersionControllerProvider.overrideWith(_Version.new),
        initialLocationProvider.overrideWithValue('/orders'),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sessionControllerProvider, (_, _) {});
    for (
      var i = 0;
      i < 100 && container.read(sessionProfileProvider) == null;
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(sessionProfileProvider)?.login, 'alice');
    await container.read(menuControllerProvider.future);
    await container.read(menuAllowedDatesProvider.future);
    container.listen(cartSubmitControllerProvider, (_, _) {});
    await container.read(cartPersistenceControllerProvider.notifier).ready;
    await container.read(cartEditControllerProvider.notifier).ready;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(cartSubmitControllerProvider).phase, expectedPhase);
  }

  CartEditController get edit =>
      container.read(cartEditControllerProvider.notifier);
  CartDraftController get draft => container.read(cartDraftProvider.notifier);
  CartSubmitController get submit =>
      container.read(cartSubmitControllerProvider.notifier);
  CartEditState get state => container.read(cartEditControllerProvider);
  Future<void> mount(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FieldKitchenApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _tapDay(WidgetTester tester, Finder day) async {
  final heading = find.descendant(of: day, matching: find.byType(Text)).first;
  await tester.ensureVisible(heading);
  await tester.pump();
  await tester.tap(heading);
}

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final empty in [false, true]) {
      testWidgets(
        'FL-UX-17: переход до медленного ответа $width, пусто $empty',
        (tester) async {
          final h = Harness();
          if (empty) h.user['order'] = [];
          await tester.runAsync(h.init);
          await h.mount(tester, width);
          h.calls.clear();
          final held = Completer<http.Response>();
          h.heldSnapshot = held;
          await tester.ensureVisible(
            find.byKey(const ValueKey('orders-start-$date')),
          );
          await tester.tap(find.byKey(const ValueKey('orders-start-$date')));
          // В кадре перехода запросы ещё не выполняются.
          await tester.pump();
          expect(h.calls, isEmpty);
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          final router = h.container.read(routerProvider);
          expect(router.routerDelegate.state.uri.path, '/cart');
          expect(
            find.byKey(const ValueKey('order-preparation-page')),
            findsOneWidget,
          );
          expect(find.text('Подготовка заказа…'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('orders-start-$date')),
            findsNothing,
          );
          expect(h.calls, ['snapshot']);
          await tester.runAsync(() async {
            held.complete(h.json(h.snapshotBody()));
            for (var i = 0; i < 30; i++) {
              await Future<void>.delayed(Duration.zero);
            }
          });
          await tester.pumpAndSettle();
          expect(
            router.routerDelegate.state.uri.path,
            empty && width < 1200 ? '/orders/categories' : '/cart',
          );
          expect(router.routerDelegate.state.uri.queryParameters, isEmpty);
          expect(
            find.byKey(const ValueKey('order-preparation-page')),
            findsNothing,
          );
          expect(h.state.active, isTrue);
          expect(h.calls, ['snapshot']);
          expect(h.requests, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('FL-UX-17: Back во время подготовки игнорирует поздний ответ', (
    tester,
  ) async {
    final h = Harness();
    await tester.runAsync(h.init);
    await h.mount(tester, 390);
    final before = h.container.read(cartDraftProvider);
    final held = Completer<http.Response>();
    h.heldSnapshot = held;
    await tester.ensureVisible(
      find.byKey(const ValueKey('orders-start-$date')),
    );
    await tester.tap(find.byKey(const ValueKey('orders-start-$date')));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(h.state.loading, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      h.container.read(routerProvider).routerDelegate.state.uri.path,
      '/orders',
    );
    await tester.runAsync(() async {
      held.complete(h.json(h.snapshotBody()));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    expect(h.state.active, isFalse);
    expect(h.state.loading, isFalse);
    expect(h.container.read(cartDraftProvider), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FL-UX-17: ошибка подготовки и повтор на новом экране', (
    tester,
  ) async {
    final h = Harness();
    await tester.runAsync(h.init);
    await h.mount(tester, 390);

    final held = Completer<http.Response>();
    h.heldSnapshot = held;
    await tester.ensureVisible(
      find.byKey(const ValueKey('orders-start-$date')),
    );
    await tester.tap(find.byKey(const ValueKey('orders-start-$date')));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.runAsync(() async {
      held.complete(h.json({...h.snapshotBody(), 'schemaVersion': 2}));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('order-preparation-retry')),
      findsOneWidget,
    );
    expect(h.state.active, isFalse);
    final retryHeld = Completer<http.Response>();
    h.heldSnapshot = retryHeld;
    await tester.tap(find.byKey(const ValueKey('order-preparation-retry')));
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.runAsync(() async {
      retryHeld.complete(h.json(h.snapshotBody()));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pumpAndSettle();
    expect(h.state.active, isTrue);
    expect(find.byKey(const ValueKey('order-preparation-page')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final empty in [false, true]) {
    testWidgets('FL-10-13: повторные шаги сокращают цепочку, пусто $empty', (
      tester,
    ) async {
      final h = Harness();
      if (empty) h.user['order'] = [];
      await tester.runAsync(h.init);
      await h.mount(tester, 390);
      await tester.runAsync(() async {
        expect(await h.edit.begin(date), isTrue);
        await h.container
            .read(menuSelectionProvider.notifier)
            .openDate(
              date,
              await h.container.read(menuControllerProvider.future),
            );
      });
      final router = h.container.read(routerProvider);
      final navigation = appNavigationOf(router)!;
      navigation.startOrder(skipCart: empty);
      void open(String route) => navigation.navigate(
        router.routerDelegate.navigatorKey.currentContext!,
        route,
      );
      open('/orders/categories');
      await tester.pumpAndSettle();
      open('/menu');
      await tester.pumpAndSettle();
      final draft = h.container.read(cartDraftProvider);
      open('/cart');
      await tester.pumpAndSettle();
      expect(navigation.stack.map((match) => match.matchedLocation), [
        '/',
        '/orders',
        '/cart',
      ]);
      expect(h.state.active, isTrue);
      open('/orders/categories');
      await tester.pumpAndSettle();
      open('/menu');
      await tester.pumpAndSettle();
      open('/orders/categories');
      await tester.pumpAndSettle();
      expect(navigation.stack.map((match) => match.matchedLocation), [
        '/',
        '/orders',
        '/cart',
        '/orders/categories',
      ]);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routerDelegate.state.uri.path, '/cart');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routerDelegate.state.uri.path, '/orders');
      expect(h.state.active, isTrue);
      expect(h.container.read(cartDraftProvider), draft);
      expect(h.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'changes: boolean и серверные строки; неизвестное запрещает изменение',
    () {
      for (final value in [true, 'Открыт', ' открыт ']) {
        expect(UserOrderDay.fromJson({'changes': value}).changes, isTrue);
      }
      for (final value in [false, 'Закрыт', null, 'unknown']) {
        expect(UserOrderDay.fromJson({'changes': value}).changes, isFalse);
      }
    },
  );
  test('подготовка всех дней, повторный клик сохраняет правки, разрешение не восстанавливается', () async {
    final h = Harness();
    await h.init();
    h.draft.replaceAll({
      date: {'draft': 9},
      '2030-02-03': {'untouched': 7},
    });
    final generation = h.container.read(sessionControllerProvider).generation;
    final api = h.container.read(sessionApiProvider);
    expect(await h.edit.begin(date), isTrue);
    expect(h.container.read(cartDraftProvider), {
      date: {'dish': 2},
      '2030-02-03': {'untouched': 7},
    });
    expect(h.state.revision, 'rev-a');
    expect(h.container.read(sessionControllerProvider).generation, generation);
    expect(h.container.read(sessionApiProvider), same(api));
    expect(h.container.read(cartDayEditableProvider(date)), isTrue);
    expect(h.container.read(cartDayEditableProvider(other)), isTrue);
    h.draft.increment(date, 'dish');
    expect(await h.edit.begin(date), isTrue);
    expect(h.container.read(cartDraftProvider)[date], {'dish': 3});
    h.edit.end();
    expect(h.container.read(cartDayEditableProvider(date)), isTrue);
    expect(h.container.read(cartDraftProvider)[date], {'dish': 3});
    h.container.invalidate(cartEditControllerProvider);
    expect(h.state.active, isFalse);
    expect(h.requests, isEmpty);
  });
  for (final kind in [
    'revision',
    'profile',
    'dates',
    'quantity',
    'closed',
    'ambiguous',
  ]) {
    test('ошибка подготовки $kind сохраняет черновики', () async {
      final h = Harness();
      await h.init();
      final original = {
        date: {'old': 4},
        other: {'other': 2},
      };
      h.draft.replaceAll(original);
      switch (kind) {
        case 'revision':
          h.snapshotOverride = {...h.snapshotBody(), 'states': []};
        case 'profile':
          h.profileFail = true;
        case 'dates':
          h.datesFail = true;
        case 'quantity':
          ((h.user['order'] as List).first['dishes'] as List)
                  .first['quantity'] =
              1.5;
        case 'closed':
          h.allowed = {other};
        case 'ambiguous':
          h.revision = 'ambiguous';
      }
      expect(await h.edit.begin(date), isFalse);
      expect(h.container.read(cartDraftProvider), original);
      expect(h.state.message, isNotNull);
      expect(h.state.loading, isFalse);
      expect(h.requests, isEmpty);
    });
  }
  test(
    'отмена подготовки и повторные клики не применяют поздний ответ',
    () async {
      final h = Harness();
      await h.init();
      h.draft.setQuantity(other, 'untouched', 3);
      final held = Completer<http.Response>();
      h.heldSnapshot = held;
      final preparing = h.edit.begin(date);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.state.loading, isTrue);
      expect(await h.edit.begin(date), isFalse);
      h.edit.end();
      held.complete(h.json(h.snapshotBody()));
      expect(await preparing, isFalse);
      expect(h.state.active, isFalse);
      expect(h.container.read(cartDraftProvider), {
        other: {'untouched': 3},
      });
    },
  );
  test('новая отправка только одного дня; success очищает старые черновики и сохраняет результат', () async {
    final h = Harness();
    await h.init();
    h.draft.setQuantity('2030-02-03', 'untouched', 7);
    expect(await h.edit.begin(date), isTrue);
    h.draft.setQuantity(date, 'dish', 3);
    h.calls.clear();
    await h.submit.submit();
    expect(h.calls, ['basket']);
    expect(h.requests.single['includeSnapshot'], isTrue);
    expect(
      h.requests.single['expectedOwnerScope'],
      h.snapshotBody()['ownerScope'],
    );
    final days = h.requests.single['order'] as List;
    expect(days, hasLength(1));
    expect(days.single['date'], '${date}T00:00:00');
    expect(days.single['revision'], 'rev-a');
    expect(days.single['dishes'].single['quantity'], 3);
    expect(h.container.read(cartDraftProvider), isEmpty);
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.succeeded,
    );
    expect(h.state.active, isFalse);
  });
  test(
    'FL-UX-24: один basket обновляет полный профиль, историю и даты',
    () async {
      final h = Harness();
      await h.init();
      expect(await h.edit.begin(date), isTrue);
      h.user = {
        ...h.user,
        'employee': 'Новое имя',
        'email': 'new@example.invalid',
        'order': [
          {
            'date': date,
            'changes': 'Открыт',
            'status': 'Принят',
            'sum': 300,
            'dishes': [
              {
                'dish': 'dish',
                'name': 'Тестовый суп',
                'quantity': 3,
                'sum': 300,
              },
            ],
          },
          {
            'date': other,
            'changes': 'Открыт',
            'status': 'Принят',
            'sum': 100,
            'dishes': [
              {
                'dish': 'dish',
                'name': 'Тестовый суп',
                'quantity': 1,
                'sum': 100,
              },
            ],
          },
        ],
      };
      h.allowed = {date};
      h.draft.setQuantity(date, 'dish', 3);
      h.calls.clear();
      await h.submit.submit();
      expect(h.calls, ['basket']);
      final profile = h.container.read(sessionProfileProvider)!;
      expect(profile.employee, 'Новое имя');
      expect(profile.email, 'new@example.invalid');
      expect(profile.orders, hasLength(2));
      expect(profile.orders.first.dishes.single.quantity, 3);
      expect(h.container.read(menuAllowedDatesProvider).asData?.value, {date});
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.succeeded,
      );
    },
  );
  for (final invalid in [
    'missing',
    'malformed',
    'foreign_login',
    'foreign_scope',
    'dates',
  ]) {
    test(
      'FL-UX-24: $invalid снимок не отменяет accepted и не вызывает запросов',
      () async {
        final h = Harness();
        await h.init();
        expect(await h.edit.begin(date), isTrue);
        h.draft.setQuantity(date, 'dish', 3);
        final before = h.container.read(sessionProfileProvider);
        final snapshot = h.snapshotBody();
        if (invalid == 'missing') {
          h.omitAcceptedSnapshot = true;
        }
        if (invalid == 'malformed') snapshot['user'] = {};
        if (invalid == 'foreign_login') {
          (snapshot['user'] as Map)['login'] = 'foreign';
        }
        if (invalid == 'foreign_scope') snapshot['ownerScope'] = 'snapshot-v1:11111111-1111-4111-8111-111111111111:33333333-3333-4333-8333-333333333333';
        if (invalid == 'dates') snapshot['states'] = [];
        h.acceptedSnapshotOverride = snapshot;
        h.calls.clear();
        await h.submit.submit();
        expect(h.calls, ['basket']);
        expect(
          h.container.read(cartSubmitControllerProvider).phase,
          CartSubmitPhase.succeeded,
        );
        expect(
          h.container.read(cartSubmitControllerProvider).message,
          contains('обновите заказы вручную'),
        );
        expect(
          identical(h.container.read(sessionProfileProvider), before),
          isTrue,
        );
        expect(h.container.read(cartDraftProvider), isEmpty);
        expect(
          await h.container.read(cartSubmissionStoreProvider).load('alice'),
          isNull,
        );
      },
    );
  }
  test('FL-UX-24: день закрывается после подготовки — один basket и сохранённый draft', () async {
    final h = Harness();
    await h.init();
    expect(await h.edit.begin(date), isTrue);
    h.draft.setQuantity(date, 'dish', 3);
    h.allowed.remove(date);
    h.calls.clear();
    await h.submit.submit();
    expect(h.calls, ['basket']);
    expect(h.state.blocked, isTrue);
    expect(h.container.read(cartDraftProvider)[date], {'dish': 3});
    expect(
      await h.container.read(cartSubmissionStoreProvider).load('alice'),
      isNull,
    );
  });
  test('FL-UX-24: потеря ответа — тот же ID, basketresult со снимком без новой записи', () async {
    final h = Harness();
    await h.init();
    expect(await h.edit.begin(date), isTrue);
    h.draft.setQuantity(date, 'dish', 3);
    h.loseResponse = true;
    h.calls.clear();
    await h.submit.submit();
    final pending = (await h.container
        .read(cartSubmissionStoreProvider)
        .load('alice'))!;
    expect(pending.body['includeSnapshot'], isTrue);
    expect(
      CartPendingSubmission.fromJson(pending.toJson(), 'alice').body,
      pending.body,
    );
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.outcomeUnknown,
    );
    await h.submit.resolveUnknownOutcome();
    expect(h.calls, ['basket', 'basketresult']);
    expect(h.requests, hasLength(1));
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.succeeded,
    );
  });
  test(
    'отмена существующего заказа передаёт одну дату с пустыми блюдами',
    () async {
      final h = Harness();
      await h.init();
      h.draft.setQuantity('2030-02-03', 'untouched', 7);
      expect(await h.edit.begin(date), isTrue);
      h.draft.clearDay(date);
      h.calls.clear();
      await h.submit.submit(confirmedCancellations: {date});
      expect(h.calls, ['basket']);
      final days = h.requests.single['order'] as List;
      expect(days, hasLength(1));
      expect(days.single['dishes'], isEmpty);
      expect(days.single['revision'], 'rev-a');
      expect(h.container.read(cartDraftProvider), isEmpty);
    },
  );
  test('FL-UX-24: not_found повторяет сохранённые includeSnapshot, scope, ID и состав', () async {
    final h = Harness();
    await h.init();
    expect(await h.edit.begin(date), isTrue);
    h.draft.setQuantity(date, 'dish', 3);
    h.loseResponse = true;
    h.calls.clear();
    await h.submit.submit();
    h.resultNotFound = true;
    h.loseResponse = false;
    await h.submit.resolveUnknownOutcome();
    expect(h.calls, ['basket', 'basketresult', 'basket']);
    expect(h.requests, hasLength(2));
    expect(h.requests.last, h.requests.first);
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.succeeded,
    );
  });
  test(
    'FL-UX-24: поздний ответ после смены сессии не применяет снимок',
    () async {
      final h = Harness();
      await h.init();
      expect(await h.edit.begin(date), isTrue);
      h.draft.setQuantity(date, 'dish', 3);
      final held = Completer<http.Response>();
      h.heldBasket = held;
      h.calls.clear();
      final saving = h.submit.submit();
      for (var i = 0; i < 100 && h.accepted == null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.calls, ['basket']);
      expect(h.accepted, isNotNull);
      await h.container
          .read(sessionControllerProvider.notifier)
          .clearLocalSession();
      held.complete(h.json(h.accepted!));
      await saving;
      expect(h.container.read(sessionProfileProvider), isNull);
      expect(
        await h.container.read(cartSubmissionStoreProvider).load('alice'),
        isNotNull,
      );
    },
  );
  test('пустой новый день не отправляется, чужой черновик не считается составом дня', () async {
    final h = Harness();
    await h.init();
    h.draft.setQuantity('2030-02-03', 'draft', 8);
    expect(await h.edit.begin(other), isTrue);
    expect(h.container.read(editingCartProvider).dayFor(date), isNotNull);
    await h.submit.submit();
    expect(h.requests, isEmpty);
    expect(h.container.read(cartDraftProvider), {
      date: {'dish': 2},
      '2030-02-03': {'draft': 8},
    });
  });
  test('неизвестное блюдо сохраняет имя и количество, блокирует отправку до удаления', () async {
    final h = Harness();
    await h.init();
    ((h.user['order'] as List).first['dishes'] as List).add({
      'dish': 'missing',
      'name': 'Убранное блюдо',
      'sum': 300,
      'quantity': 3,
    });
    expect(await h.edit.begin(date), isTrue);
    final pricing = h.container.read(cartPricingProvider)!;
    expect(
      pricing.days.single.lines
          .singleWhere((l) => l.dishId == 'missing')
          .dishName,
      'Убранное блюдо',
    );
    expect(h.container.read(cartDraftProvider)[date]?['missing'], 3);
    await h.submit.submit();
    expect(h.requests, isEmpty);
    h.draft.removeItem(date, 'missing');
    await h.submit.submit();
    expect(h.requests, hasLength(1));
  });
  for (final kind in ['revision', 'order_changed', 'order_day_closed']) {
    test(
      'конфликт $kind оставляет состав и блокирует новую отправку',
      () async {
        final h = Harness();
        await h.init();
        expect(await h.edit.begin(date), isTrue);
        h.draft.setQuantity(date, 'dish', 3);
        if (kind == 'revision') {
          h.revision = 'rev-b';
        } else {
          h.basketError = kind;
        }
        await h.submit.submit();
        expect(h.state.blocked, isTrue);
        expect(h.container.read(cartDraftProvider)[date], {'dish': 3});
        final count = h.requests.length;
        await h.submit.submit();
        expect(h.requests.length, count);
      },
    );
  }
  test(
    'W07 и неизвестный исход блокируют начало; без запуска отправка запрещена',
    () async {
      final h = Harness();
      await h.init();
      h.draft.setQuantity(date, 'dish', 2);
      await h.submit.submit();
      expect(h.requests, isEmpty);
      (h.container.read(appVersionControllerProvider.notifier) as _Version)
          .block();
      expect(await h.edit.begin(date), isFalse);
      (h.container.read(appVersionControllerProvider.notifier) as _Version)
          .allow();
      expect(await h.edit.begin(date), isTrue);
      h.draft.increment(date, 'dish');
      h.loseResponse = true;
      await h.submit.submit();
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.outcomeUnknown,
      );
      expect(await h.edit.begin(other), isFalse);
      expect(h.container.read(cartDayEditableProvider(date)), isFalse);
    },
  );
  test('сохранённая отмена и прежняя многодневная попытка восстанавливаются без изменения тела', () async {
    final h = Harness();
    await h.init();
    const id = '11111111-1111-4111-8111-111111111111';
    final body = <String, Object?>{
      'submissionId': id,
      'order': [
        {
          'date': '${date}T00:00:00',
          'revision': 'rev-a',
          'dishes': <Object?>[],
        },
        {
          'date': '${other}T00:00:00',
          'revision': 'none',
          'dishes': [
            {'dish': 'dish', 'name': 'Суп', 'quantity': 1, 'DiscountClient': 0},
          ],
        },
      ],
    };
    final pending = CartPendingSubmission(
      owner: 'alice',
      body: body,
      preliminary: {other: 100},
    );
    expect(
      CartPendingSubmission.fromJson(pending.toJson(), 'alice').body,
      body,
    );
    await h.container.read(cartSubmissionStoreProvider).save(pending);
    h.container.invalidate(cartSubmitControllerProvider);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.outcomeUnknown,
    );
    expect(h.state.active, isFalse);
    expect(await h.edit.begin(date), isFalse);
    await h.submit.resolveUnknownOutcome();
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.succeeded,
    );
    expect(h.requests, isEmpty);
  });
  testWidgets(
    'права и ошибки скрывают кнопку дня, просмотр остаётся доступным',
    (tester) async {
      final h = Harness();
      await tester.runAsync(h.init);
      await h.mount(tester, 390);
      Finder start() => find.byKey(const ValueKey('orders-start-2030-01-02'));
      expect(start(), findsOneWidget);
      h.allowed = {other};
      await tester.runAsync(
        () => h.container.read(menuAllowedDatesProvider.notifier).reload(),
      );
      await tester.pumpAndSettle();
      expect(start(), findsNothing);
      h.allowed = {date, other};
      h.datesFail = true;
      await tester.runAsync(
        () => h.container.read(menuAllowedDatesProvider.notifier).reload(),
      );
      await tester.pumpAndSettle();
      expect(start(), findsNothing);
      h.datesFail = false;
      await tester.runAsync(
        () => h.container.read(menuAllowedDatesProvider.notifier).reload(),
      );
      (h.user['order'] as List).first['changes'] = 'Закрыт';
      await tester.runAsync(
        () => h.container
            .read(sessionControllerProvider.notifier)
            .refreshProfile(),
      );
      await tester.pumpAndSettle();
      expect(start(), findsNothing);
      await _tapDay(
        tester,
        find.byKey(const ValueKey('orders-day-2030-01-02')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Тестовый суп × 2'),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('orders-calendar-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('Тестовый суп × 2'), findsOneWidget);
      expect(h.state.active, isFalse);
      expect(h.requests, isEmpty);
    },
  );
  testWidgets(
    'resize и заказы сохраняют редактирование, день, категорию и историю',
    (tester) async {
      final h = Harness();
      await tester.runAsync(h.init);
      await h.mount(tester, 390);
      await tester.runAsync(() async {
        expect(await h.edit.begin(date), isTrue);
        await h.container
            .read(menuSelectionProvider.notifier)
            .openDate(
              date,
              await h.container.read(menuControllerProvider.future),
            );
      });
      final router = h.container.read(routerProvider);
      appNavigationOf(router)!.startOrder(skipCart: false);
      appNavigationOf(
        router,
      )!.navigate(router.routerDelegate.navigatorKey.currentContext!, '/cart');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cart-add-dishes')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Супы'));
      await tester.pumpAndSettle();
      final draft = h.container.read(cartDraftProvider);
      for (final width in [1200.0, 599.0, 1199.0, 390.0]) {
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/menu');
        expect(h.state.active, isTrue);
        expect(h.container.read(cartDraftProvider), draft);
        expect(h.container.read(menuSelectionProvider)?.dateKey, date);
        expect(h.container.read(menuActiveCategoryProvider), 'soup');
        expect(
          find.byKey(const ValueKey('menu-dish-quantity-dish')),
          findsOneWidget,
        );
      }

      (h.container.read(appVersionControllerProvider.notifier) as _Version)
          .block();
      await tester.pump();
      expect(h.container.read(cartDayEditableProvider(date)), isFalse);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/menu');
      (h.container.read(appVersionControllerProvider.notifier) as _Version)
          .allow();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/orders/categories',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/cart');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/orders');
      expect(h.state.active, isTrue);
      appNavigationOf(router)!.navigate(
        router.routerDelegate.navigatorKey.currentContext!,
        '/profile',
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      router.go('/menu');
      await tester.pumpAndSettle();
      expect(h.container.read(cartDayEditableProvider(date)), isTrue);
      expect(find.byTooltip('Увеличить количество'), findsWidgets);
      expect(find.byTooltip('Уменьшить количество'), findsWidgets);
      expect(h.container.read(cartDraftProvider), draft);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 599.0, 600.0, 1199.0, 1200.0]) {
    for (final empty in [true, false]) {
      testWidgets(
        'кнопка дня → корзина/категории → блюда → Back: $width, пусто $empty',
        (tester) async {
          final h = Harness();
          if (empty) h.user['order'] = [];
          await tester.runAsync(h.init);
          await tester.runAsync(() async {
            h.draft.setQuantity('2030-02-03', 'untouched', 7);
            await h.container
                .read(cartPersistenceControllerProvider.notifier)
                .ready;
          });
          await h.mount(tester, width);
          final router = h.container.read(routerProvider);
          final dayButton = find.byKey(const ValueKey('orders-day-2030-01-02'));
          await tester.ensureVisible(dayButton);
          await _tapDay(tester, dayButton);
          await tester.pumpAndSettle();
          await _tapDay(tester, dayButton);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/orders');
          expect(h.state.active, isFalse);
          final start = find.byKey(const ValueKey('orders-start-2030-01-02'));
          await tester.ensureVisible(start);
          await tester.runAsync(
            () => h.container
                .read(cartPersistenceControllerProvider.notifier)
                .ready,
          );
          final held = Completer<http.Response>();
          h.heldSnapshot = held;
          await tester.tap(start);
          await tester.pump();
          await tester.pump();
          await tester.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          expect(
            find.byKey(const ValueKey('order-preparation-page')),
            findsOneWidget,
          );
          await tester.runAsync(() async {
            held.complete(h.json(h.snapshotBody()));
          });
          for (var i = 0; i < 100 && h.state.loading; i++) {
            await tester.pump(const Duration(milliseconds: 10));
            await tester.runAsync(() async {
              await Future<void>.delayed(Duration.zero);
            });
          }
          expect(h.state.loading, isFalse, reason: h.calls.toString());
          await tester.pumpAndSettle();
          expect(h.state.active, isTrue);
          expect(
            router.routeInformationProvider.value.uri.path,
            empty && width < 1200 ? '/orders/categories' : '/cart',
          );
          if (width >= 1200) {
            expect(find.byKey(const ValueKey('cart-add-dishes')), findsNothing);
            expect(
              find
                  .byKey(const ValueKey('menu-dish-quantity-dish'))
                  .hitTestable(),
              findsOneWidget,
            );
          } else {
            if (!empty) {
              final add = find.byKey(const ValueKey('cart-add-dishes'));
              await tester.ensureVisible(add);
              await tester.tap(add);
              await tester.pumpAndSettle();
            }
            expect(
              find.byKey(const ValueKey('menu-categories-page')),
              findsOneWidget,
            );
            await tester.tap(find.text('Супы'));
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri.path, '/menu');
            final card = find.byKey(const ValueKey('menu-dish-quantity-dish'));
            await tester.ensureVisible(card);
            final plus = find.descendant(
              of: card,
              matching: find.byTooltip('Увеличить количество'),
            );
            expect(plus, findsOneWidget);
            await tester.ensureVisible(plus);
            await tester.tap(plus);
            await tester.pumpAndSettle();
            expect(
              h.container.read(cartDraftProvider)[date]?['dish'],
              empty ? 1 : 3,
            );
            if (width < 600) {
              h.container
                  .read(orderSheetProvider.notifier)
                  .toggle(OrderSheet.day);
              await tester.pumpAndSettle();
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
              expect(router.routeInformationProvider.value.uri.path, '/menu');
              expect(h.container.read(orderSheetProvider), isNull);
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              '/orders/categories',
            );
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            if (!empty) {
              expect(router.routeInformationProvider.value.uri.path, '/cart');
              expect(
                find.byKey(const ValueKey('cart-add-dishes')).hitTestable(),
                findsOneWidget,
              );
              await tester.binding.handlePopRoute();
              await tester.pumpAndSettle();
            }
          }
          if (width >= 1200) {
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
          }
          expect(router.routeInformationProvider.value.uri.path, '/orders');
          expect(h.state.active, isTrue);
          expect(h.container.read(cartDraftProvider)['2030-02-03'], {
            'untouched': 7,
          });
          expect(h.container.read(routerProvider), same(router));
          expect(tester.takeException(), isNull);
          expect(h.requests, isEmpty);
        },
      );
    }
  }
}
