import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('реальное хранилище записывает, читает и удаляет токен', (
    tester,
  ) async {
    final config = AppConfig.parse(
      appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
      environment: 'test',
      apiBaseUrl: 'https://storage-probe.invalid/Obmen/',
      dataBaseUrl: 'https://storage-probe.invalid/data/',
    );
    final storage = SessionStorage(config: config);
    final token = 'probe-${DateTime.now().microsecondsSinceEpoch}';

    await storage.deleteToken();
    try {
      expect(await storage.readToken(), isNull);
      await storage.writeToken(token);
      final reopened = SessionStorage(config: config);
      expect(await reopened.readToken(), token);
      await reopened.deleteToken();
      expect(await SessionStorage(config: config).readToken(), isNull);
    } finally {
      await storage.deleteToken();
    }
  });
}
