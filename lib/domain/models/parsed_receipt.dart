/// Hasil parsing teks OCR. Semua field bisa null bila tidak terdeteksi;
/// pengguna akan melengkapinya di form Review.
class ParsedReceipt {
  final DateTime? date;
  final String? merchant;
  final String? description;
  final String? category;
  final double? subtotal;
  final double? tax;
  final double? total;
  final String? paymentMethod;
  final String rawText;

  const ParsedReceipt({
    this.date,
    this.merchant,
    this.description,
    this.category,
    this.subtotal,
    this.tax,
    this.total,
    this.paymentMethod,
    this.rawText = '',
  });
}
