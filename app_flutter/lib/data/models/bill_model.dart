import 'dart:convert';
import 'order_item_model.dart';
import 'order_action_log_model.dart';
import 'promotion_model.dart';
import '../../core/domain/deleted_items.dart';
import '../../core/domain/business_day.dart';

// ==================== PAYMENT SPLIT MODEL (MULTI-METHOD) ====================
class PaymentSplitModel {
  final String method; // 'CASH', 'TRANSFER_QR', 'CARD'
  final int amount;
  final String? note;

  PaymentSplitModel({
    required this.method,
    required this.amount,
    this.note,
  });

  factory PaymentSplitModel.fromMap(Map<dynamic, dynamic> map) {
    int asInt(Object? v) {
      if (v == null) return 0;
      if (v is num) return v.isNaN || v.isInfinite ? 0 : v.toInt();
      return int.tryParse(v.toString().trim()) ?? num.tryParse(v.toString().trim())?.toInt() ?? 0;
    }
    return PaymentSplitModel(
      method: map['method']?.toString() ?? 'CASH',
      amount: asInt(map['amount']),
      note: map['note']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'method': method,
    'amount': amount,
    if (note != null && note!.isNotEmpty) 'note': note,
  };
}

// ==================== BILL MODEL ====================
class BillModel {
  final String id;
  String billCode; // Mã hóa đơn chính thức (HD-yyMMdd-NNNN, cấp tuần tự khi thanh toán)
  final String? orderCode; // Mã đặt món / gọi món kiểm soát (OD-yyMMdd-HHmmss)
  final String tableName;
  final String zone;
  final int createdAt;
  int? closedAt;
  /// Thời điểm hủy đơn (epoch ms) — chỉ có với đơn CANCELLED.
  int? cancelledAt;
  String status; // 'OPEN', 'PAID', 'CANCELLED', 'REFUNDED'
  /// uid tài khoản thu tiền (HĐ cũ không có → so khớp theo staffUsername)
  final String? staffUid;
  final String staffUsername;
  final String staffFullName;
  final String? staffCode; // Mã nhân viên (VD: NV01, TN02)
  List<OrderItemModel> items;
  int subTotal;
  List<BillDiscountModel> discounts;
  int totalDiscount;
  double vatRate;
  int vatAmount;
  int finalAmount;
  String paymentMethod; // 'CASH', 'TRANSFER_QR', 'CARD', 'SPLIT'
  List<PaymentSplitModel>? paymentSplits; // Thanh toán hỗn hợp (VD: Tiền mặt + Chuyển khoản QR)
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
  /// Món đã lưu bị xóa trước khi chốt đơn (ghi cả với HĐ PAID và CANCELLED).
  List<DeletedItemEntry> deletedItems;

