import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/site/contact_message.dart';

class ContactForm extends ConsumerStatefulWidget {
  const ContactForm({super.key});

  @override
  ConsumerState<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<ContactForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  String? _nameError;
  String? _phoneError;
  String? _emailError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final draft = ContactMessageDraft(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      message: _message.text,
    );
    final validation = validateContactMessage(draft);
    setState(() {
      _nameError = validation.nameError;
      _phoneError = validation.phoneError;
      _emailError = validation.emailError;
    });
    if (!validation.isValid) return;

    final result = await ref
        .read(contactMessageControllerProvider.notifier)
        .send(draft);
    if (!mounted) return;
    switch (result) {
      case ContactMessageResult.delivered:
        _name.clear();
        _phone.clear();
        _email.clear();
        _message.clear();
        setState(() {
          _nameError = null;
          _phoneError = null;
          _emailError = null;
        });
        _notify(AppStrings.siteContactDelivered);
      case ContactMessageResult.failed:
        _notify(AppStrings.siteContactFailed);
      case ContactMessageResult.busy:
      case ContactMessageResult.invalid:
        break;
    }
  }

  void _notify(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final message = ref.watch(contactMessageControllerProvider);
    final sending = message.phase == ContactMessagePhase.sending;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          key: const ValueKey('contact-name'),
          controller: _name,
          hint: AppStrings.siteContactName,
          error: _nameError,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('contact-phone'),
          controller: _phone,
          hint: AppStrings.siteContactPhone,
          error: _phoneError,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('contact-email'),
          controller: _email,
          hint: AppStrings.siteEmail,
          error: _emailError,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('contact-message'),
          controller: _message,
          hint: AppStrings.siteContactMessage,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
          minLines: 4,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const ValueKey('contact-send'),
            onPressed: message.canSend ? _submit : null,
            child: Text(
              sending
                  ? AppStrings.siteContactSending
                  : AppStrings.siteContactSend,
            ),
          ),
        ),
        if (message.phase == ContactMessagePhase.cooldown) ...[
          const SizedBox(height: 8),
          Text(
            AppStrings.siteContactRetryIn(message.cooldownSeconds),
            key: const ValueKey('contact-retry'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String hint,
    String? error,
    required TextInputAction textInputAction,
    required TextInputType keyboardType,
    int minLines = 1,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: minLines == 1 ? 1 : 6,
      decoration: InputDecoration(
        hintText: hint,
        errorText: error,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
      onChanged: (_) {
        if (error != null) setState(_clearError(key));
      },
    );
  }

  void Function() _clearError(Key key) {
    return () {
      if (key == const ValueKey('contact-name')) _nameError = null;
      if (key == const ValueKey('contact-phone')) _phoneError = null;
      if (key == const ValueKey('contact-email')) _emailError = null;
    };
  }
}
