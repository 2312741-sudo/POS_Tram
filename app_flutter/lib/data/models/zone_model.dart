// lib/data/models/zone_model.dart
class ZoneModel {
  final String name;

  /// Khu được ghim: luôn đứng đầu danh sách
  final bool pinned;

  /// Thứ tự do người dùng sắp xếp (nhỏ đứng trước); null = chưa sắp xếp
  final int? order;
  ZoneModel({required this.name, this.pinned = false, this.order});
  factory ZoneModel.fromMap(Map map) => ZoneModel(
        name: map['name']?.toString() ?? '',
        pinned: map['pinned'] == true,
        order: map['order'] is num ? (map['order'] as num).toInt() : null,
      );
  Map<String, dynamic> toMap() => {
        'name': name,
        if (pinned) 'pinned': true,
        if (order != null) 'order': order,
      };
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
