enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  business,
  http,
  format,
}

/// Ошибка транспорта или ответ сервера без тела запроса и секретов.
final class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.outcomeUnknown = false,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;

  /// Ответ на запись мог потеряться уже после её выполнения сервером.
  final bool outcomeUnknown;

  /// Только подтверждённый HTTP 401. Старый HTTP 400 неоднозначен.
  bool get invalidSession => kind == ApiErrorKind.unauthorized;

  @override
  String toString() => 'ApiException($kind, statusCode: $statusCode)';
}
