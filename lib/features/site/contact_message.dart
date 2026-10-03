import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';

/// Сколько секунд форма не отправляет повтор после принятого сервером сообщения.
const contactMessageCooldown = Duration(seconds: 60);

final _emailPattern = RegExp(
  r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
);

final class ContactMessageDraft {
  const ContactMessageDraft({
    required this.name,
    required this.phone,
    required this.email,
    required this.message,
  });

  final String name;
  final String phone;
  final String email;
  final String message;
}

final class ContactMessageValidation {
  const ContactMessageValidation({
    this.nameError,
    this.phoneError,
    this.emailError,
  });

  final String? nameError;
  final String? phoneError;
  final String? emailError;

  bool get isValid =>
      nameError == null && phoneError == null && emailError == null;
}

ContactMessageValidation validateContactMessage(ContactMessageDraft draft) {
  final email = draft.email.trim();
  return ContactMessageValidation(
    nameError: draft.name.trim().isEmpty
        ? AppStrings.siteContactNameRequired
        : null,
    phoneError: draft.phone.trim().isEmpty
        ? AppStrings.siteContactPhoneRequired
        : null,
    emailError: email.isNotEmpty && !_emailPattern.hasMatch(email)
        ? AppStrings.siteContactEmailInvalid
        : null,
  );
}

final contactMessageRepositoryProvider = Provider<ContactMessageRepository>((
  ref,
) {
  return ContactMessageRepository(api: ref.watch(apiClientProvider));
});

/// GET `V1/User/message`. `success: true` значит, что сервер принял запрос
/// и создал исходящее письмо в 1С. Доставка на почтовый ящик этим ответом
/// не подтверждается.
final class ContactMessageRepository {
  const ContactMessageRepository({required this.api});

  final ApiClient api;

  Future<void> send({
    required String name,
    required String phone,
    required String email,
    required String message,
  }) {
    return api.getApiJson('V1/User/message', {
      'name': name,
      'phone': phone,
      'email': email,
      'message': message,
    }, outcomeUnknown: true);
  }
}

enum ContactMessagePhase { idle, sending, cooldown }

enum ContactMessageResult { delivered, failed, busy, invalid }

final class ContactMessageState {
  const ContactMessageState({
    this.phase = ContactMessagePhase.idle,
    this.cooldownSeconds = 0,
  });

  final ContactMessagePhase phase;
  final int cooldownSeconds;

  bool get canSend => phase == ContactMessagePhase.idle;
}

final contactMessageControllerProvider =
    NotifierProvider<ContactMessageController, ContactMessageState>(
      ContactMessageController.new,
    );

class ContactMessageController extends Notifier<ContactMessageState> {
  late ContactMessageRepository _repository;
  Timer? _timer;

  @override
  ContactMessageState build() {
    _repository = ref.watch(contactMessageRepositoryProvider);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return const ContactMessageState();
  }

  Future<ContactMessageResult> send(ContactMessageDraft draft) async {
    if (!state.canSend) return ContactMessageResult.busy;
    final name = draft.name.trim();
    final phone = draft.phone.trim();
    final email = draft.email.trim();
    final message = draft.message.trim();
    if (!validateContactMessage(
      ContactMessageDraft(
        name: name,
        phone: phone,
        email: email,
        message: message,
      ),
    ).isValid) {
      return ContactMessageResult.invalid;
    }

    state = const ContactMessageState(phase: ContactMessagePhase.sending);
    try {
      await _repository.send(
        name: name,
        phone: phone,
        email: email,
        message: message,
      );
    } catch (_) {
      if (ref.mounted) state = const ContactMessageState();
      return ContactMessageResult.failed;
    }
    if (!ref.mounted) return ContactMessageResult.delivered;
    _startCooldown();
    return ContactMessageResult.delivered;
  }

  void _startCooldown() {
    _timer?.cancel();
    var left = contactMessageCooldown.inSeconds;
    state = ContactMessageState(
      phase: ContactMessagePhase.cooldown,
      cooldownSeconds: left,
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      left -= 1;
      if (!ref.mounted) {
        timer.cancel();
        return;
      }
      if (left <= 0) {
        timer.cancel();
        _timer = null;
        state = const ContactMessageState();
      } else {
        state = ContactMessageState(
          phase: ContactMessagePhase.cooldown,
          cooldownSeconds: left,
        );
      }
    });
  }
}
