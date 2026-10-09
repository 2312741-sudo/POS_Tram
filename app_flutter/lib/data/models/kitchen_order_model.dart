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
  final String? orderedBy; // Username của nhân viên gửi bếp
  final String? orderedByName; // Họ tên nhân viên gửi bếp
  final int? doneAt; // Thời điểm bếp bấm xong món
  bool pickedUp; // Đã lấy món mang ra bàn chưa
  final int? pickedUpAt; // Thời điểm lấy món
  final String? pickedUpBy; // Nhân viên nhận món

  KitchenOrderModel({
    this.firebaseKey,
    required this.tableName,
    this.orderCode,
    this.billCode,
    required this.itemsJson,
    required this.timestamp,
    this.isDone = false,
    this.note,
    this.orderedBy,
    this.orderedByName,
    this.doneAt,
    this.pickedUp = false,
    this.pickedUpAt,
    this.pickedUpBy,
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
      orderedBy: map['orderedBy']?.toString(),
      orderedByName: map['orderedByName']?.toString(),
      doneAt: (map['doneAt'] as num?)?.toInt(),
      pickedUp: map['pickedUp'] == true,
      pickedUpAt: (map['pickedUpAt'] as num?)?.toInt(),
      pickedUpBy: map['pickedUpBy']?.toString(),
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
    if (orderedBy != null) 'orderedBy': orderedBy,
    if (orderedByName != null) 'orderedByName': orderedByName,
    if (doneAt != null) 'doneAt': doneAt,
    'pickedUp': pickedUp,
    if (pickedUpAt != null) 'pickedUpAt': pickedUpAt,
    if (pickedUpBy != null) 'pickedUpBy': pickedUpBy,
  };

  KitchenOrderModel copyWith({
    String? firebaseKey,
    String? tableName,
    String? orderCode,
    String? billCode,
    String? itemsJson,
    int? timestamp,
    bool? isDone,
    String? note,
    String? orderedBy,
    String? orderedByName,
    int? doneAt,
    bool? pickedUp,
    int? pickedUpAt,
    String? pickedUpBy,
  }) {
    return KitchenOrderModel(
      firebaseKey: firebaseKey ?? this.firebaseKey,
      tableName: tableName ?? this.tableName,
      orderCode: orderCode ?? this.orderCode,
      billCode: billCode ?? this.billCode,
      itemsJson: itemsJson ?? this.itemsJson,
      timestamp: timestamp ?? this.timestamp,
      isDone: isDone ?? this.isDone,
      note: note ?? this.note,
      orderedBy: orderedBy ?? this.orderedBy,
      orderedByName: orderedByName ?? this.orderedByName,
      doneAt: doneAt ?? this.doneAt,
      pickedUp: pickedUp ?? this.pickedUp,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      pickedUpBy: pickedUpBy ?? this.pickedUpBy,
    );
  }

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
  DateTime? get doneDateTime => doneAt != null ? DateTime.fromMillisecondsSinceEpoch(doneAt!) : null;
  Duration? get doneAgo => doneAt != null ? DateTime.now().difference(doneDateTime!) : null;
}
