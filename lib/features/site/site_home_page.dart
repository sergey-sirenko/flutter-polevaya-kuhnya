import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/app/strings.dart';

class SiteHomePage extends StatelessWidget {
  const SiteHomePage({required this.isTest, required this.onOrder, super.key});

  final bool isTest;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.appTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (isTest) const Text(AppStrings.testBuild),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOrder,
                child: const Text(AppStrings.orderLunch),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
