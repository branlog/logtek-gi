import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_join_code.dart';
import '../models/membership_invite.dart';
import 'offline_storage.dart';

class RepositoryResult<T> {
  const RepositoryResult({
    required this.data,
    this.missingTables = const <String>[],
    this.error,
  });

  final T data;
  final List<String> missingTables;
  final Object? error;

  bool get hasMissingTables => missingTables.isNotEmpty;
  bool get hasError => error != null;
}

class CompanyMembership {
  const CompanyMembership({
    required this.id,
    required this.companyId,
    required this.role,
    required this.company,
  });

  final String? id;
  final String? companyId;
  final String? role;
  final Map<String, dynamic>? company;
}

class CompanyOverview {
  const CompanyOverview({
    this.membership,
    this.members = const <Map<String, dynamic>>[],
  });

  final CompanyMembership? membership;
  final List<Map<String, dynamic>> members;
}

class InventoryEntry {
  const InventoryEntry({
    required this.item,
    this.totalQty = 0,
    this.warehouseSplit = const <String, int>{},
  });

  final Map<String, dynamic> item;
  final int totalQty;
  final Map<String, int> warehouseSplit;

  InventoryEntry copyWith({
    int? totalQty,
    Map<String, int>? warehouseSplit,
  }) {
    return InventoryEntry(
      item: item,
      totalQty: totalQty ?? this.totalQty,
      warehouseSplit: warehouseSplit ?? this.warehouseSplit,
    );
  }
}

class CompanyRepository {
  CompanyRepository(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  User? get currentUser => _client.auth.currentUser;

  String? _cacheKey(String baseKey) {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return '$userId::$baseKey';
  }

  Future<void> _saveCacheForCurrentUser(String baseKey, Object data) async {
    final key = _cacheKey(baseKey);
    if (key == null) return;
    await OfflineStorage.instance.saveCache(key, data);
  }

  Future<dynamic> _readCacheForCurrentUser(String baseKey) async {
    final key = _cacheKey(baseKey);
    if (key == null) return null;
    return OfflineStorage.instance.readCache(key);
  }

  Future<RepositoryResult<CompanyOverview>> fetchCompanyOverview() async {
    final membershipResult = await _fetchMembership();
    if (membershipResult.hasMissingTables || membershipResult.hasError) {
      final cached = await _readCachedCompanyOverview();
      if (cached != null) {
        return RepositoryResult<CompanyOverview>(
          data: cached,
          missingTables: membershipResult.missingTables,
          error: membershipResult.error,
        );
      }
      return RepositoryResult<CompanyOverview>(
        data: CompanyOverview(membership: membershipResult.data),
        missingTables: membershipResult.missingTables,
        error: membershipResult.error,
      );
    }

    final membership = membershipResult.data;
    if (membership?.companyId == null) {
      final cached = await _readCachedCompanyOverview();
      if (cached != null) {
        return RepositoryResult<CompanyOverview>(data: cached);
      }
      return RepositoryResult<CompanyOverview>(
        data: CompanyOverview(membership: membership),
      );
    }
    final companyId = membership!.companyId!;

    List<Map<String, dynamic>> members = const <Map<String, dynamic>>[];
    try {
      final response = await _client.rpc(
        'list_company_members',
        params: {'p_company_id': companyId},
      );
      if (response is List) {
        members = response
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
      } else {
        members = const <Map<String, dynamic>>[];
      }
    } on PostgrestException catch (error) {
      final cached = await _readCachedCompanyOverview();
      return RepositoryResult<CompanyOverview>(
        data: cached ?? CompanyOverview(membership: membership),
        error: error,
      );
    }

    final overview =
        CompanyOverview(membership: membership, members: members);
    await _saveCacheForCurrentUser(
      OfflineCacheKeys.companyOverview,
      _companyOverviewToJson(overview),
    );
    return RepositoryResult<CompanyOverview>(data: overview);
  }

  Future<RepositoryResult<List<Map<String, dynamic>>>> fetchWarehouses() async {
    final membershipResult = await _fetchMembership();
    if (membershipResult.hasMissingTables || membershipResult.hasError) {
      final cached = await _readCachedMapList(OfflineCacheKeys.warehouses);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          missingTables: membershipResult.missingTables,
          error: membershipResult.error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        missingTables: membershipResult.missingTables,
        error: membershipResult.error,
      );
    }

    final membership = membershipResult.data;
    if (membership?.companyId == null) {
      final cached = await _readCachedMapList(OfflineCacheKeys.warehouses);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(data: cached);
      }
      return const RepositoryResult<List<Map<String, dynamic>>>(
        data: <Map<String, dynamic>>[],
      );
    }
    final companyId = membership!.companyId!;

