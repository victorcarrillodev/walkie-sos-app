import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'walkie_sos.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contactId TEXT,
            alias TEXT,
            filePath TEXT,
            isMe INTEGER, -- 1 si yo lo mandé, 0 si lo recibí
            timestamp TEXT
          )
        ''');
      },
    );
  }

  static Future<void> saveMessage(Map<String, dynamic> msg) async {
    final db = await database;
    await db.insert('messages', msg);
  }

  static Future<List<Map<String, dynamic>>> getMessages(String contactId) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'contactId = ?',
      whereArgs: [contactId],
      orderBy: 'timestamp ASC',
    );
  }
}