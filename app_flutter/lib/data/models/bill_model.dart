import 'dart:convert';
import 'order_item_model.dart';
import 'order_action_log_model.dart';
import 'promotion_model.dart';

// ==================== BILL MODEL ====================
class BillModel {
  final String id;
  final String billCode; // Mã hóa đơn chính thức (HD-yyMMdd-HHmmss)
  final String? orderCode; // Mã đặt món / gọi món kiểm soát (OD-yyMMdd-HHmmss)
  final String tableName;
  final String zone;
  final int createdAt;
  int? closedAt;
  String status; // 'OPEN', 'PAID', 'CANCELLED', 'REFUNDED'
  final String staffUsername;
  final String staffFullName;
  List<OrderItemModel> items;
  int subTotal;
  List<BillDiscountModel> discounts;
  int totalDiscount;
  double vatRate;
  int vatAmount;
  int finalAmount;
  String paymentMethod; // 'CASH', 'TRANSFER_QR', 'CARD'
  String notes;
  final String? parentBillId; // If split
  final List<String>? mergedTableNames;
  int pointsUsed;
  int pointsDiscount;
  String? customerId;
  String? customerName;
  String? customerPhone;
  String? shiftId;
  List<OrderActionLogModel> actionLogs;

  BillModel({
    required this.id,
    required this.billCode,
    this.orderCode,
    required this.tableName,
    required this.zone,
    required this.createdAt,
    this.closedAt,
    this.status = 'OPEN',
    required this.staffUsername,
    required this.staffFullName,
    required this.items,
    required this.subTotal,
    this.discounts = const [],
    this.totalDiscount = 0,
    this.vatRate = 0.0,
    this.vatAmount = 0,
    required this.finalAmount,
    this.paymentMethod = 'CASH',
    this.notes = '',
    this.parentBillId,
    this.mergedTableNames,
    this.pointsUsed = 0,
    this.pointsDiscount = 0,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.shiftId,
    this.actionLogs = const [],
  });

  factory BillModel.fromMap(Map<dynamic, dynamic> map, String id) {
    List<OrderItemModel> items = [];
    if (map['items'] != null) {
      if (map['items'] is List) {
        items = (map['items'] as List).map((e) => OrderItemModel.fromMap(e)).toList();
      } else if (map['items'] is String) {
        try {
          final List list = jsonDecode(map['items']);
          items = list.map((e) => OrderItemModel.fromMap(e)).toList();
        } catch (_) {}
      }
    }

    List<BillDiscountModel> discounts = [];
    if (map['discounts'] != null) {
      if (map['discounts'] is List) {
        discounts = (map['discounts'] as List).map((e) => BillDiscountModel.fromMap(e)).toList();
      }
    }

    List<String>? merged;
    if (map['mergedTableNames'] != null && map['mergedTableNames'] is List) {
      merged = List<String>.from(map['mergedTableNames']);
    }

    List<OrderActionLogModel> actionLogs = [];
    if (map['actionLogs'] != null && map['actionLogs'] is List) {
      actionLogs = (map['actionLogs'] as List).map((e) => OrderActionLogModel.fromMap(e)).toList();
    } else if (map['actionLogsJson'] != null && map['actionLogsJson'] is String && (map['actionLogsJson'] as String).isNotEmpty) {
      try {
        final List list = jsonDecode(map['actionLogsJson']);
        actionLogs = list.map((e) => OrderActionLogModel.fromMap(e)).toList();
      } catch (_) {}
    }

    final rawBillCode = map['billCode']?.toString();
    final rawOrderCode = map['orderCode']?.toString();

    String billCode;
    String? orderCode = rawOrderCode;

    if (rawBillCode != null && rawBillCode.isNotEmpty && !rawBillCode.startsWith('OD-')) {
      billCode = rawBillCode;
    } else if (rawOrderCode != null && rawOrderCode.startsWith('HD-')) {
      billCode = rawOrderCode;
    } else if (rawBillCode != null && rawBillCode.isNotEmpty) {
      billCode = rawBillCode;
    } else {
      billCode = rawOrderCode ?? id;
    }

    if (orderCode == null && rawBillCode != null && rawBillCode.startsWith('OD-')) {
      orderCode = rawBillCode;
    }

    return BillModel(
      id: id,
      billCode: billCode,
      orderCode: orderCode,
      tableName: map['tableName']?.toString() ?? '',
      zone: map['zone']?.toString() ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      closedAt: (map['closedAt'] as num?)?.toInt(),
      status: map['status']?.toString() ?? 'OPEN',
      staffUsername: map['staffUsername']?.toString() ?? '',
      staffFullName: map['staffFullName']?.toString() ?? '',
      items: items,
      subTotal: (map['subTotal'] as num?)?.toInt() ?? (map['totalAmount'] as num?)?.toInt() ?? 0,
      discounts: discounts,
      totalDiscount: (map['totalDiscount'] as num?)?.toInt() ?? (map['discountAmount'] as num?)?.toInt() ?? 0,
      vatRate: (map['vatRate'] as num?)?.toDouble() ?? 0.0,
      vatAmount: (map['vatAmount'] as num?)?.toInt() ?? 0,
      finalAmount: (map['finalAmount'] as num?)?.toInt() ?? (map['totalAmount'] as num?)?.toInt() ?? 0,
      paymentMethod: map['paymentMethod']?.toString() ?? 'CASH',
      notes: map['notes']?.toString() ?? map['note']?.toString() ?? '',
      parentBillId: map['parentBillId']?.toString(),
      mergedTableNames: merged,
      pointsUsed: (map['pointsUsed'] as num?)?.toInt() ?? 0,
      pointsDiscount: (map['pointsDiscount'] as num?)?.toInt() ?? 0,
      customerId: map['customerId']?.toString(),
      customerName: map['customerName']?.toString(),
      customerPhone: map['customerPhone']?.toString(),
      shiftId: map['shiftId']?.toString(),
      actionLogs: actionLogs,
    );
  }

