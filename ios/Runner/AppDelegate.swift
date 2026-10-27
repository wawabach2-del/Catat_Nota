import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Daftarkan channel Apple Vision OCR.
    if let controller = window?.rootViewController as? FlutterViewController {
      VisionOcr.register(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// CATATAN: template Flutter terbaru (UIScene / implicit engine) mengganti pola di atas.
// Bila `window?.rootViewController` bernilai nil, daftarkan channel di
// `didInitializeImplicitFlutterEngine(_ engineBridge:)` dengan:
//   VisionOcr.register(with: engineBridge.applicationRegistrar.messenger())
