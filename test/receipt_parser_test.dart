import 'package:catat_nota/services/parser/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAmount', () {
    test('format Indonesia & internasional', () {
      expect(parseAmount('Rp 1.234.567,50'), 1234567.5);
      expect(parseAmount('1,234.50'), 1234.5);
      expect(parseAmount('12.500'), 12500);
      expect(parseAmount('12,50'), 12.5);
      expect(parseAmount('150000'), 150000);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('ReceiptParser', () {
    final parser = ReceiptParser(
      now: DateTime(2026, 10, 27),
      categoryKeywords: {'Belanja': ['indomaret'], 'Makanan & Minuman': ['kopi']},
    );

    const indomaret = '''
INDOMARET PLAZA
Jl. Merdeka No. 10 Jakarta
NPWP 01.234.567.8-901.000
SARI ROTI TAWAR 2 x 15.000 30.000
AQUA 600ML 1 x 4.000 4.000
TOTAL ITEM 3
SUB TOTAL 34.000
PPN 11% 3.740
TOTAL 37.740
TUNAI 50.000
KEMBALI 12.260
12/10/2026 14:32
''';

    test('struk minimarket', () {
      final r = parser.parse(indomaret);
      expect(r.merchant, 'INDOMARET PLAZA');
      expect(r.date, DateTime(2026, 10, 12));
      expect(r.subtotal, 34000);
      expect(r.tax, 3740);
      expect(r.total, 37740);
      expect(r.paymentMethod, 'Tunai');
      expect(r.category, 'Belanja');
    });

    test('tanggal bulan teks & fallback total', () {
      final r = parser.parse('KOPI KENANGAN\n5 Okt 2026\nLatte 28.000\nQRIS');
      expect(r.date, DateTime(2026, 10, 5));
      expect(r.total, 28000);
      expect(r.paymentMethod, 'QRIS');
      expect(r.category, 'Makanan & Minuman');
    });

    test('tanggal tidak valid ditolak', () {
      expect(parser.parse('TOKO X\n31/02/2026\nTOTAL 1.000').date, isNull);
    });
  });
}
