import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../domain/models/app_settings.dart';

/// Menyimpan pengaturan non-sensitif. TIDAK menyimpan token/kredensial.
class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  AppSettings load() => AppSettings(
        currencyCode: _prefs.getString('currency') ?? 'IDR',
        dateFormat: _prefs.getString('dateFormat') ?? 'dd/MM/yyyy',
        spreadsheetId: _prefs.getString('sheetId'),
        spreadsheetTitle: _prefs.getString('sheetTitle'),
        sheetName: _prefs.getString('sheetName') ?? kDefaultSheetName,
      );

  Future<void> save(AppSettings s) async {
    await _prefs.setString('currency', s.currencyCode);
    await _prefs.setString('dateFormat', s.dateFormat);
    await _prefs.setString('sheetName', s.sheetName);
    if (s.spreadsheetId == null) {
      await _prefs.remove('sheetId');
      await _prefs.remove('sheetTitle');
    } else {
      await _prefs.setString('sheetId', s.spreadsheetId!);
      await _prefs.setString('sheetTitle', s.spreadsheetTitle ?? '');
    }
  }
}
