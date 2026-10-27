import 'package:sqflite/sqflite.dart';

import '../../domain/models/category.dart';

class CategoryRepository {
  CategoryRepository(this._db);
  final Database _db;

  Future<List<Category>> all() async {
    final rows = await _db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<void> upsert(Category c) =>
      _db.insert('categories', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Transaksi lama tetap menyimpan nama kategorinya (denormalisasi disengaja).
  Future<void> delete(String id) => _db.delete('categories', where: 'id = ?', whereArgs: [id]);
}
