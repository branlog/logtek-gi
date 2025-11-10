import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class OfflineCacheKeys {
  static const membership = 'membership';
  static const companyOverview = 'company_overview';
  static const warehouses = 'warehouses';
  static const inventory = 'inventory';
  static const purchaseRequests = 'purchase_requests';
  static const journalEntries = 'journal_entries';
}

class PendingAction {
  PendingAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.lastError,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? lastError;
}

class OfflineStorage {
  OfflineStorage._();

  static final OfflineStorage instance = OfflineStorage._();

  final _uuid = const Uuid();
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final Directory dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'offline_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE cache_entries (key TEXT PRIMARY KEY, payload TEXT NOT NULL, updated_at INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE pending_actions ('
          'id TEXT PRIMARY KEY,'
          'action_type TEXT NOT NULL,'
          'payload TEXT NOT NULL,'
          'created_at INTEGER NOT NULL,'
          'last_error TEXT'
          ')',
        );
      },
    );
  }

  Future<void> saveCache(String key, Object data) async {
    final db = _requireDb();
    final payload = jsonEncode(data);
    await db.insert(
      'cache_entries',
      {
        'key': key,
        'payload': payload,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> readCache(String key) async {
    final db = _requireDb();
    final rows = await db.query(
      'cache_entries',
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = rows.first['payload'] as String?;
    if (payload == null || payload.isEmpty) return null;
    return jsonDecode(payload);
  }

  Future<void> clearCache(String key) async {
    final db = _requireDb();
    await db
        .delete('cache_entries', where: 'key = ?', whereArgs: <Object?>[key]);
  }

  Future<void> clearUserCache(String userId) async {
    final db = _requireDb();
    await db.delete(
      'cache_entries',
      where: 'key LIKE ?',
      whereArgs: <Object?>['$userId::%'],
    );
    await db.delete('pending_actions');
  }

  Future<String> enqueueAction({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final db = _requireDb();
    final id = _uuid.v4();
    await db.insert(
      'pending_actions',
      {
        'id': id,
        'action_type': type,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<List<PendingAction>> pendingActions() async {
    final db = _requireDb();
    final rows = await db.query(
      'pending_actions',
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => PendingAction(
            id: row['id'] as String,
            type: row['action_type'] as String,
            payload: Map<String, dynamic>.from(
              jsonDecode(row['payload'] as String) as Map,
            ),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            lastError: row['last_error'] as String?,
          ),
        )
        .toList(growable: false);
  }

  Future<void> markActionCompleted(String id) async {
    final db = _requireDb();
    await db
        .delete('pending_actions', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> recordActionError(String id, String message) async {
    final db = _requireDb();
    await db.update(
      'pending_actions',
      {'last_error': message},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('OfflineStorage.init() doit être appelé avant usage.');
    }
    return db;
  }
}
