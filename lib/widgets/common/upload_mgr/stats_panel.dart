import 'package:flutter/material.dart';
import 'package:street_scan/core/models/session_model.dart';

class StatsPanel extends StatelessWidget {
  final List<SessionModel> localSessions;
  final List<SessionModel> remoteSessions;
  final bool loadingRemote;

  const StatsPanel({
    super.key,
    required this.localSessions,
    required this.remoteSessions,
    required this.loadingRemote,
  });

  @override
  Widget build(BuildContext context) {
    final totalLocal = localSessions.length;
    final uploaded = remoteSessions
        .where((r) => localSessions.any((l) => l.id == r.id))
        .length;
    final pending = totalLocal - uploaded;

    final totalLocalPotholes = localSessions.fold<int>(
      0,
      (sum, s) => sum + s.entries.length,
    );
    final totalRemotePotholes = remoteSessions.fold<int>(
      0,
      (sum, s) => sum + s.entries.length,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local Sessions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('$totalLocal total sessions'),
                    Text('$uploaded uploaded • $pending pending'),
                    Text('$totalLocalPotholes pothole(s) total'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Server Sessions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('${remoteSessions.length} total sessions on server'),
                    Text('$totalRemotePotholes pothole(s) total'),
                    if (loadingRemote)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
