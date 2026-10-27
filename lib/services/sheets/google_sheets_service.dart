import 'package:googleapis/sheets/v4.dart';
import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../domain/models/transaction.dart';

class SpreadsheetRef {
  SpreadsheetRef(this.id, this.title);
  final String id;
  final String title;
}

/// Pembungkus Google Sheets API v4. Semua request memakai HTTPS (googleapis).
/// Setiap method menerima [http.Client] terautentikasi dari GoogleAuthService.
class GoogleSheetsService {
  /// Ambil ID dari URL penuh (https://docs.google.com/spreadsheets/d/<ID>/edit)
  /// atau terima ID mentah.
  static String? extractId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(s);
    if (m != null) return m.group(1);
    return RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(s) ? s : null;
  }

  /// Verifikasi akses + pastikan tab [sheetName] ada + tulis header bila kosong.
  Future<SpreadsheetRef> prepare(http.Client client, String id, String sheetName) async {
    final api = SheetsApi(client);
    final ss = await api.spreadsheets.get(id, $fields: 'properties.title,sheets.properties.title');
    final exists = ss.sheets?.any((s) => s.properties?.title == sheetName) ?? false;
    if (!exists) {
      await api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(requests: [
          Request(addSheet: AddSheetRequest(properties: SheetProperties(title: sheetName))),
        ]),
        id,
      );
    }
    await _ensureHeader(api, id, sheetName);
    return SpreadsheetRef(id, ss.properties?.title ?? 'Spreadsheet');
  }

  /// Buat spreadsheet baru (berisi satu tab [sheetName] + header).
  Future<SpreadsheetRef> create(http.Client client, String title, String sheetName) async {
    final api = SheetsApi(client);
    final ss = await api.spreadsheets.create(Spreadsheet(
      properties: SpreadsheetProperties(title: title),
      sheets: [Sheet(properties: SheetProperties(title: sheetName))],
    ));
    await _ensureHeader(api, ss.spreadsheetId!, sheetName);
    return SpreadsheetRef(ss.spreadsheetId!, ss.properties?.title ?? title);
  }

  /// Tambahkan banyak baris dalam SATU request (hemat kuota & atomik).
  Future<void> append(http.Client client, String id, String sheetName, List<Transaction> items) async {
    if (items.isEmpty) return;
    final api = SheetsApi(client);
    await api.spreadsheets.values.append(
      ValueRange(values: items.map(_row).toList()),
      id,
      "'$sheetName'!A:H",
      // USER_ENTERED supaya "2026-10-12" menjadi tanggal sungguhan;
      // string dari OCR disanitasi di _safe() agar tidak dieksekusi sebagai rumus.
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  Future<void> _ensureHeader(SheetsApi api, String id, String sheetName) async {
    final range = "'$sheetName'!A1:H1";
    final cur = await api.spreadsheets.values.get(id, range);
    if (cur.values == null || cur.values!.isEmpty) {
      await api.spreadsheets.values.update(
        ValueRange(values: [kExportHeaders]),
        id,
        range,
        valueInputOption: 'RAW',
      );
    }
  }

  List<Object?> _row(Transaction t) => [
        '${t.date.year.toString().padLeft(4, '0')}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}',
        _safe(t.merchant),
        _safe(t.description),
        _safe(t.category),
        t.subtotal,
        t.tax,
        t.total,
        _safe(t.notes),
      ];

  /// Cegah formula injection: teks berawalan = + - @ diberi apostrof.
  String _safe(String s) => RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
}
