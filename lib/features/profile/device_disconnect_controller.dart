import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/profile/device_disconnect_repository.dart';

final deviceDisconnectControllerProvider =
    NotifierProvider<DeviceDisconnectController, DeviceDisconnectState>(
      DeviceDisconnectController.new,
    );

final class DeviceDisconnectState {
  const DeviceDisconnectState({this.isSubmitting = false, this.error});

  final bool isSubmitting;
  final String? error;
}

class DeviceDisconnectController extends Notifier<DeviceDisconnectState> {
  late DeviceDisconnectRepository _repository;
  int _generation = 0;

  @override
  DeviceDisconnectState build() {
    _generation++;
    _repository = ref.watch(deviceDisconnectRepositoryProvider);
    return const DeviceDisconnectState();
  }

  Future<bool> disconnect() async {
    final api = ref.read(sessionApiProvider);
    if (api == null || state.isSubmitting) return false;
    final generation = ++_generation;
    state = const DeviceDisconnectState(isSubmitting: true);
    try {
      await _repository.disconnect(api);
      if (!ref.mounted || generation != _generation) return false;
      // Сервер уже отозвал токен: локальная очистка без повторного logout.
      await ref.read(sessionControllerProvider.notifier).clearLocalSession();
      if (ref.mounted && generation == _generation) {
        state = const DeviceDisconnectState();
      }
      return true;
    } on StaleSessionException {
      if (ref.mounted && generation == _generation) {
        state = const DeviceDisconnectState();
      }
      return false;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = DeviceDisconnectState(error: _messageFor(error));
      }
      return false;
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return AppStrings.deviceDisconnectFailed;
    return switch (error.code) {
      'disconnect_unavailable' => AppStrings.deviceDisconnectUnavailable,
      'session_unbound' ||
      'device_mismatch' ||
      'access_denied' => AppStrings.deviceDisconnectFailed,
      _ => switch (error.kind) {
        ApiErrorKind.network ||
        ApiErrorKind.timeout => AppStrings.signInConnectionError,
        ApiErrorKind.unauthorized => AppStrings.deviceDisconnectFailed,
        _ => AppStrings.deviceDisconnectFailed,
      },
    };
  }
}
