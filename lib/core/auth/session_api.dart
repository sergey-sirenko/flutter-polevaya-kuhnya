import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';

final class StaleSessionException implements Exception {
  const StaleSessionException();

  @override
  String toString() => 'StaleSessionException';
}

/// Транспорт для Repository, привязанный к одному поколению сессии.
final class SessionApi {
  const SessionApi({
    required this._api,
    required this._credentials,
    required this._isCurrent,
    required this._onUnauthorized,
  });

  final ApiClient _api;
  final SessionCredentials _credentials;
  final bool Function() _isCurrent;
  final Future<void> Function() _onUnauthorized;

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    _checkCurrent();
    if (body.containsKey('token') || body.containsKey('deviceId')) {
      throw ArgumentError('Реквизиты сессии задаёт SessionApi.');
    }
    try {
      final response = await _api.postJson(path, {
        ...body,
        'token': _credentials.token,
        'deviceId': _credentials.deviceId,
      });
      _checkCurrent();
      return response;
    } on ApiException catch (error) {
      _checkCurrent();
      if (error.invalidSession) await _onUnauthorized();
      rethrow;
    }
  }

  void _checkCurrent() {
    if (!_isCurrent()) throw const StaleSessionException();
  }
}
