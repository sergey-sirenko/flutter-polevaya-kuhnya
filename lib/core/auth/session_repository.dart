import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return SessionRepository(
    api: ref.watch(apiClientProvider),
    storage: ref.watch(sessionStorageProvider),
  );
});

final class SessionRepository {
  const SessionRepository({required this.api, required this.storage});

  final ApiClient api;
  final SessionStorage storage;

  Future<SessionCredentials?> restoreCredentials() async {
    final token = await storage.readToken();
    if (token == null) return null;
    return SessionCredentials(token: token, deviceId: await storage.deviceId());
  }

  Future<SessionCredentials> verify(SessionCredentials credentials) async {
    final response = await api.postJson('V1/User/login', {
      'token': credentials.token,
      'deviceId': credentials.deviceId,
    });
    final token = response['token'];
    if (response['user'] is! Map<String, dynamic> ||
        (token != null && token is! String)) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный формат подтверждения сессии.',
      );
    }
    // Токеновая ветка 1С может не возвращать новый токен.
    return SessionCredentials(
      token: token is String && token.trim().isNotEmpty
          ? token
          : credentials.token,
      deviceId: credentials.deviceId,
    );
  }
}
