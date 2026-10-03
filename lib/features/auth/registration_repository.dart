import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';

final registrationRepositoryProvider = Provider<RegistrationRepository>((ref) {
  return RegistrationRepository(api: ref.watch(apiClientProvider));
});

enum RegistrationAvailability { required, ready }

final class RegistrationStartResult {
  const RegistrationStartResult({
    required this.requestId,
    required this.retryAfter,
    required this.expiresIn,
  });

  /// Временный ключ только для памяти открытой формы, не для URL или диска.
  final String requestId;
  final int retryAfter;
  final int expiresIn;
}

final class RegistrationRepository {
  const RegistrationRepository({required this.api});

  final ApiClient api;

  Future<RegistrationAvailability> check({
    required String login,
    required String password,
    required String deviceId,
  }) async {
    try {
      final response = await api.postJson('V1/User/registrationstatus', {
        'login': login,
        'password': password,
        'deviceId': deviceId,
      });
      if (response['code'] == 'ready') return RegistrationAvailability.ready;
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный статус регистрации.',
      );
    } on ApiException catch (error) {
      if (error.code == 'registration_required') {
        return RegistrationAvailability.required;
      }
      rethrow;
    }
  }

  Future<RegistrationStartResult> start({
    required String login,
    required String password,
    required String deviceId,
    required String fullName,
    required String email,
  }) async {
    final response = await api.postJson('V1/User/registrationstart', {
      'login': login,
      'password': password,
      'deviceId': deviceId,
      'fullName': fullName,
      'email': email,
      'registrationMode': 'context_v1',
    });
    return _codeSent(response);
  }

  Future<RegistrationStartResult> resend({
    required String requestId,
    required String deviceId,
  }) async {
    final response = await api.postJson('V1/User/registrationresend', {
      'requestId': requestId,
      'deviceId': deviceId,
    });
    return _codeSent(response);
  }

  Future<void> confirm({
    required String requestId,
    required String deviceId,
    required String verificationCode,
  }) async {
    final response = await api.postJson('V1/User/registrationconfirm', {
      'requestId': requestId,
      'deviceId': deviceId,
      'verificationCode': verificationCode,
    });
    if (response['code'] != 'registered') {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный ответ подтверждения регистрации.',
      );
    }
  }

  static RegistrationStartResult _codeSent(Map<String, dynamic> response) {
    final requestId = response['requestId'];
    final retryAfter = response['retryAfter'];
    final expiresIn = response['expiresIn'];
    if (response['code'] != 'code_sent' ||
        requestId is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(requestId) ||
        retryAfter is! int ||
        retryAfter < 0 ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        expiresIn > 600) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный ответ отправки кода.',
      );
    }
    return RegistrationStartResult(
      requestId: requestId,
      retryAfter: retryAfter,
      expiresIn: expiresIn,
    );
  }
}
