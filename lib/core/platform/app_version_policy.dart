import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/platform/distribution.dart';

/// Кортеж версии. Build сравнивается только при равной основной версии.
final class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch, this.build);
  final int major, minor, patch, build;
  static const maxSafeInteger = 9007199254740991;

  static AppVersion? tryParse(Object? version, Object? build) {
    if (version is! String ||
        build is! int ||
        build < 1 ||
        build > maxSafeInteger ||
        !RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
            .hasMatch(version)) {
      return null;
    }
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.any((p) => p == null || p > maxSafeInteger)) return null;
    return AppVersion._(parts[0]!, parts[1]!, parts[2]!, build);
  }

  static AppVersion parseRecord(Object? value) {
    final parsed = value is Map
        ? tryParse(value['version'], value['build'])
        : null;
    if (parsed == null) throw const FormatException('Некорректная версия.');
    return parsed;
  }

  @override
  int compareTo(AppVersion other) {
    final left = [major, minor, patch, build];
    final right = [other.major, other.minor, other.patch, other.build];
    for (var i = 0; i < left.length; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch+$build';
}

final class AppRelease {
  const AppRelease(this.version, this.uri);
  final AppVersion version;
  final Uri uri;
}

final class AppVersionPolicy {
  const AppVersionPolicy._(this.minimum, this.web, this.android, this.ios);
  final AppVersion minimum;
  final AppRelease web;
  final AppRelease? android, ios;

  AppRelease? releaseFor(InstallChannel channel) => switch (channel) {
    InstallChannel.web => web,
    InstallChannel.android => android,
    InstallChannel.ios => ios,
    InstallChannel.other => null,
  };

  /// Пока магазинные URL не приняты, allowlist native пуст: выпуск только null.
  static AppVersionPolicy parse(
    Object? document, {
    required AppConfig config,
    Map<InstallChannel, Uri> approvedNativeUrls = const {},
  }) {
    if (document is! Map) {
      throw const FormatException('Нет документа политики.');
    }
    final policy = document['policy'];
    if (policy is! Map ||
        policy['schema'] is! int ||
        policy['schema'] != 1 ||
        policy['environment'] != config.environment.name) {
      throw const FormatException('Неизвестная схема или среда политики.');
    }
    final minimum = AppVersion.parseRecord(policy['minimum']);
    final releases = policy['releases'];
    if (releases is! Map ||
        !['web', 'android', 'ios'].every(releases.containsKey)) {
      throw const FormatException('Не заданы каналы выпуска.');
    }
    AppRelease? read(String key, InstallChannel channel) {
      final value = releases[key];
      if (value == null && channel != InstallChannel.web) return null;
      final version = AppVersion.parseRecord(value);
      final url = (value as Map)['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      final allowed =
          uri != null &&
          uri.scheme == 'https' &&
          uri.hasAuthority &&
          uri.host.isNotEmpty &&
          (channel == InstallChannel.web
              ? uri.origin == config.appVersionUri.origin &&
                    uri.path == '/' &&
                    !uri.hasQuery
              : uri == approvedNativeUrls[channel]);
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          !allowed ||
          version.compareTo(minimum) < 0) {
        throw const FormatException('Недопустимый выпуск или URL.');
      }
      return AppRelease(version, uri);
    }

    final web = read('web', InstallChannel.web)!;
    if (AppVersion.parseRecord(document).compareTo(web.version) != 0) {
      throw const FormatException('Версия Web не совпала с документом.');
    }
    return AppVersionPolicy._(
      minimum,
      web,
      read('android', InstallChannel.android),
      read('ios', InstallChannel.ios),
    );
  }
}
