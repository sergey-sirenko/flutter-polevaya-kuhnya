import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  configureUrlStrategy();
  await applyPreferredOrientations(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const FieldKitchenApp(),
    ),
  );
}
