import 'package:sqflite/sqflite.dart';

import '../../domain/models/sync_queue_item.dart';
import '../../domain/models/transaction.dart';

/// Antrean sinkronisasi offline-first. Antrean hanya berisi item yang belum
/// terkirim; item sukses dihapus dan `transactions.synced` diset 1.
class SyncQueueRepository {
  SyncQueueRepository(this._db);
  final Database _db;

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM sync_queue')) ?? 0;

  Future<int> failedCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM sync_queue WHERE status = 'failed'")) ?? 0;

  Future<List<SyncQueueItem>> items() async {
    final rows = await _db.query('sync_queue', orderBy: 'id');
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// Transaksi yang menunggu dikirim, urut sesuai antrean.
  Future<List<Transaction>> pendingTransactions({int limit = 100}) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM sync_queue q
      JOIN transactions t ON t.id = q.transaction_id
      ORDER BY q.id LIMIT ?''', [limit]);
    return rows.map(Transaction.fromMap).toList();
  }

  /// Masukkan semua transaksi yang belum pernah tersinkron (mis. setelah
  /// pengguna baru menghubungkan Google Sheets).
  Future<int> enqueueAllUnsynced() => _db.rawInsert('''
      INSERT OR IGNORE INTO sync_queue (transaction_id, status, attempts, created_at)
      SELECT id, 'pending', 0, ? FROM transactions WHERE synced = 0''',
      [DateTime.now().toIso8601String()]);

  Future<void> markDone(Iterable<String> transactionIds) async {
    await _db.transaction((txn) async {
      for (final id in transactionIds) {
        await txn.delete('sync_queue', where: 'transaction_id = ?', whereArgs: [id]);
        await txn.update('transactions', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<void> markFailed(Iterable<String> transactionIds, String error) async {
    final batch = _db.batch();
    for (final id in transactionIds) {
      batch.rawUpdate(
        "UPDATE sync_queue SET attempts = attempts + 1, status = 'failed', last_error = ? WHERE transaction_id = ?",
        [error, id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Kosongkan antrean (dipakai saat Google Sheets diputus).
  Future<void> clear() => _db.delete('sync_queue');
}