  String get note => notes;

  /// Danh sách nhân viên đã nhận order các món trong đơn
  String get orderStaffSummary {
    final staffNames = <String>{};
    for (final it in items) {
      if (it.orderedByName.isNotEmpty) {
        staffNames.add(it.orderedByName);
      }
    }
    if (staffNames.isNotEmpty) return staffNames.join(', ');
    return staffFullName.isNotEmpty ? staffFullName : staffUsername;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'billCode': billCode,
    if (orderCode != null) 'orderCode': orderCode,
    'tableName': tableName,
    'zone': zone,
    'createdAt': createdAt,
    if (closedAt != null) 'closedAt': closedAt,
    'status': status,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    'cashierName': staffFullName.isNotEmpty ? staffFullName : staffUsername,
    'orderStaff': orderStaffSummary,
    'items': items.map((e) => e.toMap()).toList(),
    'subTotal': subTotal,
    'discounts': discounts.map((e) => e.toMap()).toList(),
    'totalDiscount': totalDiscount,
    'vatRate': vatRate,
    'vatAmount': vatAmount,
    'finalAmount': finalAmount,
    'paymentMethod': paymentMethod,
    'notes': notes,
    'note': notes,
    if (parentBillId != null) 'parentBillId': parentBillId,
    if (mergedTableNames != null) 'mergedTableNames': mergedTableNames,
    if (pointsUsed > 0) 'pointsUsed': pointsUsed,
    if (pointsDiscount > 0) 'pointsDiscount': pointsDiscount,
    if (customerId != null) 'customerId': customerId,
    if (customerName != null) 'customerName': customerName,
    if (customerPhone != null) 'customerPhone': customerPhone,
    if (shiftId != null) 'shiftId': shiftId,
    'actionLogs': actionLogs.map((e) => e.toMap()).toList(),
    'actionLogsJson': jsonEncode(actionLogs.map((e) => e.toMap()).toList()),
  };

  void recalculateTotals() {
    subTotal = items.fold(0, (s, i) => s + i.itemTotal);
    totalDiscount = discounts.fold(0, (s, d) => s + d.amount) + pointsDiscount;
    if (totalDiscount > subTotal) totalDiscount = subTotal;
    final afterDiscount = subTotal - totalDiscount;
    vatAmount = (afterDiscount * (vatRate / 100)).round();
    finalAmount = afterDiscount + vatAmount;
  }
}
