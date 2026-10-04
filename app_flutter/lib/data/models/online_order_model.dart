import 'dart:convert';
import 'order_item_model.dart';

// ==================== ONLINE ORDER MODEL ====================
class OnlineOrderModel {
  final String? firebaseKey;
  final String tableName;
  final String tableZone;
  final String itemsJson;
  String status; // PENDING, CONFIRMED, COMPLETED, CANCELLED
  final String type; // ORDER, CALL_WAITER
  final int timestamp;
  final String? notes;

  OnlineOrderModel({
    this.firebaseKey,
    required this.tableName,
    required this.tableZone,
    required this.itemsJson,
    required this.status,
    required this.type,
    required this.timestamp,
    this.notes,
  });

  factory OnlineOrderModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return OnlineOrderModel(
      firebaseKey: key,
      tableName: map['tableName']?.toString() ?? '',
      tableZone: map['tableZone']?.toString() ?? '',
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      status: map['status']?.toString() ?? 'PENDING',
      type: map['type']?.toString() ?? 'ORDER',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'tableName': tableName,
    'tableZone': tableZone,
    'itemsJson': itemsJson,
    'status': status,
    'type': type,
    'timestamp': timestamp,
    if (notes != null) 'notes': notes,
  };

  List<OrderItemModel> get items {
    if (itemsJson.isEmpty || type == 'CALL_WAITER') return [];
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => OrderItemModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  bool get isPending => status == 'PENDING';
  bool get isCallWaiter => type == 'CALL_WAITER';
}
