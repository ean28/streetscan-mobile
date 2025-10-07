// lib/widgets/session_tile.dart
import 'package:flutter/material.dart';
import '../core/models/session_model.dart';
import '../screens/upload_screen.dart';

class SessionTile extends StatelessWidget {
  final SessionModel session;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const SessionTile({
    Key? key,
    required this.session,
    required this.onTap,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final int potholeCount = session.count;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          'Session: ${_formatDate(session.createdAt)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          potholeCount > 0 
            ? '$potholeCount pothole(s) detected' 
            : 'No potholes detected',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Upload button only if pendingUpload
            if (session.pendingUpload)
              IconButton(
                icon: const Icon(Icons.cloud_upload, color: Colors.orange),
                tooltip: "Upload this session",
                onPressed: () async {
                  // Navigate to UploadScreen with just this session
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UploadScreen(sessions: [session]),
                    ),
                  );
                  // if upload succeeded, you can choose to refresh parent screen
                  if (result == true) {
                    // parent should reload sessions when it receives pop...
                    // you can call a callback or rely on `.then` when pushing
                  }
                },
              )
            else
              const Icon(Icons.check_circle, color: Colors.green),

            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
                tooltip: 'Delete session',
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
  enabled: true,
        // Add semantic label for screen readers
        // (optionally, wrap with Semantics if more detail is needed)
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
