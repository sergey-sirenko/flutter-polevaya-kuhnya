import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_version_controller.dart';
import 'app_version_policy.dart';
import 'app_version_repository.dart';
import 'distribution.dart';
import 'web_update_browser.dart';
import 'web_update_browser_api.dart';

final webAutoUpdateProvider = Provider<WebAutoUpdate>((ref) {
  final updater = WebAutoUpdate(
    repository: ref.watch(appVersionRepositoryProvider),
    current: ref.watch(currentAppVersionProvider),
    browser: createWebUpdateBrowser(),
    enabled: ref.watch(installChannelProvider) == InstallChannel.web,
  );
  ref.onDispose(updater.dispose);
  return updater;
});

/// Проверка распространения не меняет gate и не блокирует бизнес-интерфейс.
class WebAutoUpdate {
  WebAutoUpdate({
    required this.repository,
    required this.current,
    required this.browser,
    required this.enabled,
    this.interval = const Duration(seconds: 10),
  });
  final AppVersionRepository repository;
  final AppVersion? current;
  final WebUpdateBrowser browser;
  final bool enabled;
  final Duration interval;
  Timer? _timer;
  void Function()? _unwatch;
  bool _checking = false;
  bool _disposed = false;
  final Set<String> _attempts = {};

  void start() {
    if (_disposed ||
        _timer != null ||
        !enabled ||
        !browser.supported ||
        current == null) {
      return;
    }
    _unwatch = browser.watchForeground(() => unawaited(check()));
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  Future<void> consider(AppRelease? release) async {
    if (_disposed ||
        !enabled ||
        !browser.supported ||
        current == null ||
        release == null ||
        release.version.compareTo(current!) <= 0) {
      return;
    }
    final target = release.version.toString();
    if (!_attempts.add(target)) return;
    try {
      await browser.reloadRelease(target);
    } catch (_) {
      // Без повторного reload на тот же release; следующий выпуск проверяется.
    }
  }

  Future<void> check() async {
    if (_disposed ||
        _checking ||
        !enabled ||
        !browser.supported ||
        !browser.visible ||
        current == null) {
      return;
    }
    _checking = true;
    try {
      final policy = await repository.fetch();
      if (!_disposed) await consider(policy.web);
    } on Exception {
      // Сеть/невалидная policy не меняют доступ; следующая проверка повторит GET.
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _unwatch?.call();
  }
}
