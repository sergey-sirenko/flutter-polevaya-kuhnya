import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

class _FailingStorage extends FlutterSecureStorage {
  _FailingStorage(this.operation);

  final String operation;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (operation == 'read') throw StateError('secret-storage-detail');
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (operation == 'write') throw StateError('secret-storage-detail');
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (operation == 'delete') throw StateError('secret-storage-detail');
  }
}

AppConfig config(
  String environment, [
  String api = 'https://example.test/api/',
]) => AppConfig.parse(
  appVersionUrl: environment == 'prod'
      ? 'https://new.obedmoscow.ru/version.json'
      : 'https://flutter-test.obedmoscow.ru/version.json',
  environment: environment,
  apiBaseUrl: api,
  dataBaseUrl: 'https://example.test/data/',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'UUID постоянен, одинаков при конкурентном чтении и переживает logout',
    () async {
      final storage = SessionStorage(config: config('test'));
      final ids = await Future.wait([storage.deviceId(), storage.deviceId()]);
      expect(ids[0], ids[1]);
      expect(
        ids[0],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      final save = storage.writeToken('test-token');
      final remove = storage.deleteToken();
      await Future.wait([save, remove]);
      final reopened = SessionStorage(config: config('test'));
      expect(await reopened.readToken(), isNull);
      expect(await reopened.deviceId(), ids[0]);
    },
  );

  test(
    'токены test/prod и разных API изолированы; профиль не сохраняется',
    () async {
      final testStorage = SessionStorage(config: config('test'));
      await testStorage.writeToken('test-token');
      await testStorage.deviceId();
      expect(await SessionStorage(config: config('prod')).readToken(), isNull);
      final testId = await testStorage.deviceId();
      final prodId = await SessionStorage(config: config('prod')).deviceId();
      final otherApiId = await SessionStorage(
        config: config('test', 'https://other.test/api/'),
      ).deviceId();
      expect(prodId, isNot(testId));
      expect(otherApiId, isNot(testId));
      expect(
        await SessionStorage(config: config('test', 'https://other.test/api/'))
            .readToken(),
        isNull,
      );
      final values = await const FlutterSecureStorage().readAll();
      expect(values.length, 4);
      expect(
        values.keys.every(
          (key) => key.endsWith('.token') || key.endsWith('.device_id'),
        ),
        isTrue,
      );
    },
  );

  test('повреждённый или не-v4 ID не заменяется новой привязкой', () async {
    final storage = SessionStorage(config: config('test'));
    await storage.deviceId();
    final secure = const FlutterSecureStorage();
    final key = (await secure.readAll()).keys.singleWhere(
      (value) => value.endsWith('.device_id'),
    );
    for (final invalid in [
      '',
      '00000000-0000-1000-8000-000000000000',
      'New3_00000000-0000-4000-8000-000000000000',
    ]) {
      await secure.write(key: key, value: invalid);
      await expectLater(
        SessionStorage(config: config('test')).deviceId(),
        throwsA(isA<SessionStorageException>()),
      );
      expect(await secure.read(key: key), invalid);
    }
  });

  test(
    'сбой хранилища не раскрывает подробности и не блокирует очередь',
    () async {
      for (final operation in ['read', 'write', 'delete']) {
        final storage = SessionStorage(
          config: config('test'),
          storage: _FailingStorage(operation),
        );
        final action = switch (operation) {
          'read' => storage.readToken(),
          'write' => storage.writeToken('synthetic-token'),
          _ => storage.deleteToken(),
        };
        await expectLater(action, throwsA(isA<SessionStorageException>()));
        expect(
          const SessionStorageException().toString(),
          'SessionStorageException',
        );
        final next = operation == 'read'
            ? storage.deleteToken()
            : storage.readToken();
        await next;
      }
    },
  );
}
