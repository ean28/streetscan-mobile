// lib/core/utils/image_utils.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

Future<File> compressAndSave(File src, String destPath,
    {int maxDim = 1280, int quality = 82}) async {
  final lastSeg = p.basename(destPath);
  final destDir = p.dirname(destPath);
  final tmpOut = '$destDir/_tmp_$lastSeg';

  final dir = Directory(destDir);
  if (!await dir.exists()) await dir.create(recursive: true);

  final result = await FlutterImageCompress.compressAndGetFile(
    src.absolute.path,
    tmpOut,
    quality: quality,
    keepExif: true,
  );

  if (result == null) {
    final copy = await src.copy(destPath);
    return copy;
  }

  final f = File(tmpOut);
  final saved = await f.copy(destPath);
  if (await f.exists()) await f.delete();
  return saved;
}

/// Loads an image widget safely from a file path, with a fallback icon.
Widget loadImage(String path, {double size = 80, BoxFit fit = BoxFit.cover}) {
  return FutureBuilder<bool>(
    future: File(path).exists(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return SizedBox(
          width: size,
          height: size,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (snapshot.hasData && snapshot.data == true) {
        return Image.file(
          File(path),
          width: size,
          height: size,
          fit: fit,
        );
      }
      return Container(
        width: size,
        height: size,
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image, size: 32, color: Colors.grey),
      );
    },
  );
}
