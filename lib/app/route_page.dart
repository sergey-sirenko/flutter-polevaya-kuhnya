import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/content_panel.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

// Временный экран адреса до реализации соответствующего feature.
class RoutePage extends StatelessWidget {
  const RoutePage({
    required this.title,
    required this.onHome,
    this.message = AppStrings.sectionUnavailable,
    this.isLoading = false,
    this.quietLoading = false,
    this.showTitle = true,
    this.onRetry,
    this.onSignIn,
    super.key,
  });

  final String title;
  final VoidCallback onHome;
  final String message;
  final bool isLoading;
  final bool quietLoading;
  final bool showTitle;
  final VoidCallback? onRetry;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: showTitle
            ? Text(title, key: const ValueKey('route-page-title'))
            : null,
      ),
      body: SafeArea(
        child: isLoading && quietLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ContentPanel(
                    maxWidth: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                        ] else ...[
                          Icon(
                            Icons.info_outline,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(message, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        if (onRetry != null)
                          FilledButton(
                            onPressed: onRetry,
                            child: const Text(AppStrings.retrySession),
                          ),
                        if (onSignIn != null)
                          FilledButton(
                            key: const ValueKey('guest-sign-in'),
                            onPressed: onSignIn,
                            child: const Text(AppStrings.signInSubmit),
                          ),
                        TextButton(
                          onPressed: onHome,
                          child: const Text(AppStrings.home),
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
