import 'package:flutter/material.dart';

class AnimatedProgress extends StatelessWidget {
  final double value;
  final double height;
  const AnimatedProgress({super.key, required this.value, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: value),
      duration: const Duration(milliseconds: 500),
      builder: (context, v, child) {
        return LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(
            Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}