  BillModel({
    required this.id,
    required this.billCode,
    this.orderCode,
    required this.tableName,
    required this.zone,
    required this.createdAt,
    this.closedAt,
    this.cancelledAt,
    this.status = 'OPEN',
    this.staffUid,
    required this.staffUsername,
    required this.staffFullName,
    this.staffCode,
    required this.items,
    required this.subTotal,
    this.discounts = const [],
    this.totalDiscount = 0,
    this.vatRate = 0.0,
    this.vatAmount = 0,
    required this.finalAmount,
    this.paymentMethod = 'CASH',
    this.paymentSplits,
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
    this.deletedItems = const [],
  });

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is num) return v.isNaN || v.isInfinite ? null : v.toInt();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? num.tryParse(s)?.toInt();
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.isNaN || v.isInfinite ? null : v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static int? _asEpochMs(Object? v) {
    final n = _asInt(v);
    if (n != null && n > 0) return n;
    if (v is String && v.trim().isNotEmpty) {
      final dt = DateTime.tryParse(v.trim());
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return n;
  }

  static List<Map<dynamic, dynamic>> _asMapList(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<dynamic, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      return raw.values
          .whereType<Map>()
          .map((e) => Map<dynamic, dynamic>.from(e))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        return _asMapList(decoded);
      } catch (_) {}
    }
    return const [];
  }

  static String _normalizeStatus(Object? raw) {
    final s = raw?.toString().trim().toUpperCase() ?? '';
    if (s.isEmpty || s == 'PENDING') return 'OPEN';
    if (s == 'COMPLETED' || s == 'CLOSED' || s == 'SUCCESS') return 'PAID';
    if (s == 'CANCELED') return 'CANCELLED';
    return s;
  }

  factory BillModel.fromMap(Map<dynamic, dynamic> map, String id) {
    final List<OrderItemModel> items = [];
    final rawItems = map['items'] ?? map['itemsJson'] ?? map['currentOrderJson'];
    for (final itemMap in _asMapList(rawItems)) {
      try {
        items.add(OrderItemModel.fromMap(itemMap));
      } catch (_) {}
    }

    final List<BillDiscountModel> discounts = [];
    final rawDiscounts = map['discounts'] ?? map['discountsJson'];
    for (final discMap in _asMapList(rawDiscounts)) {
      try {
        discounts.add(BillDiscountModel.fromMap(discMap));
      } catch (_) {}
    }

    List<String>? merged;
    if (map['mergedTableNames'] is List) {
      merged = (map['mergedTableNames'] as List)
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList();
    } else if (map['mergedTableNames'] is Map) {
      merged = (map['mergedTableNames'] as Map)
          .values
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList();
    }

    final List<OrderActionLogModel> actionLogs = [];
    final rawActionLogs = map['actionLogs'] ?? map['actionLogsJson'];
    for (final logMap in _asMapList(rawActionLogs)) {
      try {
        actionLogs.add(OrderActionLogModel.fromMap(logMap));
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

    List<PaymentSplitModel>? splits;
    final rawSplits = _asMapList(map['paymentSplits']);
    if (rawSplits.isNotEmpty) {
      splits = [];
      for (final spMap in rawSplits) {
        try {
          splits.add(PaymentSplitModel.fromMap(spMap));
        } catch (_) {}
      }
      if (splits.isEmpty) splits = null;
    }

    final tableName = map['tableName']?.toString() ?? '';
    final parentBillId = map['parentBillId']?.toString();
    int? closedAt = _asEpochMs(map['closedAt']);
    final cancelledAt = _asEpochMs(map['cancelledAt']);
    final timestampFallback = _asEpochMs(map['timestamp']);
    final createdAt = _asEpochMs(map['createdAt']) ??
        timestampFallback ??
        closedAt ??
        cancelledAt ??
        0;
    String status = _normalizeStatus(map['status']);
    if (status == 'PAID' && closedAt == null && timestampFallback != null && timestampFallback > 0) {
      closedAt = timestampFallback;
    }
    final isLegacySplitBill =
        tableName.contains('(Tách)') || (parentBillId != null && parentBillId.trim().isNotEmpty);
    if (status == 'OPEN' && isLegacySplitBill) {
      status = 'PAID';
      closedAt ??= createdAt > 0 ? createdAt : null;
    }

    final itemsGross = items.fold<int>(0, (s, i) => s + (i.unitPrice * i.quantity));
    final parsedSubTotal = _asInt(map['subTotal']) ?? _asInt(map['totalAmount']);
    final subTotal = (parsedSubTotal != null && parsedSubTotal > 0)
        ? parsedSubTotal
        : (itemsGross > 0 ? itemsGross : (parsedSubTotal ?? 0));
    final totalDiscount = _asInt(map['totalDiscount']) ?? _asInt(map['discountAmount']) ?? 0;
    final vatRate = _asDouble(map['vatRate']) ?? 0.0;
    final vatAmount = _asInt(map['vatAmount']) ?? 0;
    final parsedFinalAmount = _asInt(map['finalAmount']) ?? _asInt(map['totalAmount']);
    final finalAmount = parsedFinalAmount ??
        ((subTotal - totalDiscount + vatAmount) < 0 ? 0 : (subTotal - totalDiscount + vatAmount));

    final staffUsername = map['staffUsername']?.toString().trim().isNotEmpty == true
        ? map['staffUsername']!.toString()
        : (map['username']?.toString() ?? map['createdBy']?.toString() ?? '');
    final staffFullName = map['staffFullName']?.toString().trim().isNotEmpty == true
        ? map['staffFullName']!.toString()
        : (map['cashierName']?.toString() ?? map['creatorName']?.toString() ?? '');

    return BillModel(
      id: id,
      billCode: billCode,
      orderCode: orderCode,
      tableName: tableName,
      zone: map['zone']?.toString() ?? '',
      createdAt: createdAt,
      closedAt: closedAt,
      cancelledAt: cancelledAt,
      status: status,
      staffUid: map['staffUid']?.toString(),
      staffUsername: staffUsername,
      staffFullName: staffFullName,
      staffCode: (map['staffCode'] ?? map['staffEmployeeCode'] ?? map['employeeCode'])?.toString(),
      items: items,
      subTotal: subTotal,
      discounts: discounts,
      totalDiscount: totalDiscount,
      vatRate: vatRate,
      vatAmount: vatAmount,
      finalAmount: finalAmount,
      paymentMethod: map['paymentMethod']?.toString() ?? 'CASH',
      paymentSplits: splits,
      notes: map['notes']?.toString() ?? map['note']?.toString() ?? '',
      parentBillId: parentBillId,
      mergedTableNames: merged,
      pointsUsed: _asInt(map['pointsUsed']) ?? 0,
      pointsDiscount: _asInt(map['pointsDiscount']) ?? 0,
      customerId: map['customerId']?.toString(),
      customerName: map['customerName']?.toString(),
      customerPhone: map['customerPhone']?.toString(),
      shiftId: map['shiftId']?.toString(),
      actionLogs: actionLogs,
      deletedItems: DeletedItemsLogic.decode(map['deletedItems'] ?? map['deletedItemsJson']),
    );
  }

  /// Mốc xếp NGÀY KINH DOANH (lùi theo giờ bắt đầu ngày của cửa hàng) — dùng cho lọc/gom theo ngày,
  /// KHÔNG dùng để hiển thị giờ.
  int get businessTimeMs => BusinessDay.shiftMs(reportTimeMs);

  /// Mốc thời gian xếp ngày báo cáo (docs/REPORT_SPEC.md §3.4):
  /// - CANCELLED: cancelledAt → closedAt → createdAt (đơn hủy thuộc NGÀY HỦY)
  /// - PAID / REFUNDED: closedAt → createdAt
  /// - OPEN / khác: createdAt → closedAt
  int get reportTimeMs {
    bool ok(int? v) => v != null && v > 0;
    if (status == 'CANCELLED') {
      if (ok(cancelledAt)) return cancelledAt!;
      if (ok(closedAt)) return closedAt!;
      return createdAt;
    }
    if (status == 'PAID' || status == 'REFUNDED') {
      return ok(closedAt) ? closedAt! : createdAt;
    }
    if (createdAt > 0) return createdAt;
    return ok(closedAt) ? closedAt! : 0;
  }

  int get deletedItemsCount => DeletedItemsLogic.summarize(deletedItems).count;
  int get deletedItemsAmount => DeletedItemsLogic.summarize(deletedItems).amount;

  /// Tổng giảm giá theo món (lineDiscountTotal) của hóa đơn.
  int get itemDiscountTotal => items.fold(0, (s, i) => s + i.lineDiscountTotal);

  /// Giảm giá cấp đơn = tổng giảm − giảm theo món (gồm voucher/CTKM + đổi điểm).
  int get orderLevelDiscount {
    final v = totalDiscount - itemDiscountTotal;
    return v < 0 ? 0 : v;
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
    if (cancelledAt != null) 'cancelledAt': cancelledAt,
    'status': status,
    if (staffUid != null && staffUid!.isNotEmpty) 'staffUid': staffUid,
    'staffUsername': staffUsername,
    'staffFullName': staffFullName,
    if (staffCode != null && staffCode!.isNotEmpty) 'staffCode': staffCode,
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
    if (paymentSplits != null && paymentSplits!.isNotEmpty)
      'paymentSplits': paymentSplits!.map((e) => e.toMap()).toList(),
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
    'deletedItems': deletedItems.map((e) => e.toMap()).toList(),
    'deletedItemsCount': deletedItemsCount,
    'deletedItemsAmount': deletedItemsAmount,
  };

  void recalculateTotals() {
    final rawSubTotal = items.fold(0, (s, i) => s + (i.unitPrice * i.quantity));
    final itemDiscountTotal = items.fold(0, (s, i) => s + i.lineDiscountTotal);
    subTotal = rawSubTotal;
    final voucherDiscount = discounts.fold(0, (s, d) => s + d.amount);
    totalDiscount = itemDiscountTotal + voucherDiscount + pointsDiscount;
    if (totalDiscount > subTotal) totalDiscount = subTotal;
    final afterDiscount = subTotal - totalDiscount;
    vatAmount = (afterDiscount * (vatRate / 100)).round();
    finalAmount = afterDiscount + vatAmount;
  }
}
