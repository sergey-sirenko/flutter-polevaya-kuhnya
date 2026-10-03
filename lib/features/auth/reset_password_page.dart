import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/api/api_client_provider.dart';
import 'package:polevaya_kuhnya/core/api/api_exception.dart';

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({
    required this.onSignIn,
    required this.onHome,
    super.key,
  });

  final VoidCallback onSignIn;
  final VoidCallback onHome;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _queued = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _queued = false;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).postJson(
        'V1/User/passwordrecovery',
        {'email': _email.text.trim().toLowerCase()},
      );
      if (!mounted) return;
      setState(() {
        if (response['code'] == 'credentials_queued') {
          _queued = true;
        } else {
          _error = AppStrings.passwordRecoveryFailed;
        }
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.code) {
          'invalid_email' => AppStrings.passwordRecoveryInvalidEmail,
          'email_not_found' => AppStrings.passwordRecoveryNotFound,
          'access_denied' => AppStrings.passwordRecoveryDenied,
          'credentials_unavailable' => AppStrings.passwordRecoveryUnavailable,
          'rate_limited' => AppStrings.passwordRecoveryRateLimited,
          _ => AppStrings.passwordRecoveryFailed,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppStrings.passwordRecoveryFailed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          AppStrings.resetPassword,
          key: ValueKey('route-page-title'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ContentPanel(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(AppStrings.passwordRecoveryDescription),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('reset-password-email'),
                      controller: _email,
                      enabled: !_sending,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Электронная почта',
                      ),
                      onChanged: (_) => setState(() {
                        _queued = false;
                        _error = null;
                      }),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) {
                        final email = (value ?? '').trim();
                        if (email.length > 254 ||
                            !RegExp(
                              r'^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[^\s@<>(),;:"\\.]+$',
                            ).hasMatch(email)) {
                          return AppStrings.passwordRecoveryInvalidEmail;
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const ValueKey('reset-password-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_queued) ...[
                      const SizedBox(height: 16),
                      const Text(
                        AppStrings.passwordRecoveryQueued,
                        key: ValueKey('reset-password-success'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const ValueKey('reset-password-send'),
                      onPressed: _sending ? null : _submit,
                      child: Text(
                        _sending
                            ? 'Отправка…'
                            : AppStrings.passwordRecoverySend,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('reset-password-sign-in'),
                      onPressed: widget.onSignIn,
                      child: const Text(AppStrings.resetPasswordBackToSignIn),
                    ),
                    TextButton(
                      onPressed: widget.onHome,
                      child: const Text(AppStrings.home),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
