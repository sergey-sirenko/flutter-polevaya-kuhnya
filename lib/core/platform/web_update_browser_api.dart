abstract interface class WebUpdateBrowser {
  bool get supported;
  bool get visible;
  void Function() watchForeground(void Function() onForeground);
  Future<bool> reloadRelease(String release);
}

/// Технический маркер одновременно обновляет URL документа и ограничивает
/// попытку одним переходом, даже если браузер запретил sessionStorage.
String? webUpdateLocation(
  String href,
  String release,
  String? previousAttempt,
) {
  final current = Uri.parse(href);
  if (previousAttempt == release ||
      current.queryParameters['_app_update'] == release) {
    return null;
  }
  return current
      .replace(
        queryParameters: {
          ...current.queryParametersAll,
          '_app_update': release,
        },
      )
      .toString();
}
