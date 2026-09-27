import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  throw StateError('AppConfig должен быть передан при запуске приложения.');
});
