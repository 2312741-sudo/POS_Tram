// lib/data/models/zone_model.dart
class ZoneModel {
  final String name;

  /// Khu được ghim: luôn đứng đầu danh sách
  final bool pinned;

  /// Thứ tự do người dùng sắp xếp (nhỏ đứng trước); null = chưa sắp xếp
  final int? order;

  /// Thứ tự bàn trong khu do người dùng sắp xếp (tên bàn gốc); rỗng = chưa sắp xếp
  final List<String> tableOrder;
  ZoneModel({required this.name, this.pinned = false, this.order, this.tableOrder = const []});
  factory ZoneModel.fromMap(Map map) => ZoneModel(
        name: map['name']?.toString() ?? '',
        pinned: map['pinned'] == true,
        order: map['order'] is num ? (map['order'] as num).toInt() : null,
        tableOrder: _parseTableOrder(map['tableOrder']),
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        if (pinned) 'pinned': true,
        if (order != null) 'order': order,
        if (tableOrder.isNotEmpty) 'tableOrder': tableOrder,
      };
}

List<String> _parseTableOrder(dynamic raw) {
  final Iterable items = raw is List ? raw : (raw is Map ? raw.values : const []);
  return [for (final e in items) if (e != null && e.toString().trim().isNotEmpty) e.toString().trim()];
}

/// Sắp xếp bàn theo thứ tự người dùng đặt trong từng khu ([ZoneModel.tableOrder]).
/// Bàn có trong thứ tự đứng trước theo đúng thứ tự đó; bàn chưa có (mới tạo) giữ vị trí cũ rồi xếp sau.
/// Bàn tách ("Bàn 01 (2)") đi theo bàn gốc. Khu không đổi chỗ nhau: chỉ thứ tự trong cùng khu thay đổi.
List<T> sortTablesByZoneOrder<T>(
  List<T> tables,
  List<ZoneModel> zones, {
  required String Function(T) zoneOf,
  required String Function(T) baseNameOf,
}) {
  final orderByZone = {
    for (final z in zones)
      if (z.tableOrder.isNotEmpty) z.name.trim(): {for (var i = 0; i < z.tableOrder.length; i++) z.tableOrder[i]: i},
  };
  if (orderByZone.isEmpty) return tables;
  final indexed = [for (var i = 0; i < tables.length; i++) (i, tables[i])];
  // Chỉ xếp lại trong từng khu: giữ nguyên thứ tự xuất hiện của các khu
  final zoneFirstSeen = <String, int>{};
  for (final e in indexed) {
    zoneFirstSeen.putIfAbsent(zoneOf(e.$2).trim(), () => e.$1);
  }
  int rank(T t) => orderByZone[zoneOf(t).trim()]?[baseNameOf(t).trim()] ?? 1 << 20;
  indexed.sort((a, b) {
    final za = zoneFirstSeen[zoneOf(a.$2).trim()]!, zb = zoneFirstSeen[zoneOf(b.$2).trim()]!;
    if (za != zb) return za.compareTo(zb);
    final c = rank(a.$2).compareTo(rank(b.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Sắp xếp tên khu: ghim trước, rồi theo thứ tự đã đặt, rồi theo bảng chữ cái.
/// Khu không có trong [zones] (chỉ có bàn) xếp sau các khu đã khai báo.
List<String> sortZoneNames(Iterable<String> names, List<ZoneModel> zones) {
  final meta = {for (final z in zones) z.name.trim(): z};
  final list = names.toSet().toList();
  int rank(String n) => meta[n] == null ? 2 : (meta[n]!.pinned ? 0 : 1);
  list.sort((a, b) {
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    final oa = meta[a]?.order, ob = meta[b]?.order;
    if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
    if (oa != null && ob == null) return -1;
    if (oa == null && ob != null) return 1;
    return a.compareTo(b);
  });
  return list;
}
