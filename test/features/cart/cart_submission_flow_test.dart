import '../../support/compatible_version.dart';

import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_page.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submission_store.dart';
import 'package:polevaya_kuhnya/features/cart/cart_submit_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_controller.dart';
import 'package:polevaya_kuhnya/features/menu/menu_models.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _date = '2030-01-02';
const _id = '11111111-1111-4111-8111-111111111111';
final _config = AppConfig.parse(
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
  environment: 'test',
  apiBaseUrl: 'https://api.example.invalid/Obmen/',
  dataBaseUrl: 'https://data.example.invalid/data/',
);
final _owner = NotifierProvider<_Owner, String?>(_Owner.new);

class _Owner extends Notifier<String?> {
  @override
  String? build() => 'alpha';
  void change(String? value) => state = value;
}

class _Menu extends MenuController {
  @override
  Future<List<MenuWeek>> build() async => [
    MenuWeek(
      weekType: 'current',
      days: [
        MenuDay(
          dateKey: _date,
          date: DateTime(2030, 1, 2),
          categories: [
            MenuCategory(
              categoryId: 'soup',
              categoryName: 'Супы',
              dishes: const [
                MenuDish(dishId: 'dish-a', dishName: 'Суп', price: 100),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}

class _PreparedEdit extends CartEditController {
  @override
  CartEditState build() =>
      CartEditState(dateKey: _date, owner: ref.watch(_owner), revision: 'none');
}

class _Session extends SessionController {
  @override
  SessionState build() => const SessionState(SessionStatus.signedIn, 0);
  @override
  UserProfile? get profile => ref.read(sessionProfileProvider);
  @override
  Future<UserProfile> refreshProfile() async => profile!;
  @override
  void applyProfileSnapshot(
    UserProfile profile, {
    required int generation,
    required String ownerScope,
  }) {
    if (profile.login != this.profile?.login) {
      throw const FormatException('Владелец снимка изменился.');
    }
  }
}

class _Dates extends MenuAllowedDatesController {
  @override
  Future<Set<String>?> build() async => {_date};
  @override
  Future<void> reload() async {
    state = AsyncData({_date});
  }
}

http.Response _json(Map<String, Object?> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);
Map<String, Object?> _accepted(String id) => {
  'success': true,
  'submission': {'id': id, 'status': 'accepted'},
  'order': [
    {
      'date': '${_date}T00:00:00',
      'finalPayable': 100,
      'finalPayableScope': 'employee_dishes',
    },
  ],
  'snapshot': {
    'success': true,
    'schemaVersion': 1,
    'ownerScope': 'snapshot-v1:11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222',
    'user': {
      'login': 'alpha',
      'name': 'Alpha',
      'employee': '',
      'email': '',
      'phone': '',
      'LimitPeriod': '',
      'DiscountPercentage': null,
      'DiscountClient': 0,
      'DiscountPromotion': 0,
      'Limit': 0,
      'MinimumOrderAmount': 0,
      'MinimumPaymentAmount': 0,
      'order': [],
    },
    'menudates': ['${_date}T00:00:00'],
    'states': [
      {'date': '${_date}T00:00:00', 'revision': 'rev-after'},
    ],
  },
};
CartPendingSubmission _pending({String owner = 'alpha'}) =>
    CartPendingSubmission(
      owner: owner,
      body: {
        'submissionId': _id,
        'order': [
          {
            'date': '${_date}T00:00:00',
            'revision': 'none',
            'dishes': [
              {
                'dish': 'dish-a',
                'name': 'Суп',
                'quantity': 1,
                'DiscountClient': 0,
              },
            ],
          },
        ],
      },
      preliminary: {_date: 100},
    );

class _Harness {
  _Harness(
    Future<http.Response> Function(http.Request) handler, {
    SharedPreferences? draftPrefs,
    SharedPreferences? attemptPrefs,
  }) {
    final client = MockClient(handler);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_config),
        appVersionControllerProvider.overrideWith(
          CompatibleVersionController.new,
        ),
        cartEditControllerProvider.overrideWith(_PreparedEdit.new),
        sessionControllerProvider.overrideWith(_Session.new),
        if (draftPrefs != null)
          cartDraftStoreProvider.overrideWithValue(
            CartDraftStore(config: _config, prefs: draftPrefs),
          ),
        if (attemptPrefs != null)
          cartSubmissionStoreProvider.overrideWithValue(
            CartSubmissionStore(config: _config, prefs: attemptPrefs),
          ),
        sessionProfileProvider.overrideWith((ref) {
          final owner = ref.watch(_owner);
          return owner == null
              ? null
              : UserProfile.fromUserJson({'login': owner});
        }),
        sessionStatusProvider.overrideWithValue(SessionStatus.signedIn),
        menuControllerProvider.overrideWith(_Menu.new),
        menuAllowedDatesProvider.overrideWith(_Dates.new),
        cartRepositoryProvider.overrideWith((ref) {
          final owner = ref.watch(_owner);
          if (owner == null) return null;
          return CartRepository(
            sessionApi: SessionApi(
              api: ApiClient(config: _config, client: client),
              credentials: SessionCredentials(
                token: 'synthetic-$owner',
                deviceId: _id,
              ),
              isCurrent: () => ref.read(_owner) == owner,
              onUnauthorized: () async {},
            ),
            store: ref.watch(cartSubmissionStoreProvider),
          );
        }),
      ],
    );
    container.listen(cartSubmitControllerProvider, (_, _) {});
    container.listen(cartPersistenceControllerProvider, (_, _) {});
  }
  late final ProviderContainer container;
  CartSubmitController get controller =>
      container.read(cartSubmitControllerProvider.notifier);
  CartSubmitState get state => container.read(cartSubmitControllerProvider);
  Map<String, Map<String, int>> get draft => container.read(cartDraftProvider);
  Future<void> settle() async {
    await container.read(menuControllerProvider.future);
    await container.read(menuAllowedDatesProvider.future);
    await container.read(cartPersistenceControllerProvider.notifier).ready;
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void choose(int quantity) => container
      .read(cartDraftProvider.notifier)
      .setQuantity(_date, 'dish-a', quantity);
  void dispose() => container.dispose();
}

class _FailingPrefs implements SharedPreferences {
  _FailingPrefs(this.delegate);
  final SharedPreferences delegate;
  bool failWrites = false;
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  bool containsKey(String key) => delegate.containsKey(key);
  @override
  Future<bool> setString(String key, String value) async =>
      failWrites ? false : delegate.setString(key, value);
  @override
  Future<bool> remove(String key) async =>
      failWrites ? false : delegate.remove(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('отказ сохранения попытки не допускает POST корзины', () async {
    final prefs = _FailingPrefs(await SharedPreferences.getInstance())
      ..failWrites = true;
    final h = _Harness((r) async {
      expect(r.url.path, endsWith('basketstate'));
      return _json({
        'success': true,
        'states': [
          {'date': _date, 'revision': 'none'},
        ],
      });
    }, attemptPrefs: prefs);
    addTearDown(h.dispose);
    await h.settle();
    h.choose(1);
    await h.controller.submit();
    expect(h.state.phase, CartSubmitPhase.recoveryBlocked);
    expect(h.draft[_date]?['dish-a'], 1);
  });

  test(
    'отказ сохранения очищенного draft сохраняет попытку для проверки',
    () async {
      final prefs = _FailingPrefs(await SharedPreferences.getInstance());
      final h = _Harness((r) async {
        if (r.url.path.endsWith('basketstate')) {
          return _json({
            'success': true,
            'states': [
              {'date': _date, 'revision': 'none'},
            ],
          });
        }
        prefs.failWrites = true;
        return _json(_accepted(jsonDecode(r.body)['submissionId'] as String));
      }, draftPrefs: prefs);
      addTearDown(h.dispose);
      await h.settle();
      h.choose(1);
      await h.controller.submit();
      expect(h.state.phase, CartSubmitPhase.outcomeUnknown);
      expect(h.state.editingLocked, isTrue);
      expect(h.state.message, AppStrings.cartAcceptedCleanupFailed);
      expect(
        await CartSubmissionStore(config: _config).load('alpha'),
        isNotNull,
      );
    },
  );

  testWidgets('успех показан уведомлением после очистки всей корзины', (
    tester,
  ) async {
    late _Harness h;
    await tester.runAsync(() async {
      h = _Harness((r) async {
        final body = jsonDecode(r.body) as Map;
        if (r.url.path.endsWith('basketstate')) {
          return _json({
            'success': true,
            'states': [
              {'date': _date, 'revision': 'none'},
            ],
          });
        }
        return _json(_accepted(body['submissionId'] as String));
      });
      await h.settle();
      h.choose(1);
      await h.controller.submit();
    });
    addTearDown(h.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: const MaterialApp(home: CartPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.state.phase, CartSubmitPhase.idle);
    expect(h.draft, isEmpty);
    expect(find.text(AppStrings.cartAccepted), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('100 ₽'), findsNothing);
    expect(find.text(AppStrings.cartGoToOrders), findsNothing);
    expect(find.text(AppStrings.cartContinueChoosing), findsNothing);
    expect(find.text(AppStrings.cartEmpty), findsOneWidget);
    expect(
      await tester.runAsync(
        () => CartSubmissionStore(config: _config).load('alpha'),
      ),
      isNull,
    );
  });

  test('перезапуск восстанавливает ID, accepted не повторяет POST', () async {
    Map<String, Object?>? sent;
    final first = _Harness((r) async {
      if (r.url.path.endsWith('basketstate')) {
        return _json({
          'success': true,
          'states': [
            {'date': _date, 'revision': 'none'},
          ],
        });
      }
      sent = Map<String, Object?>.from(jsonDecode(r.body) as Map)
        ..remove('token')
        ..remove('deviceId');
      throw http.ClientException('synthetic offline');
    });
    await first.settle();
    first.choose(1);
    await first.controller.submit();
    expect(first.state.phase, CartSubmitPhase.outcomeUnknown);
    final id = sent!['submissionId'] as String;
    first.dispose();
    var reads = 0;
    final second = _Harness((r) async {
      expect(r.url.path, endsWith('basketresult'));
      expect(jsonDecode(r.body)['submissionId'], id);
      reads++;
      return _json(_accepted(id));
    });
    addTearDown(second.dispose);
    await second.settle();
    expect(reads, 0); // при старте даже чтение сети не автоматическое
    expect(second.state.submissionId, id);
    expect(second.draft[_date]?['dish-a'], 1);
    await second.controller.submit();
    expect(reads, 0); // новый независимый POST заблокирован
    await second.controller.resolveUnknownOutcome();
    expect(reads, 1);
    expect(second.state.phase, CartSubmitPhase.succeeded);
    expect(second.draft, isEmpty);
  });

  test('not_found повторяет ровно сохранённое тело и прежний ID', () async {
    final pending = _pending();
    await CartSubmissionStore(config: _config).save(pending);
    var writes = 0;
    final h = _Harness((r) async {
      if (r.url.path.endsWith('basketresult')) {
        return _json({'success': false, 'code': 'not_found'});
      }
      expect(r.url.path, endsWith('/basket'));
      final body = Map<String, Object?>.from(jsonDecode(r.body) as Map)
        ..remove('token')
        ..remove('deviceId');
      expect(body, pending.body);
      writes++;
      return _json(_accepted(_id));
    });
    addTearDown(h.dispose);
    await h.settle();
    h.choose(3); // обновлённый draft НЕ подменяет снимок запроса
    await h.controller.resolveUnknownOutcome();
    expect(writes, 1);
    expect(h.draft, isEmpty);
  });

  test('сбой basketresult разрешает только повтор чтения', () async {
    await CartSubmissionStore(config: _config).save(_pending());
    var calls = 0;
    final h = _Harness((r) async {
      expect(r.url.path, endsWith('basketresult'));
      calls++;
      throw http.ClientException('synthetic offline');
    });
    addTearDown(h.dispose);
    await h.settle();
    await h.controller.resolveUnknownOutcome();
    await h.controller.submit();
    await h.controller.resolveUnknownOutcome();
    expect(calls, 2);
    expect(h.state.phase, CartSubmitPhase.outcomeUnknown);
    expect(await CartSubmissionStore(config: _config).load('alpha'), isNotNull);
  });

  test('другая квитанция не подтверждает успех и не разрешает POST', () async {
    await CartSubmissionStore(config: _config).save(_pending());
    final h = _Harness(
      (r) async => _json(_accepted('22222222-2222-4222-8222-222222222222')),
    );
    addTearDown(h.dispose);
    await h.settle();
    await h.controller.resolveUnknownOutcome();
    expect(h.state.phase, CartSubmitPhase.outcomeUnknown);
    expect(await CartSubmissionStore(config: _config).load('alpha'), isNotNull);
  });

  test(
    'поздний успех после logout не очищает draft другого владельца',
    () async {
      final reply = Completer<http.Response>();
      final dispatched = Completer<String>();
      final h = _Harness((r) async {
        if (r.url.path.endsWith('basketstate')) {
          return _json({
            'success': true,
            'states': [
              {'date': _date, 'revision': 'none'},
            ],
          });
        }
        dispatched.complete(jsonDecode(r.body)['submissionId'] as String);
        return reply.future;
      });
      addTearDown(h.dispose);
      await h.settle();
      h.choose(1);
      final sending = h.controller.submit();
      final id = await dispatched.future;
      h.container.read(_owner.notifier).change(null);
      await h.settle();
      h.container.read(_owner.notifier).change('beta');
      await h.settle();
      h.choose(7);
      reply.complete(_json(_accepted(id)));
      await sending;
      await h.settle();
      expect(h.draft[_date]?['dish-a'], 7);
      expect(h.state.phase, CartSubmitPhase.idle);
      expect(
        await CartSubmissionStore(config: _config).load('alpha'),
        isNotNull,
      );
      expect(await CartSubmissionStore(config: _config).load('beta'), isNull);
      h.container.read(_owner.notifier).change('alpha');
      await h.settle();
      expect(h.state.phase, CartSubmitPhase.outcomeUnknown);
      expect(h.draft[_date]?['dish-a'], 1);
    },
  );

  test('подтверждённый успех очищает все старые черновики даже после программных правок', () async {
    final reply = Completer<http.Response>();
    final dispatched = Completer<String>();
    final h = _Harness((r) async {
      if (r.url.path.endsWith('basketstate')) {
        return _json({
          'success': true,
          'states': [
            {'date': _date, 'revision': 'none'},
          ],
        });
      }
      dispatched.complete(jsonDecode(r.body)['submissionId'] as String);
      return reply.future;
    });
    addTearDown(h.dispose);
    await h.settle();
    h.choose(1);
    final sending = h.controller.submit();
    final id = await dispatched.future;
    expect(h.state.editingLocked, isTrue);
    h.choose(4); // защитная проверка даже для программного изменения
    h.container
        .read(cartDraftProvider.notifier)
        .setQuantity('2030-01-03', 'new-dish', 2);
    reply.complete(_json(_accepted(id)));
    await sending;
    expect(h.state.phase, CartSubmitPhase.succeeded);
    expect(h.draft, isEmpty);
  });

  test('старый ключ блокирует новую отправку и не мигрирует', () async {
    SharedPreferences.setMockInitialValues({
      'cart.pending.alpha': '{"submissionId":"old"}',
    });
    final h = _Harness((_) async {
      fail('Сети быть не должно');
    });
    addTearDown(h.dispose);
    await h.settle();
    expect(h.state.phase, CartSubmitPhase.recoveryBlocked);
    h.choose(1);
    await h.controller.submit();
    await h.controller.retryRestore();
    expect(h.state.phase, CartSubmitPhase.recoveryBlocked);
    expect(
      (await SharedPreferences.getInstance()).containsKey('cart.pending.alpha'),
      isTrue,
    );
  });

  test('области API и владельцы изолированы, снимок неизменен', () async {
    final store = CartSubmissionStore(config: _config);
    final pending = _pending();
    final copy = pending.body;
    (copy['order'] as List).clear();
    await store.save(pending);
    expect((await store.load('alpha'))!.body['order'], isNotEmpty);
    expect(await store.load('beta'), isNull);
    final other = CartSubmissionStore(
      config: AppConfig.parse(
        appVersionUrl: 'https://new.obedmoscow.ru/version.json',
        environment: 'prod',
        apiBaseUrl: 'https://other.example.invalid/Obmen/',
        dataBaseUrl: 'https://data.example.invalid/data/',
      ),
    );
    expect(await other.load('alpha'), isNull);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().single;
    await prefs.setString(key, '{broken');
    await expectLater(store.load('alpha'), throwsFormatException);
    expect(prefs.getString(key), '{broken');
  });

  for (final kind in ['http500', 'invalid-json', 'missing-receipt']) {
    test('$kind при записи сохраняет неизвестный исход', () async {
      final h = _Harness((r) async {
        if (r.url.path.endsWith('basketstate')) {
          return _json({
            'success': true,
            'states': [
              {'date': _date, 'revision': 'none'},
            ],
          });
        }
        return switch (kind) {
          'http500' => http.Response(jsonEncode({'success': false}), 500),
          'invalid-json' => http.Response('{broken', 200),
          _ => _json({'success': true, 'order': []}),
        };
      });
      addTearDown(h.dispose);
      await h.settle();
      h.choose(1);
      await h.controller.submit();
      expect(h.state.phase, CartSubmitPhase.outcomeUnknown);
      expect(h.draft[_date]?['dish-a'], 1);
      expect(
        await CartSubmissionStore(config: _config).load('alpha'),
        isNotNull,
      );
    });
  }

  test('явный отказ сервера сохраняет draft, но завершает попытку', () async {
    final h = _Harness((r) async {
      if (r.url.path.endsWith('basketstate')) {
        return _json({
          'success': true,
          'states': [
            {'date': _date, 'revision': 'none'},
          ],
        });
      }
      return _json({
        'success': false,
        'code': 'order_changed',
        'message': 'День изменён',
      });
    });
    addTearDown(h.dispose);
    await h.settle();
    h.choose(1);
    await h.controller.submit();
    expect(h.state.phase, CartSubmitPhase.failed);
    expect(h.draft[_date]?['dish-a'], 1);
    expect(await CartSubmissionStore(config: _config).load('alpha'), isNull);
  });

  test(
    'заблокированная подготовка не создаёт попытку и сетевой запрос',
    () async {
      final h = _Harness((r) async {
        fail('Нельзя обращаться к серверу без подготовленной revision');
      });
      addTearDown(h.dispose);
      await h.settle();
      h.choose(1);
      h.container
          .read(cartEditControllerProvider.notifier)
          .block('Версия недоступна');
      await h.controller.submit();
      expect(h.state.phase, CartSubmitPhase.failed);
      expect(await CartSubmissionStore(config: _config).load('alpha'), isNull);
    },
  );

  test(
    'повторное нажатие во время запроса не вызывает вторую запись',
    () async {
      final reply = Completer<http.Response>();
      final dispatched = Completer<String>();
      var writes = 0;
      final h = _Harness((r) async {
        if (r.url.path.endsWith('basketstate')) {
          return _json({
            'success': true,
            'states': [
              {'date': _date, 'revision': 'none'},
            ],
          });
        }
        writes++;
        dispatched.complete(jsonDecode(r.body)['submissionId'] as String);
        return reply.future;
      });
      addTearDown(h.dispose);
      await h.settle();
      h.choose(1);
      final first = h.controller.submit();
      final id = await dispatched.future;
      await h.controller.submit();
      expect(writes, 1);
      reply.complete(_json(_accepted(id)));
      await first;
      expect(h.state.phase, CartSubmitPhase.succeeded);
    },
  );
}
