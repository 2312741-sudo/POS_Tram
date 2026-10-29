// lib/core/domain/kitchen_sla.dart
// SLA bếp: đo thời gian từ lúc "gửi bếp" (KitchenOrderModel.timestamp) đến lúc bếp bấm xong (doneAt).
// Thuần Dart, không phụ thuộc Firebase — dễ test.
//
// Dữ liệu cũ (không có batchId/itemGroup) vẫn tính được: mỗi phiếu = một đơn.
// Khi bếp xong từng phần (nước / bánh) phiếu được tách: phần đã xong là một phiếu mới cùng
// `batchId` với phiếu gốc → gộp theo batchId thì "đơn" hoàn tất khi phần cuối cùng xong.
import '../../data/models/kitchen_order_model.dart';

const String kKitchenGroupDrink = 'drink';
const String kKitchenGroupFood = 'food';

/// Nhóm bếp của một danh mục: bánh / đồ ăn → food, còn lại → drink.
/// Heuristic theo tên danh mục (không có cờ riêng trong dữ liệu).
String kitchenGroupOfCategory(String category) {
  final c = category.toLowerCase();
  const foodWords = ['bánh', 'banh', 'cake', 'ăn', 'food', 'snack', 'tráng miệng', 'dessert', 'xôi', 'cơm', 'mì ', 'phở'];
  for (final w in foodWords) {
    if (c.contains(w)) return kKitchenGroupFood;
  }
  return kKitchenGroupDrink;
}

String kitchenGroupLabel(String? group) {
  switch (group) {
    case kKitchenGroupDrink:
      return 'Nước';
    case kKitchenGroupFood:
      return 'Bánh';
    default:
      return 'Cả đơn';
  }
}

/// Một dòng món đã xong của phiếu bếp.
class KitchenSlaItem {
  final String orderKey; // batchId ?? firebaseKey
  final String tableName;
  final String itemName;
  final int quantity;
  final String? group;
  final int sentAt;
  final int doneAt;

  const KitchenSlaItem({
    required this.orderKey,
    required this.tableName,
    required this.itemName,
    required this.quantity,
    required this.group,
    required this.sentAt,
    required this.doneAt,
  });

  Duration get duration => Duration(milliseconds: (doneAt - sentAt).clamp(0, 1 << 62));
}

/// Một đơn (gộp các phiếu cùng batchId): sentAt = lúc gửi bếp, doneAt = lúc phần cuối xong.
class KitchenSlaOrder {
  final String orderKey;
  final String tableName;
  final String? orderCode;
  final int sentAt;
  final int doneAt;
  final int itemCount;
  final bool isPartialSplit; // đơn được bếp xong từng phần

  const KitchenSlaOrder({
    required this.orderKey,
    required this.tableName,
    required this.orderCode,
    required this.sentAt,
    required this.doneAt,
    required this.itemCount,
    required this.isPartialSplit,
  });

  Duration get duration => Duration(milliseconds: (doneAt - sentAt).clamp(0, 1 << 62));
  bool isLate(Duration threshold) => duration > threshold;
}

class KitchenSlaSummary {
  final List<KitchenSlaOrder> orders;
  final List<KitchenSlaItem> items;
  final Duration averageOrder;
  final Duration maxOrder;
  final Duration averageItem;
  final Duration maxItem;
  final int lateOrderCount;
  final Duration threshold;

  const KitchenSlaSummary({
    required this.orders,
    required this.items,
    required this.averageOrder,
    required this.maxOrder,
    required this.averageItem,
    required this.maxItem,
    required this.lateOrderCount,
    required this.threshold,
  });

  List<KitchenSlaOrder> get lateOrders => orders.where((o) => o.isLate(threshold)).toList()
    ..sort((a, b) => b.duration.compareTo(a.duration));
}

class KitchenSla {
  KitchenSla._();

  static Duration _avg(Iterable<Duration> ds) {
    if (ds.isEmpty) return Duration.zero;
    final total = ds.fold<int>(0, (s, d) => s + d.inMilliseconds);
    return Duration(milliseconds: (total / ds.length).round());
  }

  /// Tính SLA từ các phiếu bếp. Chỉ phiếu đã xong (isDone && doneAt != null) và có timestamp > 0.
  /// [fromMs]/[toMs] lọc theo thời điểm gửi bếp (bao gồm 2 đầu).
  static KitchenSlaSummary compute(
    Iterable<KitchenOrderModel> tickets, {
    Duration threshold = const Duration(minutes: 10),
    int? fromMs,
    int? toMs,
  }) {
    final items = <KitchenSlaItem>[];
    final byOrder = <String, List<KitchenOrderModel>>{};
    // Đơn đã tách mà vẫn còn phần chưa xong → chưa tính vào SLA theo đơn (món đã xong vẫn tính theo món)
    final openBatches = <String>{
      for (final t in tickets)
        if (!t.isDone && t.batchId != null) t.batchId!,
    };

    for (final t in tickets) {
      final done = t.doneAt;
      if (!t.isDone || done == null || t.timestamp <= 0) continue;
      if (fromMs != null && t.timestamp < fromMs) continue;
      if (toMs != null && t.timestamp > toMs) continue;
      final orderKey = t.batchId ?? t.firebaseKey ?? '${t.tableName}_${t.timestamp}';
      byOrder.putIfAbsent(orderKey, () => []).add(t);
      final groups = t.itemGroups;
      for (var i = 0; i < t.items.length; i++) {
        final it = t.items[i];
        final groupFromItem = (i < groups.length ? groups[i] : null);
        final inferredGroup = t.itemGroup ?? groupFromItem ?? kitchenGroupOfCategory(it.name);
        items.add(KitchenSlaItem(
          orderKey: orderKey,
          tableName: t.tableName,
          itemName: it.name,
          quantity: it.quantity,
          group: inferredGroup,
          sentAt: t.timestamp,
          doneAt: done,
        ));
      }
    }

    final orders = <KitchenSlaOrder>[];
    byOrder.forEach((key, list) {
      if (openBatches.contains(key)) return;
      final sentAt = list.map((e) => e.timestamp).reduce((a, b) => a < b ? a : b);
      final doneAt = list.map((e) => e.doneAt!).reduce((a, b) => a > b ? a : b);
      orders.add(KitchenSlaOrder(
        orderKey: key,
        tableName: list.first.tableName,
        orderCode: list.first.orderCode,
        sentAt: sentAt,
        doneAt: doneAt,
        itemCount: list.fold<int>(0, (s, e) => s + e.items.length),
        isPartialSplit: list.length > 1,
      ));
    });
    orders.sort((a, b) => b.sentAt.compareTo(a.sentAt));

    Duration maxOf(Iterable<Duration> ds) => ds.isEmpty ? Duration.zero : ds.reduce((a, b) => a > b ? a : b);
    return KitchenSlaSummary(
      orders: orders,
      items: items,
      averageOrder: _avg(orders.map((o) => o.duration)),
      maxOrder: maxOf(orders.map((o) => o.duration)),
      averageItem: _avg(items.map((i) => i.duration)),
      maxItem: maxOf(items.map((i) => i.duration)),
      lateOrderCount: orders.where((o) => o.isLate(threshold)).length,
      threshold: threshold,
    );
  }
}
