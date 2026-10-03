import 'package:flutter/material.dart';

/// Общая поверхность формы или справки; прокруткой владеет страница.
class ContentPanel extends StatelessWidget {
  const ContentPanel({required this.child, this.maxWidth = 440, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}
