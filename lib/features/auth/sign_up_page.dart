import 'dart:async';

import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/auth/login_controller.dart';
import 'package:polevaya_kuhnya/features/auth/registration_controller.dart';
import 'package:polevaya_kuhnya/features/auth/registration_repository.dart';

enum _RegistrationStep { credentials, profile, codeSent, signIn }

final registrationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({
    required this.onSignIn,
    required this.onPrivacy,
    required this.onConsent,
    super.key,
  });

  final VoidCallback onSignIn;
  final VoidCallback onPrivacy;
  final VoidCallback onConsent;

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  _RegistrationStep _step = _RegistrationStep.credentials;
  String? _requestId;
  String? _notice;
  DateTime? _expiresAt;
  DateTime? _retryAt;
  Timer? _ticker;
  int _flowGeneration = 0;
  bool _hasConsent = false;
  bool _consentError = false;

  @override
  void dispose() {
    _login.dispose();
    _password.clear();
    _password.dispose();
    _fullName.dispose();
    _email.dispose();
    _code.clear();
    _code.dispose();
    _ticker?.cancel();
    _requestId = null;
    super.dispose();
  }

  int _remaining(DateTime? deadline) {
    if (deadline == null) return 0;
    final milliseconds = deadline.difference(_now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds + 999) ~/ 1000;
  }

  DateTime _now() => ref.read(registrationClockProvider)();

  void _clearTemporaryCredentials() {
    _hasConsent = false;
    _consentError = false;
    _requestId = null;
    _expiresAt = null;
    _retryAt = null;
    _password.clear();
    _code.clear();
    _fullName.clear();
    _email.clear();
  }

  void _resetFlow({String? notice}) {
    _flowGeneration++;
    _ticker?.cancel();
    _ticker = null;
    _clearTemporaryCredentials();
    ref.read(registrationControllerProvider.notifier).reset();
    ref.read(loginControllerProvider.notifier).clearError();
    setState(() {
      _notice = notice;
      _step = _RegistrationStep.credentials;
    });
  }

  void _openSignIn({required String notice}) {
    _ticker?.cancel();
    _ticker = null;
    _clearTemporaryCredentials();
    ref.read(registrationControllerProvider.notifier).reset();
    ref.read(loginControllerProvider.notifier).clearError();
    setState(() {
      _notice = notice;
      _step = _RegistrationStep.signIn;
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _step != _RegistrationStep.codeSent) return;
      if (_remaining(_expiresAt) == 0) {
        _resetFlow(notice: AppStrings.registrationExpired);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _check() async {
    if (!_canRegister()) return;
    FocusScope.of(context).unfocus();
    final result = await ref
        .read(registrationControllerProvider.notifier)
        .check(login: _login.text.trim(), password: _password.text);
    if (!mounted) return;
    if (result == RegistrationAvailability.required) {
      setState(() {
        _notice = null;
        _step = _RegistrationStep.profile;
      });
    } else if (result == RegistrationAvailability.ready) {
      _openSignIn(notice: AppStrings.registrationAlreadyReady);
    }
  }

  Future<void> _start() async {
    if (!_canRegister()) return;
    FocusScope.of(context).unfocus();
    final result = await ref
        .read(registrationControllerProvider.notifier)
        .start(
          login: _login.text.trim(),
          password: _password.text,
          fullName: _fullName.text.trim(),
          email: _email.text.trim(),
        );
    if (!mounted) return;
    // После любого ответа start новая попытка требует повторного ввода пароля.
    _password.clear();
    TextInput.finishAutofillContext(shouldSave: false);
    if (result == null) {
      setState(() {
        _hasConsent = false;
        _consentError = false;
        _step = _RegistrationStep.credentials;
      });
      return;
    }
    _requestId = result.requestId;
    final now = _now();
    _expiresAt = now.add(Duration(seconds: result.expiresIn));
    _retryAt = now.add(Duration(seconds: result.retryAfter));
    _code.clear();
    _startTicker();
    setState(() => _step = _RegistrationStep.codeSent);
  }

  bool _canRegister() {
    if (ref.read(registrationControllerProvider).isSubmitting) return false;
    final valid = _formKey.currentState!.validate();
    setState(() => _consentError = !_hasConsent);
    return valid && _hasConsent;
  }

  Future<void> _resend() async {
    final requestId = _requestId;
    if (requestId == null ||
        _remaining(_expiresAt) == 0 ||
        _remaining(_retryAt) > 0 ||
        ref.read(registrationControllerProvider).isSubmitting) {
      return;
    }
    final generation = _flowGeneration;
    final result = await ref
        .read(registrationControllerProvider.notifier)
        .resend(requestId);
    if (!mounted || generation != _flowGeneration) return;
    if (result == null) {
      final failure = ref.read(registrationControllerProvider);
      if (failure.outcomeUnknown ||
          failure.errorCode == 'invalid_request' ||
          failure.errorCode == 'code_expired' ||
          failure.errorCode == 'attempts_exhausted' ||
          _registrationDenied(failure.errorCode)) {
        _resetFlow(
          notice: failure.outcomeUnknown
              ? AppStrings.registrationResendUnknown
              : failure.error,
        );
      } else if (failure.retryAfter case final seconds?) {
        setState(() => _retryAt = _now().add(Duration(seconds: seconds)));
      }
      return;
    }
    final now = _now();
    final serverExpiry = now.add(Duration(seconds: result.expiresIn));
    if (_expiresAt == null || serverExpiry.isBefore(_expiresAt!)) {
      _expiresAt = serverExpiry;
    }
    _requestId = result.requestId;
    _code.clear();
    setState(() => _retryAt = now.add(Duration(seconds: result.retryAfter)));
  }

  Future<void> _confirm() async {
    if (_requestId == null ||
        _remaining(_expiresAt) == 0 ||
        ref.read(registrationControllerProvider).isSubmitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final generation = _flowGeneration;
    final success = await ref
        .read(registrationControllerProvider.notifier)
        .confirm(_requestId!, _code.text);
    if (!mounted || generation != _flowGeneration) return;
    if (!success) {
      final failure = ref.read(registrationControllerProvider);
      _code.clear();
      if (failure.errorCode == 'invalid_request' ||
          failure.errorCode == 'code_expired' ||
          failure.errorCode == 'attempts_exhausted' ||
          _registrationDenied(failure.errorCode)) {
        _resetFlow(notice: failure.error);
      }
      return;
    }
    _openSignIn(notice: AppStrings.registrationCompleted);
  }

  bool _registrationDenied(String? code) => switch (code) {
    'access_denied' ||
    'device_mismatch' ||
    'ambiguous_employee' ||
    'email_in_use' => true,
    _ => false,
  };

  Future<void> _signIn() async {
    if (ref.read(loginControllerProvider).isSubmitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final signedIn = await ref
        .read(loginControllerProvider.notifier)
        .submit(login: _login.text.trim(), password: _password.text);
    if (!mounted) return;
    TextInput.finishAutofillContext(shouldSave: signedIn);
    _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationControllerProvider);
    final loginState = ref.watch(loginControllerProvider);
    final busy = state.isSubmitting || loginState.isSubmitting;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.signUp, key: ValueKey('route-page-title')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ContentPanel(
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_step == _RegistrationStep.credentials) ...[
                        Text(
                          AppStrings.registrationPrompt,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const ValueKey('sign-up-login'),
                          controller: _login,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: AppStrings.signInLogin,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? AppStrings.signInLoginRequired
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('sign-up-password'),
                          controller: _password,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.password],
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                            labelText: AppStrings.signInPassword,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? AppStrings.signInPasswordRequired
                              : null,
                        ),
                      ] else if (_step == _RegistrationStep.profile) ...[
                        Text(
                          AppStrings.signUp,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const ValueKey('sign-up-full-name'),
                          controller: _fullName,
                          enabled: !busy,
                          maxLength: 50,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: AppStrings.registrationFullName,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? AppStrings.registrationFullNameRequired
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('sign-up-email'),
                          controller: _email,
                          enabled: !busy,
                          maxLength: 100,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: AppStrings.registrationEmail,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(email)
                                ? null
                                : AppStrings.registrationEmailRequired;
                          },
                        ),
                      ] else if (_step == _RegistrationStep.codeSent) ...[
                        const Text(AppStrings.registrationCodeSent),
                        const SizedBox(height: 16),
                        Text(
                          '${AppStrings.registrationTimeRemaining} ${_remaining(_expiresAt)}',
                          key: const ValueKey('registration-expiry'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('sign-up-code'),
                          controller: _code,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: const InputDecoration(
                            labelText: AppStrings.registrationCode,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              RegExp(r'^\d{6}$').hasMatch(value ?? '')
                              ? null
                              : AppStrings.registrationCodeRequired,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey('sign-up-confirm'),
                          onPressed: busy ? null : _confirm,
                          child: const Text(AppStrings.registrationConfirm),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const ValueKey('sign-up-resend'),
                          onPressed: busy || _remaining(_retryAt) > 0
                              ? null
                              : _resend,
                          child: Text(
                            _remaining(_retryAt) > 0
                                ? '${AppStrings.registrationResendAfter} ${_remaining(_retryAt)}'
                                : AppStrings.registrationResend,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('sign-up-cancel'),
                          onPressed: () => _resetFlow(
                            notice: AppStrings.registrationCanceled,
                          ),
                          child: const Text(AppStrings.registrationCancel),
                        ),
                      ] else ...[
                        Text(
                          AppStrings.signInPrompt,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (_notice case final notice?) Text(notice),
                        const SizedBox(height: 24),
                        TextFormField(
                          key: const ValueKey('sign-up-login'),
                          controller: _login,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: AppStrings.signInLogin,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? AppStrings.signInLoginRequired
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('sign-up-password'),
                          controller: _password,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.password],
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _signIn(),
                          decoration: const InputDecoration(
                            labelText: AppStrings.signInPassword,
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? AppStrings.signInPasswordRequired
                              : null,
                        ),
                        if (loginState.error case final error?) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          key: const ValueKey('sign-up-login-submit'),
                          onPressed: busy ? null : _signIn,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(AppStrings.signInSubmit),
                        ),
                      ],
                      if (_step != _RegistrationStep.signIn)
                        if (_notice case final notice?) ...[
                          const SizedBox(height: 12),
                          Text(notice),
                        ],
                      if (state.error case final error?) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      if (_step == _RegistrationStep.credentials ||
                          _step == _RegistrationStep.profile) ...[
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          key: const ValueKey('sign-up-consent'),
                          value: _hasConsent,
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  _hasConsent = value ?? false;
                                  _consentError = false;
                                }),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(AppStrings.registrationConsent),
                        ),
                        if (_consentError)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              AppStrings.registrationConsentRequired,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              key: const ValueKey('sign-up-consent-link'),
                              onPressed: busy ? null : widget.onConsent,
                              child: const Text(AppStrings.personalDataConsent),
                            ),
                            TextButton(
                              key: const ValueKey('sign-up-privacy-link'),
                              onPressed: busy ? null : widget.onPrivacy,
                              child: const Text(AppStrings.privacy),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          key: ValueKey(
                            _step == _RegistrationStep.credentials
                                ? 'sign-up-check'
                                : 'sign-up-start',
                          ),
                          onPressed: busy
                              ? null
                              : _step == _RegistrationStep.credentials
                              ? _check
                              : _start,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _step == _RegistrationStep.credentials
                                      ? AppStrings.registrationCheck
                                      : AppStrings.registrationStart,
                                ),
                        ),
                      ],
                      if (_step != _RegistrationStep.signIn) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: busy && _step != _RegistrationStep.codeSent
                              ? null
                              : () {
                                  _flowGeneration++;
                                  _ticker?.cancel();
                                  _clearTemporaryCredentials();
                                  ref
                                      .read(
                                        registrationControllerProvider.notifier,
                                      )
                                      .reset();
                                  widget.onSignIn();
                                },
                          child: const Text(AppStrings.signIn),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
