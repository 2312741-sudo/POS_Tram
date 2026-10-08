// ==================== CATEGORY MODEL ====================
class CategoryModel {
  final String name;
  final List<String> allowedToppingIds;

  CategoryModel({
    required this.name,
    this.allowedToppingIds = const [],
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
      );
    } else if (val is String) {
      return CategoryModel(name: val);
    }
    return CategoryModel(name: key ?? '');
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    if (allowedToppingIds.isNotEmpty) 'allowedToppingIds': allowedToppingIds,
  };

  CategoryModel copyWith({
    String? name,
    List<String>? allowedToppingIds,
  }) => CategoryModel(
    name: name ?? this.name,
    allowedToppingIds: allowedToppingIds ?? this.allowedToppingIds,
  );
}
