import 'package:flutter/material.dart';
import 'package:street_scan/core/services/inference_isolate.dart';

class InferenceOverlay extends StatelessWidget {
  final ValueNotifier<ManagerStats> stats;
  const InferenceOverlay({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ManagerStats>(
      valueListenable: stats,
      builder: (context, s, _) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sent: ${s.framesSent}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Processed: ${s.framesProcessed}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Dropped: ${s.framesDropped}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Infer(ms): ${s.lastInferenceMs}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Detect(ms): ${s.lastDetectionMs}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                'Interval(ms): ${s.currentIntervalMs}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
