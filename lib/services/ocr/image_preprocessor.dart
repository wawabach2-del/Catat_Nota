import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Crop (UI native) dan kompres gambar sebelum OCR.
class ImagePreprocessor {
  /// Tampilkan UI crop. Mengembalikan null bila pengguna membatalkan.
  Future<String?> crop(String path) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Potong struk',
          toolbarColor: Colors.teal,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Potong struk'),
      ],
    );
    return cropped?.path;
  }

  /// Kecilkan sisi terpanjang ke ~1800px + JPEG kualitas 85.
  /// Cukup tajam untuk OCR, dan menghemat penyimpanan. Orientasi EXIF
  /// dikoreksi otomatis oleh flutter_image_compress.
  Future<String> compress(String path) async {
    final tmp = await getTemporaryDirectory();
    final target = p.join(tmp.path, 'scan_${DateTime.now().microsecondsSinceEpoch}.jpg');
    final out = await FlutterImageCompress.compressAndGetFile(
      path,
      target,
      quality: 85,
      minWidth: 1800,
      minHeight: 1800,
      format: CompressFormat.jpeg,
    );
    return out?.path ?? path; // bila gagal, pakai gambar asli
  }

  /// Simpan salinan permanen di folder privat aplikasi (tidak tampil di galeri).
  Future<String> persist(String path, String transactionId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'receipts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = p.join(dir.path, '$transactionId.jpg');
    await File(path).copy(dest);
    return dest;
  }
}
