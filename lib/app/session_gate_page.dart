import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:polevaya_kuhnya/app/route_page.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_status.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';

// Применяется и для адреса личного раздела, и для соседней колонки на широком экране.
class SessionGatePage extends ConsumerWidget {
  const SessionGatePage({required this.title, required this.isTest, super.key});

  final String title;
  final bool isTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionStatusProvider);
    final (heading, message) = switch (status) {
      SessionStatus.signedIn => (title, AppStrings.sectionUnavailable),
      SessionStatus.restoring => (
        AppStrings.checkingSession,
        AppStrings.pleaseWait,
      ),
      SessionStatus.unavailable => (
        AppStrings.sessionUnavailable,
        AppStrings.sessionUnavailableMessage,
      ),
      SessionStatus.signedOut => (title, AppStrings.signInRequired),
    };
    return RoutePage(
      title: heading,
      message: message,
      isLoading: status == SessionStatus.restoring,
      isTest: isTest,
      onHome: () => context.go('/'),
      onRetry: status == SessionStatus.unavailable
          ? () => ref.read(sessionControllerProvider.notifier).restore()
          : null,
    );
  }
}
