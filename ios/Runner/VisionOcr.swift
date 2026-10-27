import Flutter
import UIKit
import Vision

/// OCR on-device memakai Apple Vision (iOS 13+).
/// Channel: "catatnota/vision_ocr" (harus sama dengan kVisionChannel di Dart).
final class VisionOcr {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "catatnota/vision_ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      recognize(path: path, result: result)
    }
  }

  private static func recognize(path: String, result: @escaping FlutterResult) {
    guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
      result(FlutterError(code: "BAD_IMAGE", message: "Tidak bisa membuka gambar", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
      let text = groupIntoRows(observations)
      DispatchQueue.main.async { result(text) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false   // angka/harga jangan "dikoreksi"
    // Bahasa Indonesia tersedia mulai iOS 16; pakai hanya bila didukung.
    if let supported = try? request.supportedRecognitionLanguages() {
      let wanted = ["id-ID", "en-US"].filter { supported.contains($0) }
      if !wanted.isEmpty { request.recognitionLanguages = wanted }
    }

    // Jalankan di background agar UI tidak macet.
    DispatchQueue.global(qos: .userInitiated).async {
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do { try handler.perform([request]) }
      catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Gabungkan observasi yang sejajar secara vertikal (nama barang + harga) menjadi satu baris.
  /// Koordinat Vision: origin kiri-bawah, nilai 0...1.
  private static func groupIntoRows(_ obs: [VNRecognizedTextObservation]) -> String {
    struct Item { let text: String; let box: CGRect }
    let items = obs.compactMap { o -> Item? in
      guard let top = o.topCandidates(1).first else { return nil }
      return Item(text: top.string, box: o.boundingBox)
    }.sorted { $0.box.midY > $1.box.midY }   // atas -> bawah

    var rows: [[Item]] = []
    for item in items {
      if let ref = rows.last?.first {
        let tolerance = 0.6 * min(ref.box.height, item.box.height)
        if abs(item.box.midY - ref.box.midY) <= tolerance {
          rows[rows.count - 1].append(item)
          continue
        }
      }
      rows.append([item])
    }
    return rows
      .map { $0.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: "  ") }
      .joined(separator: "\n")
  }
}
