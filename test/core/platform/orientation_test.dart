import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

void main() {
  test('портрет только у установленного Android и iOS', () {
    const portrait = [DeviceOrientation.portraitUp];
    for (final platform in TargetPlatform.values) {
      expect(
        preferredOrientationsFor(isWeb: true, platform: platform),
        isNull,
        reason: platform.name,
      );
    }
    expect(
      preferredOrientationsFor(isWeb: false, platform: TargetPlatform.android),
      portrait,
    );
    expect(
      preferredOrientationsFor(isWeb: false, platform: TargetPlatform.iOS),
      portrait,
    );
    for (final platform in [
      TargetPlatform.fuchsia,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        preferredOrientationsFor(isWeb: false, platform: platform),
        isNull,
        reason: platform.name,
      );
    }
  });
}
