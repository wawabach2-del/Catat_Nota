import '../../core/constants.dart';

/// Pengaturan pengguna. Tidak berisi token/kredensial apa pun:
/// token Google dikelola oleh google_sign_in di Keychain/Keystore sistem.
class AppSettings {
  final String currencyCode;
  final String dateFormat;
  final String? spreadsheetId;
  final String? spreadsheetTitle;
  final String sheetName;

  const AppSettings({
    this.currencyCode = 'IDR',
    this.dateFormat = 'dd/MM/yyyy',
    this.spreadsheetId,
    this.spreadsheetTitle,
    this.sheetName = kDefaultSheetName,
  });

  String get currencySymbol => kCurrencies[currencyCode] ?? currencyCode;
  bool get hasSpreadsheet => spreadsheetId != null;

  AppSettings copyWith({
    String? currencyCode,
    String? dateFormat,
    String? sheetName,
  }) =>
      AppSettings(
        currencyCode: currencyCode ?? this.currencyCode,
        dateFormat: dateFormat ?? this.dateFormat,
        spreadsheetId: spreadsheetId,
        spreadsheetTitle: spreadsheetTitle,
        sheetName: sheetName ?? this.sheetName,
      );

  /// Set / hapus spreadsheet tujuan (null = putus).
  AppSettings withSpreadsheet({String? id, String? title}) => AppSettings(
        currencyCode: currencyCode,
        dateFormat: dateFormat,
        spreadsheetId: id,
        spreadsheetTitle: title,
        sheetName: sheetName,
      );
}
