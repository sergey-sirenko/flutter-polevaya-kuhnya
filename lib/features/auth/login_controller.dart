import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/features/auth/login_repository.dart';

final loginControllerProvider = NotifierProvider<LoginController, LoginState>(
  LoginController.new,
);

final class LoginState {
  const LoginState({this.isSubmitting = false, this.error});

  final bool isSubmitting;
  final String? error;
}

class LoginController extends Notifier<LoginState> {
  late LoginRepository _repository;

  @override
  LoginState build() {
    _repository = ref.watch(loginRepositoryProvider);
    return const LoginState();
  }

  void clearError() {
    if (!state.isSubmitting) state = const LoginState();
  }

  Future<bool> submit({required String login, required String password}) async {
    if (state.isSubmitting) return false;
    state = const LoginState(isSubmitting: true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(
            (deviceId) => _repository.authenticate(
              login: login,
              password: password,
              deviceId: deviceId,
            ),
          );
      if (!ref.mounted) return false;
      final signedIn =
          ref.read(sessionControllerProvider).status == SessionStatus.signedIn;
      state = const LoginState();
      return signedIn;
    } catch (error) {
      if (ref.mounted) {
        state = LoginState(error: _messageFor(error));
      }
      return false;
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return AppStrings.signInUnexpectedError;
    return switch (error.code) {
      'invalid_credentials' => AppStrings.signInInvalidCredentials,
      'registration_required' => AppStrings.signInRegistrationRequired,
      'access_denied' || 'device_mismatch' => AppStrings.signInAccessDenied,
      _ => switch (error.kind) {
        ApiErrorKind.network ||
        ApiErrorKind.timeout => AppStrings.signInConnectionError,
        ApiErrorKind.forbidden ||
        ApiErrorKind.unauthorized => AppStrings.signInAccessDenied,
        _ => AppStrings.signInUnexpectedError,
      },
    };
  }
}
