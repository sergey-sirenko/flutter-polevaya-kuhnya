import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';

final loginRepositoryProvider = Provider<LoginRepository>((ref) {
  return LoginRepository(api: ref.watch(apiClientProvider));
});

final class LoginRepository {
  const LoginRepository({required this.api});

  final ApiClient api;

  Future<String> authenticate({
    required String login,
    required String password,
    required String deviceId,
  }) async {
    final response = await api.postJson('V1/User/login', {
      'login': login,
      'password': password,
      'deviceId': deviceId,
      'selfRegistration': true,
    });
    final token = response['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'В ответе входа отсутствует токен.',
      );
    }
    return token;
  }
}
