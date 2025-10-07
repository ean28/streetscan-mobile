// lib/screens/assessmodel_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:street_scan/core/services/pothole_detector.dart';
import 'package:street_scan/core/detection/detection.dart';
import 'package:street_scan/core/detection/detection_painter.dart';

class AssessModelScreen extends StatefulWidget {
  const AssessModelScreen({super.key});

  @override
  State<AssessModelScreen> createState() => _AssessModelScreenState();
}

class _AssessModelScreenState extends State<AssessModelScreen> {
  List<Detection> _detections = [];
  bool _loading = false;
  img.Image? _decoded;
  Uint8List? _displayBytes;

  // For selection
  final List<String> _assetImages = [
    'assets/test/img-595.jpg',
    'assets/test/img-658.jpg',
    'assets/test/img-663.jpg',
    'assets/test/img-585.jpg',
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
      // Load chosen image
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

      // Ensure model is loaded
      await PotholeDetector.instance.loadModel();

      // Run inference
      final detections = await PotholeDetector.instance.processImageBytes(
        rgbBytes,
        decoded.width,
        decoded.height,
      );

      // Cache the display bytes once
      _displayBytes = Uint8List.fromList(img.encodeJpg(decoded));

      // Default model input size
      _modelInputW = 640;
      _modelInputH = 640;

      setState(() {
        _decoded = decoded;
        _detections = detections;
      });
    } catch (e, st) {
      debugPrint("❌ AssessModelScreen error: $e\n$st");
    } finally {
      setState(() => _loading = false);
    }
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
            child: DropdownButton<String>(
              hint: const Text("Select test image"),
              value: _selectedImage,
              items: _assetImages
                  .map((path) => DropdownMenuItem(
                        value: path,
                        child: Text(path.split('/').last),
                      ))
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

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _decoded == null || _displayBytes == null
                    ? const Center(child: Text("No image loaded"))
                    : Column(
                        children: [
                          // ==== IMAGE WITH BOXES ====
                          Expanded(
                            flex: 3,
                            child: Center(
                              child: FittedBox(
                                child: SizedBox(
                                  width: _decoded!.width.toDouble(),
                                  height: _decoded!.height.toDouble(),
                                  child: Stack(
                                    children: [
                                      Image.memory(_displayBytes!, fit: BoxFit.contain),
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

                          // ==== INFO PREVIEW ====
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                if (_origW != null && _origH != null)
                                  Text("Input Image Size: $_origW × $_origH"),
                                if (_modelInputW != null && _modelInputH != null)
                                  Text("Model Input Size: $_modelInputW × $_modelInputH"),
                                if (_origW != null && _origH != null)
                                  Text("Mapped Output Size: $_origW × $_origH"),
                                  Text("Inference Time: ${PotholeDetector.instance.lastInferenceMs ?? 0} ms"),
                              ],
                            ),
                          ),

                          // ==== DESCRIPTIVE LIST ====
                          Expanded(
                            flex: 2,
                            child: _detections.isEmpty
                                ? const Center(child: Text("No detections"))
                                : ListView.builder(
                                    itemCount: _detections.length,
                                    itemBuilder: (context, index) {
                                      final d = _detections[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Detection ${index + 1}",
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              Text("Label: ${d.label}"),
                                              Text("Confidence: ${(d.confidence * 100).toStringAsFixed(1)}%"),
                                              Text(
                                                  "Bounding Box: left=${d.box.left.toStringAsFixed(1)}, "
                                                  "top=${d.box.top.toStringAsFixed(1)}, "
                                                  "right=${d.box.right.toStringAsFixed(1)}, "
                                                  "bottom=${d.box.bottom.toStringAsFixed(1)}"),
                                              Text("Inference Time: ${d.inferenceTime ?? 0} ms"),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
