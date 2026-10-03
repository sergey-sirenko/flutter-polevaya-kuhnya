import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/platform/app_version_policy.dart';

/// Flutter передаёт метаданные сборки на всех клиентах, без запроса к серверу.
final appVersionLabelProvider = Provider<String>((ref) {
  return buildVersionLabel(version: appBuildName, build: appBuildNumber);
});

String buildVersionLabel({required String? version, required String? build}) {
  final name = version?.trim() ?? '';
  final number = build?.trim() ?? '';
  if (name.isEmpty || !RegExp(r'^\d+$').hasMatch(number)) {
    return AppStrings.aboutAppVersionUnavailable;
  }
  return '$name+$number';
}

/// Сравнение version.json со сборкой (FL-06-12/13).
/// Неизвестный ответ не считается устаревшей версией и не запускает перезагрузку.
enum VersionRelation { current, updateAvailable, unknown }

VersionRelation compareAppVersion({
  required String localVersion,
  required int localBuild,
  required Object? remote,
}) {
  if (remote is! Map) return VersionRelation.unknown;
  final local = AppVersion.tryParse(localVersion, localBuild);
  final published = AppVersion.tryParse(remote['version'], remote['build']);
  if (local == null || published == null) return VersionRelation.unknown;
  return published.compareTo(local) > 0
      ? VersionRelation.updateAvailable
      : VersionRelation.current;
}

/// Пути, которые нельзя класть в офлайн-кэш оболочки (FL-06-11).
bool isOfflineForbiddenPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('/api/') ||
      normalized.contains('/data/') ||
      normalized.contains('/obmen/') ||
      normalized.endsWith('/version.json');
}
