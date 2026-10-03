import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_storage.dart';
import 'package:polevaya_kuhnya/features/auth/registration_repository.dart';

final registrationControllerProvider =
    NotifierProvider<RegistrationController, RegistrationState>(
      RegistrationController.new,
    );

final class RegistrationState {
  const RegistrationState({
    this.isSubmitting = false,
    this.error,
    this.errorCode,
    this.retryAfter,
    this.outcomeUnknown = false,
  });

  final bool isSubmitting;
  final String? error;
  final String? errorCode;
  final int? retryAfter;
  final bool outcomeUnknown;
}

class RegistrationController extends Notifier<RegistrationState> {
  late RegistrationRepository _repository;
  late SessionStorage _storage;
  int _generation = 0;

  @override
  RegistrationState build() {
    _generation++;
    _repository = ref.watch(registrationRepositoryProvider);
    _storage = ref.watch(sessionStorageProvider);
    return const RegistrationState();
  }

  void reset() {
    _generation++;
    state = const RegistrationState();
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  RegistrationState _failure(Object error) => RegistrationState(
    error: _messageFor(error),
    errorCode: error is ApiException ? error.code : null,
    retryAfter: error is ApiException ? error.retryAfter : null,
    outcomeUnknown: error is ApiException && error.outcomeUnknown,
  );

  Future<RegistrationAvailability?> check({
    required String login,
    required String password,
  }) async {
    if (state.isSubmitting) return null;
    final generation = _generation;
    state = const RegistrationState(isSubmitting: true);
    try {
      final deviceId = await _storage.deviceId();
      final result = await _repository.check(
        login: login,
        password: password,
        deviceId: deviceId,
      );
      if (_current(generation)) state = const RegistrationState();
      return _current(generation) ? result : null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  Future<RegistrationStartResult?> start({
    required String login,
    required String password,
    required String fullName,
    required String email,
  }) async {
    if (state.isSubmitting) return null;
    final generation = _generation;
    state = const RegistrationState(isSubmitting: true);
    try {
      final deviceId = await _storage.deviceId();
      final result = await _repository.start(
        login: login,
        password: password,
        deviceId: deviceId,
        fullName: fullName,
        email: email,
      );
      if (_current(generation)) state = const RegistrationState();
      return _current(generation) ? result : null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  Future<RegistrationStartResult?> resend(String requestId) async {
    if (state.isSubmitting) return null;
    final generation = _generation;
    state = const RegistrationState(isSubmitting: true);
    try {
      final deviceId = await _storage.deviceId();
      if (!_current(generation)) return null;
      final result = await _repository.resend(
        requestId: requestId,
        deviceId: deviceId,
      );
      if (_current(generation)) state = const RegistrationState();
      return _current(generation) ? result : null;
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return null;
    }
  }

  Future<bool> confirm(String requestId, String code) async {
    if (state.isSubmitting) return false;
    final generation = _generation;
    state = const RegistrationState(isSubmitting: true);
    try {
      final deviceId = await _storage.deviceId();
      if (!_current(generation)) return false;
      await _repository.confirm(
        requestId: requestId,
        deviceId: deviceId,
        verificationCode: code,
      );
      if (_current(generation)) state = const RegistrationState();
      return _current(generation);
    } catch (error) {
      if (_current(generation)) state = _failure(error);
      return false;
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return AppStrings.registrationUnexpectedError;
    return switch (error.code) {
      'invalid_credentials' => AppStrings.signInInvalidCredentials,
      'access_denied' => switch (error.message.trim()) {
        'Доступ запрещён. Обратитесь к ответственному.' ||
        'Доступ организации запрещён.' =>
          AppStrings.registrationOrganizationDenied,
        'Доступ устройства запрещён. Обратитесь к ответственному.' =>
          AppStrings.registrationDeviceDenied,
        'Доступ сотрудника ограничен. Обратитесь к ответственному.' =>
          AppStrings.registrationEmployeeDenied,
        'Сотрудник недоступен. Обратитесь к ответственному.' ||
        'Сотрудник недоступен.' => AppStrings.registrationEmployeeUnavailable,
        'Привязка устройства изменена. Обратитесь к ответственному.' =>
          AppStrings.registrationBindingChanged,
        _ => AppStrings.registrationAccessDenied,
      },
      'device_mismatch' => AppStrings.registrationDeviceMismatch,
      'ambiguous_employee' => switch (error.message.trim()) {
        'Для этой почты найдено несколько сотрудников. Обратитесь к ответственному.' =>
          AppStrings.registrationDuplicateEmail,
        'У устройства несколько сотрудников. Обратитесь к ответственному.' =>
          AppStrings.registrationAmbiguousDevice,
        _ => AppStrings.registrationAmbiguousEmployee,
      },
      'email_in_use' => AppStrings.registrationEmailInUse,
      'rate_limited' => AppStrings.registrationRateLimited,
      'invalid_code' => AppStrings.registrationInvalidCode,
      'code_expired' => AppStrings.registrationExpired,
      'attempts_exhausted' => AppStrings.registrationAttemptsExhausted,
      'invalid_request' => AppStrings.registrationExpired,
      'registration_unavailable' => AppStrings.registrationUnavailable,
      'invalid_profile' => AppStrings.registrationInvalidProfile,
      'registration_not_required' ||
      'already_registered' => AppStrings.registrationAlreadyReady,
      _ => switch (error.kind) {
        ApiErrorKind.network ||
        ApiErrorKind.timeout => AppStrings.signInConnectionError,
        _ => AppStrings.registrationUnexpectedError,
      },
    };
  }
}
