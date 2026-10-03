import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';
import 'package:polevaya_kuhnya/core/auth/session_repository.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Свежий профиль доступен UI только после серверного подтверждения сессии.
/// Поколение в SessionState инвалидирует потребителей при повторной проверке.
final sessionProfileProvider = Provider<UserProfile?>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session.status == SessionStatus.signedIn
      ? ref.read(sessionControllerProvider.notifier).profile
      : null;
});

/// Feature Repository должен зависеть от этого provider, чтобы смена сессии
/// инвалидировала его данные. Публичные файлы используют apiClientProvider.
/// Следит только за status/generation: обновление полей профиля не пересоздаёт API.
final sessionApiProvider = Provider<SessionApi?>((ref) {
  final session = ref.watch(
    sessionControllerProvider.select(
      (value) => (value.status, value.generation),
    ),
  );
  return session.$1 == SessionStatus.signedIn
      ? ref.read(sessionControllerProvider.notifier)._createApi()
      : null;
});

class SessionController extends Notifier<SessionState> {
  int _generation = 0;
  SessionCredentials? _credentials;
  UserProfile? _profile;
  String? _snapshotOwnerScope;
  late SessionRepository _repository;

  @override
  SessionState build() {
    _repository = ref.watch(sessionRepositoryProvider);
    final generation = ++_generation;
    _credentials = null;
    _profile = null;
    _snapshotOwnerScope = null;
    ref.onDispose(() {
      _generation++;
      _credentials = null;
      _profile = null;
      _snapshotOwnerScope = null;
    });
    unawaited(Future<void>.microtask(() => _restore(generation, _repository)));
    return SessionState(SessionStatus.restoring, generation);
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  int _begin() {
    final generation = ++_generation;
    _credentials = null;
    _profile = null;
    _snapshotOwnerScope = null;
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
      if (error is ApiException && _current(generation)) {
        // Парольный вход ещё не сохранил токен: отказ API оставляет гостя.
        state = SessionState(SessionStatus.signedOut, generation);
      } else {
        await _handleFailure(error, generation, repository);
      }
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
    await repository.storage.writeToken(verified.credentials.token);
    if (!_current(generation)) return;
    _credentials = verified.credentials;
    _profile = verified.profile;
    state = SessionState(SessionStatus.signedIn, generation);
  }

  /// Профиль последней успешной проверки; не пишется в хранилище.
  UserProfile? get profile => _profile;

  /// Обновить профиль, сохранив поколение сессии и mounted-экраны.
  Future<UserProfile> refreshProfile() async {
    final generation = _generation;
    final credentials = _credentials;
    if (credentials == null || state.status != SessionStatus.signedIn) {
      throw const StaleSessionException();
    }
    try {
      final verified = await _repository.verify(credentials);
      if (!_current(generation)) throw const StaleSessionException();
      if (verified.profile.login != _profile?.login) {
        throw const FormatException('Владелец обновлённого профиля изменился.');
      }
      await _repository.storage.writeToken(verified.credentials.token);
      if (!_current(generation)) throw const StaleSessionException();
      _credentials = verified.credentials;
      _profile = verified.profile;
      state = SessionState(SessionStatus.signedIn, generation);
      return verified.profile;
    } on ApiException catch (error) {
      if (error.requiresReauth) {
        await _handleFailure(error, generation, _repository);
      }
      rethrow;
    }
  }

  /// Применение уже проверенного снимка без запроса, токена и смены поколения.
  void applyProfileSnapshot(
    UserProfile profile, {
    required int generation,
    required String ownerScope,
  }) {
    if (!_current(generation) ||
        state.status != SessionStatus.signedIn ||
        _credentials == null ||
        _profile == null) {
      throw const StaleSessionException();
    }
    if (profile.login != _profile!.login ||
        (_snapshotOwnerScope != null && _snapshotOwnerScope != ownerScope)) {
      throw const FormatException('Владелец снимка заказа изменился.');
    }
    _snapshotOwnerScope = ownerScope;
    _profile = profile;
    state = SessionState(SessionStatus.signedIn, generation);
  }

  /// Подтверждённый новый email без повторного login и без смены generation.
  void applyConfirmedEmail(String email) {
    final generation = state.generation;
    if (!_current(generation) ||
        state.status != SessionStatus.signedIn ||
        _profile == null) {
      return;
    }
    _profile = _profile!.withEmail(email);
    state = SessionState(SessionStatus.signedIn, generation);
  }

  Future<void> _handleFailure(
    Object error,
    int generation,
    SessionRepository repository,
  ) async {
    if (!_current(generation)) return;
    _credentials = null;
    _profile = null;
    _snapshotOwnerScope = null;
    if (error is ApiException && error.requiresReauth) {
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

  Future<void> signOut() => _endSession(revoke: true);

  /// Сервер уже отозвал доступ (истечение или `devicedisconnect`): без logout.
  Future<void> clearLocalSession() => _endSession(revoke: false);

  /// Сервер уже признал токен недействительным: закрываем доступ без logout.
  Future<void> _expireSession() => _endSession(revoke: false);

  Future<void> _endSession({required bool revoke}) async {
    final credentials = _credentials;
    final generation = _begin();
    final repository = _repository;
    try {
      await repository.storage.deleteToken();
      if (_current(generation)) {
        state = SessionState(SessionStatus.signedOut, generation);
      }
      if (revoke && credentials != null) {
        unawaited(_revokeSilently(repository, credentials));
      }
    } catch (error) {
      await _handleFailure(error, generation, repository);
    }
  }

  Future<void> _revokeSilently(
    SessionRepository repository,
    SessionCredentials credentials,
  ) async {
    try {
      await repository.revoke(credentials);
    } catch (_) {
      // Локальный выход уже завершён; сеть не может вернуть прежнюю сессию.
    }
  }

  SessionApi _createApi() {
    final generation = _generation;
    return SessionApi(
      api: _repository.api,
      credentials: _credentials!,
      isCurrent: () => _current(generation) && _credentials != null,
      onUnauthorized: _expireSession,
    );
  }
}
