// lib/screens/assessmodel_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:street_scan/core/services/pothole_detector.dart';
import 'package:street_scan/core/services/config/detection_settings.dart';
import 'package:street_scan/core/detection/detection.dart';
import 'package:street_scan/core/detection/detection_painter.dart';

class AssessModelScreen extends StatefulWidget {
  const AssessModelScreen({super.key});

  @override
  State<AssessModelScreen> createState() => _AssessModelScreenState();
}

// Model-input PAD overlay removed to simplify UI/perf

class _AssessModelScreenState extends State<AssessModelScreen> {
  List<Detection> _detections = [];
  bool _loading = false;
  img.Image? _decoded;
  Uint8List? _displayBytes;
  // Model-input preview and PAD overlays removed for performance

  // Debug: raw detections exposed by PotholeDetector
  List<Detection> _rawDetections = [];
  bool _showRaw = false;

  PreprocessMode? _selectedMode;

  // For selection
  final List<String> _assetImages = [
    'assets/test/img-595.jpg',
    'assets/test/img-658.jpg',
    //'assets/test/img-663.jpg',
    'assets/test/img-585.jpg',
    //'assets/test/img-654.jpg',
    //'assets/test/img-458.jpg',
    //'assets/test/img-39.jpg',
    'assets/test/IMG_0054.jpg',
    //'assets/test/IMG_0046.jpg',
    //'assets/test/IMG_0043.jpg',
  ];
  String? _selectedImage;

  // Sizes
  int? _origW, _origH;
  int? _modelInputW, _modelInputH;

