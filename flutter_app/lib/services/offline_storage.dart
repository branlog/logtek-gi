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
  static const equipment = 'equipment';
  static const joinCodes = 'join_codes';
  static const membershipInvites = 'membership_invites';
  static const userProfile = 'user_profile';
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
  final Map<String, String> _idMappingCache = <String, String>{};

  Future<void> init() async {
    if (_db != null) return;
    final Directory dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'offline_cache.db');
    _db = await openDatabase(
      path,
      version: 2,
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
        await db.execute(
          'CREATE TABLE id_mappings ('
          'temp_id TEXT PRIMARY KEY,'
          'actual_id TEXT NOT NULL,'
          'created_at INTEGER NOT NULL'
          ')',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS id_mappings ('
            'temp_id TEXT PRIMARY KEY,'
            'actual_id TEXT NOT NULL,'
            'created_at INTEGER NOT NULL'
            ')',
          );
        }
      },
    );
    await _hydrateIdMappingCache();
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
    await db.delete('id_mappings');
    _idMappingCache.clear();
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

  /// Sauvegarde une préférence utilisateur
  Future<void> setPreference(String key, String value) async {
    final db = _requireDb();
    await db.insert(
      'cache_entries',
      {
        'key': 'pref::$key',
        'payload': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère une préférence utilisateur
  Future<String?> getPreference(String key) async {
    final db = _requireDb();
    final rows = await db.query(
      'cache_entries',
      where: 'key = ?',
      whereArgs: <Object?>['pref::$key'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('OfflineStorage.init() doit être appelé avant usage.');
    }
    return db;
  }

  Future<void> saveIdMapping(String tempId, String actualId) async {
    final db = _requireDb();
    await db.insert(
      'id_mappings',
      {
        'temp_id': tempId,
        'actual_id': actualId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _idMappingCache[tempId] = actualId;
  }

  Future<String?> resolveIdMapping(String tempId) async {
    final cached = _idMappingCache[tempId];
    if (cached != null) return cached;
    final db = _requireDb();
    final rows = await db.query(
      'id_mappings',
      columns: const ['actual_id'],
      where: 'temp_id = ?',
      whereArgs: <Object?>[tempId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final actual = rows.first['actual_id'] as String?;
    if (actual != null) {
      _idMappingCache[tempId] = actual;
    }
    return actual;
  }

  Future<Map<String, String>> loadAllIdMappings() async {
    final db = _requireDb();
    final rows = await db.query('id_mappings');
    final map = <String, String>{};
    for (final row in rows) {
      final temp = row['temp_id'] as String?;
      final actual = row['actual_id'] as String?;
      if (temp != null && actual != null) {
        map[temp] = actual;
      }
    }
    _idMappingCache
      ..clear()
      ..addAll(map);
    return Map<String, String>.from(_idMappingCache);
  }

  Map<String, String> snapshotIdMappings() {
    return Map<String, String>.from(_idMappingCache);
  }

  Future<void> _hydrateIdMappingCache() async {
    try {
      await loadAllIdMappings();
    } catch (_) {
      // ignore cache load errors
    }
  }
}
