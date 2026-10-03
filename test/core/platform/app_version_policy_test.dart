import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

final versionConfig = AppConfig.parse(
  environment: 'test',
  apiBaseUrl: 'https://api.example.test/',
  dataBaseUrl: 'https://data.example.test/',
  appVersionUrl: 'https://flutter-test.obedmoscow.ru/version.json',
);

Map<String, Object?> policyDocument({int minimum = 1, int release = 8}) => {
  'version': '0.1.0',
  'build': release,
  'policy': <String, Object?>{
    'schema': 1,
    'environment': 'test',
    'minimum': {'version': '0.1.0', 'build': minimum},
    'releases': {
      'web': {
        'version': '0.1.0',
        'build': release,
        'url': 'https://flutter-test.obedmoscow.ru/',
      },
      'android': null,
      'ios': null,
    },
  },
};

void main() {
  test('version uses tuple, not build priority or folded rank', () {
    expect(
      AppVersion.tryParse(
        '0.2.0',
        1,
      )!.compareTo(AppVersion.tryParse('0.1.0', 99)!),
      greaterThan(0),
    );
    expect(
      AppVersion.tryParse(
        '0.1.1000',
        1,
      )!.compareTo(AppVersion.tryParse('0.2.0', 1)!),
      lessThan(0),
    );
    expect(
      AppVersion.tryParse(
        '1.0.0',
        3,
      )!.compareTo(AppVersion.tryParse('1.0.0', 2)!),
      greaterThan(0),
    );
  });
  test('strict version components and safe numeric bounds', () {
    for (final version in [
      '1.2',
      '1.2.3.4',
      '01.2.3',
      '1.2.3 ',
      '1.2.3\n',
      '-1.2.3',
      '1.2.3+4',
      '1.2.3-beta',
      '9007199254740992.0.0',
    ]) {
      expect(AppVersion.tryParse(version, 1), isNull, reason: version);
    }
    for (final build in [null, true, '1', 1.5, 0, -1, 9007199254740992]) {
      expect(AppVersion.tryParse('1.2.3', build), isNull, reason: '$build');
    }
    expect(
      AppVersion.tryParse('9007199254740991.0.0', 9007199254740991),
      isNotNull,
    );
  });
  test('web/version.json содержит принятую test-policy текущей сборки', () {
    final document = jsonDecode(
      File('web/version.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final policy = AppVersionPolicy.parse(document, config: versionConfig);
    expect(policy.minimum.toString(), '0.1.0+1');
    final sourceVersion = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    expect(policy.web.version.toString(), sourceVersion);
    expect(policy.web.uri.toString(), 'https://flutter-test.obedmoscow.ru/');
    expect(policy.releaseFor(InstallChannel.android), isNull);
    expect(policy.releaseFor(InstallChannel.ios), isNull);
    expect(document['version'], '0.1.0');
    expect(document['build'], int.parse(sourceVersion.split('+').last));
  });
  test('valid common minimum and native null, extra fields ignored', () {
    final doc = policyDocument()..['future'] = true;
    final policy = AppVersionPolicy.parse(doc, config: versionConfig);
    expect(policy.minimum.toString(), '0.1.0+1');
    expect(policy.releaseFor(InstallChannel.android), isNull);
    expect(policy.releaseFor(InstallChannel.ios), isNull);
    expect(policy.web.version.toString(), '0.1.0+8');
  });
  test('rejects whole policy on legacy, schema, environment, structure or mismatch', () {
    final invalid = <Object?>[
      null,
      {'version': '0.1.0', 'build': 8},
    ];
    for (final key in ['schema', 'environment', 'minimum', 'releases']) {
      final doc = policyDocument();
      (doc['policy'] as Map)[key] = key == 'environment' ? 'prod' : null;
      invalid.add(doc);
    }
    invalid.add(policyDocument(minimum: 9));
    invalid.add(policyDocument()..['build'] = 7);
    final missing = policyDocument();
    (((missing['policy'] as Map)['releases']) as Map).remove('ios');
    invalid.add(missing);
    for (final doc in invalid) {
      expect(
        () => AppVersionPolicy.parse(doc, config: versionConfig),
        throwsFormatException,
      );
    }
  });
  test(
    'release URL restricted to environment root; no credentials or redirects',
    () {
      for (final url in [
        'http://flutter-test.obedmoscow.ru/',
        'ftp://flutter-test.obedmoscow.ru/',
        '//flutter-test.obedmoscow.ru/',
        'https://evil.example/',
        'https://u:p@flutter-test.obedmoscow.ru/',
        'https://flutter-test.obedmoscow.ru/#a',
        'https://flutter-test.obedmoscow.ru/?next=a',
        'https://flutter-test.obedmoscow.ru/apk',
      ]) {
        final doc = policyDocument();
        ((((doc['policy'] as Map)['releases'] as Map)['web']) as Map)['url'] =
            url;
        expect(
          () => AppVersionPolicy.parse(doc, config: versionConfig),
          throwsFormatException,
          reason: url,
        );
      }
    },
  );
  test(
    'native release requires exact approved product URL and compatibility',
    () {
      final doc = policyDocument();
      final url = Uri.parse(
        'https://play.google.com/store/apps/details?id=approved.example',
      );
      (((doc['policy'] as Map)['releases']) as Map)['android'] = {
        'version': '0.1.0',
        'build': 4,
        'url': url.toString(),
      };
      expect(
        () => AppVersionPolicy.parse(doc, config: versionConfig),
        throwsFormatException,
      );
      final policy = AppVersionPolicy.parse(
        doc,
        config: versionConfig,
        approvedNativeUrls: {InstallChannel.android: url},
      );
      expect(policy.android!.version.toString(), '0.1.0+4');
    },
  );
}
