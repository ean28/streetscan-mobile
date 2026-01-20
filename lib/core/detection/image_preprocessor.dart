import 'package:flutter/foundation.dart';

import 'yolo_output_parser.dart';

class PreprocessResult {
  final Uint8List inputBuffer;
  final LetterboxInfo letterbox;
  final int preprocessMs;

  const PreprocessResult({
    required this.inputBuffer,
    required this.letterbox,
    required this.preprocessMs,
  });
}

/// Handles image preprocessing for YOLO-style object detection models.
class ImagePreprocessor {
  // Cached buffer to avoid per-frame allocation
  Uint8List? _inputBuffer;

  /// Preprocess RGB bytes into model input format with letterboxing.
  ///
  /// [rgbBytes] - Source RGB image bytes (3 bytes per pixel, row-major)
  /// [srcWidth], [srcHeight] - Source image dimensions
  /// [inputW], [inputH] - Target model input dimensions
  /// [inputChannels] - Number of input channels (typically 3)
  /// [useQuantizedInput] - Whether to output quantized (int8/uint8) or float32
  /// [isInt8] - If quantized, whether int8 (vs uint8)
  /// [inScale], [inZero] - Input quantization parameters
  /// [useBgr] - If true, swap R and B channels for BGR model input
  PreprocessResult preprocessRgb({
    required Uint8List rgbBytes,
    required int srcWidth,
    required int srcHeight,
    required int inputW,
    required int inputH,
    required int inputChannels,
    required bool useQuantizedInput,
    bool isInt8 = false,
    double inScale = 1.0,
    int inZero = 0,
    bool useBgr = false,
  }) {
    final swPre = Stopwatch()..start();

    final requiredBytes =
        inputW * inputH * inputChannels * (useQuantizedInput ? 1 : 4);
    if (_inputBuffer == null || _inputBuffer!.length != requiredBytes) {
      _inputBuffer = Uint8List(requiredBytes);
    }

    if (kDebugMode) {
      debugPrint(
        "🔍 Processing RGB frame: ${srcWidth}x$srcHeight -> ${inputW}x$inputH, "
        "quantized: $useQuantizedInput (inScale: $inScale, inZero: $inZero), useBgr: $useBgr",
      );
      // Sample a few source pixels for diagnostic
      if (rgbBytes.length >= 9) {
        debugPrint(
          "🎨 Source pixel[0]: R=${rgbBytes[0]}, G=${rgbBytes[1]}, B=${rgbBytes[2]}  "
          "pixel[1]: R=${rgbBytes[3]}, G=${rgbBytes[4]}, B=${rgbBytes[5]}  "
          "pixel[2]: R=${rgbBytes[6]}, G=${rgbBytes[7]}, B=${rgbBytes[8]}",
        );
      }
    }

    // Calculate letterbox scaling
    final double scale = (inputW / srcWidth < inputH / srcHeight)
        ? inputW / srcWidth
        : inputH / srcHeight;
    final int resizedW = (srcWidth * scale).round();
    final int resizedH = (srcHeight * scale).round();
    final int dx = (inputW - resizedW) ~/ 2;
    final int dy = (inputH - resizedH) ~/ 2;

    final letterbox = LetterboxInfo(
      scale: scale,
      dx: dx.toDouble(),
      dy: dy.toDouble(),
      srcWidth: srcWidth,
      srcHeight: srcHeight,
    );

    // Set up typed views for efficient writes
    final bool writeFloat = !useQuantizedInput;
    Float32List? floatView;
    Uint8List? byteView;
    if (writeFloat) {
      floatView = _inputBuffer!.buffer.asFloat32List();
    } else {
      byteView = _inputBuffer!;
    }
    int floatIndex = 0;
    int byteIndex = 0;

    // YOLO pad color (114 gray)
    final int padVal = useQuantizedInput
        ? ((114.0 / 255.0 / inScale).round() + inZero).clamp(
            isInt8 ? -128 : 0,
            isInt8 ? 127 : 255,
          )
        : 0;
    final int pVal = useQuantizedInput ? padVal : 114;

    // Process each output pixel
    for (int y = 0; y < inputH; y++) {
      final int sourceY = ((y - dy) / scale).floor();
      final bool yInBounds = sourceY >= 0 && sourceY < srcHeight;

      for (int x = 0; x < inputW; x++) {
        if (!yInBounds) {
          _writePadPixel(
            writeFloat,
            floatView,
            byteView,
            floatIndex,
            byteIndex,
            pVal,
          );
          if (writeFloat) {
            floatIndex += 3;
          } else {
            byteIndex += 3;
          }
          continue;
        }

        final int sourceX = ((x - dx) / scale).floor();
        if (sourceX < 0 || sourceX >= srcWidth) {
          _writePadPixel(
            writeFloat,
            floatView,
            byteView,
            floatIndex,
            byteIndex,
            pVal,
          );
          if (writeFloat) {
            floatIndex += 3;
          } else {
            byteIndex += 3;
          }
          continue;
        }

        final int srcIndex = (sourceY * srcWidth + sourceX) * 3;
        int R = rgbBytes[srcIndex];
        int G = rgbBytes[srcIndex + 1];
        int B = rgbBytes[srcIndex + 2];

        // Swap R and B if model expects BGR input
        if (useBgr) {
          final tmp = R;
          R = B;
          B = tmp;
        }

        if (writeFloat) {
          floatView![floatIndex++] = R / 255.0;
          floatView[floatIndex++] = G / 255.0;
          floatView[floatIndex++] = B / 255.0;
        } else {
          final int qr = ((R / 255.0) / inScale).round() + inZero;
          final int qg = ((G / 255.0) / inScale).round() + inZero;
          final int qb = ((B / 255.0) / inScale).round() + inZero;
          final int minVal = isInt8 ? -128 : 0;
          final int maxVal = isInt8 ? 127 : 255;
          byteView![byteIndex++] = qr.clamp(minVal, maxVal) & 0xFF;
          byteView[byteIndex++] = qg.clamp(minVal, maxVal) & 0xFF;
          byteView[byteIndex++] = qb.clamp(minVal, maxVal) & 0xFF;
        }
      }
    }

    swPre.stop();
    if (kDebugMode) {
      debugPrint(
        "⏱️ RGB Preprocessing completed in ${swPre.elapsedMilliseconds} ms",
      );
    }

    return PreprocessResult(
      inputBuffer: _inputBuffer!,
      letterbox: letterbox,
      preprocessMs: swPre.elapsedMilliseconds,
    );
  }

