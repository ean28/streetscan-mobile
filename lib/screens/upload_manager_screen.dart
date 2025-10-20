import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/services/local_storage_service.dart';
import '../core/services/firebase_service.dart';
import '../core/models/session_model.dart';
import 'upload_screen.dart';
import 'package:street_scan/widgets/common/upload_mgr/stats_panel.dart';
import 'package:street_scan/widgets/common/upload_mgr/local_list.dart';
import 'package:street_scan/widgets/common/upload_mgr/remote_list.dart';

enum _SessionsTab { local, remote }

class UploadManagerScreen extends StatefulWidget {
  const UploadManagerScreen({super.key});

  @override
  State<UploadManagerScreen> createState() => _UploadManagerScreenState();
}

class _UploadManagerScreenState extends State<UploadManagerScreen> {
  final FirebaseService _firebase = FirebaseService();

  List<SessionModel> _local = [];
  List<SessionModel> _remote = [];
  bool _loadingRemote = false;
  bool _loadingLocal = false;

  final Map<String, bool> _selectedLocal = {};

  Set<_SessionsTab> _selectedTab = {_SessionsTab.local};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadLocal();
    await _fetchRemote();
  }

  Future<void> _loadLocal() async {
    setState(() => _loadingLocal = true);
    await LocalStorageService.init();
    final list = LocalStorageService.getAllSessions();
    if (!mounted) return;
    setState(() {
      _local = list;
      final prevKeys = Map<String, bool>.from(_selectedLocal);
      _selectedLocal.clear();
      for (final s in _local) {
        _selectedLocal[s.id] = prevKeys[s.id] ?? true;
      }
      _loadingLocal = false;
    });
  }

  Future<void> _fetchRemote() async {
    setState(() => _loadingRemote = true);
    try {
      final rem = await _firebase.fetchSessions();

      // Local-first: if session exists locally, use local entries
      for (var session in rem) {
        final local = _local.firstWhere(
          (s) => s.id == session.id,
          orElse: () => session,
        );

        if (local.entries.isEmpty) {
          session.entries = await _firebase.fetchEntriesForSession(session.id);
        } else {
          // use local entries
          session.entries = local.entries;
        }
      }

      if (!mounted) return;
      setState(() {
        _remote = rem;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to fetch sessions from server: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingRemote = false);
      }
    }
  }

  bool _isSessionUploaded(SessionModel s) {
    return _remote.any((r) => r.id == s.id);
  }

  void _toggleLocalSelection(String sessionId, bool val) {
    setState(() {
      _selectedLocal[sessionId] = val;
    });
  }

  void _openUploadSelection(List<SessionModel> sessions) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UploadScreen(sessions: sessions)),
    );
    await _loadAll();
  }

  void _uploadSelected() {
    final chosen = _local.where((s) => _selectedLocal[s.id] == true).toList();
    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No sessions selected for upload.')),
      );
      return;
    }
    _openUploadSelection(chosen);
  }

  void _selectAllLocal(bool value) {
    setState(() {
      for (final s in _local) {
        _selectedLocal[s.id] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showingLocal = _selectedTab.contains(_SessionsTab.local);

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Manager'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            // Stats panel + tab selector
            Material(
              elevation: 2,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    StatsPanel(
                      localSessions: _local,
                      remoteSessions: _remote,
                      loadingRemote: _loadingRemote,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: SegmentedButton<_SessionsTab>(
                        segments: const [
                          ButtonSegment(
                            value: _SessionsTab.local,
                            label: Text('Local'),
                            icon: Icon(Icons.storage_rounded),
                          ),
                          ButtonSegment(
                            value: _SessionsTab.remote,
                            label: Text('Server'),
                            icon: Icon(Icons.cloud_done_rounded),
                          ),
                        ],
                        selected: _selectedTab,
                        onSelectionChanged: (newSet) {
                          setState(() => _selectedTab = newSet);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: showingLocal
                    ? RefreshIndicator(
                        key: const ValueKey('local_refresh'),
                        onRefresh: _loadLocal,
                        child: LocalList(
                          localSessions: _local,
                          selectedLocal: _selectedLocal,
                          isSessionUploaded: _isSessionUploaded,
                          loadingLocal: _loadingLocal,
                          toggleLocalSelection: _toggleLocalSelection,
                          openUploadSelection: _openUploadSelection,
                          selectAllLocal: _selectAllLocal,
                        ),
                      )
                    : RefreshIndicator(
                        key: const ValueKey('remote_refresh'),
                        onRefresh: _fetchRemote,
                        child: RemoteList(
                          loadingRemote: _loadingRemote,
                          remoteSessions: _remote,
                          localSessions: _local,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: showingLocal
          ? FloatingActionButton.extended(
              onPressed: _uploadSelected,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Review Selected'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
