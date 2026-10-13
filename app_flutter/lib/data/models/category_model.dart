import '../../core/domain/item_options.dart';

// ==================== CATEGORY MODEL ====================
class CategoryModel {
  final String name;
  final List<String> allowedToppingIds;
  // Danh mục note/topping áp dụng cho cả nhóm: null = không gắn (xem item_options.dart)
  final List<String>? noteGroupIds;
  final List<String>? toppingGroupIds;

  /// Thứ tự hiển thị (nhỏ đứng trước), đồng bộ với web; null = chưa sắp xếp
  final int? order;

  CategoryModel({
    required this.name,
    this.allowedToppingIds = const [],
    this.noteGroupIds,
    this.toppingGroupIds,
    this.order,
  });

  factory CategoryModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      final map = Map<dynamic, dynamic>.from(val);
      List<String> toppings = [];
      if (map['allowedToppingIds'] is List) {
        toppings = List<String>.from(map['allowedToppingIds']);
      } else if (map['allowedToppingIds'] is Map) {
        toppings = (map['allowedToppingIds'] as Map).keys.map((e) => e.toString()).toList();
      }
      return CategoryModel(
        name: map['name']?.toString() ?? key ?? '',
        allowedToppingIds: toppings,
        noteGroupIds: parseGroupIds(map['noteGroupIds']),
        toppingGroupIds: parseGroupIds(map['toppingGroupIds']),
        order: map['order'] is num ? (map['order'] as num).toInt() : null,
      );
    } else if (val is String) {
      return CategoryModel(name: val);
    }
    return CategoryModel(name: key ?? '');
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    if (allowedToppingIds.isNotEmpty) 'allowedToppingIds': allowedToppingIds,
    if (noteGroupIds != null) 'noteGroupIds': encodeGroupIds(noteGroupIds),
    if (toppingGroupIds != null) 'toppingGroupIds': encodeGroupIds(toppingGroupIds),
    if (order != null) 'order': order,
  };

  CategoryModel copyWith({
    String? name,
    List<String>? allowedToppingIds,
    List<String>? noteGroupIds,
    List<String>? toppingGroupIds,
    int? order,
    bool clearNoteGroupIds = false,
    bool clearToppingGroupIds = false,
  }) => CategoryModel(
    name: name ?? this.name,
    allowedToppingIds: allowedToppingIds ?? this.allowedToppingIds,
    noteGroupIds: clearNoteGroupIds ? null : (noteGroupIds ?? this.noteGroupIds),
    toppingGroupIds: clearToppingGroupIds ? null : (toppingGroupIds ?? this.toppingGroupIds),
    order: order ?? this.order,
  );
}

/// Thứ tự danh mục: có `order` trước (nhỏ → lớn), chưa có sau, rồi theo tên (khớp web/lib/category-order.ts)
int compareCategories(CategoryModel a, CategoryModel b) {
  final oa = a.order, ob = b.order;
  if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
  if (oa != null && ob == null) return -1;
  if (oa == null && ob != null) return 1;
  return a.name.compareTo(b.name);
}
