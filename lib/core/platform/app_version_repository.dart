import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';

final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return HttpAppVersionRepository(
    ref.watch(apiClientProvider),
    ref.watch(appConfigProvider),
  );
});

abstract interface class AppVersionRepository {
  Future<AppVersionPolicy> fetch();
}

final class HttpAppVersionRepository implements AppVersionRepository {
  HttpAppVersionRepository(this._client, this._config);
  final ApiClient _client;
  final AppConfig _config;
  final String _instance = Random().nextInt(1 << 30).toRadixString(16);
  int _sequence = 0;

  @override
  Future<AppVersionPolicy> fetch() async {
    final check =
        '${DateTime.now().microsecondsSinceEpoch}-$_instance-${++_sequence}';
    final json = await _client.getVersionJson(check: check);
    return AppVersionPolicy.parse(json, config: _config);
  }
}
