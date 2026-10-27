enum SyncStatus { pending, failed }

/// Satu item antrean sinkronisasi ke Google Sheets.
/// Item dihapus dari antrean setelah berhasil dikirim.
class SyncQueueItem {
  final int id;
  final String transactionId;
  final SyncStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;

  const SyncQueueItem({
    required this.id,
    required this.transactionId,
    required this.status,
    required this.attempts,
    this.lastError,
    required this.createdAt,
  });

  factory SyncQueueItem.fromMap(Map<String, Object?> m) => SyncQueueItem(
        id: m['id'] as int,
        transactionId: m['transaction_id'] as String,
        status: SyncStatus.values.byName(m['status'] as String),
        attempts: m['attempts'] as int,
        lastError: m['last_error'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
