import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:polevaya_kuhnya/core/config/app_config.dart';
import 'package:polevaya_kuhnya/core/config/app_config_provider.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage(config: ref.watch(appConfigProvider));
});

final class SessionStorageException implements Exception {
  const SessionStorageException();

  @override
  String toString() => 'SessionStorageException';
}

/// Операции упорядочены: удаление после незавершённой записи не потеряется.
class SessionStorage {
  SessionStorage({required AppConfig config, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      _scope =
          'field_kitchen.v1.${config.environment.name}.'
          '${base64Url.encode(utf8.encode(config.apiBaseUri.toString()))}';

  final FlutterSecureStorage _storage;
  final String _scope;
  Future<void> _pending = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) async {
      try {
        return await action();
      } catch (_) {
        throw const SessionStorageException();
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String?> readToken() => _serialize(() async {
    final token = await _storage.read(key: '$_scope.token');
    return token == null || token.trim().isEmpty ? null : token;
  });

  Future<void> writeToken(String token) {
    if (token.trim().isEmpty) throw ArgumentError('Пустой токен');
    return _serialize(() => _storage.write(key: '$_scope.token', value: token));
  }

  Future<void> deleteToken() =>
      _serialize(() => _storage.delete(key: '$_scope.token'));

  /// ID переживает выход; формат HTTP — UUID v4 без префикса New3_.
  Future<String> deviceId() => _serialize(() async {
    final key = '$_scope.device_id';
    final saved = await _storage.read(key: key);
    if (saved != null) {
      if (!RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(saved)) {
        throw const SessionStorageException();
      }
      return saved;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final id =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await _storage.write(key: key, value: id);
    return id;
  });
}
