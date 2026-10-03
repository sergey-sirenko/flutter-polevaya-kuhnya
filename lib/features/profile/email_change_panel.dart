import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/features/profile/email_change_controller.dart';
import 'package:polevaya_kuhnya/features/profile/email_change_repository.dart';

enum _EmailStep { idle, editing, codeSent }

final emailChangeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class EmailChangePanel extends ConsumerStatefulWidget {
  const EmailChangePanel({super.key});

  @override
  ConsumerState<EmailChangePanel> createState() => _EmailChangePanelState();
}

class _EmailChangePanelState extends ConsumerState<EmailChangePanel> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  _EmailStep _step = _EmailStep.idle;
  String? _requestId;
  String? _notice;
  DateTime? _expiresAt;
  DateTime? _retryAt;
  Timer? _ticker;
  int _flowGeneration = 0;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(sessionApiProvider) != null) {
        _ensureLoaded();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.clear();
    _code.dispose();
    _requestId = null;
    super.dispose();
  }

  DateTime _now() => ref.read(emailChangeClockProvider)();

  int _remaining(DateTime? deadline) {
    if (deadline == null) return 0;
    final milliseconds = deadline.difference(_now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds + 999) ~/ 1000;
  }

  void _clearTemps() {
    _requestId = null;
    _expiresAt = null;
    _retryAt = null;
    _code.clear();
  }

  void _resetFlow({String? notice}) {
    _flowGeneration++;
    _ticker?.cancel();
    _ticker = null;
    _clearTemps();
    _email.clear();
    ref.read(emailChangeControllerProvider.notifier).reset();
    setState(() {
      _notice = notice;
      _step = _EmailStep.idle;
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _step != _EmailStep.codeSent) return;
      if (_remaining(_expiresAt) == 0) {
        _resetFlow(notice: AppStrings.emailChangeExpired);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await ref.read(emailChangeControllerProvider.notifier).load();
  }

  Future<void> _start() async {
    if (ref.read(emailChangeControllerProvider).isSubmitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await ref
        .read(emailChangeControllerProvider.notifier)
        .start(_email.text.trim());
    if (!mounted) return;
    if (result == null) {
      final failure = ref.read(emailChangeControllerProvider);
      if (failure.errorCode == 'request_stale') {
        _resetFlow(notice: failure.error);
      }
      return;
    }
    if (result.outcome == EmailChangeStartOutcome.unchanged) {
      _email.clear();
      setState(() {
        _notice = AppStrings.emailChangeUnchanged;
        _step = _EmailStep.idle;
      });
      return;
    }
    final codeSent = result.codeSent!;
    _requestId = codeSent.requestId;
    final now = _now();
    _expiresAt = now.add(Duration(seconds: codeSent.expiresIn));
    _retryAt = now.add(Duration(seconds: codeSent.retryAfter));
    _code.clear();
    _startTicker();
    setState(() {
      _notice = null;
      _step = _EmailStep.codeSent;
    });
  }

  Future<void> _resend() async {
    final requestId = _requestId;
    if (requestId == null ||
        _remaining(_expiresAt) == 0 ||
        _remaining(_retryAt) > 0 ||
        ref.read(emailChangeControllerProvider).isSubmitting) {
      return;
    }
    final generation = _flowGeneration;
    final result = await ref
        .read(emailChangeControllerProvider.notifier)
        .resend(requestId);
    if (!mounted || generation != _flowGeneration) return;
    if (result == null) {
      final failure = ref.read(emailChangeControllerProvider);
      if (failure.outcomeUnknown ||
          failure.errorCode == 'invalid_request' ||
          failure.errorCode == 'code_expired' ||
          failure.errorCode == 'attempts_exhausted' ||
          failure.errorCode == 'request_stale') {
        _resetFlow(
          notice: failure.outcomeUnknown
              ? AppStrings.emailChangeUnexpectedError
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
        ref.read(emailChangeControllerProvider).isSubmitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final generation = _flowGeneration;
    final email = await ref
        .read(emailChangeControllerProvider.notifier)
        .confirm(requestId: _requestId!, verificationCode: _code.text);
    if (!mounted || generation != _flowGeneration) return;
    if (email == null) {
      final failure = ref.read(emailChangeControllerProvider);
      _code.clear();
      if (failure.errorCode == 'invalid_request' ||
          failure.errorCode == 'code_expired' ||
          failure.errorCode == 'attempts_exhausted' ||
          failure.errorCode == 'request_stale') {
        _resetFlow(notice: failure.error);
      }
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _clearTemps();
    _email.clear();
    setState(() {
      _notice = AppStrings.emailChangeSuccess;
      _step = _EmailStep.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionApiProvider, (previous, next) {
      if (previous == null && next != null) {
        _loaded = false;
        _ensureLoaded();
      } else if (next == null) {
        _loaded = false;
        _resetFlow();
      }
    });

    final state = ref.watch(emailChangeControllerProvider);
    final profileEmail = ref.watch(sessionProfileProvider)?.email;
    final displayed =
        state.status?.email ??
        (profileEmail == null || profileEmail.isEmpty
            ? AppStrings.emailChangeEmpty
            : profileEmail);
    final canChange = state.status?.canChangeEmail ?? false;
    final busy = state.isLoading || state.isSubmitting;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.emailChangeTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            '${AppStrings.emailChangeCurrent} $displayed',
            key: const ValueKey('email-change-current'),
          ),
          if (state.isLoading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ] else if (state.status == null && state.error != null) ...[
            const SizedBox(height: 12),
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () {
                _loaded = false;
                _ensureLoaded();
              },
              child: const Text(AppStrings.emailChangeRetry),
            ),
          ] else if (!canChange && state.status != null) ...[
            const SizedBox(height: 12),
            const Text(AppStrings.emailChangeNotAllowed),
          ] else if (_step == _EmailStep.idle && canChange) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('email-change-open'),
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _notice = null;
                      _step = _EmailStep.editing;
                    }),
              child: const Text(AppStrings.emailChangeEdit),
            ),
          ] else if (_step == _EmailStep.editing) ...[
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('email-change-new'),
              controller: _email,
              enabled: !busy,
              maxLength: 100,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: AppStrings.emailChangeNew,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                    ? null
                    : AppStrings.emailChangeInvalidEmail;
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('email-change-start'),
              onPressed: busy ? null : _start,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.emailChangeStart),
            ),
            TextButton(
              onPressed: busy ? null : () => _resetFlow(),
              child: const Text(AppStrings.emailChangeCancel),
            ),
          ] else if (_step == _EmailStep.codeSent) ...[
            const SizedBox(height: 16),
            const Text(AppStrings.emailChangeCodeSent),
            const SizedBox(height: 8),
            Text(
              '${AppStrings.emailChangeTimeRemaining} ${_remaining(_expiresAt)}',
              key: const ValueKey('email-change-expiry'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('email-change-code'),
              controller: _code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: AppStrings.emailChangeCode,
                border: OutlineInputBorder(),
              ),
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                  ? null
                  : AppStrings.emailChangeCodeRequired,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('email-change-confirm'),
              onPressed: busy ? null : _confirm,
              child: const Text(AppStrings.emailChangeConfirm),
            ),
            OutlinedButton(
              key: const ValueKey('email-change-resend'),
              onPressed: busy || _remaining(_retryAt) > 0 ? null : _resend,
              child: Text(
                _remaining(_retryAt) > 0
                    ? '${AppStrings.emailChangeResendAfter} ${_remaining(_retryAt)}'
                    : AppStrings.emailChangeResend,
              ),
            ),
            TextButton(
              key: const ValueKey('email-change-cancel'),
              onPressed: () =>
                  _resetFlow(notice: AppStrings.emailChangeCanceled),
              child: const Text(AppStrings.emailChangeCancel),
            ),
          ],
          if (_notice case final notice?) ...[
            const SizedBox(height: 12),
            Text(notice),
          ],
          if (state.error case final error?
              when _step != _EmailStep.idle || state.status != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
