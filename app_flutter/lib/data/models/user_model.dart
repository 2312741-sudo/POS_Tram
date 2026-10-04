import '../../core/permissions/app_permissions.dart';
import 'role_model.dart';

// ==================== USER MODEL ====================
class UserModel {
  final String username;
  final String fullName;
  final String password;
  final String roleId;
  final bool isRootOwner;
  final List<String> customPermissions; // Specific individual overrides
  final bool isActive;
  final String phone;
  final String uid;

  UserModel({
    required this.username,
    required this.fullName,
    required this.password,
    required this.roleId,
    this.isRootOwner = false,
    this.customPermissions = const [],
    this.isActive = true,
    this.phone = '',
    this.uid = '',
  });

  factory UserModel.fromMap(Map<dynamic, dynamic> map) {
    List<String> customPerms = [];
    if (map['customPermissions'] != null) {
      if (map['customPermissions'] is List) {
        customPerms = List<String>.from(map['customPermissions']);
      } else if (map['customPermissions'] is Map) {
        customPerms = (map['customPermissions'] as Map).keys.map((e) => e.toString()).toList();
      }
    }
    return UserModel(
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      roleId: map['roleId']?.toString() ?? 'STAFF',
      isRootOwner: map['isRootOwner'] == true || (map['roleId']?.toString().toUpperCase() == 'OWNER'),
      customPermissions: customPerms,
      isActive: map['isActive'] ?? true,
      phone: map['phone']?.toString() ?? '',
      uid: map['uid']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'username': username,
    'fullName': fullName,
    'password': password,
    'roleId': roleId,
    'isRootOwner': isRootOwner,
    'customPermissions': customPermissions,
    'isActive': isActive,
    'phone': phone,
    'uid': uid,
  };

  UserRole get role => UserRole.fromString(roleId);
  bool get isOwner => isRootOwner || role.isOwner;
  bool get isManager => role.isManager;

  /// Kiểm tra có phải Chủ quán cửa hàng (Owner Sovereign Rule)
  bool isStoreOwner(String? storeOwnerId) {
    if (storeOwnerId != null && storeOwnerId.isNotEmpty && uid.isNotEmpty && uid == storeOwnerId) {
      return true;
    }
    return isRootOwner || role.isOwner;
  }

  /// Check permission considering Root Owner + Role permissions + Individual custom overrides
  bool can(String permKey, [List<RoleModel>? roles, String? storeOwnerId]) {
    if (isStoreOwner(storeOwnerId)) return true; // Nguyên tắc tối thượng bảo vệ Chủ quán
    if (customPermissions.contains(permKey)) return true;
    if (roles != null && roles.isNotEmpty) {
      final matchedRole = roles.where((r) => r.id == roleId).firstOrNull;
      if (matchedRole != null) return matchedRole.hasPermission(permKey);
    }
    return role.hasDefaultPermission(permKey);
  }
}