  /// Preprocess YUV420 planes into model input format with letterboxing.
  PreprocessResult preprocessYuv({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int inputW,
    required int inputH,
    required int inputChannels,
    required bool useQuantizedInput,
    bool isInt8 = false,
    double inScale = 1.0,
    int inZero = 0,
    bool useBgr = false,
  }) {
    final swPre = Stopwatch()..start();

    final requiredBytes =
        inputW * inputH * inputChannels * (useQuantizedInput ? 1 : 4);
    if (_inputBuffer == null || _inputBuffer!.length != requiredBytes) {
      _inputBuffer = Uint8List(requiredBytes);
    }

    if (kDebugMode) {
      debugPrint(
        "🔍 Processing YUV frame: ${srcWidth}x$srcHeight -> ${inputW}x$inputH, "
        "quantized: $useQuantizedInput (scale: $inScale, zero: $inZero)",
      );
    }

    // Calculate letterbox scaling
    final double scale = (inputW / srcWidth < inputH / srcHeight)
        ? inputW / srcWidth
        : inputH / srcHeight;
    final int resizedW = (srcWidth * scale).round();
    final int resizedH = (srcHeight * scale).round();
    final int dx = (inputW - resizedW) ~/ 2;
    final int dy = (inputH - resizedH) ~/ 2;

    final letterbox = LetterboxInfo(
      scale: scale,
      dx: dx.toDouble(),
      dy: dy.toDouble(),
      srcWidth: srcWidth,
      srcHeight: srcHeight,
    );

    // Set up typed views
    final bool writeFloat = !useQuantizedInput;
    Float32List? floatView;
    Uint8List? byteView;
    if (writeFloat) {
      floatView = _inputBuffer!.buffer.asFloat32List();
    } else {
      byteView = _inputBuffer!;
    }
    int floatIndex = 0;
    int byteIndex = 0;

    // Pad color
    final int padVal = useQuantizedInput
        ? ((114.0 / 255.0 / inScale).round() + inZero).clamp(
            isInt8 ? -128 : 0,
            isInt8 ? 127 : 255,
          )
        : 0;
    final int pVal = useQuantizedInput ? padVal : 114;

    for (int y = 0; y < inputH; y++) {
      final int sourceY = ((y - dy) / scale).floor();
      final bool yInBounds = sourceY >= 0 && sourceY < srcHeight;

      for (int x = 0; x < inputW; x++) {
        if (!yInBounds) {
          _writePadPixel(
            writeFloat,
            floatView,
            byteView,
            floatIndex,
            byteIndex,
            pVal,
          );
          if (writeFloat) {
            floatIndex += 3;
          } else {
            byteIndex += 3;
          }
          continue;
        }

        final int sourceX = ((x - dx) / scale).floor();
        if (sourceX < 0 || sourceX >= srcWidth) {
          _writePadPixel(
            writeFloat,
            floatView,
            byteView,
            floatIndex,
            byteIndex,
            pVal,
          );
          if (writeFloat) {
            floatIndex += 3;
          } else {
            byteIndex += 3;
          }
          continue;
        }

        // Sample YUV
        final int uvRow = sourceY >> 1;
        final int uvCol = sourceX >> 1;
        final int yIndex = sourceY * yRowStride + sourceX;
        final int uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        final int Y = yPlane[yIndex] & 0xFF;
        final int U = uPlane[uvIndex] & 0xFF;
        final int V = vPlane[uvIndex] & 0xFF;

        // YUV to RGB conversion
        int R = (Y + 1.370705 * (V - 128)).round().clamp(0, 255);
        int G = (Y - 0.698001 * (V - 128) - 0.337633 * (U - 128)).round().clamp(
          0,
          255,
        );
        int B = (Y + 1.732446 * (U - 128)).round().clamp(0, 255);

        if (useBgr) {
          final tmp = R;
          R = B;
          B = tmp;
        }

        if (writeFloat) {
          floatView![floatIndex++] = R / 255.0;
          floatView[floatIndex++] = G / 255.0;
          floatView[floatIndex++] = B / 255.0;
        } else {
          final int qr = ((R / 255.0) / inScale).round() + inZero;
          final int qg = ((G / 255.0) / inScale).round() + inZero;
          final int qb = ((B / 255.0) / inScale).round() + inZero;
          final int minVal = isInt8 ? -128 : 0;
          final int maxVal = isInt8 ? 127 : 255;
          byteView![byteIndex++] = qr.clamp(minVal, maxVal) & 0xFF;
          byteView[byteIndex++] = qg.clamp(minVal, maxVal) & 0xFF;
          byteView[byteIndex++] = qb.clamp(minVal, maxVal) & 0xFF;
        }
      }
    }

    swPre.stop();
    if (kDebugMode) {
      debugPrint(
        "⏱️ YUV Preprocessing completed in ${swPre.elapsedMilliseconds} ms",
      );
    }

    return PreprocessResult(
      inputBuffer: _inputBuffer!,
      letterbox: letterbox,
      preprocessMs: swPre.elapsedMilliseconds,
    );
  }

  /// Write padding pixel value.
  void _writePadPixel(
    bool writeFloat,
    Float32List? floatView,
    Uint8List? byteView,
    int floatIndex,
    int byteIndex,
    int pVal,
  ) {
    if (writeFloat) {
      final double v = 114.0 / 255.0;
      floatView![floatIndex] = v;
      floatView[floatIndex + 1] = v;
      floatView[floatIndex + 2] = v;
    } else {
      final int pv = pVal & 0xFF;
      byteView![byteIndex] = pv;
      byteView[byteIndex + 1] = pv;
      byteView[byteIndex + 2] = pv;
    }
  }
}
