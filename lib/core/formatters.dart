import 'package:intl/intl.dart';

import 'constants.dart';
import '../domain/models/app_settings.dart';

class Fmt {
  static String money(double v, AppSettings s) {
    final digits = kZeroDecimalCurrencies.contains(s.currencyCode) ? 0 : 2;
    return NumberFormat.currency(locale: 'id_ID', symbol: '${s.currencySymbol} ', decimalDigits: digits)
        .format(v);
  }

  static String date(DateTime d, AppSettings s) => DateFormat(s.dateFormat, 'id_ID').format(d);
}
