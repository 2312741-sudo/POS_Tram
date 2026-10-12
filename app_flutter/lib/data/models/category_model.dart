import '../../core/domain/item_options.dart';

// ==================== CATEGORY MODEL ====================
class CategoryModel {
  final String name;
  final List<String> allowedToppingIds;
  // Danh mục note/topping áp dụng cho cả nhóm: null = không gắn (xem item_options.dart)
  final List<String>? noteGroupIds;
  final List<String>? toppingGroupIds;

  CategoryModel({
    required this.name,
    this.allowedToppingIds = const [],
    this.noteGroupIds,
    this.toppingGroupIds,
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
  };

  CategoryModel copyWith({
    String? name,
    List<String>? allowedToppingIds,
    List<String>? noteGroupIds,
    List<String>? toppingGroupIds,
    bool clearNoteGroupIds = false,
    bool clearToppingGroupIds = false,
  }) => CategoryModel(
    name: name ?? this.name,
    allowedToppingIds: allowedToppingIds ?? this.allowedToppingIds,
    noteGroupIds: clearNoteGroupIds ? null : (noteGroupIds ?? this.noteGroupIds),
    toppingGroupIds: clearToppingGroupIds ? null : (toppingGroupIds ?? this.toppingGroupIds),
  );
}