    try {
      final response = await _client
          .from('warehouses')
          .select(
            'id, name, code, active, created_at',
          )
          .eq('company_id', companyId)
          .order('name');
      final rows = (response as List).cast<Map<String, dynamic>>();
      await _saveCacheForCurrentUser(OfflineCacheKeys.warehouses, rows);

      return RepositoryResult<List<Map<String, dynamic>>>(
        data: rows,
      );
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing = _extractMissingTable(error.message) ?? 'warehouses';
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: const <Map<String, dynamic>>[],
          missingTables: <String>[missing],
        );
      }
      final cached = await _readCachedMapList(OfflineCacheKeys.warehouses);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        error: error,
      );
    } catch (error) {
      final cached = await _readCachedMapList(OfflineCacheKeys.warehouses);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        error: error,
      );
    }
  }

  Future<RepositoryResult<List<InventoryEntry>>> fetchInventory() async {
    final membershipResult = await _fetchMembership();
    if (membershipResult.hasMissingTables || membershipResult.hasError) {
      final cached = await _readCachedInventoryEntries();
      if (cached != null) {
        return RepositoryResult<List<InventoryEntry>>(
          data: cached,
          missingTables: membershipResult.missingTables,
          error: membershipResult.error,
        );
      }
      return RepositoryResult<List<InventoryEntry>>(
        data: const <InventoryEntry>[],
        missingTables: membershipResult.missingTables,
        error: membershipResult.error,
      );
    }

    final membership = membershipResult.data;
    if (membership?.companyId == null) {
      final cached = await _readCachedInventoryEntries();
      if (cached != null) {
        return RepositoryResult<List<InventoryEntry>>(data: cached);
      }
      return const RepositoryResult<List<InventoryEntry>>(
        data: <InventoryEntry>[],
      );
    }
    final companyId = membership!.companyId!;

    List<Map<String, dynamic>> itemRows;
    try {
      final response = await _client
          .from('items')
          .select(
            'id, name, sku, unit, category, active, meta, created_at',
          )
          .eq('company_id', companyId)
          .order('name');
      itemRows = (response as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing = _extractMissingTable(error.message) ?? 'items';
        return RepositoryResult<List<InventoryEntry>>(
          data: const <InventoryEntry>[],
          missingTables: <String>[missing],
        );
      }
      final cached = await _readCachedInventoryEntries();
      if (cached != null) {
        return RepositoryResult<List<InventoryEntry>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<InventoryEntry>>(
        data: const <InventoryEntry>[],
        error: error,
      );
    } catch (error) {
      final cached = await _readCachedInventoryEntries();
      if (cached != null) {
        return RepositoryResult<List<InventoryEntry>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<InventoryEntry>>(
        data: const <InventoryEntry>[],
        error: error,
      );
    }

    var entries = itemRows
        .map(
          (item) => InventoryEntry(
            item: item,
          ),
        )
        .toList();

    try {
      final stockRows = await _client
          .from('stock')
          .select('item_id, warehouse_id, qty')
          .eq('company_id', companyId);
      final rows = (stockRows as List).cast<Map<String, dynamic>>();

      final grouped = <String, Map<String, int>>{};
      for (final row in rows) {
        final itemId = row['item_id'] as String?;
        if (itemId == null) continue;
        final warehouseId = row['warehouse_id'] as String? ?? 'warehouse';
        final rawQty = row['qty'];
        final qty =
            rawQty is num ? rawQty.round() : int.tryParse('$rawQty') ?? 0;
        final perWarehouse = grouped.putIfAbsent(
          itemId,
          () => <String, int>{},
        );
        perWarehouse[warehouseId] = (perWarehouse[warehouseId] ?? 0) + qty;
      }

      entries = entries.map((entry) {
        final itemId = entry.item['id'] as String?;
        if (itemId == null) return entry;
        final splits = grouped[itemId];
        if (splits == null) return entry;

        final total = splits.values.fold<int>(
          0,
          (acc, value) => acc + value,
        );
        return entry.copyWith(
          totalQty: total,
          warehouseSplit: splits,
        );
      }).toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        // Aucun stock disponible, on retourne juste les items.
        return RepositoryResult<List<InventoryEntry>>(
          data: entries,
          missingTables: <String>['stock'],
        );
      }
      return RepositoryResult<List<InventoryEntry>>(
        data: entries,
        error: error,
      );
    }

    final result = RepositoryResult<List<InventoryEntry>>(data: entries);
    await _saveCacheForCurrentUser(
      OfflineCacheKeys.inventory,
      _inventoryEntriesToJson(entries),
    );
    return result;
  }

  Future<RepositoryResult<List<MembershipInvite>>> fetchMembershipInvites({
    required String companyId,
  }) async {
    try {
      final response = await _client
          .from('membership_invites')
          .select(
            'id, company_id, email, role, status, user_uid, invited_by, created_at, responded_at',
          )
          .eq('company_id', companyId)
          .order('created_at', ascending: false);
      final rows = (response as List)
          .cast<Map<String, dynamic>>()
          .map(MembershipInvite.fromMap)
          .toList(growable: false);
      return RepositoryResult<List<MembershipInvite>>(data: rows);
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing =
            _extractMissingTable(error.message) ?? 'membership_invites';
        return RepositoryResult<List<MembershipInvite>>(
          data: const <MembershipInvite>[],
          missingTables: <String>[missing],
        );
      }
      return RepositoryResult<List<MembershipInvite>>(
        data: const <MembershipInvite>[],
        error: error,
      );
    }
  }

  Future<RepositoryResult<List<CompanyJoinCode>>> fetchJoinCodes({
    required String companyId,
  }) async {
    try {
      final response = await _client
          .from('company_join_codes')
          .select(
            'id, company_id, role, uses, max_uses, expires_at, revoked_at, created_at, code_hint, label',
          )
          .eq('company_id', companyId)
          .order('created_at', ascending: false);
      final rows = (response as List)
          .cast<Map<String, dynamic>>()
          .map(CompanyJoinCode.fromMap)
          .toList(growable: false);
      return RepositoryResult<List<CompanyJoinCode>>(data: rows);
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing =
            _extractMissingTable(error.message) ?? 'company_join_codes';
        return RepositoryResult<List<CompanyJoinCode>>(
          data: const <CompanyJoinCode>[],
          missingTables: <String>[missing],
        );
      }
      return RepositoryResult<List<CompanyJoinCode>>(
        data: const <CompanyJoinCode>[],
        error: error,
      );
    }
  }

  Future<RepositoryResult<List<Map<String, dynamic>>>> fetchEquipment() async {
    final membershipResult = await _fetchMembership();
    if (membershipResult.hasMissingTables || membershipResult.hasError) {
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        missingTables: membershipResult.missingTables,
        error: membershipResult.error,
      );
    }

    final membership = membershipResult.data;
    if (membership?.companyId == null) {
      final cached =
          await _readCachedMapList(OfflineCacheKeys.purchaseRequests);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(data: cached);
      }
      return const RepositoryResult<List<Map<String, dynamic>>>(
        data: <Map<String, dynamic>>[],
      );
    }
    final companyId = membership!.companyId!;

    try {
      final response = await _client
          .from('equipment')
          .select(
            'id, name, brand, model, serial, active, meta, created_at',
          )
          .eq('company_id', companyId)
          .order('name');
      final rows = (response as List).cast<Map<String, dynamic>>();

      return RepositoryResult<List<Map<String, dynamic>>>(
        data: rows,
      );
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing = _extractMissingTable(error.message) ?? 'equipment';
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: const <Map<String, dynamic>>[],
          missingTables: <String>[missing],
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        error: error,
      );
    }
  }

  Future<RepositoryResult<Map<String, dynamic>?>> fetchUserProfile() async {
    final user = currentUser;
    if (user == null) {
      return const RepositoryResult<Map<String, dynamic>?>(data: null);
    }

    try {
      final response = await _client
          .from('user_profiles')
          .select()
          .eq('user_uid', user.id)
          .maybeSingle();
      if (response == null) {
        return const RepositoryResult<Map<String, dynamic>?>(data: null);
      }
      return RepositoryResult<Map<String, dynamic>?>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final missing = _extractMissingTable(error.message) ?? 'user_profiles';
        return RepositoryResult<Map<String, dynamic>?>(
          data: null,
          missingTables: <String>[missing],
        );
      }
      return RepositoryResult<Map<String, dynamic>?>(
        data: null,
        error: error,
      );
    }
  }

  Future<RepositoryResult<List<Map<String, dynamic>>>>
      fetchPurchaseRequests() async {
    final membershipResult = await _fetchMembership();
    if (membershipResult.hasMissingTables || membershipResult.hasError) {
      final cached =
          await _readCachedMapList(OfflineCacheKeys.purchaseRequests);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          missingTables: membershipResult.missingTables,
          error: membershipResult.error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        missingTables: membershipResult.missingTables,
        error: membershipResult.error,
      );
    }

    final membership = membershipResult.data;
    if (membership?.companyId == null) {
      return const RepositoryResult<List<Map<String, dynamic>>>(
        data: <Map<String, dynamic>>[],
      );
    }
    final companyId = membership!.companyId!;

    try {
      final response = await _client
          .from('purchase_requests')
          .select(
            'id, name, qty, note, status, item_id, warehouse_id, purchased_at, created_at, warehouse:warehouses(id, name)',
          )
          .eq('company_id', companyId)
          .order('status')
          .order('created_at');
      final rows = (response as List).cast<Map<String, dynamic>>();
      await _saveCacheForCurrentUser(OfflineCacheKeys.purchaseRequests, rows);
      return RepositoryResult<List<Map<String, dynamic>>>(data: rows);
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        return const RepositoryResult<List<Map<String, dynamic>>>(
          data: <Map<String, dynamic>>[],
          missingTables: <String>['purchase_requests'],
        );
      }
      final cached =
          await _readCachedMapList(OfflineCacheKeys.purchaseRequests);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        error: error,
      );
    } catch (error) {
      final cached =
          await _readCachedMapList(OfflineCacheKeys.purchaseRequests);
      if (cached != null) {
        return RepositoryResult<List<Map<String, dynamic>>>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<List<Map<String, dynamic>>>(
        data: const <Map<String, dynamic>>[],
        error: error,
      );
    }
  }

  Future<RepositoryResult<CompanyMembership?>> _fetchMembership() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const RepositoryResult<CompanyMembership?>(
        data: null,
      );
    }

    try {
      final response = await _client
          .from('memberships')
          .select(
            'id, company_id, role, company:companies(*)',
          )
          .eq('user_uid', user.id)
          .maybeSingle();

      if (response == null) {
        return const RepositoryResult<CompanyMembership?>(
          data: null,
        );
      }

      final row = Map<String, dynamic>.from(response as Map);
      final companyMap = row['company'] as Map<String, dynamic>?;
      final membership = CompanyMembership(
        id: row['id'] as String?,
        companyId: row['company_id'] as String?,
        role: row['role'] as String?,
        company: companyMap,
      );
      await _saveCacheForCurrentUser(
        OfflineCacheKeys.membership,
        _membershipToJson(membership),
      );

      return RepositoryResult<CompanyMembership?>(
        data: membership,
      );
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        final inferred = _extractMissingTable(error.message);
        final tables = inferred != null
            ? <String>[inferred]
            : <String>['memberships', 'companies'];
        final cached = await _readCachedMembership();
        if (cached != null) {
          return RepositoryResult<CompanyMembership?>(
            data: cached,
            missingTables: tables,
          );
        }
        return RepositoryResult<CompanyMembership?>(
          data: null,
          missingTables: tables,
        );
      }
      final cached = await _readCachedMembership();
      if (cached != null) {
        return RepositoryResult<CompanyMembership?>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<CompanyMembership?>(
        data: null,
        error: error,
      );
    } catch (error) {
      final cached = await _readCachedMembership();
      if (cached != null) {
        return RepositoryResult<CompanyMembership?>(
          data: cached,
          error: error,
        );
      }
      return RepositoryResult<CompanyMembership?>(
        data: null,
        error: error,
      );
    }
  }

  bool _isMissingTable(PostgrestException error) {
    if (error.code == '42P01') return true;
    final message = error.message.toLowerCase();
    return message.contains('does not exist') && message.contains('relation');
  }

  String? _extractMissingTable(String message) {
    final match = RegExp(r'relation "?([a-zA-Z0-9_\.]+)"? does not exist')
        .firstMatch(message);
    if (match == null) return null;
    final raw = match.group(1);
    if (raw == null) return null;
    final parts = raw.split('.');
    return parts.isEmpty ? raw : parts.last;
  }

  Future<CompanyOverview?> _readCachedCompanyOverview() async {
    final raw =
        await _readCacheForCurrentUser(OfflineCacheKeys.companyOverview);
    final map = _coerceMap(raw);
    if (map == null) return null;
    return _companyOverviewFromJson(map);
  }

  Future<List<Map<String, dynamic>>?> _readCachedMapList(String key) async {
    final raw = await _readCacheForCurrentUser(key);
    if (raw == null) return null;
    final list = _decodeMapList(raw);
    if (list.isEmpty) return null;
    return list;
  }

  Future<List<InventoryEntry>?> _readCachedInventoryEntries() async {
    final raw = await _readCacheForCurrentUser(OfflineCacheKeys.inventory);
    return _inventoryEntriesFromJson(raw);
  }

  Future<CompanyMembership?> _readCachedMembership() async {
    final raw = await _readCacheForCurrentUser(OfflineCacheKeys.membership);
    final map = _coerceMap(raw);
    if (map == null) return null;
    return _membershipFromJson(map);
  }

  Map<String, dynamic> _companyOverviewToJson(CompanyOverview overview) {
    return <String, dynamic>{
      'membership': overview.membership != null
          ? _membershipToJson(overview.membership!)
          : null,
      'members': overview.members,
    };
  }

  CompanyOverview? _companyOverviewFromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    final membership = _membershipFromJson(_coerceMap(map['membership']));
    final members = _decodeMapList(map['members']);
    return CompanyOverview(membership: membership, members: members);
  }

  Map<String, dynamic> _membershipToJson(CompanyMembership membership) {
    return <String, dynamic>{
      'id': membership.id,
      'companyId': membership.companyId,
      'role': membership.role,
      'company': membership.company,
    };
  }

  CompanyMembership? _membershipFromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    return CompanyMembership(
      id: map['id'] as String?,
      companyId: map['companyId'] as String?,
      role: map['role'] as String?,
      company: map['company'] == null
          ? null
          : Map<String, dynamic>.from(map['company'] as Map),
    );
  }

  List<Map<String, dynamic>> _decodeMapList(dynamic input) {
    if (input is List) {
      return input
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _inventoryEntriesToJson(
    List<InventoryEntry> entries,
  ) {
    return entries
        .map(
          (entry) => <String, dynamic>{
            'item': entry.item,
            'totalQty': entry.totalQty,
            'warehouseSplit': entry.warehouseSplit,
          },
        )
        .toList(growable: false);
  }

  List<InventoryEntry>? _inventoryEntriesFromJson(dynamic input) {
    final list = _decodeMapList(input);
    if (list.isEmpty) return null;
    return list
        .map(
          (map) => InventoryEntry(
            item: Map<String, dynamic>.from(
              _coerceMap(map['item']) ?? const <String, dynamic>{},
            ),
            totalQty: (map['totalQty'] as num?)?.round() ?? 0,
            warehouseSplit: _decodeWarehouseSplit(map['warehouseSplit']),
          ),
        )
        .toList(growable: false);
  }

  Map<String, int> _decodeWarehouseSplit(dynamic input) {
    final map = _coerceMap(input);
    if (map == null) return const <String, int>{};
    return map.map(
      (key, value) => MapEntry(
        key,
        value is num ? value.round() : int.tryParse('$value') ?? 0,
      ),
    );
  }

  Map<String, dynamic>? _coerceMap(dynamic input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      return input.map(
        (key, value) => MapEntry('$key', value),
      );
    }
    return null;
  }
}
