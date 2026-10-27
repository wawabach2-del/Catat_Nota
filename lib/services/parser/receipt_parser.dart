import '../../domain/models/parsed_receipt.dart';

/// Mengubah string nominal gaya Indonesia/internasional menjadi double.
///   "Rp 1.234.567,50" -> 1234567.5     "1,234.50" -> 1234.5
///   "12.500"          -> 12500         "12,50"    -> 12.5
/// Mengembalikan null bila tidak ada angka.
double? parseAmount(String input) {
  var s = input.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (s.isEmpty || !RegExp(r'\d').hasMatch(s)) return null;
  s = s.replaceAll(RegExp(r'^[.,]+|[.,]+$'), '');

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    // Pemisah yang muncul paling akhir adalah desimal.
    final decimalIsComma = lastComma > lastDot;
    s = decimalIsComma ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
  } else if (lastDot >= 0 || lastComma >= 0) {
    final sep = lastDot >= 0 ? '.' : ',';
    final count = sep.allMatches(s).length;
    final digitsAfter = s.length - s.lastIndexOf(sep) - 1;
    if (count > 1 || digitsAfter == 3) {
      s = s.replaceAll(sep, ''); // pemisah ribuan
    } else {
      s = s.replaceAll(sep, '.'); // desimal
    }
  }
  return double.tryParse(s);
}

/// Parser heuristik untuk struk Indonesia (Indomaret, Alfamart, resto, SPBU, dll).
/// Bukan ML — hasilnya selalu ditampilkan di form agar pengguna bisa mengoreksi.
class ReceiptParser {
  ReceiptParser({this.categoryKeywords = const {}, DateTime? now}) : _now = now ?? DateTime.now();

  /// nama kategori -> kata kunci huruf kecil.
  final Map<String, List<String>> categoryKeywords;
  final DateTime _now;