  Future<void> _runAssessment(String assetPath) async {
    setState(() {
      _loading = true;
      _detections = [];
      _decoded = null;
      _displayBytes = null;
      _origW = null;
      _origH = null;
      _modelInputW = null;
      _modelInputH = null;
    });

    try {
      final bytes = await rootBundle.load(assetPath);
      final decoded = img.decodeImage(bytes.buffer.asUint8List());
      if (decoded == null) throw Exception("Failed to decode test image.");

      _origW = decoded.width;
      _origH = decoded.height;

      // Convert RGBA → RGB
      final rgbaBytes = decoded.getBytes();
      final rgbBytes = Uint8List(decoded.width * decoded.height * 3);
      for (int i = 0, j = 0; i < rgbaBytes.length; i += 4, j += 3) {
        rgbBytes[j] = rgbaBytes[i];
        rgbBytes[j + 1] = rgbaBytes[i + 1];
        rgbBytes[j + 2] = rgbaBytes[i + 2];
      }

      // Cache the display bytes and show the image immediately to avoid UI freeze.
      _displayBytes = Uint8List.fromList(img.encodeJpg(decoded));
      _modelInputW = 320;
      _modelInputH = 320;
      setState(() {
        _decoded = decoded;
      });

      // Ensure model is loaded with the current preprocess mode.
      // Ensure model is loaded
      if (!PotholeDetector.instance.initialized) {
        await PotholeDetector.instance.loadModel();
      }

      // Run inference (updates detections when complete)
      final detections = await PotholeDetector.instance.processFrameFromRgb(
        rgbBytes,
        decoded.width,
        decoded.height,
      );

      setState(() {
        _detections = detections;
        _rawDetections = [];
      });
    } catch (e, st) {
      debugPrint("❌ AssessModelScreen error: $e\n$st");
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMode = DetectionConfig.instance.preprocessMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Assess Model")),
      body: Column(
        children: [
          // ==== IMAGE SELECTION ====
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preprocess Mode', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButton<PreprocessMode>(
                  value: _selectedMode,
                  items: PreprocessMode.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.toString().split('.').last),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _selectedMode = val);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              hint: const Text("Select test image"),
              value: _selectedImage,
              items: _assetImages
                  .map(
                    (path) => DropdownMenuItem(
                      value: path,
                      child: Text(path.split('/').last),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedImage = val);
                  _runAssessment(val);
                }
              },
            ),
          ),
          TextButton(
            onPressed: _selectedImage != null && !_loading
                ? () => _runAssessment(_selectedImage!)
                : null,
            child: const Text("Re-run"),
          ),

          // Quick reload model button to apply preprocess mode immediately
          TextButton(
            onPressed: _loading
                ? null
                : () async {
                    if (_selectedMode != null) {
                      DetectionConfig.instance.setPreprocessMode(
                        _selectedMode!,
                      );
                    }
                    setState(() => _loading = true);
                    try {
                      PotholeDetector.instance.close();
                    } catch (_) {}
                    await PotholeDetector.instance.loadModel();
                    setState(() => _loading = false);
                  },
            child: const Text('Reload Model (apply mode)'),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _decoded == null || _displayBytes == null
                ? const Center(child: Text("No image loaded"))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final h = MediaQuery.of(context).size.height;
                      return ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          // IMAGE WITH BOXES - fixed height area
                          SizedBox(
                            height: h * 0.42,
                            child: Center(
                              child: FittedBox(
                                child: SizedBox(
                                  width: _decoded!.width.toDouble(),
                                  height: _decoded!.height.toDouble(),
                                  child: Stack(
                                    children: [
                                      Image.memory(
                                        _displayBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                      CustomPaint(
                                        size: Size(
                                          _decoded!.width.toDouble(),
                                          _decoded!.height.toDouble(),
                                        ),
                                        painter: DetectionPainter(
                                          _detections,
                                          Size(
                                            _decoded!.width.toDouble(),
                                            _decoded!.height.toDouble(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const Divider(),

                          // MODEL INPUT PREVIEW REMOVED (improves performance)

                          // INFO PREVIEW
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_origW != null && _origH != null)
                                  Text("Input Image Size: $_origW × $_origH"),
                                if (_modelInputW != null &&
                                    _modelInputH != null)
                                  Text(
                                    "Model Input Size: $_modelInputW × $_modelInputH",
                                  ),
                                if (_origW != null && _origH != null)
                                  Text("Mapped Output Size: $_origW × $_origH"),
                                Text(
                                  "Preprocess Time: ${PotholeDetector.instance.lastPreprocessMs} ms",
                                ),
                                Text(
                                  "Inference Time: ${PotholeDetector.instance.lastInferenceMs} ms",
                                ),
                                Text(
                                  "NMS Time: ${PotholeDetector.instance.lastNmsMs} ms",
                                ),
                              ],
                            ),
                          ),

                          // Toggle: show raw (pre-NMS) detections
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Show raw (pre-NMS) detections',
                              ),
                              value: _showRaw,
                              onChanged: (v) => setState(() => _showRaw = v),
                            ),
                          ),

                          // Raw detections area (optional)
                          if (_showRaw)
                            Container(
                              height: 160,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: _rawDetections.isEmpty
                                  ? const Center(
                                      child: Text('No raw detections'),
                                    )
                                  : ListView.builder(
                                      itemCount: _rawDetections.length,
                                      itemBuilder: (context, idx) {
                                        final r = _rawDetections[idx];
                                        return ListTile(
                                          title: Text(
                                            'Raw ${idx + 1}: ${r.label} (${(r.confidence * 100).toStringAsFixed(1)}%)',
                                          ),
                                          subtitle: Text(
                                            'Box (pad px): left=${r.box.left.toStringAsFixed(1)}, top=${r.box.top.toStringAsFixed(1)}, right=${r.box.right.toStringAsFixed(1)}, bottom=${r.box.bottom.toStringAsFixed(1)}\nletterbox: scale=${r.letterboxScale.toStringAsFixed(3)}, dx=${r.letterboxDx}, dy=${r.letterboxDy}',
                                          ),
                                        );
                                      },
                                    ),
                            ),

                          // DESCRIPTIVE LIST
                          SizedBox(
                            height: 220,
                            child: _detections.isEmpty
                                ? const Center(child: Text("No detections"))
                                : ListView.builder(
                                    itemCount: _detections.length,
                                    itemBuilder: (context, index) {
                                      final d = _detections[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Detection ${index + 1}",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text("Label: ${d.label}"),
                                              Text(
                                                "Confidence: ${(d.confidence * 100).toStringAsFixed(1)}%",
                                              ),
                                              Text(
                                                "Bounding Box: left=${d.box.left.toStringAsFixed(1)}, "
                                                "top=${d.box.top.toStringAsFixed(1)}, "
                                                "right=${d.box.right.toStringAsFixed(1)}, "
                                                "bottom=${d.box.bottom.toStringAsFixed(1)}",
                                              ),
                                              Text(
                                                "Inference Time: ${d.inferenceTime ?? 0} ms",
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
