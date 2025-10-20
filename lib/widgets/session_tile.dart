// lib/widgets/session_tile.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/models/session_model.dart';
import '../screens/upload_screen.dart';
import '../core/services/upload_manager.dart';
import '../core/services/upload_metadata_service.dart';

class SessionTile extends StatelessWidget {
  final SessionModel session;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const SessionTile({
    super.key,
    required this.session,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final int potholeCount = session.count;
    final manager = Provider.of<UploadManager?>(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Session: ${_formatDate(session.createdAt)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // show small warning if any failures recorded
            Builder(
              builder: (ctx) {
                final failures = UploadMetadataService.failureCountForSession(
                  session.entries.map((e) => e.id).toList(),
                );
                if (failures > 0) {
                  return Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$failures',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        subtitle: Text(
          potholeCount > 0
              ? '$potholeCount pothole(s) detected'
              : 'No potholes detected',
        ),

        // ✅ FIXED trailing to prevent overflow
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (manager != null && session.pendingUpload)
              StreamBuilder<Map<String, double>>(
                stream: manager.progressStream,
                builder: (context, snap) {
                  double fraction = 0.0;
                  if (snap.hasData && snap.data!.containsKey(session.id)) {
                    fraction = snap.data![session.id]!;
                  } else if (manager.progressFor(session.id) != null) {
                    final p = manager.progressFor(session.id)!;
                    fraction = p.totalCount > 0
                        ? p.uploadedCount / p.totalCount
                        : 0.0;
                  }

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 72,
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 6,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.cloud_upload,
                          color: Colors.orange,
                        ),
                        tooltip: "Upload this session",
                        onPressed: () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UploadScreen(sessions: [session]),
                            ),
                          );
                          if (result == true) {}
                        },
                      ),
                    ],
                  );
                },
              )
            else if (session.pendingUpload)
              IconButton(
                icon: const Icon(Icons.cloud_upload, color: Colors.orange),
                tooltip: "Upload this session",
                onPressed: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UploadScreen(sessions: [session]),
                    ),
                  );
                  if (result == true) {}
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
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
