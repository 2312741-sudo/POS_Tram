// ==================== CATEGORY MODEL ====================
class CategoryModel {
  final String name;
  CategoryModel({required this.name});
  factory CategoryModel.fromMap(dynamic val, [String? key]) {
    if (val is Map) {
      return CategoryModel(name: val['name']?.toString() ?? key ?? '');
    } else if (val is String) {
      return CategoryModel(name: val);
    }
    return CategoryModel(name: key ?? '');
  }
  Map<String, dynamic> toMap() => {'name': name};
}
