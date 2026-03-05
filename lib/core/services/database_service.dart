import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';

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
      version: 2, // ← subimos la versión para forzar recreación
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Borra la tabla vieja y la recrea limpia
        await db.execute('DROP TABLE IF EXISTS messages');
        await _createTables(db);
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
  }

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
}