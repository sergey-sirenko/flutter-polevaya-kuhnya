import 'package:url_launcher/url_launcher.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Отказ платформенного обработчика — обычный результат внешнего действия.
Future<bool> tryOpenExternal(Uri uri, {ExternalUrlLauncher? launcher}) async {
  if (!uri.hasScheme) return false;
  try {
    return await (launcher?.call(uri) ??
        launchUrl(uri, mode: LaunchMode.externalApplication));
  } catch (_) {
    return false;
  }
}
