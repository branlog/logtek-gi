import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_role.dart';

class CommandResult<T> {
  const CommandResult({this.data, this.error});

  final T? data;
  final Object? error;

  bool get ok => error == null;
}

class CompanyCommands {
  CompanyCommands(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<CommandResult<Map<String, dynamic>>> createCompany({
    required String name,
    String? shopDomain,
    String? shopId,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      return const CommandResult(error: 'Utilisateur non authentifié');
    }

    final payload = <String, dynamic>{
      'name': name.trim(),
      'owner_uid': currentUser.id,
      if (shopDomain != null && shopDomain.trim().isNotEmpty)
        'shop_domain': shopDomain.trim(),
      if (shopId != null && shopId.trim().isNotEmpty) 'shop_id': shopId.trim(),
    };

    try {
      final response =
          await _client.from('companies').insert(payload).select().single();
      final company = Map<String, dynamic>.from(response as Map);

      try {
        await _client.from('memberships').insert({
          'company_id': company['id'],
          'user_uid': currentUser.id,
          'role': 'owner',
        });
      } on PostgrestException catch (error) {
        return CommandResult(
          data: company,
          error:
              'Entreprise créée mais impossible d’ajouter le membership owner : ${error.message}',
        );
      }

      return CommandResult<Map<String, dynamic>>(data: company);
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> createWarehouse({
    required String companyId,
    required String name,
    String? code,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
    };

    try {
      final response =
          await _client.from('warehouses').insert(payload).select().single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateWarehouse({
    required String warehouseId,
    required Map<String, dynamic> patch,
  }) async {
    try {
      final response = await _client
          .from('warehouses')
          .update(patch)
          .eq('id', warehouseId)
          .select('id, name, code, active, created_at')
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
          error: 'Entrepôt introuvable ou déjà supprimé.',
        );
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<void>> deleteWarehouse({
    required String warehouseId,
  }) async {
    try {
      await _client.from('warehouses').delete().eq('id', warehouseId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> createInventorySection({
    required String companyId,
    required String warehouseId,
    required String name,
    String? code,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'warehouse_id': warehouseId,
      'name': name.trim(),
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
    };

    try {
      final response = await _client
          .from('inventory_sections')
          .insert(payload)
          .select(
            'id, name, code, active, warehouse_id, company_id, created_at',
          )
          .single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<void>> deleteInventorySection({
    required String sectionId,
  }) async {
    try {
      await _client.from('inventory_sections').delete().eq('id', sectionId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateInventorySection({
    required String sectionId,
    required Map<String, dynamic> patch,
  }) async {
    try {
      final response = await _client
          .from('inventory_sections')
          .update(patch)
          .eq('id', sectionId)
          .select('id, name, code, warehouse_id, active, created_at')
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
          error: 'Section introuvable ou déjà supprimée.',
        );
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> createItem({
    required String companyId,
    required String name,
    String? sku,
    String? unit,
    String? category,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      if (sku != null && sku.trim().isNotEmpty) 'sku': sku.trim(),
      if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
    };

    try {
      final response =
          await _client.from('items').insert(payload).select().single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<void>> deleteItem({
    required String companyId,
    required String itemId,
  }) async {
    try {
      await _client
          .from('stock')
          .delete()
          .eq('company_id', companyId)
          .eq('item_id', itemId);
      await _client
          .from('items')
          .delete()
          .eq('company_id', companyId)
          .eq('id', itemId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateItem({
    required String itemId,
    String? name,
    String? sku,
    Map<String, dynamic>? meta,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return const CommandResult(error: 'Nom requis.');
      }
      payload['name'] = trimmed;
    }
    if (sku != null) {
      payload['sku'] = sku.trim().isEmpty ? null : sku.trim();
    }
    if (meta != null) {
      payload['meta'] = meta;
    }
    if (payload.isEmpty) {
      return const CommandResult(error: 'Aucune modification fournie.');
    }

    try {
      final response = await _client
          .from('items')
          .update(payload)
          .eq('id', itemId)
          .select(
            'id, name, sku, unit, category, active, meta, created_at',
          )
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
            error: 'Pièce introuvable ou déjà supprimée.');
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateItemMeta({
    required String itemId,
    required Map<String, dynamic> meta,
  }) async {
    try {
      final response = await _client
          .from('items')
          .update({'meta': meta})
          .eq('id', itemId)
          .select(
            'id, name, sku, unit, category, active, meta, created_at',
          )
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
          error: 'Pièce introuvable ou déjà supprimée.',
        );
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<int>> applyStockDelta({
    required String companyId,
    required String itemId,
    required String warehouseId,
    required int delta,
    String? sectionId,
  }) async {
    if (delta == 0) {
      try {
        var query = _client
            .from('stock')
            .select('qty')
            .eq('company_id', companyId)
            .eq('item_id', itemId)
            .eq('warehouse_id', warehouseId);
        query = sectionId == null
            ? query.filter('section_id', 'is', null)
            : query.eq('section_id', sectionId);
        final existing = await query.maybeSingle();
        final currentQty =
            existing == null ? 0 : ((existing['qty'] as num?)?.round() ?? 0);
        return CommandResult<int>(data: currentQty);
      } on PostgrestException catch (error) {
        return CommandResult<int>(error: error.message);
      } catch (error) {
        return CommandResult<int>(error: error);
      }
    }

    try {
      var selectQuery = _client
          .from('stock')
          .select('id, qty')
          .eq('company_id', companyId)
          .eq('item_id', itemId)
          .eq('warehouse_id', warehouseId);
      selectQuery = sectionId == null
          ? selectQuery.filter('section_id', 'is', null)
          : selectQuery.eq('section_id', sectionId);
      final existing = await selectQuery.maybeSingle();

      final currentQty =
          existing == null ? 0 : ((existing['qty'] as num?)?.round() ?? 0);
      final newQty = currentQty + delta;

      if (existing == null && delta < 0) {
        return const CommandResult<int>(
          error: 'Impossible de retirer du stock inexistant pour cet entrepôt.',
        );
      }

      if (newQty < 0) {
        return const CommandResult<int>(
          error: 'Stock insuffisant pour cet entrepôt.',
        );
      }

      if (existing == null) {
        await _client.from('stock').insert({
          'company_id': companyId,
          'item_id': itemId,
          'warehouse_id': warehouseId,
          'section_id': sectionId,
          'qty': newQty,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        var updateQuery = _client
            .from('stock')
            .update({
              'qty': newQty,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('company_id', companyId)
            .eq('item_id', itemId)
            .eq('warehouse_id', warehouseId);
        updateQuery = sectionId == null
            ? updateQuery.filter('section_id', 'is', null)
            : updateQuery.eq('section_id', sectionId);
        await updateQuery;
      }

      return CommandResult<int>(data: newQty);
    } on PostgrestException catch (error) {
      return CommandResult<int>(error: error.message);
    } catch (error) {
      return CommandResult<int>(error: error);
    }
  }

  Future<CommandResult<int>> incrementStock({
    required String companyId,
    required String itemId,
    required String warehouseId,
    required int qty,
    String? sectionId,
  }) async {
    return applyStockDelta(
      companyId: companyId,
      itemId: itemId,
      warehouseId: warehouseId,
      delta: qty,
      sectionId: sectionId,
    );
  }

  Future<CommandResult<Map<String, dynamic>>> createEquipment({
    required String companyId,
    required String name,
    String? brand,
    String? model,
    String? serial,
    String? type,
    String? year,
    Map<String, dynamic>? meta,
  }) async {
    final payload = <String, dynamic>{
      'company_id': companyId,
      'name': name.trim(),
      if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (serial != null && serial.trim().isNotEmpty) 'serial': serial.trim(),
    };
    final metaMap = <String, dynamic>{};
    if (meta != null) metaMap.addAll(meta);
    if (type != null && type.trim().isNotEmpty) metaMap['type'] = type.trim();
    if (year != null && year.trim().isNotEmpty) metaMap['year'] = year.trim();
    if (metaMap.isNotEmpty) {
      payload['meta'] = metaMap;
    }

    try {
      final response =
          await _client.from('equipment').insert(payload).select().single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateEquipment({
    required String equipmentId,
    String? name,
    String? brand,
    String? model,
    String? serial,
    bool? active,
    String? type,
    String? year,
    Map<String, dynamic>? meta,
  }) async {
    final payload = <String, dynamic>{};

    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        return const CommandResult(error: 'Nom requis.');
      }
      payload['name'] = trimmed;
    }

    void handleOptional(String key, String? value) {
      if (value != null) {
        final trimmed = value.trim();
        payload[key] = trimmed.isEmpty ? null : trimmed;
      }
    }

    handleOptional('brand', brand);
    handleOptional('model', model);
    handleOptional('serial', serial);
    if (active != null) {
      payload['active'] = active;
    }
    final metaMap = <String, dynamic>{};
    if (meta != null) metaMap.addAll(meta);
    if (type != null && type.trim().isNotEmpty) metaMap['type'] = type.trim();
    if (year != null && year.trim().isNotEmpty) metaMap['year'] = year.trim();
    if (metaMap.isNotEmpty) {
      payload['meta'] = metaMap;
    }

    if (payload.isEmpty) {
      return const CommandResult(error: 'Aucune modification fournie.');
    }

    try {
      final response = await _client
          .from('equipment')
          .update(payload)
          .eq('id', equipmentId)
          .select(
            'id, company_id, name, brand, model, serial, active, meta, created_at',
          )
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
          error: 'Équipement introuvable ou déjà supprimé.',
        );
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<void>> deleteEquipment({
    required String equipmentId,
  }) async {
    try {
      await _client.from('equipment').delete().eq('id', equipmentId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST116') {
        // No row affected: treat as already deleted.
        return const CommandResult<void>(data: null);
      }
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updateEquipmentMeta({
    required String equipmentId,
    required Map<String, dynamic> meta,
  }) async {
    try {
      final response = await _client
          .from('equipment')
          .update({'meta': meta})
          .eq('id', equipmentId)
          .select(
            'id, company_id, name, brand, model, serial, active, meta, created_at',
          )
          .maybeSingle();
      if (response == null) {
        return const CommandResult(
          error: 'Équipement introuvable ou déjà supprimé.',
        );
      }
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST116') {
        return const CommandResult(
          error: 'Équipement introuvable ou déjà supprimé.',
        );
      }
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<void> logJournalEntry({
    required String companyId,
    required String scope,
    String? entityId,
    required String event,
    Map<String, dynamic>? payload,
    String? note,
  }) async {
    final currentUser = _client.auth.currentUser;
    final entry = <String, dynamic>{
      'company_id': companyId,
      'scope': scope,
      'event': event,
      if (entityId != null) 'entity_id': entityId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (payload != null && payload.isNotEmpty) 'payload': payload,
      if (currentUser != null) 'created_by': currentUser.id,
    };
    try {
      await _client.from('journal_entries').insert(entry);
    } catch (_) {
      // journal logging is best-effort
    }
  }

  Future<List<Map<String, dynamic>>> fetchJournalEntries({
    required String companyId,
    String? scope,
    String? entityId,
    int limit = 50,
    bool prefix = false,
  }) async {
    var query = _client
        .from('journal_entries')
        .select(
          'id, scope, entity_id, event, note, payload, created_at, created_by',
        )
        .eq('company_id', companyId);
    if (scope != null) {
      query = query.eq('scope', scope);
    }
    if (entityId != null && entityId.isNotEmpty) {
      if (prefix) {
        query = query.like('entity_id', '$entityId%');
      } else {
        query = query.eq('entity_id', entityId);
      }
    }
    final response =
        await query.order('created_at', ascending: false).limit(limit);
    return (response as List).cast<Map<String, dynamic>>();
  }

  Future<CommandResult<Map<String, dynamic>>> createPurchaseRequest({
    required String companyId,
    required String name,
    required int qty,
    String? warehouseId,
    String? sectionId,
    String? note,
    String? itemId,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      return const CommandResult(error: 'Utilisateur non authentifié');
    }

    final payload = <String, dynamic>{
      'company_id': companyId,
      'created_by': currentUser.id,
      'name': name.trim(),
      'qty': qty,
      if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
      if (warehouseId != null && warehouseId.isNotEmpty)
        'warehouse_id': warehouseId,
      if (sectionId != null && sectionId.isNotEmpty) 'section_id': sectionId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };

    try {
      final response = await _client
          .from('purchase_requests')
          .insert(payload)
          .select(
            'id, name, qty, note, status, item_id, warehouse_id, section_id, purchased_at, created_at, warehouse:warehouses(id, name), section:inventory_sections(id, name, warehouse_id)',
          )
          .single();

      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> updatePurchaseRequest({
    required String requestId,
    required Map<String, dynamic> patch,
  }) async {
    try {
      final response = await _client
          .from('purchase_requests')
          .update(patch)
          .eq('id', requestId)
          .select(
            'id, name, qty, note, status, item_id, warehouse_id, section_id, purchased_at, created_at, warehouse:warehouses(id, name), section:inventory_sections(id, name, warehouse_id)',
          )
          .maybeSingle();

      if (response == null) {
        return const CommandResult(
            error: 'Demande d’achat introuvable ou déjà supprimée.');
      }

      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<void>> deletePurchaseRequest({
    required String requestId,
  }) async {
    try {
      await _client.from('purchase_requests').delete().eq('id', requestId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> createMove({
    required String companyId,
    required String type,
    required String itemId,
    required int qty,
    String? warehouseFrom,
    String? warehouseTo,
    String? note,
    String? ref,
  }) async {
    final params = <String, dynamic>{
      'p_company_id': companyId,
      'p_type': type,
      'p_item_id': itemId,
      'p_qty': qty,
      if (warehouseFrom != null) 'p_warehouse_from': warehouseFrom,
      if (warehouseTo != null) 'p_warehouse_to': warehouseTo,
      if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
      if (ref != null && ref.trim().isNotEmpty) 'p_ref': ref.trim(),
    };

    try {
      final response = await _client.rpc('create_move', params: params);
      if (response is Map<String, dynamic>) {
        return CommandResult<Map<String, dynamic>>(data: response);
      }
      if (response is Map) {
        final normalized = <String, dynamic>{};
        response.forEach((key, value) {
          if (key == null) return;
          final keyStr = key.toString();
          if (keyStr.isEmpty) return;
          normalized[keyStr] = value;
        });
        return CommandResult<Map<String, dynamic>>(data: normalized);
      }
      return const CommandResult<Map<String, dynamic>>(
          data: <String, dynamic>{});
    } on PostgrestException catch (error) {
      return CommandResult(error: error.message);
    } catch (error) {
      return CommandResult(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> upsertUserProfile({
    required String userUid,
    String? firstName,
    String? lastName,
    String? role,
    String? phone,
    String? address,
  }) async {
    String? clean(String? value) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    }

    final payload = <String, dynamic>{
      'user_uid': userUid,
      'first_name': clean(firstName),
      'last_name': clean(lastName),
      'role': clean(role),
      'phone': clean(phone),
      'address': clean(address),
    };

    try {
      final response = await _client
          .from('user_profiles')
          .upsert(payload, onConflict: 'user_uid')
          .select()
          .single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error.message);
    } catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> addMembership({
    required String companyId,
    required String userUid,
    required String role,
  }) async {
    final trimmedUid = userUid.trim();
    if (trimmedUid.isEmpty) {
      return const CommandResult(error: 'UID utilisateur requis.');
    }
    final normalizedRole = role.trim().toLowerCase();
    if (!CompanyRoles.isValid(normalizedRole)) {
      return const CommandResult(error: 'Rôle invalide.');
    }

    final payload = <String, dynamic>{
      'company_id': companyId,
      'user_uid': trimmedUid,
      'role': normalizedRole,
    };

    try {
      final response = await _client
          .from('memberships')
          .insert(payload)
          .select('user_uid, role, created_at')
          .single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error.message);
    } catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error);
    }
  }

  Future<CommandResult<void>> updateMembershipRole({
    required String companyId,
    required String userUid,
    required String role,
  }) async {
    final trimmedUid = userUid.trim();
    if (trimmedUid.isEmpty) {
      return const CommandResult(error: 'UID utilisateur requis.');
    }
    final normalizedRole = role.trim().toLowerCase();
    if (!CompanyRoles.isValid(normalizedRole)) {
      return const CommandResult(error: 'Rôle invalide.');
    }

    final payload = <String, dynamic>{
      'role': normalizedRole,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final response = await _client
          .from('memberships')
          .update(payload)
          .eq('company_id', companyId)
          .eq('user_uid', trimmedUid)
          .select('user_uid')
          .maybeSingle();

      if (response == null) {
        return const CommandResult<void>(
          error: 'Membre introuvable ou déjà retiré.',
        );
      }

      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<void>> removeMembership({
    required String companyId,
    required String userUid,
  }) async {
    final trimmedUid = userUid.trim();
    if (trimmedUid.isEmpty) {
      return const CommandResult(error: 'UID utilisateur requis.');
    }

    try {
      final response = await _client
          .from('memberships')
          .delete()
          .eq('company_id', companyId)
          .eq('user_uid', trimmedUid)
          .select('user_uid')
          .maybeSingle();

      if (response == null) {
        return const CommandResult<void>(
          error: 'Membre introuvable ou déjà retiré.',
        );
      }

      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> inviteMemberByEmail({
    required String companyId,
    required String email,
    required String role,
    String? notes,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (!CompanyRoles.isValid(normalizedRole)) {
      return const CommandResult(error: 'Rôle invalide.');
    }
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      return const CommandResult(error: 'L’adresse e-mail est requise.');
    }

    try {
      final response = await _client.functions.invoke(
        'company-membership/invite',
        body: {
          'companyId': companyId,
          'email': trimmedEmail,
          'role': normalizedRole,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      final data = response.data;
      return CommandResult<Map<String, dynamic>>(
        data: data is Map<String, dynamic> ? data : <String, dynamic>{},
      );
    } on FunctionException catch (error) {
      final detail = error.details?.toString();
      return CommandResult<Map<String, dynamic>>(
        error: detail?.isNotEmpty == true
            ? detail
            : error.reasonPhrase ?? 'Erreur lors de l’envoi de l’invitation.',
      );
    } catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error);
    }
  }

  Future<CommandResult<void>> cancelMembershipInvite({
    required String inviteId,
  }) async {
    try {
      await _client.from('membership_invites').update({
        'status': 'cancelled',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', inviteId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<Map<String, dynamic>>> createJoinCode({
    required String companyId,
    required String role,
    required String codeHash,
    required String codeHint,
    String? label,
    int? maxUses,
    DateTime? expiresAt,
  }) async {
    final normalizedRole = role.trim().toLowerCase();
    if (!CompanyRoles.isValid(normalizedRole)) {
      return const CommandResult(error: 'Rôle invalide.');
    }
    if (codeHash.trim().isEmpty) {
      return const CommandResult(error: 'Code invalide.');
    }

    final payload = <String, dynamic>{
      'company_id': companyId,
      'role': normalizedRole,
      'code_hash': codeHash,
      'code_hint': codeHint,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (maxUses != null && maxUses > 0) 'max_uses': maxUses,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
    };

    try {
      final response = await _client
          .from('company_join_codes')
          .insert(payload)
          .select(
            'id, company_id, role, uses, max_uses, expires_at, revoked_at, created_at, code_hint, label',
          )
          .single();
      return CommandResult<Map<String, dynamic>>(
        data: Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error.message);
    } catch (error) {
      return CommandResult<Map<String, dynamic>>(error: error);
    }
  }

  Future<CommandResult<void>> revokeJoinCode({
    required String codeId,
  }) async {
    try {
      await _client.from('company_join_codes').update({
        'revoked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', codeId);
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      return CommandResult<void>(error: error.message);
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<void>> deleteJoinCode({
    required String codeId,
  }) async {
    Future<CommandResult<void>> fallbackDelete() async {
      try {
        final response = await _client
            .from('company_join_codes')
            .delete()
            .eq('id', codeId)
            .select('id')
            .maybeSingle();
        if (response == null) {
          return const CommandResult<void>(
            error: 'Code introuvable ou déjà supprimé.',
          );
        }
        return const CommandResult<void>(data: null);
      } on PostgrestException catch (error) {
        final detailText = error.details?.toString() ?? '';
        if (error.code == 'PGRST116' || detailText.contains('0 rows')) {
          return const CommandResult<void>(data: null);
        }
        return CommandResult<void>(error: error.message);
      } catch (error) {
        return CommandResult<void>(error: error);
      }
    }

    try {
      final result = await _client.rpc(
        'delete_join_code',
        params: {'p_code_id': codeId},
      );
      final deleted = result is bool
          ? result
          : result is int
              ? result > 0
              : result != null;
      if (!deleted) {
        return const CommandResult<void>(
          error: 'Code introuvable ou déjà supprimé.',
        );
      }
      return const CommandResult<void>(data: null);
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.contains('delete_join_code')) {
        return fallbackDelete();
      }
      return CommandResult<void>(error: error.message);
    } on FunctionException catch (error) {
      final detail = error.details?.toString();
      if ((detail ?? '').contains('delete_join_code')) {
        return fallbackDelete();
      }
      return CommandResult<void>(
        error: detail?.isNotEmpty == true
            ? detail
            : error.reasonPhrase ?? 'Impossible de supprimer ce code.',
      );
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<void>> joinCompanyWithCode({
    required String code,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const CommandResult(error: 'Code requis.');
    }

    try {
      await _client.functions.invoke(
        'company-membership',
        queryParameters: const {'route': 'join-code'},
        body: {'code': trimmed},
      );
      return const CommandResult<void>(data: null);
    } on FunctionException catch (error) {
      final detail = error.details?.toString();
      return CommandResult<void>(
        error: detail?.isNotEmpty == true
            ? detail
            : error.reasonPhrase ?? 'Impossible de rejoindre cette entreprise.',
      );
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }

  Future<CommandResult<void>> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account');
      return const CommandResult<void>(data: null);
    } on FunctionException catch (error) {
      final detail = error.details?.toString();
      return CommandResult<void>(
        error: detail?.isNotEmpty == true
            ? detail
            : error.reasonPhrase ?? 'Suppression impossible.',
      );
    } catch (error) {
      return CommandResult<void>(error: error);
    }
  }
}
