import 'dart:async';

import 'connectivity_service.dart';
import 'offline_storage.dart';
import '../utils/async_utils.dart';

typedef OfflineActionHandler = Future<void> Function(
    Map<String, dynamic> payload);

class OfflineActionTypes {
  static const purchaseRequestCreate = 'purchase_request_create';
  static const purchaseRequestUpdate = 'purchase_request_update';
  static const purchaseRequestDelete = 'purchase_request_delete';
  static const purchaseRequestMarkToPlace = 'purchase_request_mark_to_place';
  static const inventoryStockDelta = 'inventory_stock_delta';
  static const inventoryDeleteItem = 'inventory_delete_item';
  static const inventorySectionCreate = 'inventory_section_create';
  static const inventorySectionUpdate = 'inventory_section_update';
  static const inventorySectionDelete = 'inventory_section_delete';
  static const inventoryItemCreate = 'inventory_item_create';
  static const inventoryItemMetaUpdate = 'inventory_item_meta_update';
  static const equipmentMetaUpdate = 'equipment_meta_update';
  static const equipmentDelete = 'equipment_delete';
  static const joinCodeDelete = 'join_code_delete';
  static const warehouseCreate = 'warehouse_create';
  static const equipmentCreate = 'equipment_create';
}

class OfflineActionsService {
  OfflineActionsService._();

  static final OfflineActionsService instance = OfflineActionsService._();

  final Map<String, OfflineActionHandler> _handlers =
      <String, OfflineActionHandler>{};
  bool _processing = false;
  bool _initialized = false;
  final StreamController<int> _queueController =
      StreamController<int>.broadcast();

  Stream<int> get onQueueChanged => _queueController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    ConnectivityService.instance.onStatusChange.listen((online) {
      if (online) {
        runDetached(processQueue());
      }
    });
    if (ConnectivityService.instance.isOnline) {
      await processQueue();
    }
  }

  void registerHandler(String type, OfflineActionHandler? handler) {
    if (handler == null) {
      _handlers.remove(type);
    } else {
      _handlers[type] = handler;
    }
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    await OfflineStorage.instance.enqueueAction(
      type: type,
      payload: payload,
    );
    await _notifyQueueLength();
    if (ConnectivityService.instance.isOnline) {
      await processQueue();
    }
  }

  Future<void> processQueue() async {
    if (_processing || !ConnectivityService.instance.isOnline) return;
    _processing = true;
    try {
      final actions = await OfflineStorage.instance.pendingActions();
      for (final action in actions) {
        final handler = _handlers[action.type];
        if (handler == null) continue;
        try {
          await handler(action.payload);
          await OfflineStorage.instance.markActionCompleted(action.id);
        } catch (error) {
          await OfflineStorage.instance.recordActionError(
            action.id,
            error.toString(),
          );
          break;
        }
      }
    } finally {
      _processing = false;
      await _notifyQueueLength();
    }
  }

  Future<void> _notifyQueueLength() async {
    final count = (await OfflineStorage.instance.pendingActions()).length;
    if (!_queueController.isClosed) {
      _queueController.add(count);
    }
  }
}
