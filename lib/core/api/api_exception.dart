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
    this.retryAfter,
    this.outcomeUnknown = false,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;

  /// Секунды ожидания при `rate_limited`, если сервер передал `retryAfter`.
  final int? retryAfter;

  /// Ответ на запись мог потеряться уже после её выполнения сервером.
  final bool outcomeUnknown;

  /// Сессия недействительна: HTTP 401 или код `invalid_session` / `invalid_token`
  /// (в том числе на переходном HTTP 400).
  bool get invalidSession =>
      kind == ApiErrorKind.unauthorized ||
      code == 'invalid_session' ||
      code == 'invalid_token';

  /// Нужен новый вход: недействительная сессия или сбой привязки устройства.
  /// `access_denied` сюда не входит — токен сам по себе не очищается.
  bool get requiresReauth =>
      invalidSession || code == 'device_mismatch' || code == 'session_unbound';

  @override
  String toString() => 'ApiException($kind, statusCode: $statusCode)';
}
