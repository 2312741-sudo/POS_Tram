// lib/core/domain/order_guards.dart
//
// Kiểm tra an toàn trước khi THANH TOÁN / CHUYỂN BÀN / GỘP BÀN, dựa trên bản bàn đọc lại từ server.
// Nguyên tắc: chỉ CHẶN khi chắc chắn có vấn đề. Không đọc được (mất mạng, hết giờ chờ, bàn tách tự động
// chưa có trên server...) thì KHÔNG chặn, dùng dữ liệu trên máy như trước.
import 'dart:convert';
import '../../data/models/order_item_model.dart';

/// Kết quả đọc lại một bàn từ server
class ServerTableRead {
  /// Đọc thành công (có hoặc không có node)
  final bool ok;

  /// Node có tồn tại không (bàn tách tự động "Bàn X (2)" có thể chưa có)
  final bool exists;
  final bool inUse;
  final String orderJson;
  final String? closedBillId;

  const ServerTableRead({
    required this.ok,
    this.exists = false,
    this.inUse = false,
    this.orderJson = '',
    this.closedBillId,
  });

  /// Không đọc được (lỗi / hết giờ / mất mạng)
  static const failed = ServerTableRead(ok: false);

  factory ServerTableRead.fromNode(Object? node) {
    if (node is! Map) return const ServerTableRead(ok: true, exists: false);
    final rawInUse = node['inUse'];
    return ServerTableRead(
      ok: true,
      exists: true,
      inUse: rawInUse == true || rawInUse == 1 || rawInUse?.toString().toLowerCase() == 'true',
      orderJson: node['currentOrderJson']?.toString() ?? '',
      closedBillId: node['closedBillId']?.toString(),
    );
  }

  List<OrderItemModel> get items {
    if (orderJson.trim().isEmpty) return const [];
    try {
      final raw = jsonDecode(orderJson);
      if (raw is! List) return const [];
      return [for (final e in raw) if (e is Map) OrderItemModel.fromMap(e)];
    } catch (_) {
      return const [];
    }
  }
}

class OrderGuards {
  OrderGuards._();

  /// Nhận diện "món nào" của một dòng (bỏ qua mã dòng, đã gửi bếp hay chưa, giảm giá, ghi chú)
  static String _identity(OrderItemModel it) =>
      '${it.productId}|${it.name.trim().toLowerCase()}|${it.selectedSize}|${it.selectedSugar}|${it.selectedIce}|'
      '${([...it.selectedToppings]..sort()).join(',')}|${it.rewardCampaignId}';

  /// Các món có trên server mà hóa đơn sắp thanh toán THIẾU (tên x số phần thiếu). Rỗng = an toàn.
  /// Chỉ trả về khi đọc được và bàn trên server đang có khách với đơn có món.
  static List<String> missingFromBill(ServerTableRead server, List<OrderItemModel> billItems) {
    if (!server.ok || !server.exists || !server.inUse) return const [];
    final serverItems = server.items;
    if (serverItems.isEmpty) return const [];
    final billQty = <String, int>{};
    for (final it in billItems) {
      billQty[_identity(it)] = (billQty[_identity(it)] ?? 0) + it.quantity;
    }
    final serverQty = <String, int>{};
    final names = <String, String>{};
    for (final it in serverItems) {
      final k = _identity(it);
      serverQty[k] = (serverQty[k] ?? 0) + it.quantity;
      names[k] = it.name;
    }
    return [
      for (final e in serverQty.entries)
        if (e.value > (billQty[e.key] ?? 0)) '${names[e.key]} x${e.value - (billQty[e.key] ?? 0)}',
    ];
  }

  /// Quyết định đơn dùng để CHUYỂN / GỘP bàn nguồn:
  ///  - trả `blockReason` khi bàn nguồn trên máy không có món, hoặc server XÁC NHẬN đơn này đã đóng / đã chuyển
  ///    (bàn trống và closedBillId trùng mã hóa đơn của đơn đang thao tác);
  ///  - `useServer` = true khi server đang có món (bản mới nhất, gồm món máy khác vừa thêm);
  ///  - còn lại (không đọc được, node chưa có, server trống nhưng chưa xác nhận) → dùng bản trên máy.
  static ({String? blockReason, bool useServer}) sourceForMove({
    required String tableName,
    required bool localInUse,
    required int localItemCount,
    required String? localBillId,
    required ServerTableRead server,
  }) {
    final serverHasItems = server.ok && server.exists && server.inUse && server.items.isNotEmpty;
    if (serverHasItems) return (blockReason: null, useServer: true);
    final confirmedClosed = server.ok &&
        server.exists &&
        !server.inUse &&
        localBillId != null &&
        localBillId.isNotEmpty &&
        server.closedBillId == localBillId;
    if (confirmedClosed) {
      return (blockReason: 'Đơn của bàn $tableName đã được chuyển / thanh toán ở thao tác trước.', useServer: false);
    }
    if (!localInUse || localItemCount == 0) {
      return (blockReason: 'Bàn $tableName không còn món để chuyển.', useServer: false);
    }
    return (blockReason: null, useServer: false);
  }
}
