import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

// Временный экран адреса до реализации соответствующего feature.
class RoutePage extends StatelessWidget {
  const RoutePage({
    required this.title,
    required this.isTest,
    required this.onHome,
    this.message = AppStrings.sectionUnavailable,
    this.isLoading = false,
    this.onRetry,
    super.key,
  });

  final String title;
  final bool isTest;
  final VoidCallback onHome;
  final String message;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(title, key: const ValueKey('route-page-title')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isTest) const Text(AppStrings.testBuild),
                if (isLoading) const CircularProgressIndicator(),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (onRetry != null)
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text(AppStrings.retrySession),
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
    );
  }
}
