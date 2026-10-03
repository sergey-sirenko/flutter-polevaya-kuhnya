enum AppEnvironment { test, prod }

final class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.apiBaseUri,
    required this.dataBaseUri,
    required this.appVersionUri,
  });

  final AppEnvironment environment;
  final Uri apiBaseUri;
  final Uri dataBaseUri;
  final Uri appVersionUri;

  bool get isTest => environment == AppEnvironment.test;

  Uri get menuUri => dataBaseUri.resolve('dishes.json');

  static AppConfig fromEnvironment() => parse(
    environment: const String.fromEnvironment('APP_ENV'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    dataBaseUrl: const String.fromEnvironment('DATA_BASE_URL'),
    appVersionUrl: const String.fromEnvironment('APP_VERSION_URL'),
  );

  static AppConfig parse({
    required String environment,
    required String apiBaseUrl,
    required String dataBaseUrl,
    required String appVersionUrl,
  }) {
    final appEnvironment = switch (environment) {
      'test' => AppEnvironment.test,
      'prod' => AppEnvironment.prod,
      _ => throw StateError('APP_ENV должен быть test или prod.'),
    };

    return AppConfig._(
      environment: appEnvironment,
      apiBaseUri: _parseBaseUri('API_BASE_URL', apiBaseUrl),
      dataBaseUri: _parseBaseUri('DATA_BASE_URL', dataBaseUrl),
      appVersionUri: _parseVersionUri(appVersionUrl),
    );
  }

  static Uri _parseVersionUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/version.json') {
      throw StateError(
        'APP_VERSION_URL должен быть HTTPS-адресом /version.json без параметров.',
      );
    }
    return uri;
  }

  static Uri _parseBaseUri(String name, String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/')) {
      throw StateError('$name должен быть базовым HTTPS-адресом с / в конце.');
    }
    return uri;
  }
}
