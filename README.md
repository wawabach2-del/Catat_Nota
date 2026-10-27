# CatatNota (ganti dengan nama aplikasi Anda)

Foto struk/nota → OCR on-device → form koreksi → database lokal → Excel (.xlsx) dan/atau Google Sheets.
Flutter, satu codebase Android + iOS, offline-first.

> **Status:** kode ditulis tanpa Flutter SDK di lingkungan penulisnya, jadi **belum pernah dikompilasi atau dijalankan**.
> Kemungkinan perlu perbaikan kecil (versi paket, nama API). Mulai dengan `flutter pub get && flutter analyze && flutter test`.

## 1. Struktur folder

```
lib/
├─ main.dart                      # init DB, prefs, ProviderScope
├─ app.dart                       # MaterialApp, tema, aktifkan auto-sync
├─ core/
│  ├─ constants.dart              # nama app, header kolom, mata uang, dsb.
│  ├─ formatters.dart             # format uang & tanggal
│  └─ permissions.dart            # izin kamera (+ buka Settings bila ditolak permanen)
├─ domain/models/                 # Transaction, Category, SyncQueueItem, AppSettings, ParsedReceipt
├─ data/
│  ├─ local/app_database.dart     # skema SQLite + kategori awal
│  └─ repositories/               # transaction, category, sync_queue, settings
├─ services/
│  ├─ ocr/                        # ocr_engine (ML Kit / Vision), image_preprocessor, ocr_service
│  ├─ parser/receipt_parser.dart  # teks OCR -> data terstruktur
│  ├─ export/excel_export_service.dart
│  └─ sheets/                     # google_auth_service, google_sheets_service, sync_service
└─ presentation/
   ├─ providers.dart              # Riverpod: repo, service, state, sync controller
   ├─ screens/                    # app_shell, home, scan, review, history, settings
   └─ widgets/export_sheet.dart
ios/Runner/VisionOcr.swift        # Apple Vision OCR (MethodChannel)
ios/Runner/AppDelegate.swift      # mendaftarkan channel
test/receipt_parser_test.dart
```

Alur data: `Scan → crop → kompres → OCR → ReceiptParser → ReviewScreen → TransactionRepository (SQLite)
→ sync_queue → SyncService → Google Sheets`. Penyimpanan lokal selalu terjadi lebih dulu, jadi semua fitur inti jalan tanpa internet.

## 2. Menyiapkan proyek

Folder ini hanya berisi `lib/`, `test/`, `pubspec.yaml`, dan file iOS native. Buat kerangka platform dulu, lalu timpa:

```bash
flutter create --org com.contoh --project-name catat_nota --platforms android,ios tmp_app
cp -rn tmp_app/android tmp_app/ios .        # -n: jangan timpa AppDelegate.swift & VisionOcr.swift yang sudah ada
rm -rf tmp_app
# Bila AppDelegate.swift bawaan template ingin dipakai, lihat catatan di dalam file AppDelegate.swift kita.
flutter pub get
flutter analyze && flutter test
```

Lalu **tambahkan `VisionOcr.swift` ke target Runner di Xcode** (Runner → klik kanan → Add Files to "Runner").

## 3. Izin dan konfigurasi platform

### Android

`android/app/build.gradle(.kts)`: `minSdk = 21` (syarat ML Kit).

