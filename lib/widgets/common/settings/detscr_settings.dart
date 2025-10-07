// lib/widgets/common/settings/detscr_settings.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:street_scan/core/services/config/detection_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:street_scan/core/services/pothole_detector.dart';

class DetectionScreenSettings extends StatefulWidget {
  final bool isDetectionActive;
  final VoidCallback onToggleDetection;
  final VoidCallback onOpenSettings;
  final ValueChanged<OverlayMode>? onOverlayModeChanged;

  const DetectionScreenSettings({
    super.key,
    required this.isDetectionActive,
    required this.onToggleDetection,
    required this.onOpenSettings,
    this.onOverlayModeChanged,
  });

  @override
  State<DetectionScreenSettings> createState() =>
      _DetectionScreenSettingsState();
}

enum OverlayMode {
  alwaysOn,
  sessionOnly,
  off,
}

class _DetectionScreenSettingsState extends State<DetectionScreenSettings> {
  OverlayMode _overlayMode = OverlayMode.alwaysOn;
  InferenceBackend _selectedBackend = InferenceBackend.cpu;

  void _openSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return ListView(
            shrinkWrap: true,
            children: [
              // Overlay Mode
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Bounding Box Overlay",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<OverlayMode>(
                  isExpanded: true,
                  value: _overlayMode,
                  items: OverlayMode.values.map((e) {
                    return DropdownMenuItem(
                      value: e,
                      child: Text({
                        OverlayMode.alwaysOn: "Always On",
                        OverlayMode.sessionOnly: "Session Only",
                        OverlayMode.off: "Off",
                      }[e]!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setModalState(() => _overlayMode = value);
                    widget.onOverlayModeChanged?.call(value);
                    setState(() {});
                  },
                ),
              ),

              // Input Size
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Select Input Size",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<Map<InferenceSize, bool>>(
                  future: DetectionConfig.checkAvailableModels(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final availability = snapshot.data!;
                    return DropdownButton<InferenceSize>(
                      isExpanded: true,
                      value: DetectionConfig.instance.inputSize,
                      items: InferenceSize.values.map((e) {
                        final enabled = availability[e] ?? false;
                        return DropdownMenuItem(
                          value: e,
                          enabled: enabled,
                          child: Text(
                            "${{
                              InferenceSize.s320:
                                  "320 × 320 (Fastest, Lowest Accuracy)",
                              InferenceSize.s416: "416 × 416 (Balanced)",
                              InferenceSize.s640:
                                  "640 × 640 (Most Accurate, Slowest)",
                            }[e]!}${enabled ? "" : " ❌ Missing"}",
                            style: TextStyle(
                              color: enabled ? null : Colors.grey,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        setModalState(
                            () => DetectionConfig.instance.setInputSize(value));
                        await PotholeDetector.instance.loadModel();
                        if (kDebugMode) {
                          debugPrint(
                            "Switched input size to ${DetectionConfig.instance.sizeValue}",
                          );
                        }
                        setState(() {});
                      },
                    );
                  },
                ),
              ),

              // Backend
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Select Inference Backend",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<InferenceBackend>(
                  isExpanded: true,
                  value: _selectedBackend,
                  items: InferenceBackend.values.map((e) {
                    return DropdownMenuItem(
                      value: e,
                      child: Text(e.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setModalState(() => _selectedBackend = value);
                    await PotholeDetector.instance.loadModel();
                    if (kDebugMode) {
                      debugPrint("Switched backend to ${value.name}");
                    }
                    setState(() {});
                  },
                ),
              ),

              const Divider(),
              const ListTile(
                title: Text("GPS Logging Interval"),
                subtitle: Text("2 seconds"),
              ),
              const ListTile(
                title: Text("Image Compression Quality"),
                subtitle: Text("Medium (82%)"),
              ),
              SwitchListTile(
                title: const Text("Prevent Sleep During Logging"),
                value: true,
                onChanged: (v) {
                  if (v) {
                    WakelockPlus.enable();
                  } else {
                    WakelockPlus.disable();
                  }
                  Navigator.pop(c);
                },
              ),
              SwitchListTile(
                title: const Text("Prompt Review After Session"),
                value: true,
                onChanged: (v) {},
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: const Icon(Icons.settings, color: Colors.white),
        onPressed: () => _openSettingsSheet(context),
      ),
    );
  }
}
