import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// MODULE 4a — Local-First Encrypted Database (AES-256 via SQLCipher)
///
/// Everything (chats, prompts, recorded skills, provider settings) lives in
/// ONE encrypted database file. The master key is generated once with a
/// CSPRNG, stored in Android Keystore-backed secure storage, and NEVER
/// leaves the device on the free tier. Pro sync wraps payloads in a
/// user-derived AES key before upload (see E2eSyncService).
/// ─────────────────────────────────────────────────────────────────────────

class EncryptedDbService {
  static const _keyName = 'afa_master_key';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final EncryptedDbService instance = EncryptedDbService._();
  EncryptedDbService._();

  Database? _db;

  /// Call once at app startup (and from the overlay entrypoint).
  Future<Database> init() async {
    if (_db?.isOpen == true) return _db!;

    final masterKey = await _ensureMasterKey();
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'afa_encrypted.db');

    _db = await openDatabase(
      path,
      password: masterKey, // SQLCipher AES-256 (PRAGMA key)
      version: 1,
      onCreate: _onCreate,
    );
    return _db!;
  }

  /// 256-bit random key, base64-encoded, minted once.
  Future<String> _ensureMasterKey() async {
    final existing = await _secure.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final key = base64Url.encode(bytes);
    await _secure.write(key: _keyName, value: key);
    return key;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        provider_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE prompts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        system_prompt TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        steps_json TEXT NOT NULL,
        geo_schema TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE provider_settings (
        provider_id TEXT PRIMARY KEY,
        default_model TEXT,
        is_default INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE schedules (
        skill_id TEXT PRIMARY KEY REFERENCES skills(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,            -- 'daily' | 'once'
        next_run INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_messages_chat ON messages(chat_id, created_at)');
  }

  // ───────────── Chats ─────────────

  Future<String> newChat(String title) async {
    final id = _uuid();
    await _db!.insert('chats',
        {'id': id, 'title': title, 'created_at': DateTime.now().millisecondsSinceEpoch});
    return id;
  }

  Future<void> saveMessage(String chatId, String role, String content,
      {String? providerId}) async {
    await _db!.insert('messages', {
      'id': _uuid(),
      'chat_id': chatId,
      'role': role,
      'content': content,
      'provider_id': providerId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> messages(String chatId) =>
      _db!.query('messages',
          where: 'chat_id = ?', whereArgs: [chatId], orderBy: 'created_at');

  // ───────────── Skills (recorded macros) ─────────────

  Future<void> saveSkill(String id, String name, String description,
      List<Map<String, dynamic>> steps, String? geoSchema) async {
    await _db!.insert('skills', {
      'id': id,
      'name': name,
      'description': description,
      'steps_json': jsonEncode(steps),
      'geo_schema': geoSchema,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> skills() =>
      _db!.query('skills', orderBy: 'created_at DESC');

  Future<Map<String, dynamic>?> skill(String id) async {
    final rows = await _db!.query('skills', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  // ───────────── Prompts ─────────────

  Future<void> savePrompt(String name, String systemPrompt) async {
    await _db!.insert('prompts', {
      'id': _uuid(),
      'name': name,
      'system_prompt': systemPrompt,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> prompts() =>
      _db!.query('prompts', orderBy: 'created_at DESC');

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random.secure().nextInt(1 << 32).toRadixString(36);
}
