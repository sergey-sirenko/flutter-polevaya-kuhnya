import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';
import 'package:polevaya_kuhnya/core/auth/session_api.dart';

final emailChangeRepositoryProvider = Provider<EmailChangeRepository>((ref) {
  return const EmailChangeRepository();
});

final class EmailChangeStatus {
  const EmailChangeStatus({required this.email, required this.canChangeEmail});

  final String email;
  final bool canChangeEmail;
}

final class EmailChangeCodeSent {
  const EmailChangeCodeSent({
    required this.requestId,
    required this.retryAfter,
    required this.expiresIn,
  });

  final String requestId;
  final int retryAfter;
  final int expiresIn;
}

enum EmailChangeStartOutcome { codeSent, unchanged }

final class EmailChangeStartResult {
  const EmailChangeStartResult.codeSent(this.codeSent)
    : outcome = EmailChangeStartOutcome.codeSent,
      email = null;

  const EmailChangeStartResult.unchanged(this.email)
    : outcome = EmailChangeStartOutcome.unchanged,
      codeSent = null;

  final EmailChangeStartOutcome outcome;
  final EmailChangeCodeSent? codeSent;
  final String? email;
}

final class EmailChangeRepository {
  const EmailChangeRepository();

  Future<EmailChangeStatus> status(SessionApi api) async {
    final response = await api.postJson('V1/User/emailchangestatus', {});
    if (response['code'] != 'email_change_status') {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный статус смены почты.',
      );
    }
    return EmailChangeStatus(
      email: response['email']?.toString() ?? '',
      canChangeEmail: response['canChangeEmail'] == true,
    );
  }

  Future<EmailChangeStartResult> start(SessionApi api, String email) async {
    final response = await api.postJson('V1/User/emailchangestart', {
      'email': email,
    });
    if (response['code'] == 'email_unchanged') {
      return EmailChangeStartResult.unchanged(
        response['email']?.toString() ?? email,
      );
    }
    return EmailChangeStartResult.codeSent(_codeSent(response));
  }

  Future<EmailChangeCodeSent> resend(SessionApi api, String requestId) async {
    final response = await api.postJson('V1/User/emailchangeresend', {
      'requestId': requestId,
    });
    return _codeSent(response);
  }

  Future<String> confirm(
    SessionApi api, {
    required String requestId,
    required String verificationCode,
  }) async {
    final response = await api.postJson('V1/User/emailchangeconfirm', {
      'requestId': requestId,
      'verificationCode': verificationCode,
    });
    if (response['code'] != 'email_changed') {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный ответ подтверждения почты.',
      );
    }
    final email = response['email']?.toString();
    if (email == null || email.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'В ответе смены почты отсутствует адрес.',
      );
    }
    return email;
  }

  static EmailChangeCodeSent _codeSent(Map<String, dynamic> response) {
    final requestId = response['requestId'];
    final retryAfter = response['retryAfter'];
    final expiresIn = response['expiresIn'];
    if (response['code'] != 'code_sent' ||
        requestId is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(requestId) ||
        retryAfter is! int ||
        retryAfter < 0 ||
        expiresIn is! int ||
        expiresIn <= 0 ||
        expiresIn > 600) {
      throw const ApiException(
        kind: ApiErrorKind.format,
        message: 'Неожиданный ответ отправки кода смены почты.',
      );
    }
    return EmailChangeCodeSent(
      requestId: requestId,
      retryAfter: retryAfter,
      expiresIn: expiresIn,
    );
  }
}
