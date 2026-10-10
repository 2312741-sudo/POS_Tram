// lib/core/domain/deleted_items.dart
//
// XÓA MÓN / GIẢM SỐ LƯỢNG MÓN ĐÃ LƯU TRÊN BÀN — hợp đồng chung với web admin.
//
// - Chỉ áp dụng cho phần số lượng đã được LƯU trong `currentOrderJson` của bàn.
//   Món vừa thêm (chưa lưu) bớt/xóa tự do, không cần lý do, không ghi nhận.
// - Mỗi lần xóa ghi 1 entry: {name, productId, quantity, unitPrice, amount, reason,
//   staffUsername, staffFullName, timestamp, sentToKitchen}.
// - Bàn: `deletedItemsJson` (chuỗi JSON mảng entry, giống currentOrderJson).
// - Hóa đơn (PAID & CANCELLED): `deletedItems`, `deletedItemsCount` (tổng số lượng),
//   `deletedItemsAmount` (tổng tiền).
// - Audit log: action `DELETE_ITEM`, targetType `ORDER_ITEM`.
import 'dart:convert';

import '../../data/models/order_item_model.dart';

/// Lý do xóa món (giá trị lưu đúng chuỗi tiếng Việt, khớp web).
class DeleteItemReasons {
  static const String changedItem = 'Khách đổi món';
  static const String cancelledByGuest = 'Khách hủy món';
  static const String wrongEntry = 'Nhập sai';
  static const String outOfStock = 'Hết món/hết nguyên liệu';
  static const String other = 'Khác';

  static const List<String> all = [changedItem, cancelledByGuest, wrongEntry, outOfStock, other];

  /// Lý do cuối cùng ghi nhận. "Khác" bắt buộc có nội dung → "Khác: {nội dung}".
  /// Trả về null nếu không hợp lệ.
  static String? resolve(String? reason, {String otherText = ''}) {
    if (reason == null || !all.contains(reason)) return null;
    if (reason == other) {
      final t = otherText.trim();
      if (t.isEmpty) return null;
      return '$other: $t';
    }
    return reason;
  }
}

class DeletedItemEntry {
  final String name;
  final int productId;
  final int quantity;
  final int unitPrice; // gồm size + topping
  final int amount; // giá trị phần đã xóa sau phần giảm giá dòng tương ứng
  final String reason;
  final String staffUsername;
  final String staffFullName;
  final int timestamp;
  final bool sentToKitchen;

  const DeletedItemEntry({
    required this.name,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    required this.reason,
    required this.staffUsername,
    required this.staffFullName,
    required this.timestamp,
    required this.sentToKitchen,
  });

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  factory DeletedItemEntry.fromMap(Map<dynamic, dynamic> m) {
    final qty = _int(m['quantity']);
    final unit = _int(m['unitPrice']);
    final rawAmount = m['amount'];
    final sent = m['sentToKitchen'];
    return DeletedItemEntry(
      name: m['name']?.toString() ?? '',
      productId: _int(m['productId']),
      quantity: qty,
      unitPrice: unit,
      amount: rawAmount == null ? unit * qty : _int(rawAmount),
      reason: m['reason']?.toString() ?? '',
      staffUsername: m['staffUsername']?.toString() ?? '',
      staffFullName: m['staffFullName']?.toString() ?? '',
      timestamp: _int(m['timestamp']),
      sentToKitchen: sent == true || sent?.toString().toLowerCase() == 'true',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'amount': amount,
        'reason': reason,
        'staffUsername': staffUsername,
        'staffFullName': staffFullName,
        'timestamp': timestamp,
        'sentToKitchen': sentToKitchen,
      };
}

class DeletedItemsSummary {
  final int count;
  final int amount;
  const DeletedItemsSummary(this.count, this.amount);
}

class DeletedItemsLogic {
  /// Khóa so khớp dòng giỏ hiện tại với dòng đã lưu (không gồm cờ gửi bếp / giảm giá
  /// vì các trường này có thể đổi sau khi lưu).
  static String matchKey(OrderItemModel i) {
    final toppings = [...i.selectedToppings]..sort();
    return jsonEncode([
      i.productId,
      i.price,
      i.selectedSize,
      i.sizeExtraPrice,
      i.selectedSugar,
      i.selectedIce,
      toppings,
      i.toppingPrice,
      i.note.trim(),
    ]);
  }

