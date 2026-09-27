import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

final initialLocationProvider = Provider<String>(
  (ref) => initialLocationFor(isWeb: kIsWeb, platform: defaultTargetPlatform),
);

String initialLocationFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return '/';
  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS => '/menu',
    // Остальные платформы нужны только для среды разработки и тестов.
    _ => '/',
  };
}

// Сохраняем также fragment явного Web-адреса; на native SDK делает no-op.
void configureUrlStrategy() =>
    setUrlStrategy(PathUrlStrategy(BrowserPlatformLocation(), true));