  static final _amountRe = RegExp(r'(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)');
  static final _subtotalRe = RegExp(r'sub\s*-?\s*total|\bdpp\b|jumlah\s*harga', caseSensitive: false);
  static final _taxRe = RegExp(r'\b(ppn|pb\s?1|pajak|tax|vat)\b', caseSensitive: false);
  static final _totalStrongRe =
      RegExp(r'grand\s*total|total\s*(bayar|tagihan|belanja|akhir|pembayaran)|amount\s*due|total\s*due', caseSensitive: false);
  static final _totalRe = RegExp(r'\btotal\b|\bjumlah\b', caseSensitive: false);
  static final _notTotalRe = RegExp(
      r'sub\s*-?\s*total|total\s*(item|qty|diskon|hemat|potongan|barang)|jumlah\s*(item|qty|barang)|hemat|diskon',
      caseSensitive: false);
  static final _payLineRe =
      RegExp(r'\b(tunai|cash|kembali|kembalian|change|bayar|debit|kredit|card|qris)\b', caseSensitive: false);
  static final _skipMerchantRe = RegExp(
      r'^(jl\.?|jalan|telp|tel\.?|npwp|no\.?|struk|nota|invoice|receipt|kasir|tanggal|date|www\.|http)',
      caseSensitive: false);

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'mei': 5, 'may': 5, 'jun': 6, 'jul': 7,
    'agu': 8, 'agt': 8, 'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10, 'nov': 11, 'des': 12, 'dec': 12,
  };

  ParsedReceipt parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final date = _findDate(lines);
    final merchant = _findMerchant(lines);
    final tax = _findKeywordAmount(lines, (l) => _taxRe.hasMatch(l) && !_notTotalRe.hasMatch(l));
    var subtotal = _findKeywordAmount(lines, (l) => _subtotalRe.hasMatch(l));
    var total = _findTotal(lines) ?? _fallbackMaxAmount(lines);

    // Rekonsiliasi angka yang hilang.
    if (total == null && subtotal != null) total = subtotal + (tax ?? 0);
    if (subtotal == null && total != null) subtotal = total - (tax ?? 0);

    final description = _buildDescription(lines);
    final payment = _findPayment(raw);
    final category = _guessCategory('${merchant ?? ''} $raw'.toLowerCase());

    return ParsedReceipt(
      date: date,
      merchant: merchant,
      description: description,
      category: category,
      subtotal: subtotal,
      tax: tax,
      total: total,
      paymentMethod: payment,
      rawText: raw,
    );
  }

  // ---------- tanggal ----------
  DateTime? _findDate(List<String> lines) {
    final ymd = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})');
    final dmy = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})');
    final dMonY = RegExp(r'(\d{1,2})\s*[-/ ]?\s*([A-Za-z]{3,9})\s*[-/ ]?\s*(\d{2,4})');

    for (final l in lines) {
      var m = ymd.firstMatch(l);
      if (m != null) {
        final d = _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        if (d != null) return d;
      }
      m = dmy.firstMatch(l);
      if (m != null) {
        var day = int.parse(m[1]!), month = int.parse(m[2]!);
        final year = _fullYear(int.parse(m[3]!));
        if (month > 12 && day <= 12) {
          final t = day; day = month; month = t; // format m/d/y
        }
        final d = _validDate(year, month, day);
        if (d != null) return d;
      }
      m = dMonY.firstMatch(l);
      if (m != null) {
        final month = _months[m[2]!.substring(0, 3).toLowerCase()];
        if (month != null) {
          final d = _validDate(_fullYear(int.parse(m[3]!)), month, int.parse(m[1]!));
          if (d != null) return d;
        }
      }
    }
    return null;
  }

  int _fullYear(int y) => y < 100 ? 2000 + y : y;

  DateTime? _validDate(int y, int m, int d) {
    if (y < 2000 || y > _now.year + 1) return null;
    final dt = DateTime(y, m, d);
    return (dt.year == y && dt.month == m && dt.day == d) ? dt : null; // tolak limpahan (31 Feb, dst.)
  }

  // ---------- merchant ----------
  String? _findMerchant(List<String> lines) {
    for (final l in lines.take(6)) {
      final letters = RegExp(r'[A-Za-z]').allMatches(l).length;
      if (letters < 3 || letters / l.length < 0.5) continue;
      if (_skipMerchantRe.hasMatch(l)) continue;
      return l;
    }
    return null;
  }

  // ---------- nominal ----------
  /// Ambil nominal dari baris yang cocok; bila baris tidak punya angka, coba baris berikutnya.
  double? _findKeywordAmount(List<String> lines, bool Function(String) match, {bool last = false}) {
    double? found;
    for (var i = 0; i < lines.length; i++) {
      if (!match(lines[i])) continue;
      final v = _lastAmountIn(lines[i]) ?? (i + 1 < lines.length ? _lastAmountIn(lines[i + 1]) : null);
      if (v != null) {
        found = v;
        if (!last) return found;
      }
    }
    return found;
  }

  double? _findTotal(List<String> lines) {
    final strong = _findKeywordAmount(lines, (l) => _totalStrongRe.hasMatch(l) && !_notTotalRe.hasMatch(l), last: true);
    if (strong != null) return strong;
    return _findKeywordAmount(
        lines, (l) => _totalRe.hasMatch(l) && !_notTotalRe.hasMatch(l) && !_taxRe.hasMatch(l), last: true);
  }

  double? _lastAmountIn(String line) {
    final ms = _amountRe.allMatches(line).toList();
    if (ms.isEmpty) return null;
    return parseAmount(ms.last[0]!);
  }

  /// Cadangan: angka terbesar yang bukan tanggal/telepon/jam.
  double? _fallbackMaxAmount(List<String> lines) {
    double? best;
    for (final l in lines) {
      if (RegExp(r'\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}:\d{2}|\d{9,}').hasMatch(l)) continue;
      if (_payLineRe.hasMatch(l)) continue;
      final v = _lastAmountIn(l);
      if (v != null && v < 1e10 && (best == null || v > best)) best = v;
    }
    return best;
  }

  // ---------- deskripsi ----------
  String? _buildDescription(List<String> lines) {
    final items = <String>[];
    for (final l in lines.skip(1)) {
      if (_totalRe.hasMatch(l) || _subtotalRe.hasMatch(l) || _taxRe.hasMatch(l) || _payLineRe.hasMatch(l)) continue;
      final m = _amountRe.allMatches(l).toList();
      if (m.isEmpty) continue;
      var name = l.substring(0, m.first.start).trim();
      name = name.replaceFirst(RegExp(r'^\d+\s*[xX]?\s+'), ''); // buang qty di depan
      if (RegExp(r'[A-Za-z]{3,}').hasMatch(name) &&
          !RegExp(r'\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}').hasMatch(l) &&
          !_skipMerchantRe.hasMatch(name)) {
        items.add(name);
      }
    }
    if (items.isEmpty) return null;
    final shown = items.take(3).join(', ');
    return items.length > 3 ? '$shown +${items.length - 3} item' : shown;
  }

  // ---------- metode pembayaran ----------
  String? _findPayment(String raw) {
    const rules = <(String, String)>[
      (r'qris', 'QRIS'), (r'go-?\s?pay', 'GoPay'), (r'\bovo\b', 'OVO'), (r'\bdana\b', 'DANA'),
      (r'shopee\s?pay', 'ShopeePay'), (r'link\s?aja', 'LinkAja'),
      (r'debit', 'Debit'), (r'kredit|credit|visa|master\s?card', 'Kredit'), (r'transfer', 'Transfer'),
      (r'\btunai\b|\bcash\b', 'Tunai'),
    ];
    for (final (pattern, label) in rules) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(raw)) return label;
    }
    return null;
  }

  // ---------- kategori ----------
  String? _guessCategory(String haystack) {
    for (final e in categoryKeywords.entries) {
      if (e.value.any((k) => k.isNotEmpty && haystack.contains(k))) return e.key;
    }
    return null;
  }
}
