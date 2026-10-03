import 'package:polevaya_kuhnya/core/platform/app_version_controller.dart';
export 'package:polevaya_kuhnya/core/platform/app_version_controller.dart'
    show appVersionControllerProvider;

/// Бизнес-сценарии исходят из совместимой версии; startup проверяется отдельно.
class CompatibleVersionController extends AppVersionController {
  @override
  AppVersionCheck build() => const AppVersionCheck(AppVersionStatus.current);

  @override
  Future<void> check() async {}
}
