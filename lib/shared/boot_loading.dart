import 'package:flutter/material.dart';

/// Одинаковый нейтральный экран до готовности версии и данных главной.
class BootLoading extends StatelessWidget {
  const BootLoading({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: Color(0xFF305F3D),
          semanticsLabel: 'Загрузка',
        ),
      ),
    ),
  );
}
