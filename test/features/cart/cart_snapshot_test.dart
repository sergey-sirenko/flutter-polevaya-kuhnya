import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/features/cart/cart_draft.dart';
import 'package:polevaya_kuhnya/features/cart/cart_edit_controller.dart';
import 'package:polevaya_kuhnya/features/cart/cart_repository.dart';
import 'package:polevaya_kuhnya/features/cart/cart_snapshot.dart';
import 'package:polevaya_kuhnya/features/menu/menu_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_edit_flow_test.dart' show Harness, config, date, other;

Map<String, dynamic> fixture() =>
    jsonDecode(jsonEncode(Harness().snapshotBody())) as Map<String, dynamic>;

Future<void> tick() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final explicit in [false, true]) {
    test('Repository: один POST snapshot, dates указан $explicit', () async {
      final body = fixture();
      if (explicit) body['states'] = [(body['states'] as List).first];
      if (!explicit) {
        body['states'] = [
          for (var i = 0; i < 14; i++)
            {
              'date':
                  '${DateTime.utc(2026, 10, 5 + i).toIso8601String().substring(0, 10)}T00:00:00',
              'revision': 'none',
            },
        ];
      }
      var count = 0;
      final api = SessionApi(
        api: ApiClient(
          config: config,
          client: MockClient((request) async {
            count++;
            expect(request.method, 'POST');
            expect(request.url.path, endsWith('/V1/Orders/snapshot'));
            final sent = jsonDecode(request.body) as Map;
            expect(sent['token'], 'synthetic');
            expect(sent['deviceId'], '11111111-1111-4111-8111-111111111111');
            if (explicit) {
              expect(sent['dates'], ['${date}T00:00:00']);
            } else {
              expect(sent.containsKey('dates'), isFalse);
            }
            return Harness().json(body);
          }),
        ),
        credentials: const SessionCredentials(
          token: 'synthetic',
          deviceId: '11111111-1111-4111-8111-111111111111',
        ),
        isCurrent: () => true,
        onUnauthorized: () async {},
      );
      final snapshot = await CartRepository(sessionApi: api)
          .loadSnapshot(explicit ? [date] : null);
      expect(count, 1);
      expect(snapshot.profile.orders.single.dishes.single.quantity, 2);
      expect(snapshot.revisions.length, explicit ? 1 : 14);
      expect(snapshot.allowedDates, {date, other});
    });
  }

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'schema': (b) => b['schemaVersion'] = 2,
    'scope': (b) => b['ownerScope'] = 'repeat-v1:wrong',
    'profile': (b) => (b['user'] as Map).remove('email'),
    'conditions': (b) => (b['user'] as Map)['Limit'] = '100',
    'history': (b) =>
        (b['user']['order'] as List).first['date'] = '2030-02-30T00:00:00',
    'dishes': (b) => (b['user']['order'] as List).first['dishes'] = {},
    'quantity': (b) => b['user']['order'][0]['dishes'][0]['quantity'] = '2',
    'dates': (b) => b['menudates'] = ['2030-01-02T12:00:00'],
    'duplicate dates': (b) =>
        b['menudates'] = ['${date}T00:00:00', '${date}T00:00:00'],
    'missing revision': (b) => b['states'] = [],
    'extra revision': (b) => (b['states'] as List).add({
      'date': '${other}T00:00:00',
      'revision': 'none',
    }),
    'duplicate revision': (b) =>
        (b['states'] as List).add(Map.from(b['states'][0])),
    'empty revision': (b) => b['states'][0]['revision'] = '',
    'date in revision': (b) => b['states'][0]['date'] = '2030-01-32T00:00:00',
    'payable': (b) => b['user']['order'][0]['finalPayable'] = -1,
  };
  for (final entry in mutations.entries) {
    test('snapshot отклоняет ${entry.key}', () {
      final body = fixture();
      entry.value(body);
      expect(() => OrderSnapshot.parse(body, [date]), throwsFormatException);
    });
  }
  test('горизонт без dates требует обе недели полностью', () {
    final body = fixture();
    expect(() => OrderSnapshot.parse(body, null), throwsFormatException);
  });

  test(
    'применение без загрузки и запросов сохраняет поколение сессии',
    () async {
      final h = Harness();
      await h.init();
      final generation = h.container.read(sessionControllerProvider).generation;
      h.user['employee'] = 'Обновлённое имя';
      h.user['email'] = 'new@example.invalid';
      h.allowed = {date};
      final states = <bool>[];
      h.container.listen(
        menuAllowedDatesProvider,
        (_, next) => states.add(next.isLoading),
      );
      h.calls.clear();
      expect(await h.edit.begin(date), isTrue);
      await tick();
      expect(h.calls, ['snapshot']);
      expect(
        h.container.read(sessionControllerProvider).generation,
        generation,
      );
      expect(
        h.container.read(sessionProfileProvider)?.email,
        'new@example.invalid',
      );
      expect(h.container.read(menuAllowedDatesProvider).asData?.value, {date});
      expect(states, everyElement(isFalse));
      expect(h.state.revision, 'rev-a');
      expect(h.container.read(cartDraftProvider)[date], {'dish': 2});
    },
  );

  for (final invalid in [
    'owner',
    'scope change',
    'schema',
    'duplicate day',
    'none with dishes',
  ]) {
    test('отказ $invalid не применяет профиль, даты или черновик', () async {
      final h = Harness();
      await h.init();
      if (invalid == 'scope change') {
        expect(await h.edit.begin(date), isTrue);
        await h.edit.persistNow();
        h.container.invalidate(cartEditControllerProvider);
        await h.edit.ready;
      }
      h.draft.setQuantity(other, 'untouched', 5);
      final profile = h.container.read(sessionProfileProvider);
      final allowed = h.container.read(menuAllowedDatesProvider).asData?.value;
      final draft = h.container.read(cartDraftProvider);
      final body = fixture();
      body['user']['email'] = 'should-not-apply@example.invalid';
      body['menudates'] = ['${date}T00:00:00'];
      switch (invalid) {
        case 'owner':
          body['user']['login'] = 'someone-else';
        case 'scope change':
          body['ownerScope'] = (body['ownerScope'] as String).replaceFirst(
            '22222222',
            '33333333',
          );
        case 'schema':
          body['schemaVersion'] = 2;
        case 'duplicate day':
          body['user']['order'].add(Map.from(body['user']['order'][0]));
        case 'none with dishes':
          body['states'][0]['revision'] = 'none';
      }
      h.snapshotOverride = body;
      h.calls.clear();
      expect(
        await (invalid == 'scope change'
            ? h.edit.resume()
            : h.edit.begin(date)),
        isFalse,
      );
      expect(h.calls, ['snapshot']);
      expect(h.container.read(sessionProfileProvider), same(profile));
      expect(h.container.read(menuAllowedDatesProvider).asData?.value, allowed);
      expect(h.container.read(cartDraftProvider), draft);
    });
  }

  test('смена поколения сессии отклоняет поздний снимок', () async {
    final h = Harness();
    await h.init();
    final held = Completer<http.Response>();
    h.heldSnapshot = held;
    final preparing = h.edit.begin(date);
    await tick();
    await h.container.read(sessionControllerProvider.notifier).restore();
    await tick();
    final profile = h.container.read(sessionProfileProvider);
    final draft = h.container.read(cartDraftProvider);
    final body = fixture();
    body['user']['email'] = 'late@example.invalid';
    held.complete(h.json(body));
    expect(await preparing, isFalse);
    expect(h.container.read(sessionProfileProvider), same(profile));
    expect(h.container.read(cartDraftProvider), draft);
    expect(h.state.active, isFalse);
  });

  for (final failure in [false, true]) {
    test('поздний reload дат, ошибка $failure, не затирает snapshot', () async {
      final h = Harness();
      await h.init();
      final held = Completer<http.Response>();
      h.heldDates = held;
      final pending = h.container
          .read(menuAllowedDatesProvider.notifier)
          .reload();
      await tick();
      h.allowed = {date};
      expect(await h.edit.begin(date), isTrue);
      if (failure) {
        held.completeError(http.ClientException('late failure'));
      } else {
        held.complete(
          h.json({
            'success': true,
            'menudates': [other],
          }),
        );
      }
      await pending;
      expect(h.container.read(menuAllowedDatesProvider).asData?.value, {date});
      expect(h.container.read(menuAllowedDatesProvider).hasError, isFalse);
    });
  }

  for (final failure in [false, true]) {
    test(
      'поздняя начальная загрузка дат, ошибка $failure, сохраняет snapshot',
      () async {
        final h = Harness();
        await h.init();
        final held = Completer<http.Response>();
        h.heldDates = held;
        h.container.invalidate(menuAllowedDatesProvider);
        final initial = h.container.read(menuAllowedDatesProvider.future);
        await tick();
        h.allowed = {date};
        expect(await h.edit.begin(date), isTrue);
        if (failure) {
          held.completeError(http.ClientException('late initial failure'));
        } else {
          held.complete(
            h.json({
              'success': true,
              'menudates': [other],
            }),
          );
        }
        await initial;
        await tick();
        expect(h.container.read(menuAllowedDatesProvider).asData?.value, {
          date,
        });
        expect(h.container.read(menuAllowedDatesProvider).hasError, isFalse);
      },
    );
  }

  test(
    'неподдерживаемый сервером snapshot: ошибка без fallback, повтор возможен',
    () async {
      final h = Harness();
      await h.init();
      final held = Completer<http.Response>();
      h.heldSnapshot = held;
      h.calls.clear();
      final preparing = h.edit.begin(date);
      await tick();
      held.complete(h.json({'success': false, 'code': 'not_found'}, 404));
      expect(await preparing, isFalse);
      expect(h.calls, ['snapshot']);
      expect(h.state.message, isNotNull);
      expect(await h.edit.begin(date), isTrue);
      expect(h.calls, ['snapshot', 'snapshot']);
    },
  );
}
