import 'dart:io';

import 'package:sqflite/sqflite.dart' hide Transaction;

import '../../domain/models/transaction.dart';

/// Filter untuk layar Riwayat.
class TransactionFilter {
  final String query;
  final DateTime? from;
  final DateTime? to;
  final String? category;

  const TransactionFilter({this.query = '', this.from, this.to, this.category});

  bool get isEmpty => query.isEmpty && from == null && to == null && category == null;

  TransactionFilter copyWith({
    String? query,
    DateTime? from,
    DateTime? to,
    String? category,
    bool clearDates = false,
    bool clearCategory = false,
  }) =>
      TransactionFilter(
        query: query ?? this.query,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        category: clearCategory ? null : (category ?? this.category),
      );
}

/// CRUD transaksi. Insert + antrean sync dilakukan dalam SATU database
/// transaction agar tidak ada transaksi "yatim" tanpa antrean.
class TransactionRepository {
  TransactionRepository(this._db);
  final Database _db;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> insert(Transaction t, {required bool enqueueForSync}) async {
    await _db.transaction((txn) async {
      await txn.insert('transactions', t.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
      if (enqueueForSync) {
        await txn.insert('sync_queue', {
          'transaction_id': t.id,
          'status': 'pending',
          'attempts': 0,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// Update data. Catatan: baris yang SUDAH ada di Google Sheets tidak
  /// diubah di sana (Sheets diperlakukan sebagai log append-only).
  Future<void> update(Transaction t) async {
    await _db.update('transactions', t.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?', whereArgs: [t.id]);
  }

  Future<void> delete(String id) async {
    final rows = await _db.query('transactions', columns: ['image_path'], where: 'id = ?', whereArgs: [id]);
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]); // antrean ikut terhapus (CASCADE)
    final path = rows.isEmpty ? null : rows.first['image_path'] as String?;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {/* abaikan bila file sudah tidak ada */}
    }
  }

  Future<Transaction?> getById(String id) async {
    final rows = await _db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Transaction.fromMap(rows.first);
  }

  Future<List<Transaction>> query(TransactionFilter f, {int? limit, bool onlyNotExported = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (f.query.trim().isNotEmpty) {
      where.add('(merchant LIKE ? OR description LIKE ? OR notes LIKE ?)');
      final q = '%${f.query.trim()}%';
      args.addAll([q, q, q]);
    }
    if (f.from != null) {
      where.add('date >= ?');
      args.add(_iso(f.from!));
    }
    if (f.to != null) {
      where.add('date <= ?');
      args.add(_iso(f.to!));
    }
    if (f.category != null) {
      where.add('category = ?');
      args.add(f.category);
    }
    if (onlyNotExported) where.add('exported_at IS NULL');

    final rows = await _db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(Transaction.fromMap).toList();
  }

  /// Total pengeluaran dan jumlah transaksi dalam rentang tanggal (inklusif).
  Future<({double total, int count})> summary(DateTime from, DateTime to) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(SUM(total),0) AS s, COUNT(*) AS c FROM transactions WHERE date >= ? AND date <= ?',
      [_iso(from), _iso(to)],
    );
    return (total: (r.first['s'] as num).toDouble(), count: r.first['c'] as int);
  }

  Future<void> markExported(Iterable<String> ids) async {
    final now = DateTime.now().toIso8601String();
    final batch = _db.batch();
    for (final id in ids) {
      batch.update('transactions', {'exported_at': now}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }
}
