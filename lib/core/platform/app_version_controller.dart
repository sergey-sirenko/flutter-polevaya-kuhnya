import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_repository.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

final currentAppVersionProvider = Provider<AppVersion?>(
  (ref) =>
      AppVersion.tryParse(appBuildName, int.tryParse(appBuildNumber ?? '')),
);

final appVersionControllerProvider =
    NotifierProvider<AppVersionController, AppVersionCheck>(
      AppVersionController.new,
    );

enum AppVersionStatus { checking, current, available, required, unknown }

enum AppVersionFailure { transport, invalidPolicy, invalidCurrent }

bool versionBlocksWork(AppVersionCheck version) =>
    version.requiresUpdate ||
    version.checking ||
    version.status == AppVersionStatus.checking ||
    (version.status == AppVersionStatus.unknown && version.failure == null);

final class AppVersionCheck {
  const AppVersionCheck(
    this.status, {
    this.current,
    this.policy,
    this.release,
    this.checking = false,
    this.failure,
  });
  final AppVersionStatus status;
  final AppVersion? current;
  final AppVersionPolicy? policy;
  final AppRelease? release;
  final bool checking;
  final AppVersionFailure? failure;
  bool get requiresUpdate => status == AppVersionStatus.required;
}

/// Стартовая проверка вызывается app один раз; последующие — по кнопке повтора.
class AppVersionController extends Notifier<AppVersionCheck> {
  int _generation = 0;
  AppVersionCheck? _required;
  late AppVersionRepository _repository;
  AppVersion? _current;
  late InstallChannel _channel;

  @override
  AppVersionCheck build() {
    _generation++;
    _required = null;
    _repository = ref.watch(appVersionRepositoryProvider);
    _current = ref.watch(currentAppVersionProvider);
    _channel = ref.watch(installChannelProvider);
    ref.onDispose(() => _generation++);
    return AppVersionCheck(AppVersionStatus.unknown, current: _current);
  }

  Future<void> check() async {
    final generation = ++_generation;
    final current = _current;
    if (current == null) {
      state = const AppVersionCheck(
        AppVersionStatus.unknown,
        failure: AppVersionFailure.invalidCurrent,
      );
      return;
    }
    final required = _required;
    state = AppVersionCheck(
      required?.status ?? AppVersionStatus.checking,
      current: current,
      policy: required?.policy,
      release: required?.release,
      checking: true,
    );
    try {
      final policy = await _repository.fetch();
      if (generation != _generation) return;
      final release = policy.releaseFor(_channel);
      final status = current.compareTo(policy.minimum) < 0
          ? AppVersionStatus.required
          : release != null && release.version.compareTo(current) > 0
          ? AppVersionStatus.available
          : AppVersionStatus.current;
      state = AppVersionCheck(
        status,
        current: current,
        policy: policy,
        release: release,
      );
      _required = state.requiresUpdate ? state : null;
    } on Exception catch (error) {
      if (generation != _generation) return;
      final required = _required;
      state = AppVersionCheck(
        required?.status ?? AppVersionStatus.unknown,
        current: current,
        policy: required?.policy,
        release: required?.release,
        failure: error is FormatException
            ? AppVersionFailure.invalidPolicy
            : AppVersionFailure.transport,
      );
    }
  }
}
