import 'package:flutter/material.dart';

class SessionTimer extends StatelessWidget {
  final int durationSeconds;
  const SessionTimer({super.key, required this.durationSeconds});

  String _format(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topCenter,
      child: Text(
        _format(durationSeconds),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        
      ),
    );
  }
}
