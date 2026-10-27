import 'package:image_picker/image_picker.dart';

import '../../domain/models/parsed_receipt.dart';
import '../parser/receipt_parser.dart';
import 'image_preprocessor.dart';
import 'ocr_engine.dart';

/// Hasil satu kali pemindaian.
class ScanResult {
  ScanResult({required this.imagePath, required this.parsed});
  final String imagePath; // gambar yang sudah di-crop & dikompres
  final ParsedReceipt parsed;
}

/// Orkestrasi: ambil gambar -> crop -> kompres -> OCR -> parse.
/// Dipecah menjadi langkah agar UI bisa menampilkan progres.
class OcrService {
  OcrService({ImagePicker? picker, ImagePreprocessor? preprocessor, OcrEngine? engine})
      : _picker = picker ?? ImagePicker(),
        _pre = preprocessor ?? ImagePreprocessor(),
        _engine = engine ?? OcrEngine.forPlatform();

  final ImagePicker _picker;
  final ImagePreprocessor _pre;
  final OcrEngine _engine;

  ImagePreprocessor get preprocessor => _pre;

  /// Langkah 1: ambil dari kamera/galeri. null = dibatalkan.
  Future<String?> pick(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 3000, imageQuality: 95);
    return x?.path;
  }

  /// Langkah 2: crop. null = dibatalkan.
  Future<String?> crop(String path) => _pre.crop(path);

  /// Langkah 3: kompres + OCR + parse.
  Future<ScanResult> process(String path, ReceiptParser parser) async {
    final compressed = await _pre.compress(path);
    final text = await _engine.recognize(compressed);
    return ScanResult(imagePath: compressed, parsed: parser.parse(text));
  }
}
