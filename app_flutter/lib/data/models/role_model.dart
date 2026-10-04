// ==================== ROLE MODEL ====================
class RoleModel {
  final String id;
  final String name;
  final String description;
  final List<String> permissions;
  final bool isSystemRole;

  RoleModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.permissions,
    this.isSystemRole = false,
  });

  factory RoleModel.fromMap(Map<dynamic, dynamic> map, String id) {
    List<String> perms = [];
    if (map['permissions'] != null) {
      if (map['permissions'] is List) {
        perms = List<String>.from(map['permissions']);
      } else if (map['permissions'] is Map) {
        perms = (map['permissions'] as Map).keys.map((e) => e.toString()).toList();
      }
    }
    return RoleModel(
      id: id,
      name: map['name']?.toString() ?? id,
      description: map['description']?.toString() ?? '',
      permissions: perms,
      isSystemRole: map['isSystemRole'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'permissions': permissions,
    'isSystemRole': isSystemRole,
  };

  bool hasPermission(String permKey) => permissions.contains(permKey);
}
