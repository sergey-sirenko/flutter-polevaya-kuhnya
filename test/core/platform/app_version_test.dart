import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/platform/app_version.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

void main() {
  test('метаданные запущенной сборки формируют версию без жёсткого номера', () {
    expect(buildVersionLabel(version: '2.3.4', build: '42'), '2.3.4+42');
    expect(buildVersionLabel(version: ' 0.1.0 ', build: ' 7 '), '0.1.0+7');
    for (final build in <String?>[null, '', 'unknown', '-1']) {
      expect(
        buildVersionLabel(version: '0.1.0', build: build),
        AppStrings.aboutAppVersionUnavailable,
      );
    }
    expect(
      buildVersionLabel(version: null, build: '7'),
      AppStrings.aboutAppVersionUnavailable,
    );
  });
  test('канал установки отделён от бизнес-маршрута', () {
    expect(
      installChannelFor(isWeb: true, platform: TargetPlatform.android),
      InstallChannel.web,
    );
    expect(
      installChannelFor(isWeb: false, platform: TargetPlatform.android),
      InstallChannel.android,
    );
    expect(
      initialLocationFor(isWeb: false, platform: TargetPlatform.android),
      '/',
    );
  });

  test('новая сборка в version.json требует обновления', () {
    expect(
      compareAppVersion(
        localVersion: '0.1.0',
        localBuild: 1,
        remote: {'version': '0.1.0', 'build': 2},
      ),
      VersionRelation.updateAvailable,
    );
  });

  test('сбой version.json не объявляет несовместимость', () {
    expect(
      compareAppVersion(localVersion: '0.1.0', localBuild: 1, remote: null),
      VersionRelation.unknown,
    );
    expect(
      compareAppVersion(
        localVersion: '0.1.0',
        localBuild: 1,
        remote: {'version': '', 'build': 'нет'},
      ),
      VersionRelation.unknown,
    );
    expect(
      compareAppVersion(
        localVersion: '0.1.0',
        localBuild: 1,
        remote: {'version': '0.1.0', 'build': 1},
      ),
      VersionRelation.current,
    );
  });

  test('API и данные не входят в офлайн-кэш оболочки', () {
    expect(isOfflineForbiddenPath('/data/dishes.json'), isTrue);
    expect(
      isOfflineForbiddenPath('/Zakaz_http/hs/Obmen/V1/User/login'),
      isTrue,
    );
    expect(isOfflineForbiddenPath('/version.json'), isTrue);
    expect(isOfflineForbiddenPath('/assets/FontManifest.json'), isFalse);
  });
}
