import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';
import '../models/alert_recording_model.dart';

class DatabaseService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'walkie_sos.db');
    return await openDatabase(
      path,
      version: 3, // ← v3: añade tabla alert_recordings
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS messages');
          await _createTables(db);
        }
        if (oldVersion < 3) {
          // Solo agrega la tabla nueva — no toca mensajes existentes
          await _createAlertRecordingsTable(db);
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        channelId TEXT NOT NULL,
        userId TEXT NOT NULL,
        alias TEXT NOT NULL,
        audioPath TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await _createAlertRecordingsTable(db);
  }

  Future<void> _createAlertRecordingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alert_recordings (
        id TEXT PRIMARY KEY,
        alertId TEXT NOT NULL,
        audioPath TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  // ── messages ──────────────────────────────────────────────────────────────

  Future<void> saveMessage(MessageModel message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MessageModel>> getMessagesByChannel(String channelId) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'channelId = ?',
      whereArgs: [channelId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  // ── alert_recordings ──────────────────────────────────────────────────────

  Future<void> saveAlertRecording(AlertRecordingModel rec) async {
    final db = await database;
    await db.insert(
      'alert_recordings',
      rec.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Devuelve el clip más reciente asociado a [alertId], o null si no existe.
  Future<AlertRecordingModel?> getRecordingByAlertId(String alertId) async {
    final db = await database;
    final maps = await db.query(
      'alert_recordings',
      where: 'alertId = ?',
      whereArgs: [alertId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AlertRecordingModel.fromMap(maps.first);
  }

  /// Devuelve TODAS las grabaciones locales, ordenadas por fecha desc.
  Future<List<AlertRecordingModel>> getAllRecordings() async {
    final db = await database;
    final maps = await db.query(
      'alert_recordings',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => AlertRecordingModel.fromMap(m)).toList();
  }
}