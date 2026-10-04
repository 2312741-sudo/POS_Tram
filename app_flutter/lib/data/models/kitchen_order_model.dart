import 'dart:convert';
import 'order_item_model.dart';

// ==================== KITCHEN ORDER MODEL ====================
class KitchenOrderModel {
  final String? firebaseKey;
  final String tableName;
  final String? orderCode; // Mã đặt món (OD-...)
  final String? billCode; // Mã hóa đơn (HD-...)
  final String itemsJson;
  final int timestamp;
  bool isDone;
  final String? note;

  KitchenOrderModel({
    this.firebaseKey,
    required this.tableName,
    this.orderCode,
    this.billCode,
    required this.itemsJson,
    required this.timestamp,
    this.isDone = false,
    this.note,
  });

  factory KitchenOrderModel.fromMap(Map<dynamic, dynamic> map, {String? key}) {
    return KitchenOrderModel(
      firebaseKey: key,
      tableName: map['tableName']?.toString() ?? '',
      orderCode: map['orderCode']?.toString(),
      billCode: map['billCode']?.toString(),
      itemsJson: map['itemsJson']?.toString() ?? '[]',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      isDone: map['isDone'] == true,
      note: map['note']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'tableName': tableName,
    if (orderCode != null) 'orderCode': orderCode,
    if (billCode != null) 'billCode': billCode,
    'itemsJson': itemsJson,
    'timestamp': timestamp,
    'isDone': isDone,
    if (note != null) 'note': note,
  };

  List<OrderItemModel> get items {
    try {
      final List list = jsonDecode(itemsJson);
      return list.map((e) => OrderItemModel.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
  Duration get waitingTime => DateTime.now().difference(dateTime);
}
