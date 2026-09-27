import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

AppConfig config(
  String environment, [
  String api = 'https://example.test/api/',
]) => AppConfig.parse(
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
      expect(
        await SessionStorage(config: config('test', 'https://other.test/api/'))
            .readToken(),
        isNull,
      );
      final values = await const FlutterSecureStorage().readAll();
      expect(values.length, 2);
      expect(
        values.keys.every(
          (key) => key.endsWith('.token') || key.endsWith('.device_id'),
        ),
        isTrue,
      );
    },
  );
}
