import 'package:flutter/material.dart';
import 'package:street_scan/screens/misc/uploadprogress.dart';
import '../core/models/session_model.dart';
import '../core/utils/image_utils.dart' as image_utils;

class UploadScreen extends StatefulWidget {
  final List<SessionModel> sessions;

  const UploadScreen({super.key, required this.sessions});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final Map<String, bool> _sessionSelected = {};
  final Map<String, Set<String>> _potholeSelected = {};

  @override
  void initState() {
    super.initState();
    for (final s in widget.sessions) {
      _sessionSelected[s.id] = true;
      _potholeSelected[s.id] = s.entries.map((e) => e.id).toSet();
    }
  }

  void _toggleSession(String sessionId, bool val) {
    setState(() {
      _sessionSelected[sessionId] = val;
      if (!val) {
        _potholeSelected[sessionId] = {};
      } else {
        final s = widget.sessions.firstWhere((x) => x.id == sessionId);
        _potholeSelected[sessionId] = s.entries.map((e) => e.id).toSet();
      }
    });
  }

  void _togglePothole(String sessionId, String potholeId, bool val) {
    setState(() {
      final set = _potholeSelected[sessionId] ?? <String>{};
      if (val) {
        set.add(potholeId);
      } else {
        set.remove(potholeId);
      }
      _potholeSelected[sessionId] = set;
    });
  }

  int _countSelectedPotholes() {
    int count = 0;
    for (final session in widget.sessions) {
      count += _potholeSelected[session.id]?.length ?? 0;
    }
    return count;
  }

  void _performUpload() {
    final toUpload = <SessionModel>[];
    for (final s in widget.sessions) {
      if (_sessionSelected[s.id] != true) continue;
      final chosenIds = _potholeSelected[s.id] ?? <String>{};
      final chosen = s.entries.where((e) => chosenIds.contains(e.id)).toList();
      if (chosen.isNotEmpty) {
        toUpload.add(s.copyWith(entries: chosen));
      }
    }

    if (toUpload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sessions or potholes selected')),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => UploadProgressScreen(toUpload: toUpload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSelected = _countSelectedPotholes();

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Upload')),
      body: ListView(
        children: widget.sessions.map((s) {
          final selected = _sessionSelected[s.id] ?? false;
          return ExpansionTile(
            initiallyExpanded: true,
            title: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _toggleSession(s.id, v ?? false),
                ),
                Expanded(
                  child: Text('Session: ${s.id} — ${s.count} pothole(s)'),
                ),
              ],
            ),
            children: s.entries.map((p) {
              final potholeSelected =
                  _potholeSelected[s.id]?.contains(p.id) ?? false;
              return ListTile(
                leading: image_utils.loadImage(p.imagePath, size: 52),
                title: Text(
                  'Pothole @ ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                ),
                subtitle: Text(
                  'Captured: ${p.timestamp.toLocal().toString().split('.')[0]}',
                ),
                trailing: Checkbox(
                  value: potholeSelected,
                  onChanged: selected
                      ? (v) => _togglePothole(s.id, p.id, v ?? false)
                      : null,
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _performUpload,
            icon: const Icon(Icons.cloud_upload),
            label: Text('Confirm Upload ($totalSelected)'),
          ),
        ),
      ),
    );
  }
}
