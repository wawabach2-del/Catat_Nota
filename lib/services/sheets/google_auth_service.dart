import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth 2.0 lewat Google Sign-In.
///
/// * TIDAK ada service account / client secret di aplikasi.
/// * Token akses/refresh disimpan oleh SDK Google di Keychain (iOS) /
///   Play Services (Android); aplikasi tidak pernah menyentuh atau menyimpannya.
/// * Scope `spreadsheets` termasuk "sensitive scope": untuk rilis publik,
///   aplikasi perlu verifikasi OAuth di Google Cloud Console. Alternatif yang
///   lebih ringan adalah `drive.file` (hanya file yang dibuat aplikasi ini),
///   tetapi tidak bisa memakai spreadsheet lama milik pengguna.
class GoogleAuthService {
  GoogleAuthService()
      : _signIn = GoogleSignIn(scopes: const [SheetsApi.spreadsheetsScope]);

  final GoogleSignIn _signIn;

  String? get email => _signIn.currentUser?.email;

  /// Coba pulihkan sesi tanpa UI. true bila masih terhubung.
  Future<bool> restore() async {
    final acc = _signIn.currentUser ?? await _signIn.signInSilently();
    return acc != null;
  }

  /// Tampilkan layar login/persetujuan Google. null bila dibatalkan.
  Future<String?> connect() async {
    final acc = await _signIn.signIn();
    if (acc == null) return null;
    // Pastikan scope Sheets benar-benar diberikan (pengguna bisa menolak sebagian).
    final granted = await _signIn.requestScopes(const [SheetsApi.spreadsheetsScope]);
    return granted ? acc.email : null;
  }

  /// Putuskan dan CABUT akses di sisi Google.
  Future<void> disconnect() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      await _signIn.signOut();
    }
  }

  /// HTTP client terautentikasi (HTTPS). Wajib di-close() pemanggil.
  /// Mengembalikan null bila belum login / token tidak bisa diperbarui.
  Future<auth.AuthClient?> authenticatedClient() async {
    if (_signIn.currentUser == null && await _signIn.signInSilently() == null) return null;
    return _signIn.authenticatedClient();
  }
}
