import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/constants.dart';

/// Abstraksi mesin OCR agar mudah diganti/di-mock saat testing.
abstract class OcrEngine {
  /// Mengembalikan teks per baris (baris visual yang sama digabung kiri->kanan).
  Future<String> recognize(String imagePath);

  /// Pilih mesin sesuai platform: Apple Vision di iOS, ML Kit di Android.
  factory OcrEngine.forPlatform() => Platform.isIOS ? VisionOcrEngine() : MlKitOcrEngine();
}

/// Android: Google ML Kit (on-device, tanpa internet).
class MlKitOcrEngine implements OcrEngine {
  @override
  Future<String> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final lines = [
        for (final block in result.blocks)
          for (final line in block.lines) _Line(line.text, line.boundingBox),
      ];
      return groupIntoRows(lines);
    } finally {
      await recognizer.close();
    }
  }
}

/// iOS: Apple Vision lewat MethodChannel (kode native: ios/Runner/VisionOcr.swift).
class VisionOcrEngine implements OcrEngine {
  static const _channel = MethodChannel(kVisionChannel);

  @override
  Future<String> recognize(String imagePath) async {
    final text = await _channel.invokeMethod<String>('recognize', {'path': imagePath});
    return text ?? '';
  }
}

class _Line {
  _Line(this.text, this.box);
  final String text;
  final Rect box;
}

/// Struk biasanya berbentuk "NAMA BARANG ........ HARGA". OCR sering memecah
/// nama dan harga menjadi dua blok terpisah; fungsi ini menggabungkannya
/// kembali berdasarkan posisi vertikal sehingga parser menerima satu baris utuh.
String groupIntoRows(List<_Line> lines) {
  final sorted = [...lines]..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
  final rows = <List<_Line>>[];
  for (final l in sorted) {
    if (rows.isNotEmpty) {
      final ref = rows.last.first.box;
      final tolerance = 0.6 * (l.box.height < ref.height ? l.box.height : ref.height);
      if ((l.box.center.dy - ref.center.dy).abs() <= tolerance) {
        rows.last.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return rows
      .map((r) => (r..sort((a, b) => a.box.left.compareTo(b.box.left))).map((l) => l.text).join('  '))
      .join('\n');
}
