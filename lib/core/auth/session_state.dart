enum SessionStatus { restoring, signedOut, signedIn, unavailable }

/// Публичное состояние без токена, профиля и реквизитов входа.
final class SessionState {
  const SessionState(this.status, this.generation);

  final SessionStatus status;
  final int generation;
}

/// Только в памяти транспорта; не передаётся в состояние UI.
final class SessionCredentials {
  const SessionCredentials({required this.token, required this.deviceId});

  final String token;
  final String deviceId;

  @override
  String toString() => 'SessionCredentials(<redacted>)';
}
