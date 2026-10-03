import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';

final deviceDisconnectRepositoryProvider = Provider<DeviceDisconnectRepository>(
  (ref) {
    return const DeviceDisconnectRepository();
  },
);

final class DeviceDisconnectRepository {
  const DeviceDisconnectRepository();

  Future<void> disconnect(SessionApi api) async {
    final response = await api.postJson('V1/User/devicedisconnect', {});
    if (response['code'] != 'device_disconnected') {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный ответ отключения устройства.',
      );
    }
  }
}
