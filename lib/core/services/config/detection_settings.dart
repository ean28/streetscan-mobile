// lib/core/services/config/detection_settings.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

enum InferenceSize { s320, s416, s640 }

class DetectionConfig extends ChangeNotifier {
  static final DetectionConfig instance = DetectionConfig._internal();
  DetectionConfig._internal();

  InferenceSize _inputSize = InferenceSize.s640;
  InferenceSize get inputSize => _inputSize;

  static double get confThreshold => 0.25;
  static double get iouThreshold => 0.30;
  static int get maxDetections => 80;

  // 🔹 Keep track of availability
  final Map<InferenceSize, bool> _availableModels = {};

  Map<InferenceSize, bool> get availableModels => _availableModels;

  static const Map<InferenceSize, String> _modelAssets = {
    InferenceSize.s320: 'assets/models/model_320_float32.tflite',
    InferenceSize.s416: 'assets/models/model_416_float32.tflite',
    InferenceSize.s640: 'assets/models/model_640_float32.tflite',
  };

  void setInputSize(InferenceSize size) {
    _inputSize = size;
    notifyListeners();
  }

  int get sizeValue {
    switch (_inputSize) {
      case InferenceSize.s320:
        return 320;
      case InferenceSize.s416:
        return 416;
      case InferenceSize.s640:
        return 640;
    }
  }
  
  String get currentModelAsset {
    return _modelAssets[_inputSize]!;
  }

  /// 🔹 Check which models exist in assets
  static Future<Map<InferenceSize, bool>> checkAvailableModels() async {
    final availability = <InferenceSize, bool>{};
    for (final entry in _modelAssets.entries) {
      try {
        await rootBundle.load(entry.value);
        availability[entry.key] = true;
      } catch (_) {
        availability[entry.key] = false;
      }
    }
    instance._availableModels.clear();
    instance._availableModels.addAll(availability);
    return availability;
  }

  Future<List<String>> loadLabels() async {
    final data = await rootBundle.loadString('assets/model_clabels.txt');
    return data
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }
}
