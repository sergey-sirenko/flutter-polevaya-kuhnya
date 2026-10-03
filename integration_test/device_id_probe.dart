import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

void main() => runApp(const _DeviceIdProbe());

class _DeviceIdProbe extends StatefulWidget {
  const _DeviceIdProbe();

  @override
  State<_DeviceIdProbe> createState() => _DeviceIdProbeState();
}

class _DeviceIdProbeState extends State<_DeviceIdProbe> {
  late final Future<String> result = _verify();

  Future<String> _verify() async {
    try {
      final config = AppConfig.parse(
        appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
        environment: 'test',
        apiBaseUrl: 'https://device-probe.invalid/Obmen/',
        dataBaseUrl: 'https://device-probe.invalid/data/',
      );
      final storage = SessionStorage(config: config);
      final id = await storage.deviceId();
      if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id)) {
        return 'FAIL FORMAT';
      }
      await storage.deleteToken();
      if (await SessionStorage(config: config).deviceId() != id) {
        return 'FAIL LOGOUT';
      }

      const secure = FlutterSecureStorage();
      const probeKey = 'field_kitchen.fl0303.restart_probe';
      final beforeRestart = await secure.read(key: probeKey);
      if (beforeRestart == null) {
        await secure.write(key: probeKey, value: id);
        return 'BASELINE';
      }
      await secure.delete(key: probeKey);
      return beforeRestart == id ? 'PASS RESTART' : 'FAIL RESTART';
    } catch (_) {
      return 'FAIL STORAGE';
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: FutureBuilder<String>(
          future: result,
          builder: (context, snapshot) => Text(
            snapshot.data ?? 'RUNNING',
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    ),
  );
}
