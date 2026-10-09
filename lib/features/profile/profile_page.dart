import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/platform/app_version.dart';
import 'package:polevaya_kuhnya/features/profile/device_disconnect_controller.dart';
import 'package:polevaya_kuhnya/features/profile/email_change_panel.dart';
import 'package:polevaya_kuhnya/features/profile/profile_summary.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(WidgetRef ref) async {
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text(AppStrings.deviceDisconnectConfirmTitle),
        content: const Text(AppStrings.deviceDisconnectConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.deviceDisconnectCancel),
          ),
          FilledButton(
            key: const ValueKey('device-disconnect-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.deviceDisconnectConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await ref
        .read(deviceDisconnectControllerProvider.notifier)
        .disconnect();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.deviceDisconnectSuccess)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionStatusProvider);
    if (status != SessionStatus.signedIn) {
      final (heading, message) = switch (status) {
        SessionStatus.restoring => (AppStrings.profile, AppStrings.pleaseWait),
        SessionStatus.unavailable => (
          AppStrings.sessionUnavailable,
          AppStrings.sessionUnavailableMessage,
        ),
        _ => (AppStrings.profile, AppStrings.signInRequired),
      };
      return RoutePage(
        title: heading,
        message: message,
        isLoading: status == SessionStatus.restoring,
        quietLoading: true,
        onHome: () => context.go('/'),
        onRetry: status == SessionStatus.unavailable
            ? () => ref.read(sessionControllerProvider.notifier).restore()
            : null,
      );
    }

    final disconnect = ref.watch(deviceDisconnectControllerProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          AppStrings.profile,
          key: ValueKey('route-page-title'),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ContentPanel(child: ProfileSummary()),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey('profile-sign-out'),
                    onPressed: disconnect.isSubmitting
                        ? null
                        : () => _signOut(ref),
                    child: const Text(AppStrings.signOut),
                  ),
                  const SizedBox(height: 8),
                  if (disconnect.error case final error?) ...[
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton(
                    key: const ValueKey('device-disconnect'),
                    onPressed: disconnect.isSubmitting
                        ? null
                        : () => _confirmDisconnect(context, ref),
                    child: disconnect.isSubmitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(AppStrings.deviceDisconnect),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.accountDeletionUnavailableTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(AppStrings.accountDeletionUnavailableBody),
                  const SizedBox(height: 28),
                  const ContentPanel(child: EmailChangePanel()),
                  const SizedBox(height: 28),
                  Text(
                    '${AppStrings.aboutAppVersion}: ${ref.watch(appVersionLabelProvider)}',
                    key: const ValueKey('profile-app-version'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