  /// Trong [removeQty] phần sắp xóa khỏi dòng [line] của giỏ [cart], bao nhiêu phần
  /// thuộc đơn ĐÃ LƯU [persisted]? Phần chưa lưu (vừa thêm) được coi là xóa trước.
  static int persistedPortion({
    required List<OrderItemModel> persisted,
    required List<OrderItemModel> cart,
    required OrderItemModel line,
    required int removeQty,
  }) {
    if (removeQty <= 0) return 0;
    final key = matchKey(line);
    final savedQty = persisted.where((i) => matchKey(i) == key).fold<int>(0, (s, i) => s + i.quantity);
    if (savedQty <= 0) return 0;
    final cartQty = cart.where((i) => matchKey(i) == key).fold<int>(0, (s, i) => s + i.quantity);
    final unsaved = cartQty - savedQty > 0 ? cartQty - savedQty : 0;
    final fromSaved = removeQty - unsaved;
    if (fromSaved <= 0) return 0;
    return fromSaved > savedQty ? savedQty : fromSaved;
  }

  /// Giá trị (sau giảm giá dòng) của [qty] phần bị xóa khỏi dòng [line].
  /// = phần chênh lệch thành tiền dòng trước/sau khi bớt, chặn dưới bởi 0.
  static int removedAmount(OrderItemModel line, int qty) {
    if (qty <= 0 || line.quantity <= 0) return 0;
    final q = qty > line.quantity ? line.quantity : qty;
    final remaining = line.quantity - q;
    final afterTotal = remaining <= 0 ? 0 : line.copyWith(quantity: remaining).itemTotal;
    final diff = line.itemTotal - afterTotal;
    return diff < 0 ? 0 : diff;
  }

  /// Tạo entry cho [savedQty] phần đã lưu bị xóa trong lần xóa [removeQty] phần.
  static DeletedItemEntry buildEntry({
    required OrderItemModel line,
    required int removeQty,
    required int savedQty,
    required String reason,
    required String staffUsername,
    required String staffFullName,
    required int timestamp,
  }) {
    final total = removedAmount(line, removeQty);
    final amount = removeQty <= 0 ? 0 : (total * savedQty / removeQty).round();
    return DeletedItemEntry(
      name: line.name,
      productId: line.productId,
      quantity: savedQty,
      unitPrice: line.unitPrice,
      amount: amount,
      reason: reason,
      staffUsername: staffUsername,
      staffFullName: staffFullName,
      timestamp: timestamp,
      sentToKitchen: line.isSentKitchen,
    );
  }

  static List<DeletedItemEntry> decode(Object? raw) {
    if (raw == null) return [];
    Object? data = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return [];
      try {
        data = jsonDecode(raw);
      } catch (_) {
        return [];
      }
    }
    if (data is Map) data = data.values.toList(); // RTDB có thể trả object chỉ số
    if (data is! List) return [];
    return data.whereType<Map>().map((m) => DeletedItemEntry.fromMap(m)).toList();
  }

  static String encode(List<DeletedItemEntry> entries) =>
      entries.isEmpty ? '' : jsonEncode(entries.map((e) => e.toMap()).toList());

  /// Nối thêm [extra] vào chuỗi JSON [json] hiện có.
  static String append(String? json, List<DeletedItemEntry> extra) => encode([...decode(json), ...extra]);

  static DeletedItemsSummary summarize(Iterable<DeletedItemEntry> entries) {
    int c = 0, a = 0;
    for (final e in entries) {
      c += e.quantity;
      a += e.amount;
    }
    return DeletedItemsSummary(c, a);
  }

  static String _vnd(int v) {
    final s = v.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return v < 0 ? '-$s' : s;
  }

  /// Nội dung audit log: "Xóa {qty} x {name} ({amount}đ) bàn {table} — Lý do: {reason}"
  static String auditDetails(DeletedItemEntry e, String tableName) =>
      'Xóa ${e.quantity} x ${e.name} (${_vnd(e.amount)}đ) bàn $tableName — Lý do: ${e.reason}';

  /// Các trường cấu trúc kèm audit log DELETE_ITEM.
  static Map<String, dynamic> auditFields(DeletedItemEntry e, {required String tableName, String? orderCode}) => {
        'productName': e.name,
        'quantity': e.quantity,
        'amount': e.amount,
        'reason': e.reason,
        'tableName': tableName,
        'orderCode': orderCode ?? '',
      };
}
