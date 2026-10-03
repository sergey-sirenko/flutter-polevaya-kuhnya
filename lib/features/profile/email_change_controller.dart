import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/profile/email_change_repository.dart';

final emailChangeControllerProvider =
    NotifierProvider<EmailChangeController, EmailChangeState>(
      EmailChangeController.new,
    );

final class EmailChangeState {
  const EmailChangeState({
    this.isLoading = false,
    this.isSubmitting = false,
    this.status,
    this.error,
    this.errorCode,
    this.retryAfter,
    this.outcomeUnknown = false,
  });

  final bool isLoading;
  final bool isSubmitting;
  final EmailChangeStatus? status;
  final String? error;
  final String? errorCode;
  final int? retryAfter;
  final bool outcomeUnknown;
}

class EmailChangeController extends Notifier<EmailChangeState> {
  late EmailChangeRepository _repository;
  int _generation = 0;

  @override
  EmailChangeState build() {
    _generation++;
    _repository = ref.watch(emailChangeRepositoryProvider);
    return const EmailChangeState();
  }

  void reset() {
    _generation++;
    state = EmailChangeState(status: state.status);
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  SessionApi? get _api => ref.read(sessionApiProvider);

  EmailChangeState _failure(Object error) => EmailChangeState(
    status: state.status,
    error: _messageFor(error),
    errorCode: error is ApiException ? error.code : null,
    retryAfter: error is ApiException ? error.retryAfter : null,
    outcomeUnknown: error is ApiException && error.outcomeUnknown,
  );

  Future<void> load() async {
    final api = _api;
    if (api == null || state.isLoading || state.isSubmitting) return;
    final generation = _generation;
    state = EmailChangeState(isLoading: true, status: state.status);
    try {
      final status = await _repository.status(api);
      if (_current(generation)) {
        state = EmailChangeState(status: status);
      }
    } on StaleSessionException {
      if (_current(generation)) state = const EmailChangeState();
    } catch (error) {
      if (_current(generation)) state = _failure(error);
    }
  }

  Future<EmailChangeStartResult?> start(String email) async {
    final api = _api;
    if (api == null || state.isSubmitting || state.isLoading) return null;
    final generation = _generation;
    state = EmailChangeState(isSubmitting: true, status: state.status);
    try {
      final result = await _repository.start(api, email);
      if (!_current(generation)) return null;
      if (result.outcome == EmailChangeStartOutcome.unchanged) {
        final current = result.email ?? email;
        ref
            .read(sessionControllerProvider.notifier)
            .applyConfirmedEmail(current);
        state = EmailChangeState(
          status: EmailChangeStatus(
            email: current,
            canChangeEmail: state.status?.canChangeEmail ?? true,
          ),
        );
      } else {
        state = EmailChangeState(status: state.status);
      }
      return result;
    } on StaleSessionException {
      if (_current(generation)) state = const EmailChangeState();
      return null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  Future<EmailChangeCodeSent?> resend(String requestId) async {
    final api = _api;
    if (api == null || state.isSubmitting) return null;
    final generation = _generation;
    state = EmailChangeState(isSubmitting: true, status: state.status);
    try {
      final result = await _repository.resend(api, requestId);
      if (_current(generation)) {
        state = EmailChangeState(status: state.status);
      }
      return _current(generation) ? result : null;
    } on StaleSessionException {
      if (_current(generation)) state = const EmailChangeState();
      return null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  Future<String?> confirm({
    required String requestId,
    required String verificationCode,
  }) async {
    final api = _api;
    if (api == null || state.isSubmitting) return null;
    final generation = _generation;
    state = EmailChangeState(isSubmitting: true, status: state.status);
    try {
      final email = await _repository.confirm(
        api,
        requestId: requestId,
        verificationCode: verificationCode,
      );
      if (!_current(generation)) return null;
      ref.read(sessionControllerProvider.notifier).applyConfirmedEmail(email);
      state = EmailChangeState(
        status: EmailChangeStatus(
          email: email,
          canChangeEmail: state.status?.canChangeEmail ?? true,
        ),
      );
      return email;
    } on StaleSessionException {
      if (_current(generation)) state = const EmailChangeState();
      return null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return AppStrings.emailChangeUnexpectedError;
    return switch (error.code) {
      'email_change_not_allowed' => AppStrings.emailChangeNotAllowed,
      'email_change_unavailable' => AppStrings.emailChangeUnavailable,
      'invalid_email' => AppStrings.emailChangeInvalidEmail,
      'email_in_use' => AppStrings.emailChangeInUse,
      'invalid_code' => AppStrings.emailChangeInvalidCode,
      'code_expired' || 'invalid_request' => AppStrings.emailChangeExpired,
      'attempts_exhausted' => AppStrings.emailChangeAttemptsExhausted,
      'request_stale' => AppStrings.emailChangeStale,
      'rate_limited' => AppStrings.emailChangeRateLimited,
      'access_denied' ||
      'device_mismatch' => AppStrings.emailChangeAccessDenied,
      _ => switch (error.kind) {
        ApiErrorKind.network ||
        ApiErrorKind.timeout => AppStrings.signInConnectionError,
        ApiErrorKind.unauthorized => AppStrings.signInRequired,
        _ => AppStrings.emailChangeUnexpectedError,
      },
    };
  }
}
