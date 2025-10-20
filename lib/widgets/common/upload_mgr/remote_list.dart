import 'package:flutter/material.dart';
import 'package:street_scan/core/utils/image_utils.dart' as image_utils;
import 'package:street_scan/core/models/session_model.dart';

class RemoteList extends StatelessWidget {
  final bool loadingRemote;
  final List<SessionModel> remoteSessions;
  final List<SessionModel> localSessions; // for comparison

  const RemoteList({
    super.key,
    required this.loadingRemote,
    required this.remoteSessions,
    required this.localSessions,
  });

  /// Check if session exists locally
  bool _existsLocally(SessionModel session) {
    return localSessions.any((s) => s.id == session.id);
  }

  /// Get the session data: prefer local if available
  SessionModel _getEffectiveSession(SessionModel session) {
    final local = localSessions.firstWhere(
      (s) => s.id == session.id,
      orElse: () => session,
    );
    return local;
  }

  @override
  Widget build(BuildContext context) {
    if (loadingRemote) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (remoteSessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No remote sessions available.'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: remoteSessions.length,
      itemBuilder: (context, index) {
        final r = remoteSessions[index];
        final existsLocally = _existsLocally(r);

        // Use local data if available, otherwise firebase
        final session = _getEffectiveSession(r);
        final potholeCount = session.entries.length;

        return Card(
          color: existsLocally ? Colors.blue[100] : Colors.green[100],
          margin: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: ListTile(
            leading: image_utils.loadImage(
              session.entries.isNotEmpty ? session.entries.first.imagePath : '',
              size: 48,
            ),
            title: Text('Session ${session.id} — $potholeCount pothole(s)'),
            subtitle: Text(
              'Uploaded: ${session.createdAt.toLocal().toString().split('.')[0]}',
            ),
            onTap: () {
              // Optional: implement read-only session viewer
            },
          ),
        );
      },
    );
  }
}
