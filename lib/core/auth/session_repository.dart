import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';

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

  /// Обновление профиля по токену без пароля (`POST V1/User/login`).
  Future<SessionVerification> verify(SessionCredentials credentials) async {
    final response = await api.postJson('V1/User/login', {
      'token': credentials.token,
      'deviceId': credentials.deviceId,
    });
    final token = response['token'];
    if (response['user'] is! Map || (token != null && token is! String)) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный формат подтверждения сессии.',
      );
    }
    final UserProfile profile;
    try {
      profile = UserProfile.fromUserJson(response['user']);
    } on FormatException catch (error) {
      throw ApiException(kind: ApiErrorKind.format, message: error.message);
    }
    // Токеновая ветка 1С может не возвращать новый токен (или вернуть прежний).
    return SessionVerification(
      credentials: SessionCredentials(
        token: token is String && token.trim().isNotEmpty
            ? token
            : credentials.token,
        deviceId: credentials.deviceId,
      ),
      profile: profile,
    );
  }

  /// Отзыв текущего токена; вызывающий не должен ждать сеть для локального выхода.
  Future<void> revoke(SessionCredentials credentials) async {
    await api.postJson('V1/User/logout', {
      'token': credentials.token,
      'deviceId': credentials.deviceId,
    });
  }
}
