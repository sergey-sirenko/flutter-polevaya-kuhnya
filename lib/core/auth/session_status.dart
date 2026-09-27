import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_state.dart';

export 'session_state.dart' show SessionStatus;

final sessionStatusProvider = Provider<SessionStatus>(
  (ref) =>
      ref.watch(sessionControllerProvider.select((session) => session.status)),
);
