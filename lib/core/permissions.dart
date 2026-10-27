import 'package:permission_handler/permission_handler.dart';

enum PermissionResult { granted, denied, permanentlyDenied }

/// Meminta izin kamera dengan benar.
/// * Galeri tidak perlu izin: image_picker memakai Photo Picker (Android)
///   dan PHPicker (iOS) yang hanya memberi akses ke foto yang dipilih.
/// * Izin penyimpanan TIDAK diminta: file hasil export disimpan di folder
///   privat aplikasi lalu dibagikan lewat share sheet.
class PermissionHelper {
  static Future<PermissionResult> ensureCamera() async {
    var status = await Permission.camera.status;
    if (status.isGranted || status.isLimited) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;

    status = await Permission.camera.request();
    if (status.isGranted) return PermissionResult.granted;
    return status.isPermanentlyDenied ? PermissionResult.permanentlyDenied : PermissionResult.denied;
  }

  static Future<void> openSettings() => openAppSettings();
}
