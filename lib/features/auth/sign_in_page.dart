import 'package:polevaya_kuhnya/app/navigation.dart';
import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/features/auth/login_controller.dart';

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({
    required this.onHome,
    this.onSignUp,
    this.onResetPassword,
    super.key,
  });

  final VoidCallback onHome;
  final VoidCallback? onSignUp;
  final VoidCallback? onResetPassword;

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _login.dispose();
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(loginControllerProvider).isSubmitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final login = _login.text.trim();
    final password = _password.text;
    FocusScope.of(context).unfocus();
    final signedIn = await ref
        .read(loginControllerProvider.notifier)
        .submit(login: login, password: password);
    if (!mounted) return;
    TextInput.finishAutofillContext(shouldSave: signedIn);
    _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AppStrings.signIn, key: ValueKey('route-page-title')),
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
                      Text(
                        AppStrings.signInPrompt,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const ValueKey('sign-in-login'),
                        controller: _login,
                        autofillHints: const [AutofillHints.username],
                        enabled: !loginState.isSubmitting,
                        decoration: const InputDecoration(
                          labelText: AppStrings.signInLogin,
                          border: OutlineInputBorder(),
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? AppStrings.signInLoginRequired
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('sign-in-password'),
                        controller: _password,
                        autofillHints: const [AutofillHints.password],
                        enabled: !loginState.isSubmitting,
                        obscureText: !_passwordVisible,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: AppStrings.signInPassword,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible
                                ? AppStrings.hidePassword
                                : AppStrings.showPassword,
                            onPressed: loginState.isSubmitting
                                ? null
                                : () => setState(
                                    () => _passwordVisible = !_passwordVisible,
                                  ),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? AppStrings.signInPasswordRequired
                            : null,
                      ),
                      const SizedBox(height: 20),
                      if (loginState.error case final error?) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        key: const ValueKey('sign-in-submit'),
                        onPressed: loginState.isSubmitting ? null : _submit,
                        child: loginState.isSubmitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(AppStrings.signInSubmit),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: loginState.isSubmitting
                            ? null
                            : widget.onSignUp ??
                                  () => appNavigate(context, '/sign-up'),
                        child: const Text(AppStrings.signUp),
                      ),
                      TextButton(
                        key: const ValueKey('sign-in-reset-password'),
                        onPressed: loginState.isSubmitting
                            ? null
                            : widget.onResetPassword ??
                                  () => appNavigate(context, '/reset-password'),
                        child: const Text(AppStrings.resetPasswordLink),
                      ),
                      TextButton(
                        onPressed: loginState.isSubmitting
                            ? null
                            : widget.onHome,
                        child: const Text(AppStrings.home),
                      ),
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