`android/app/src/main/AndroidManifest.xml` (di dalam `<manifest>` dan `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-feature android:name="android.hardware.camera" android:required="false"/>

<application ...>
  <!-- Layar crop (image_cropper) -->
  <activity
      android:name="com.yalantis.ucrop.UCropActivity"
      android:screenOrientation="portrait"
      android:theme="@style/Theme.AppCompat.Light.NoActionBar"/>
</application>
```

* **Tidak ada izin penyimpanan.** Galeri memakai Photo Picker sistem; file Excel disimpan di folder privat aplikasi dan dibagikan lewat share sheet.
* Izin CAMERA diminta saat runtime oleh `PermissionHelper` (dengan dialog penjelasan dan jalan ke Settings bila ditolak permanen).
* Model OCR Latin sudah ikut di APK, jadi OCR bekerja tanpa internet.

### iOS

`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Kamera dipakai untuk memotret struk/nota yang akan dicatat.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Galeri dipakai untuk memilih foto struk/nota.</string>
```

`ios/Podfile`: set `platform :ios, '15.5'` dan aktifkan izin kamera untuk `permission_handler`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PERMISSION_CAMERA=1'
    end
  end
end
```

**Catatan OCR iOS:** pada iOS, OCR memakai Apple Vision (`VisionOcr.swift`), bukan ML Kit. Namun plugin
`google_mlkit_text_recognition` tetap ikut ter-link di iOS karena Flutter tidak bisa mengecualikan plugin per platform.
Pod ML Kit tidak punya slice arm64 untuk simulator, jadi di Mac Apple Silicon jalankan di **perangkat fisik**, atau
tambahkan `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` di Podfile dan jalankan simulator via Rosetta.
Jika ingin benar-benar bebas ML Kit di iOS, buat plugin lokal khusus Android yang membungkus ML Kit.

## 4. Google Sheets — OAuth 2.0 (tanpa service account)

Aplikasi memakai **Google Sign-In** (login pengguna). Tidak ada file JSON, client secret, atau token yang disimpan oleh kode
kita; token dikelola SDK Google di Keychain/Play Services. Pengaturan lokal hanya menyimpan ID spreadsheet dan nama tab (bukan kredensial).

1. [Google Cloud Console](https://console.cloud.google.com) → buat project → **APIs & Services → Library → aktifkan "Google Sheets API"**.
2. **OAuth consent screen**: tipe *External*, isi nama app, email, lalu tambahkan scope
   `https://www.googleapis.com/auth/spreadsheets`. Selama status *Testing*, tambahkan akun Anda di **Test users** (maks. 100).
3. **Credentials → Create credentials → OAuth client ID**:
   * **Android**: isi *package name* (applicationId) dan **SHA-1**.
     Debug: `cd android && ./gradlew signingReport`. Buat client terpisah untuk SHA-1 release / Play App Signing.
     Android tidak membutuhkan file apa pun di proyek.
   * **iOS**: isi *Bundle ID*. Catat **Client ID** dan **iOS URL scheme** (reversed client ID).
4. iOS — tambahkan ke `Info.plist` (ini identifier publik, bukan rahasia):

```xml
<key>GIDClientID</key>
<string>CLIENT_ID_IOS.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLSchemes</key>
  <array><string>com.googleusercontent.apps.CLIENT_ID_IOS</string></array>
</dict></array>
```

5. Di aplikasi: **Pengaturan → Hubungkan Google Sheets** → login → pilih *Buat baru* atau tempel URL/ID spreadsheet yang ada.
   Tombol *Putuskan* memanggil `disconnect()` yang mencabut akses di sisi Google dan mengosongkan antrean.

**Rilis publik:** scope `spreadsheets` termasuk *sensitive scope* → butuh verifikasi OAuth Google (beberapa hari–minggu).
Alternatif tanpa verifikasi berat: ganti ke scope `drive.file` di `google_auth_service.dart`; syaratnya aplikasi hanya bisa
mengakses spreadsheet yang **dibuat oleh aplikasi** (opsi "pakai yang ada" tidak akan berfungsi).

## 5. Perilaku penting

* **Offline-first:** simpan transaksi + masuk antrean dalam satu transaksi database. `SyncController` mencoba kirim saat
  aplikasi dibuka, setelah simpan, saat koneksi kembali (`connectivity_plus`), dan lewat tombol *Sinkron*. Item dikirim per
  batch 100 baris dalam satu request; hanya dihapus dari antrean setelah API sukses.
* **Google Sheets = log append-only.** Edit/hapus di aplikasi *tidak* mengubah baris yang sudah terkirim (diberi peringatan di UI).
  Bila perlu dua arah, tambahkan kolom ID dan operasi update/delete di antrean.
* **Excel:** hasil selalu berupa file baru di folder aplikasi lalu dibagikan (iOS/Android tidak mengizinkan menulis balik ke file
  yang dipilih). Opsi *Hanya yang belum diekspor* mencegah baris ganda. Paket `excel` dapat menghilangkan fitur lanjutan
  (chart/pivot) pada file buatan Excel desktop.
* **Parser** adalah heuristik (regex + kata kunci) untuk struk Indonesia. Akurasi tergantung kualitas foto; karena itu form
  Review selalu muncul. Peningkatan: koreksi salah-baca digit (O↔0, l↔1), daftar merchant, atau model ML.
* **Formula injection:** teks yang berawalan `= + - @` diberi apostrof sebelum dikirim ke Sheets.
* **Keamanan data:** database SQLite tidak terenkripsi; foto struk disimpan di folder privat aplikasi. Untuk enkripsi gunakan
  `sqflite_sqlcipher` dengan kunci di `flutter_secure_storage`.
* Nominal memakai `double`; untuk akuntansi ketat ganti ke integer satuan terkecil.

## 6. Ide pengembangan

Ringkasan per kategori/bulan (grafik), multi-item per struk, deteksi duplikat, backup/restore, enkripsi DB, sinkron dua arah.
