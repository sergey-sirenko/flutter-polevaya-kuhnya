import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:polevaya_kuhnya/core/platform/semantic_url_strategy.dart';

final initialLocationProvider = Provider<String>(
  (ref) => initialLocationFor(isWeb: kIsWeb, platform: defaultTargetPlatform),
);

final installChannelProvider = Provider<InstallChannel>(
  (ref) => installChannelFor(isWeb: kIsWeb, platform: defaultTargetPlatform),
);

String initialLocationFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return '/';
}

/// Канал установки. Бизнес-экраны от него не зависят (FL-06-07).
enum InstallChannel { web, android, ios, other }

InstallChannel installChannelFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return InstallChannel.web;
  return switch (platform) {
    TargetPlatform.android => InstallChannel.android,
    TargetPlatform.iOS => InstallChannel.ios,
    _ => InstallChannel.other,
  };
}

// Сохраняем также fragment явного Web-адреса; на native SDK делает no-op.
SemanticUrlStrategy? _semanticUrlStrategy;
final semanticUrlStrategyProvider = Provider<SemanticUrlStrategy?>(
  (ref) => _semanticUrlStrategy,
);

void configureUrlStrategy() {
  if (!kIsWeb) return;
  final strategy = SemanticUrlStrategy(
    PathUrlStrategy(BrowserPlatformLocation(), true),
  );
  _semanticUrlStrategy = strategy;
  setUrlStrategy(strategy);
}

/// Портрет установленного Android и iOS (ADR-10). Web не блокируется:
/// `null` означает оставить ориентацию браузера. Страница целиком не поворачивается.
List<DeviceOrientation>? preferredOrientationsFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return null;
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => const [DeviceOrientation.portraitUp],
    _ => null,
  };
}

Future<void> applyPreferredOrientations({
  required bool isWeb,
  required TargetPlatform platform,
}) async {
  final orientations = preferredOrientationsFor(
    isWeb: isWeb,
    platform: platform,
  );
  if (orientations == null) return;
  await SystemChrome.setPreferredOrientations(orientations);
}
