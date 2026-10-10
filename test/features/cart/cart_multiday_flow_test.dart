import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_pricing_bridge.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_banner.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repeat_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_edit_flow_test.dart' show Harness, date, other, config;

class _WithoutDate extends _ManyMenu {
  _WithoutDate() : super(2);

  @override
  Future<List<MenuWeek>> build() async => [
    for (final week in await super.build())
      MenuWeek(
        weekType: week.weekType,
        days: week.days.where((day) => day.dateKey != date).toList(),
      ),
  ];

  @override
  Future<void> reload() async => state = AsyncData(await build());
}

class _FailingStore extends CartWorkStore {
  _FailingStore() : super(config);
  bool failSave = false;
  bool failClear = false;
  @override
  Future<void> save(
    String login,
    String device,
    CartWorkSnapshot snapshot,
  ) async {
    if (failSave) throw StateError('disk');
    await super.save(login, device, snapshot);
  }

  @override
  Future<void> clear(String login, String device) async {
    if (failClear) throw StateError('disk');
    await super.clear(login, device);
  }
}

class _ManyMenu extends MenuController {
  _ManyMenu(this.count);
  final int count;
  @override
  Future<List<MenuWeek>> build() async => [
    MenuWeek(
      weekType: 'current',
      days: [
        for (var i = 0; i < count; i++)
          MenuDay(
            dateKey: DateTime(
              2030,
              1,
              2,
            ).add(Duration(days: i)).toIso8601String().substring(0, 10),
            date: DateTime(2030, 1, 2).add(Duration(days: i)),
            categories: [
              MenuCategory(
                categoryId: 'c',
                categoryName: 'Обед',
                dishes: [
                  const MenuDish(dishId: 'dish', dishName: 'Суп', price: 100),
                ],
              ),
            ],
          ),
      ],
    ),
  ];
}

