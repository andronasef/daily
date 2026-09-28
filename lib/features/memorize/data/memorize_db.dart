import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'memorize_models.dart';

/// Local-first SQLite database for memorization items, SRS scheduling & audio notes.
/// Follows ponytail offline-first philosophy: fast local reads and writes.
class MemorizeDb {
  MemorizeDb._(this._db);
  final Database _db;
  static MemorizeDb? _instance;

  static Future<MemorizeDb> open() async {
    if (_instance != null) return _instance!;
    final path = p.join(await getDatabasesPath(), 'memorize.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE memorize_items (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            verse TEXT NOT NULL,
            category TEXT,
            translation TEXT NOT NULL,
            audio_url TEXT,
            local_voice_path TEXT,
            recordings_json TEXT,
            source TEXT NOT NULL,
            created_at TEXT NOT NULL,
            state TEXT NOT NULL,
            repetition INTEGER NOT NULL,
            interval INTEGER NOT NULL,
            ease_factor REAL NOT NULL,
            due_date TEXT NOT NULL,
            last_reviewed_at TEXT,
            lapses INTEGER NOT NULL,
            streak INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              'ALTER TABLE memorize_items ADD COLUMN recordings_json TEXT;',
            );
          } catch (_) {}
        }
      },
      onOpen: (db) async {
        try {
          await db.execute(
            'ALTER TABLE memorize_items ADD COLUMN recordings_json TEXT;',
          );
        } catch (_) {}
      },
    );
    return _instance = MemorizeDb._(db);
  }

  /// Returns all memorization verses sorted by due date.
  Future<List<MemorizeVerse>> getAll() async {
    final rows = await _db.query(
      'memorize_items',
      orderBy: 'due_date ASC, created_at DESC',
    );
    return rows.map((r) => MemorizeVerse.fromMap(r)).toList();
  }

  /// Returns cards due for review today (or overdue / new cards).
  Future<List<MemorizeVerse>> getDueToday() async {
    final now = DateTime.now();
    final endOfToday = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    ).toIso8601String();

    final rows = await _db.query(
      'memorize_items',
      where: 'due_date <= ? OR state = ?',
      whereArgs: [endOfToday, SrsState.newCard.wireValue],
      orderBy: 'state ASC, due_date ASC',
    );
    return rows.map((r) => MemorizeVerse.fromMap(r)).toList();
  }

  Future<MemorizeVerse?> getById(String id) async {
    final rows = await _db.query(
      'memorize_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MemorizeVerse.fromMap(rows.first);
  }

  Future<void> upsert(MemorizeVerse verse) async {
    await _db.insert(
      'memorize_items',
      verse.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertAll(List<MemorizeVerse> verses) async {
    final batch = _db.batch();
    for (final v in verses) {
      batch.insert(
        'memorize_items',
        v.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> delete(String id) async {
    await _db.delete(
      'memorize_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteStarterVerses() async {
    await _db.delete(
      'memorize_items',
      where: 'id LIKE ? OR source = ?',
      whereArgs: ['starter_%', 'builtin'],
    );
  }

  Future<void> updateVoicePath(String id, String? path) async {
    await _db.update(
      'memorize_items',
      {'local_voice_path': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addRecordingToVerse(String verseId, VoiceRecording recording) async {
    final verse = await getById(verseId);
    if (verse == null) return;
    final updatedList = List<VoiceRecording>.from(verse.recordings)..add(recording);
    final updatedVerse = verse.copyWith(
      recordings: updatedList,
      localVoicePath: recording.localPath,
    );
    await upsert(updatedVerse);
  }

  Future<void> deleteRecordingFromVerse(String verseId, String recordingId) async {
    final verse = await getById(verseId);
    if (verse == null) return;
    final updatedList = verse.recordings.where((r) => r.id != recordingId).toList();
    final updatedVerse = verse.copyWith(
      recordings: updatedList,
      localVoicePath: updatedList.isNotEmpty ? updatedList.last.localPath : null,
    );
    await upsert(updatedVerse);
  }

  Future<void> updateRecordingInVerse(String verseId, VoiceRecording recording) async {
    final verse = await getById(verseId);
    if (verse == null) return;
    final updatedList = verse.recordings.map((r) => r.id == recording.id ? recording : r).toList();
    final updatedVerse = verse.copyWith(recordings: updatedList);
    await upsert(updatedVerse);
  }

  Future<List<MemorizeVerse>> search(String query) async {
    final q = '%${query.trim()}%';
    final rows = await _db.query(
      'memorize_items',
      where: 'title LIKE ? OR verse LIKE ? OR category LIKE ?',
      whereArgs: [q, q, q],
      orderBy: 'title ASC',
    );
    return rows.map((r) => MemorizeVerse.fromMap(r)).toList();
  }

  Future<List<MemorizeVerse>> getWithVoice() async {
    final rows = await _db.query(
      'memorize_items',
      where:
          '(local_voice_path IS NOT NULL AND local_voice_path != "") OR (audio_url IS NOT NULL AND audio_url != "")',
      orderBy: 'title ASC',
    );
    return rows.map((r) => MemorizeVerse.fromMap(r)).toList();
  }

  Future<MemorizeStats> getStats() async {
    final all = await getAll();
    final total = all.length;
    final dueCount = all.where((v) => v.isDue).length;
    final learningCount =
        all.where((v) => v.state == SrsState.learning).length;
    final masteredCount =
        all.where((v) => v.state == SrsState.mastered).length;

    // Calculate maximum active streak across items
    final maxStreak = all.isEmpty
        ? 0
        : all.map((v) => v.streak).reduce((a, b) => a > b ? a : b);

    return MemorizeStats(
      total: total,
      dueCount: dueCount,
      learningCount: learningCount,
      masteredCount: masteredCount,
      streakDays: maxStreak,
    );
  }
}
