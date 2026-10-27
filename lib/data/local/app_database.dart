import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Membuka database SQLite lokal dan membuat skema awal.
///
/// Database tidak dienkripsi. Bila data sangat sensitif, ganti `sqflite`
/// dengan `sqflite_sqlcipher` (API hampir sama).
class AppDatabase {
  static const _version = 1;

  static Future<Database> open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'catat_nota.db'),
      version: _version,
      onConfigure: (db) async {
        // Aktifkan foreign key (untuk ON DELETE CASCADE antrean sync).
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            merchant TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'Lainnya',
            subtotal REAL NOT NULL DEFAULT 0,
            tax REAL NOT NULL DEFAULT 0,
            total REAL NOT NULL,
            payment_method TEXT,
            notes TEXT NOT NULL DEFAULT '',
            image_path TEXT,
            raw_text TEXT,
            synced INTEGER NOT NULL DEFAULT 0,
            exported_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_tx_date ON transactions(date DESC)');
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color INTEGER NOT NULL,
            keywords TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT 'pending',
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
          )''');
        await _seedCategories(db);
      },
    );
  }

  static Future<void> _seedCategories(Database db) async {
    const seed = [
      ('Makanan & Minuman', 0xFFEF6C00, 'restoran,resto,cafe,kafe,kopi,warung,bakery,bakso,mie,ayam,pizza,burger'),
      ('Belanja', 0xFF1E88E5, 'indomaret,alfamart,alfamidi,supermarket,hypermart,mart,toko,minimarket'),
      ('Transportasi', 0xFF43A047, 'spbu,pertamina,shell,bensin,parkir,tol,grab,gojek,taxi'),
      ('Kesehatan', 0xFFE53935, 'apotek,farmasi,klinik,rumah sakit,kimia farma,guardian'),
      ('Utilitas', 0xFF8E24AA, 'pln,pdam,listrik,telkom,indihome,pulsa,internet'),
      ('Operasional', 0xFF546E7A, 'atk,fotokopi,percetakan,kantor'),
      ('Lainnya', 0xFF9E9E9E, ''),
    ];
    for (final (name, color, kw) in seed) {
      await db.insert('categories', {
        'id': 'seed_${name.hashCode.abs()}',
        'name': name,
        'color': color,
        'keywords': kw,
      });
    }
  }
}
