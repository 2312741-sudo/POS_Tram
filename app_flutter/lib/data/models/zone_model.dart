// ==================== ZONE MODEL ====================
class ZoneModel {
  final String name;
  ZoneModel({required this.name});
  factory ZoneModel.fromMap(Map map) => ZoneModel(name: map['name']?.toString() ?? '');
  Map<String, dynamic> toMap() => {'name': name};
}
