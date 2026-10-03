import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/features/cart/cart_work_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const scope =
    'snapshot-v1:11111111-1111-4111-8111-111111111111:22222222-2222-4222-8222-222222222222';
final config = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.test/',
  dataBaseUrl: 'https://data.test/',
  appVersionUrl: 'https://version.test/version.json',
);

CartWorkSnapshot make({int dates = 2}) {
  final keys = [
    for (var i = 0; i < dates; i++)
      DateTime.utc(
        2030,
        1,
        2,
      ).add(Duration(days: i)).toIso8601String().substring(0, 10),
  ];
  return CartWorkSnapshot(
    ownerScope: scope,
    selectedDateKey: keys.first,
    revisions: {for (final d in keys) d: d == keys.first ? 'old' : 'none'},
    originals: {
      for (final d in keys) d: d == keys.first ? {'dish': 2} : {},
    },
    names: {
      keys.first: {'dish': 'Суп'},
    },
    quantities: {
      keys.last: {'dish': 1},
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'пустая отмена переживает сериализацию; membership отделён от количеств',
    () {
      final snapshot = CartWorkSnapshot.parse(
        jsonDecode(jsonEncode(make().toJson())),
      );
      expect(snapshot.changedDates, ['2030-01-02', '2030-01-03']);
      expect(snapshot.cancelledDates, ['2030-01-02']);
      expect(snapshot.quantities.containsKey('2030-01-02'), isFalse);
      expect(snapshot.originals['2030-01-02'], {'dish': 2});
      expect(
        () => snapshot.originals['2030-01-02']!['dish'] = 9,
        throwsUnsupportedError,
      );
    },
  );
  test('31 дата разрешена, 32 отклоняются без сокращения', () {
    expect(make(dates: 31).revisions, hasLength(31));
    expect(() => make(dates: 32), throwsFormatException);
  });
  for (final mutation in [
    'version',
    'scope',
    'quantity',
    'original',
    'foreign',
    'selected',
  ]) {
    test('повреждённый снимок $mutation отклоняется', () {
      final raw = jsonDecode(jsonEncode(make().toJson())) as Map;
      switch (mutation) {
        case 'version':
          raw['version'] = 2;
        case 'scope':
          raw['ownerScope'] = 'foreign';
        case 'quantity':
          raw['quantities']['2030-01-03']['dish'] = 1.5;
        case 'original':
          raw['originals'].remove('2030-01-02');
        case 'foreign':
          raw['quantities']['2030-02-02'] = {'dish': 1};
        case 'selected':
          raw['selectedDateKey'] = '2030-01-32';
      }
      expect(() => CartWorkSnapshot.parse(raw), throwsFormatException);
    });
  }
  test(
    'изоляция API/окружения/login/устройства, токена в данных нет',
    () async {
      final store = CartWorkStore(config);
      await store.save('alice', 'device-a', make());
      expect(await store.load('alice', 'device-a'), isNotNull);
      expect(await store.load('bob', 'device-a'), isNull);
      expect(await store.load('alice', 'device-b'), isNull);
      final other = CartWorkStore(
        AppConfig.parse(
          environment: 'prod',
          apiBaseUrl: 'https://other.test/',
          dataBaseUrl: 'https://data.test/',
          appVersionUrl: 'https://version.test/version.json',
        ),
      );
      expect(await other.load('alice', 'device-a'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(store.key('alice', 'device-a')),
        isNot(contains('token')),
      );
      await store.clear('bob', 'device-a');
      expect(await store.load('alice', 'device-a'), isNotNull);
    },
  );
  test(
    'очередь после ошибки продолжает работу; очистка следует после записей',
    () async {
      final queue = CartWorkQueue();
      final store = CartWorkStore(config);
      final rejected = queue.run(() async => throw StateError('disk'));
      final save = queue.run(() => store.save('alice', 'device', make()));
      final clear = queue.run(() => store.clear('alice', 'device'));
      await expectLater(rejected, throwsStateError);
      await save;
      await clear;
      expect(await store.load('alice', 'device'), isNull);
    },
  );
}
