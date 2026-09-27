import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/app.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

void main() {
  const api = 'https://hleb-sol.su/Zakaz_http/hs/Obmen/';
  const data = 'https://flutter-test.obedmoscow.ru/data/';

  for (final environment in <String>['test', 'prod']) {
    testWidgets('главная site открывается в $environment', (tester) async {
      final config = AppConfig.parse(
        environment: environment,
        apiBaseUrl: api,
        dataBaseUrl: data,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStatusProvider.overrideWithValue(SessionStatus.signedOut),
            appConfigProvider.overrideWithValue(config),
            initialLocationProvider.overrideWithValue('/'),
          ],
          child: const FieldKitchenApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text(AppStrings.appTitle), findsOneWidget);
      expect(
        find.text(AppStrings.testBuild),
        environment == 'test' ? findsOneWidget : findsNothing,
      );
      final theme = Theme.of(tester.element(find.text(AppStrings.appTitle)));
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppTheme.primary);
      expect(theme.scaffoldBackgroundColor, AppTheme.background);
      expect(theme.textTheme.titleLarge?.fontFamily, 'Arial');
    });
  }
}
