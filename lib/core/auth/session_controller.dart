import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_repository.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Feature Repository должен зависеть от этого provider, чтобы смена сессии
/// инвалидировала его данные. Публичные файлы используют apiClientProvider.
final sessionApiProvider = Provider<SessionApi?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.status == SessionStatus.signedIn
      ? ref.read(sessionControllerProvider.notifier)._createApi()
      : null;
});

class SessionController extends Notifier<SessionState> {
  int _generation = 0;
  SessionCredentials? _credentials;
  late SessionRepository _repository;

  @override
  SessionState build() {
    _repository = ref.watch(sessionRepositoryProvider);
    final generation = ++_generation;
    _credentials = null;
    ref.onDispose(() {
      _generation++;
      _credentials = null;
    });
    unawaited(Future<void>.microtask(() => _restore(generation, _repository)));
    return SessionState(SessionStatus.restoring, generation);
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  int _begin() {
    final generation = ++_generation;
    _credentials = null;
    state = SessionState(SessionStatus.restoring, generation);
    return generation;
  }

  Future<void> restore() => _restore(_begin(), _repository);

  Future<void> _restore(int generation, SessionRepository repository) async {
    if (!_current(generation)) return;
    try {
      final saved = await repository.restoreCredentials();
      if (!_current(generation)) return;
      if (saved == null) {
        state = SessionState(SessionStatus.signedOut, generation);
        return;
      }
      await _verifyAndSave(saved, generation, repository);
    } catch (error) {
      await _handleFailure(error, generation, repository);
    }
  }

  /// Будущий auth Controller передаёт вызов своего Repository. Поколение
  /// фиксируется до запроса входа, поэтому поздний login не отменит logout.
  Future<void> signIn(
    Future<String> Function(String deviceId) authenticate,
  ) async {
    final generation = _begin();
    final repository = _repository;
    try {
      await repository.storage.deleteToken();
      if (!_current(generation)) return;
      final deviceId = await repository.storage.deviceId();
      if (!_current(generation)) return;
      final token = await authenticate(deviceId);
      if (!_current(generation)) return;
      if (token.trim().isEmpty) {
        throw const ApiException(
          kind: ApiErrorKind.format,
          message: 'Нет токена входа.',
        );
      }
      await _verifyAndSave(
        SessionCredentials(token: token, deviceId: deviceId),
        generation,
        repository,
      );
    } catch (error) {
      await _handleFailure(error, generation, repository);
      if (_current(generation)) rethrow;
    }
  }

  Future<void> _verifyAndSave(
    SessionCredentials credentials,
    int generation,
    SessionRepository repository,
  ) async {
    final verified = await repository.verify(credentials);
    if (!_current(generation)) return;
    await repository.storage.writeToken(verified.token);
    if (!_current(generation)) return;
    _credentials = verified;
    state = SessionState(SessionStatus.signedIn, generation);
  }

  Future<void> _handleFailure(
    Object error,
    int generation,
    SessionRepository repository,
  ) async {
    if (!_current(generation)) return;
    _credentials = null;
    if (error is ApiException && error.invalidSession) {
      try {
        await repository.storage.deleteToken();
        if (_current(generation)) {
          state = SessionState(SessionStatus.signedOut, generation);
        }
        return;
      } catch (_) {
        // Ошибка хранилища не должна выглядеть как успешное удаление токена.
      }
    }
    if (_current(generation)) {
      state = SessionState(SessionStatus.unavailable, generation);
    }
  }

  Future<void> signOut() async {
    final generation = _begin();
    final repository = _repository;
    try {
      await repository.storage.deleteToken();
      if (_current(generation)) {
        state = SessionState(SessionStatus.signedOut, generation);
      }
    } catch (error) {
      await _handleFailure(error, generation, repository);
    }
  }

  SessionApi _createApi() {
    final generation = _generation;
    return SessionApi(
      api: _repository.api,
      credentials: _credentials!,
      isCurrent: () => _current(generation) && _credentials != null,
      onUnauthorized: signOut,
    );
  }
}
