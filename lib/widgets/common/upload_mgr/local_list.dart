import 'package:flutter/material.dart';
import 'package:street_scan/core/utils/image_utils.dart' as image_utils;
import 'package:street_scan/core/models/session_model.dart';

class LocalList extends StatelessWidget {
  final bool loadingLocal;
  final List<SessionModel> localSessions;
  final Map<String, bool> selectedLocal;
  final void Function(bool) selectAllLocal;
  final void Function(String, bool) toggleLocalSelection;
  final void Function(List<SessionModel>) openUploadSelection;
  final bool Function(SessionModel) isSessionUploaded;

  const LocalList({
    super.key,
    required this.loadingLocal,
    required this.localSessions,
    required this.selectedLocal,
    required this.selectAllLocal,
    required this.toggleLocalSelection,
    required this.openUploadSelection,
    required this.isSessionUploaded,
  });

  @override
  Widget build(BuildContext context) {
    if (loadingLocal) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (localSessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No local sessions found.'),
      );
    }

    // ListView replaces SingleChildScrollView
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: localSessions.length + 1, // +1 for "Select all" checkbox
      itemBuilder: (context, index) {
        if (index == 0) {
          // Select all checkbox at top
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Checkbox(
                  value:
                      localSessions.isNotEmpty &&
                      selectedLocal.values.where((v) => v == true).length ==
                          localSessions.length,
                  onChanged: (v) => selectAllLocal(v ?? false),
                ),
                const SizedBox(width: 2),
                const Text('Select all'),
              ],
            ),
          );
        }

        final s = localSessions[index - 1];
        final uploaded = isSessionUploaded(s);
        final selected = selectedLocal[s.id] ?? false;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => toggleLocalSelection(s.id, v ?? false),
                ),
                const SizedBox(width: 4),
                image_utils.loadImage(
                  s.entries.isNotEmpty ? s.entries.first.imagePath : '',
                  size: 48,
                ),
              ],
            ),
            title: Text('Session ${s.id} — ${s.count} pothole(s)'),
            subtitle: Text(
              uploaded ? 'Already uploaded' : 'Not uploaded',
              style: TextStyle(
                color: uploaded ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: ElevatedButton(
              onPressed: () => openUploadSelection([s]),
              child: const Text('Review'),
            ),
            onTap: () =>
                toggleLocalSelection(s.id, !(selectedLocal[s.id] ?? false)),
          ),
        );
      },
    );
  }
}
