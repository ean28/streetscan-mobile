import 'package:flutter/material.dart';

class TopBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  const TopBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}