class _HeldStore extends CartWorkStore {
  _HeldStore() : super(config);
  final entered = Completer<void>();
  final release = Completer<void>();
  bool held = true;
  @override
  Future<void> save(
    String login,
    String device,
    CartWorkSnapshot snapshot,
  ) async {
    if (held) {
      held = false;
      entered.complete();
      await release.future;
    }
    await super.save(login, device, snapshot);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  for (final count in [31, 32]) {
    test('M13: подготовка $count дат без сокращения пакета', () async {
      final h = Harness();
      h.allowed = {
        for (var i = 0; i < count; i++)
          DateTime(
            2030,
            1,
            2,
          ).add(Duration(days: i)).toIso8601String().substring(0, 10),
      };
      await h.init(menuFactory: () => _ManyMenu(count));
      h.calls.clear();
      expect(await h.edit.begin(date), count == 31);
      if (count == 31) {
        expect(h.state.preparedRevisions, hasLength(31));
        for (final d in h.state.preparedRevisions.keys) {
          h.draft.increment(d, 'dish');
        }
        await h.submit.submit();
        expect(h.requests.single['order'], hasLength(31));
      } else {
        expect(h.calls, isEmpty);
        expect(h.state.message, contains('31'));
      }
    });
  }
  test('M03: закрытый ненажатый день автоматически исключён', () async {
    final h = Harness();
    h.allowed.remove(other);
    await h.init();
    expect(await h.edit.begin(date), isTrue);
    expect(h.state.preparedRevisions.keys, [date]);
    expect(h.state.message, isNull);
    expect(h.container.read(cartDayEditableProvider(other)), isFalse);
  });
  test('M10: ошибка первой записи сохраняет прежний draft', () async {
    final store = _FailingStore()..failSave = true;
    final h = Harness();
    await h.init(workStore: store);
    h.draft.setQuantity(other, 'dish', 7);
    expect(await h.edit.begin(date), isFalse);
    expect(h.container.read(cartDraftProvider)[other]?['dish'], 7);
    expect(h.state.active, isFalse);
  });
  test('M10: отменённая запись не удаляет снимок новой подготовки', () async {
    final store = _HeldStore();
    final h = Harness();
    await h.init(workStore: store);
    final old = h.edit.begin(date);
    await store.entered.future;
    h.edit.end();
    final next = h.edit.begin(other);
    store.release.complete();
    expect(await old, isFalse);
    expect(await next, isTrue);
    final saved = await store.load(
      'alice',
      h.container.read(sessionApiProvider)!.deviceId,
    );
    expect(saved?.selectedDateKey, other);
  });
  test('M03/M09: Back во время проверки активного набора сохраняет предложение восстановления', () async {
    final h = Harness();
    await h.init();
    await h.edit.begin(date);
    h.draft.increment(date, 'dish');
    await h.edit.persistNow();
    h.edit.block('Конфликт');
    final held = Completer<http.Response>();
    h.heldSnapshot = held;
    h.calls.clear();
    final checking = h.edit.resume();
    for (var i = 0; i < 100 && !h.calls.contains('snapshot'); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    h.edit.end();
    held.complete(h.json(h.snapshotBody()));
    expect(await checking, isFalse);
    expect(h.state.recovery?.quantities[date]?['dish'], 3);
    expect(await h.edit.begin(other), isFalse);
    expect(h.requests, isEmpty);
  });
  test('M09: повреждённое хранилище требует явного сброса', () async {
    final h = Harness();
    await h.init();
    final api = h.container.read(sessionApiProvider)!;
    final store = h.container.read(cartWorkStoreProvider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(store.key('alice', api.deviceId), '{broken');
    h.container.invalidate(cartEditControllerProvider);
    await h.edit.ready;
    expect(h.state.recoveryError, isTrue);
    expect(await h.edit.begin(date), isFalse);
    await h.edit.discard();
    expect(await store.load('alice', api.deviceId), isNull);
    expect(await h.edit.begin(date), isTrue);
  });
  test('M12: после перезапуска pending имеет приоритет над набором', () async {
    final first = Harness();
    await first.init();
    await first.edit.begin(date);
    first.draft.increment(date, 'dish');
    first.loseResponse = true;
    await first.submit.submit();
    final h = Harness();
    await h.init(expectedPhase: CartSubmitPhase.outcomeUnknown);
    expect(h.state.recovery, isNotNull);
    expect(
      h.container.read(cartSubmitControllerProvider).phase,
      CartSubmitPhase.outcomeUnknown,
    );
    expect(await h.edit.resume(), isFalse);
    expect(h.state.active, isFalse);
  });
  testWidgets(
    'M07: диалог отмены, отказ сохраняет набор, подтверждение отправляет пакет',
    (tester) async {
      final h = Harness();
      await tester.runAsync(() async {
        await h.init();
        expect(await h.edit.begin(date), isTrue);
        h.draft.clearDay(date);
        h.draft.increment(other, 'dish');
        await h.edit.persistNow();
      });
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(home: CartPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => h.container.read(cartRepeatControllerProvider.notifier).ready,
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('cart-save-all'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Подтвердить отмену заказов?'), findsOneWidget);
      expect(find.textContaining('Ср 02.01.30'), findsWidgets);
      await tester.tap(find.text('Назад').last);
      await tester.pumpAndSettle();
      expect(h.requests, isEmpty);
      expect(h.container.read(cartCancelledDatesProvider), [date]);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Подтвердить'));
        await tester.pump();
        for (
          var i = 0;
          i < 100 &&
              h.container.read(cartSubmitControllerProvider).phase !=
                  CartSubmitPhase.succeeded;
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
          await tester.pump();
        }
      });
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.succeeded,
        reason: 'requests: ${h.requests.length}',
      );
      expect(h.requests.single['order'], hasLength(2));
      // Изолированная CartPage без router не проверяет переход квитанции.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'M01/M02: один snapshot всех дней, независимый ID блюда на двух датах',
    () async {
      final h = Harness();
      await h.init();
      h.calls.clear();
      expect(await h.edit.begin(date), isTrue);
      expect(h.calls, ['snapshot']);
      expect(h.state.preparedRevisions.keys, unorderedEquals([date, other]));
      expect(h.container.read(cartDayEditableProvider(other)), isTrue);
      h.draft.increment(date, 'dish');
      h.draft.increment(other, 'dish');
      h.calls.clear();
      expect(await h.edit.begin(other), isTrue);
      expect(h.calls, isEmpty);
      expect(h.container.read(cartDraftProvider)[date]!['dish'], 3);
      expect(h.container.read(cartDraftProvider)[other]!['dish'], 1);
      h.edit.end();
      expect(h.state.active, isTrue);
      await h.submit.submit();
      expect(h.calls, ['basket']);
      expect((h.requests.single['order'] as List).map((d) => d['date']), [
        '${date}T00:00:00',
        '${other}T00:00:00',
      ]);
    },
  );
  test('M04/M05: неизменённый заказ исключён; возврат к исходному снимает изменение', () async {
    final h = Harness();
    await h.init();
    await h.edit.begin(other);
    expect(h.container.read(cartChangedDatesProvider), isEmpty);
    await h.submit.submit();
    expect(h.requests, isEmpty);
    h.draft.increment(date, 'dish');
    h.draft.decrement(date, 'dish');
    expect(h.container.read(cartChangedDatesProvider), isEmpty);
    h.draft.increment(other, 'dish');
    expect(
      h.container.read(cartSubmissionPricingProvider)!.cartTotals.finalTotal,
      100,
    );
    await h.submit.submit();
    expect(
      (h.requests.single['order'] as List).single['date'],
      '${other}T00:00:00',
    );
  });
  test('M06/M07: отмена требует точного подтверждения и отправляется вместе с новым днём', () async {
    final h = Harness();
    await h.init();
    await h.edit.begin(date);
    h.draft.clearDay(date);
    h.draft.increment(other, 'dish');
    await h.submit.submit();
    expect(h.requests, isEmpty);
    await h.submit.submit(confirmedCancellations: {other});
    expect(h.requests, isEmpty);
    await h.submit.submit(confirmedCancellations: {date});
    final days = h.requests.single['order'] as List;
    expect(days, hasLength(2));
    expect(days.first['dishes'], isEmpty);
    expect(days.last['dishes'].single['quantity'], 1);
  });
  test(
    'M08: перезапуск предлагает продолжение и восстанавливает количества/выбор',
    () async {
      final first = Harness();
      await first.init();
      await first.edit.begin(date);
      first.draft.increment(date, 'dish');
      first.draft.increment(other, 'dish');
      await first.edit.begin(other);
      await first.edit.persistNow();
      final h = Harness();
      await h.init();
      expect(h.state.active, isFalse);
      expect(h.state.recovery, isNotNull);
      expect(await h.edit.begin(date), isFalse);
      h.calls.clear();
      expect(await h.edit.resume(), isTrue);
      expect(h.calls, ['snapshot']);
      expect(h.state.dateKey, other);
      expect(h.container.read(cartDraftProvider)[date]!['dish'], 3);
      expect(h.container.read(cartDraftProvider)[other]!['dish'], 1);
    },
  );
  for (final closure in ['allowed', 'profile', 'menu', 'all']) {
    test('FL-UX-49: восстановление исключает закрытые дни: $closure', () async {
      final first = Harness();
      await first.init();
      expect(await first.edit.begin(date), isTrue);
      first.draft.increment(date, 'dish');
      first.draft.increment(other, 'dish');
      await first.edit.persistNow();
      final h = Harness();
      if (closure == 'allowed') h.allowed.remove(date);
      if (closure == 'all') h.allowed = {'2031-01-01'};
      if (closure == 'profile') {
        (h.user['order'] as List).first['changes'] = 'Закрыт';
      }
      await h.init(menuFactory: closure == 'menu' ? _WithoutDate.new : null);
      expect(await h.edit.resume(), closure != 'all');
      expect(h.state.recovery, isNull);
      expect(h.container.read(cartDraftProvider).containsKey(date), isFalse);
      if (closure == 'all') {
        expect(h.state.active, isFalse);
        expect(h.container.read(cartDraftProvider).containsKey(other), isFalse);
      } else {
        expect(h.state.dateKey, other);
        expect(h.state.preparedRevisions.keys, [other]);
        expect(h.container.read(cartDraftProvider)[other], {'dish': 1});
        expect(h.container.read(cartChangedDatesProvider), [other]);
      }
      // Ещё один запуск не должен возвращать удалённые даты из хранилища.
      final again = Harness();
      await again.init();
      expect(
        again.state.recovery?.revisions.containsKey(date) ?? false,
        isFalse,
      );
      expect(h.requests, isEmpty);
    });
  }
  test(
    'FL-UX-49: подготовка выбирает доступный день вместо закрытого',
    () async {
      final h = Harness();
      h.allowed.remove(date);
      await h.init();
      h.draft.setQuantity(date, 'dish', 9);
      expect(await h.edit.begin(date), isTrue);
      expect(h.state.dateKey, other);
      expect(h.state.preparedRevisions.keys, [other]);
      expect(h.container.read(cartDraftProvider).containsKey(date), isFalse);
      expect(h.requests, isEmpty);
    },
  );
  for (final conflict in [true, false]) {
    testWidgets('FL-UX-52: автоматическое восстановление, конфликт $conflict', (
      tester,
    ) async {
      final first = Harness();
      await tester.runAsync(first.init);
      await tester.runAsync(() async {
        await first.edit.begin(date);
        first.draft.increment(date, 'dish');
        first.draft.increment(other, 'dish');
        await first.edit.persistNow();
      });
      final h = Harness();
      await tester.runAsync(h.init);
      if (conflict) {
        h.revision = 'changed';
      } else {
        h.profileFail = true;
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(home: Scaffold(body: CartWorkBanner())),
        ),
      );
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        await tester.runAsync(() async {
          for (var i = 0; i < 100; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
      }
      await tester.pump();
      if (conflict) {
        expect(h.state.active, isTrue);
        expect(h.state.recovery, isNull);
        expect(h.state.message, isNull);
        expect(h.container.read(cartDraftProvider)[date], {'dish': 2});
        expect(h.container.read(cartDraftProvider).containsKey(other), isFalse);
        expect(h.container.read(cartChangedDatesProvider), isEmpty);
        expect(find.byKey(const ValueKey('work-resume')), findsNothing);
        expect(find.byKey(const ValueKey('work-discard')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(h.state.active, isFalse);
        expect(h.state.recovery, isNotNull);
        expect(find.byKey(const ValueKey('work-resume')), findsOneWidget);
        expect(find.byKey(const ValueKey('work-discard')), findsOneWidget);
        h.profileFail = false;
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('work-resume')));
          for (var i = 0; i < 100 && !h.state.active; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
        await tester.pump();
        expect(h.state.active, isTrue);
        expect(h.container.read(cartDraftProvider)[date], {'dish': 3});
        expect(h.container.read(cartDraftProvider)[other], {'dish': 1});
      }
      expect(h.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  for (final kind in ['revision', 'quantity']) {
    test(
      'FL-UX-52: конфликт $kind сохраняет актуальный исходный набор',
      () async {
        final first = Harness();
        await first.init();
        await first.edit.begin(date);
        first.draft.clearDay(date);
        first.draft.increment(other, 'dish');
        await first.edit.persistNow();
        final h = Harness();
        await h.init();
        if (kind == 'revision') h.revision = 'changed';
        if (kind == 'quantity') {
          (h.user['order'] as List).first['dishes'].first['quantity'] = 9;
        }
        expect(await h.edit.resume(), isTrue);
        expect(h.state.revision, h.revision);
        expect(h.container.read(cartDraftProvider)[date], {
          'dish': kind == 'quantity' ? 9 : 2,
        });
        expect(h.container.read(cartDraftProvider).containsKey(other), isFalse);
        expect(h.container.read(cartChangedDatesProvider), isEmpty);
        expect(h.container.read(cartCancelledDatesProvider), isEmpty);
        await h.submit.submit();
        expect(h.requests, isEmpty);
        final again = Harness();
        await again.init();
        expect(again.state.recovery, isNull);
      },
    );
  }
  test('FL-UX-52: сбой записи при конфликте не сбрасывает правки', () async {
    final store = _FailingStore();
    final h = Harness();
    await h.init(workStore: store);
    await h.edit.begin(date);
    h.draft.increment(date, 'dish');
    h.draft.increment(other, 'dish');
    await h.edit.persistNow();
    final before = h.edit.workSnapshot()!.toJson();
    final draft = h.container.read(cartDraftProvider);
    h.revision = 'changed';
    store.failSave = true;
    expect(await h.edit.resume(), isFalse);
    expect(h.container.read(cartDraftProvider), draft);
    expect(h.edit.workSnapshot()!.toJson(), before);
    expect(h.state.blocked, isTrue);
    store.failSave = false;
    expect(await h.edit.resume(), isTrue);
    expect(h.container.read(cartChangedDatesProvider), isEmpty);
    expect(h.container.read(cartDraftProvider)[date], {'dish': 2});
    expect(h.requests, isEmpty);
  });
  test('M09: чужой scope не затирает локальный снимок', () async {
    final first = Harness();
    await first.init();
    await first.edit.begin(date);
    first.draft.increment(date, 'dish');
    await first.edit.persistNow();
    final h = Harness();
    await h.init();
    final before = jsonEncode(h.state.recovery!.toJson());
    h.snapshotOverride = {
      ...h.snapshotBody(),
      'ownerScope': 'snapshot-v1:33333333-3333-4333-8333-333333333333:22222222-2222-4222-8222-222222222222',
    };
    expect(await h.edit.resume(), isFalse);
    expect(h.state.active, isFalse);
    expect(jsonEncode(h.state.recovery!.toJson()), before);
    expect(h.requests, isEmpty);
  });
  test(
    'M10/M12: ошибка записи блокирует POST; ошибка очистки сохраняет pending',
    () async {
      final store = _FailingStore();
      final h = Harness();
      await h.init(workStore: store);
      await h.edit.begin(date);
      store.failSave = true;
      h.draft.increment(date, 'dish');
      try {
        await h.edit.persistNow();
      } catch (_) {}
      expect(h.state.storageError, isTrue);
      await h.submit.submit();
      expect(h.requests, isEmpty);
      store.failSave = false;
      await h.edit.persistNow();
      expect(h.state.storageError, isFalse);
      store.failClear = true;
      await h.submit.submit();
      expect(h.requests, hasLength(1));
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.outcomeUnknown,
      );
      store.failClear = false;
      await h.submit.resolveUnknownOutcome();
      expect(h.requests, hasLength(1));
      expect(
        h.container.read(cartSubmitControllerProvider).phase,
        CartSubmitPhase.succeeded,
      );
    },
  );
  test('M11: неизвестный исход сохраняет весь пакет, not_found повторяет то же тело', () async {
    final h = Harness();
    await h.init();
    await h.edit.begin(date);
    h.draft.increment(date, 'dish');
    h.draft.increment(other, 'dish');
    h.loseResponse = true;
    await h.submit.submit();
    expect(await h.edit.begin(other), isFalse);
    h.resultNotFound = true;
    h.loseResponse = false;
    await h.submit.resolveUnknownOutcome();
    expect(h.requests, hasLength(2));
    expect(h.requests.last, h.requests.first);
  });
  test('M14: нетронутое отсутствующее блюдо не блокирует новый день', () async {
    final h = Harness();
    (h.user['order'] as List).first['dishes'].add({
      'dish': 'missing',
      'name': 'Убрано',
      'quantity': 1,
      'sum': 100,
    });
    await h.init();
    await h.edit.begin(other);
    h.draft.increment(other, 'dish');
    expect(h.container.read(cartPricingProvider)!.missingDishCount, 1);
    expect(
      h.container.read(cartSubmissionPricingProvider)!.missingDishCount,
      0,
    );
    await h.submit.submit();
    expect(h.requests, hasLength(1));
  });
  test(
    'M09/M10: поздний снимок после выхода не активирует чужой набор',
    () async {
      final h = Harness();
      await h.init();
      final held = Completer<http.Response>();
      h.heldSnapshot = held;
      final preparing = h.edit.begin(date);
      for (var i = 0; i < 100 && !h.calls.contains('snapshot'); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await h.container
          .read(sessionControllerProvider.notifier)
          .clearLocalSession();
      held.complete(h.json(h.snapshotBody()));
      expect(await preparing, isFalse);
      expect(h.state.active, isFalse);
      expect(h.requests, isEmpty);
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets('M16: вкладки и отмена $width, текст 1.6', (tester) async {
      final h = Harness();
      await tester.runAsync(h.init);
      await tester.runAsync(() async {
        await h.edit.begin(date);
        h.draft.clearDay(date);
        h.draft.increment(other, 'dish');
        await h.edit.persistNow();
      });
      await h.mount(tester, width);
      h.container.read(routerProvider).go('/cart');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-day-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-tab-$date')), findsOneWidget);
      expect(find.text('Ср!\n02.01'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('cart-tab-$other')));
      await tester.tap(find.byKey(const ValueKey('cart-tab-$other')));
      await tester.pumpAndSettle();
      expect(h.state.dateKey, other);
      expect(
        find.byKey(const ValueKey('cart-day-total-$other')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
