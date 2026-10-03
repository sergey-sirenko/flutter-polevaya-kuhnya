import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/router.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/app/theme.dart';
import 'package:polevaya_kuhnya/app/version_gate.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';
import 'package:polevaya_kuhnya/core/platform/web_auto_update.dart';
import 'package:polevaya_kuhnya/features/menu/menu_excel.dart';
import 'package:polevaya_kuhnya/features/site/site_widgets.dart';

class FieldKitchenApp extends ConsumerStatefulWidget {
  const FieldKitchenApp({super.key});

  @override
  ConsumerState<FieldKitchenApp> createState() => _FieldKitchenAppState();
}

class _FieldKitchenAppState extends ConsumerState<FieldKitchenApp> {
  bool _businessStarted = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.microtask(() async {
        if (mounted) {
          final updater = ref.read(webAutoUpdateProvider);
          await ref.read(appVersionControllerProvider.notifier).check();
          if (mounted) {
            updater.start();
            await updater.consider(
              ref.read(appVersionControllerProvider).release,
            );
          }
        }
      }),
    );
  }

  void _continueAfterUnknown() {
    if (!mounted) return;
    final latest = ref.read(appVersionControllerProvider);
    if (latest.status == AppVersionStatus.unknown &&
        latest.failure != null &&
        !latest.checking) {
      setState(() => _businessStarted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appVersionControllerProvider, (_, next) {
      if (!next.checking) {
        unawaited(ref.read(webAutoUpdateProvider).consider(next.release));
      }
    });
    final version = ref.watch(appVersionControllerProvider);
    if (version.status == AppVersionStatus.current ||
        version.status == AppVersionStatus.available ||
        (ref.watch(installChannelProvider) == InstallChannel.android &&
            version.status == AppVersionStatus.unknown &&
            version.failure != null &&
            !version.checking)) {
      _businessStarted = true;
    }
    if (!_businessStarted) {
      return MaterialApp(
        title: AppStrings.appTitle,
        theme: AppTheme.light,
        // До проверки нет Navigator/router: явный Web-адрес не переписывается.
        builder: (context, child) => Overlay.wrap(
          child: VersionGatePage(
            version: version,
            onContinue:
                version.status == AppVersionStatus.unknown &&
                    version.failure != null
                ? _continueAfterUnknown
                : null,
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: AppStrings.appTitle,
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Overlay.wrap(
        child: VersionGuard(
          version: version,
          child: SiteNavAction(
            action: const MenuDownloadButton(),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
