import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() => runApp(const _StorageProbe());

class _StorageProbe extends StatelessWidget {
  const _StorageProbe();

  Future<String> _verify() async {
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
      if (await storage.readToken() != null) return 'FAIL: initial read';
      await storage.writeToken(token);
      if (await SessionStorage(config: config).readToken() != token) {
        return 'FAIL: read after write';
      }
      await storage.deleteToken();
      if (await SessionStorage(config: config).readToken() != null) {
        return 'FAIL: read after delete';
      }
      return 'PASS';
    } catch (error) {
      return 'FAIL: $error';
    } finally {
      await storage.deleteToken();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: FutureBuilder<String>(
          future: _verify(),
          builder: (context, snapshot) => Text(
            snapshot.data ?? 'RUNNING',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    ),
  );
}
