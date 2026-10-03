import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

class PriceText extends StatelessWidget {
  const PriceText({
    required this.original,
    required this.current,
    this.style,
    this.inline = false,
    super.key,
  });
  final num original;
  final num current;
  final TextStyle? style;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final effective = style ?? Theme.of(context).textTheme.bodyMedium!;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatRubles(current)),
          if (current < original)
            TextSpan(
              text: '${inline ? '  ' : '\n'}${formatRubles(original)}',
              style: effective.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: math.max(14, (effective.fontSize ?? 14) * 0.8),
                decoration: TextDecoration.lineThrough,
              ),
            ),
        ],
      ),
      style: effective,
    );
  }
}
