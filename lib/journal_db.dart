import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-only journal store. One row per day (date = YYYY-MM-DD).
/// ponytail: local sqflite, no cloud sync — add sync only if he switches phones.
class JournalEntry {
  JournalEntry({required this.date, required this.body, required this.updatedAt});
  final String date;
  final String body;
  final String updatedAt;
}

class JournalDb {
  JournalDb._(this._db);
  final Database _db;
  static JournalDb? _instance;

  static Future<JournalDb> open() async {
    if (_instance != null) return _instance!;
    final path = p.join(await getDatabasesPath(), 'journal.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE entries('
        'date TEXT PRIMARY KEY, body TEXT NOT NULL, updated_at TEXT NOT NULL)',
      ),
    );
    return _instance = JournalDb._(db);
  }

  static String dateKey([DateTime? d]) {
    final n = d ?? DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<String> get(String date) async {
    final rows = await _db.query('entries',
        columns: ['body'], where: 'date = ?', whereArgs: [date], limit: 1);
    return rows.isEmpty ? '' : rows.first['body'] as String;
  }

  Future<void> save(String date, String body) async {
    final now = DateTime.now().toIso8601String();
    if (body.trim().isEmpty) {
      await _db.delete('entries', where: 'date = ?', whereArgs: [date]);
      return;
    }
    await _db.insert(
      'entries',
      {'date': date, 'body': body, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<JournalEntry>> all() async {
    final rows = await _db.query('entries', orderBy: 'date DESC');
    return rows
        .map((r) => JournalEntry(
              date: r['date'] as String,
              body: r['body'] as String,
              updatedAt: r['updated_at'] as String,
            ))
        .toList();
  }
}
