/// Satu catatan pembukuan.
///
/// Catatan: nominal memakai `double` demi kesederhanaan (cukup untuk IDR dan
/// mata uang umum). Untuk akuntansi ketat, ganti dengan integer satuan terkecil.
class Transaction {
  final String id;
  final DateTime date; // hanya tanggal (jam diabaikan)
  final String merchant;
  final String description;
  final String category; // disimpan sebagai nama agar riwayat tidak rusak saat kategori dihapus
  final double subtotal;
  final double tax;
  final double total;
  final String? paymentMethod;
  final String notes;
  final String? imagePath; // salinan foto struk di folder privat aplikasi
  final String? rawText; // teks OCR mentah (untuk audit/debug)
  final bool synced; // sudah masuk Google Sheets?
  final DateTime? exportedAt; // terakhir diekspor ke Excel
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transaction({
    required this.id,
    required this.date,
    required this.merchant,
    this.description = '',
    this.category = 'Lainnya',
    this.subtotal = 0,
    this.tax = 0,
    required this.total,
    this.paymentMethod,
    this.notes = '',
    this.imagePath,
    this.rawText,
    this.synced = false,
    this.exportedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Transaction copyWith({
    DateTime? date,
    String? merchant,
    String? description,
    String? category,
    double? subtotal,
    double? tax,
    double? total,
    String? paymentMethod,
    String? notes,
    String? imagePath,
    String? rawText,
    bool? synced,
    DateTime? exportedAt,
    DateTime? updatedAt,
  }) =>
      Transaction(
        id: id,
        date: date ?? this.date,
        merchant: merchant ?? this.merchant,
        description: description ?? this.description,
        category: category ?? this.category,
        subtotal: subtotal ?? this.subtotal,
        tax: tax ?? this.tax,
        total: total ?? this.total,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        notes: notes ?? this.notes,
        imagePath: imagePath ?? this.imagePath,
        rawText: rawText ?? this.rawText,
        synced: synced ?? this.synced,
        exportedAt: exportedAt ?? this.exportedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, Object?> toMap() => {
        'id': id,
        'date': _isoDate(date),
        'merchant': merchant,
        'description': description,
        'category': category,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'payment_method': paymentMethod,
        'notes': notes,
        'image_path': imagePath,
        'raw_text': rawText,
        'synced': synced ? 1 : 0,
        'exported_at': exportedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Transaction.fromMap(Map<String, Object?> m) => Transaction(
        id: m['id'] as String,
        date: DateTime.parse(m['date'] as String),
        merchant: m['merchant'] as String,
        description: (m['description'] as String?) ?? '',
        category: (m['category'] as String?) ?? 'Lainnya',
        subtotal: (m['subtotal'] as num).toDouble(),
        tax: (m['tax'] as num).toDouble(),
        total: (m['total'] as num).toDouble(),
        paymentMethod: m['payment_method'] as String?,
        notes: (m['notes'] as String?) ?? '',
        imagePath: m['image_path'] as String?,
        rawText: m['raw_text'] as String?,
        synced: (m['synced'] as int) == 1,
        exportedAt: m['exported_at'] == null ? null : DateTime.parse(m['exported_at'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );
}
