import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class MaintenanceEvent {
  const MaintenanceEvent({
    required this.id,
    required this.equipmentId,
    required this.type,
    required this.date,
    this.hours,
    this.notes,
    this.createdBy,
  });

  final String id;
  final String equipmentId;
  final String type;
  final DateTime date;
  final double? hours;
  final String? notes;
  final String? createdBy;

  factory MaintenanceEvent.fromMap(Map<String, dynamic> map) {
    return MaintenanceEvent(
      id: map['id']?.toString() ?? '',
      equipmentId: map['equipment_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      date: DateTime.tryParse(map['date']?.toString() ?? '') ??
          DateTime.now(),
      hours: (map['hours'] as num?)?.toDouble(),
      notes: map['notes']?.toString(),
      createdBy: map['created_by']?.toString(),
    );
  }
}

class MaintenanceService {
  const MaintenanceService(this._client);

  final SupabaseClient _client;

  Future<void> recordOilChange({
    required String equipmentId,
    required double hours,
    String? notes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('maintenance_events').insert({
      'equipment_id': equipmentId,
      'type': 'oil_change',
      'hours': hours,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (userId != null) 'created_by': userId,
    });
    await _client
        .from('equipment')
        .update({'last_oil_change_hours': hours}).eq('id', equipmentId);
  }

  Future<List<MaintenanceEvent>> fetchOilChanges(String equipmentId) async {
    final response = await _client
        .from('maintenance_events')
        .select()
        .eq('equipment_id', equipmentId)
        .eq('type', 'oil_change')
        .order('date', ascending: false);
    return (response as List)
        .whereType<Map>()
        .map((raw) => MaintenanceEvent.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }
}

final maintenanceService = MaintenanceService(Supa.i);
