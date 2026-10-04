import '../../core/permissions/app_permissions.dart';
import 'role_model.dart';

// ==================== AUTH UTILS ====================
class AuthUtils {
  static final RegExp usernameRegex = RegExp(r'^[a-z0-9_-]{3,30}$');

  /// Kiểm tra username có hợp lệ theo hợp đồng AUTH_CONTRACT:
  /// Chỉ gồm chữ thường a-z, số 0-9, gạch dưới _, gạch ngang -
  /// Độ dài 3-30 ký tự. Không chứa dấu chấm, khoảng trắng, ký tự tiếng Việt.
  static bool isValidUsername(String username) {
    final clean = username.trim().toLowerCase();
    return usernameRegex.hasMatch(clean);
  }

  /// Chuẩn hóa username: cắt khoảng trắng và chuyển thành chữ thường
  static String normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }

  /// Chuẩn hóa storeCode: cắt khoảng trắng và chuyển thành chữ thường khi tạo email auth
  static String normalizeStoreCode(String storeCode) {
    return storeCode.trim().toLowerCase();
  }

  /// Tạo email ảo nội bộ theo hợp đồng: {username}.{storeCode}@tram.local
  static String buildAuthEmail(String username, String storeCode) {
    final cleanUser = normalizeUsername(username);
    final cleanStore = normalizeStoreCode(storeCode);
    return '$cleanUser.$cleanStore@tram.local';
  }
}

// ==================== USER MODEL ====================
class UserModel {
  final String uid;
  final String username;
  final String fullName;
  final String roleId;
  final bool isRootOwner;
  final List<String> customPermissions; // Specific individual overrides
  final bool isActive;
  final String phone;
  final int? createdAt;
  final int? lastLoginAt;
  final bool mustChangePassword;
  final String password; // Giữ để tương thích ngược constructor cũ, tuyệt đối không lưu vào RTDB

  UserModel({
    this.uid = '',
    required this.username,
    required this.fullName,
    this.password = '',
    required this.roleId,
    this.isRootOwner = false,
    this.customPermissions = const [],
    this.isActive = true,
    this.phone = '',
    this.createdAt,
    this.lastLoginAt,
    this.mustChangePassword = false,
  });

  factory UserModel.fromMap(Map<dynamic, dynamic> map, [String? fallbackUid]) {
    List<String> customPerms = [];
    if (map['customPermissions'] != null) {
      if (map['customPermissions'] is List) {
        customPerms = List<String>.from(map['customPermissions']);
      } else if (map['customPermissions'] is Map) {
        customPerms = (map['customPermissions'] as Map).keys.map((e) => e.toString()).toList();
      }
    }

    final rawCreatedAt = map['createdAt'];
    final int? createdAt = rawCreatedAt is int
        ? rawCreatedAt
        : int.tryParse(rawCreatedAt?.toString() ?? '');

    final rawLastLoginAt = map['lastLoginAt'];
    final int? lastLoginAt = rawLastLoginAt is int
        ? rawLastLoginAt
        : int.tryParse(rawLastLoginAt?.toString() ?? '');

    final parsedUid = map['uid']?.toString() ?? '';
    final effectiveUid = parsedUid.isNotEmpty ? parsedUid : (fallbackUid ?? '');

    return UserModel(
      uid: effectiveUid,
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      roleId: map['roleId']?.toString() ?? 'ROLE_STAFF',
      isRootOwner: map['isRootOwner'] == true ||
          (map['roleId']?.toString().toUpperCase() == 'OWNER') ||
          (map['roleId']?.toString().toUpperCase() == 'ROLE_OWNER'),
      customPermissions: customPerms,
      isActive: map['isActive'] is bool ? map['isActive'] as bool : true,
      phone: map['phone']?.toString() ?? '',
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      mustChangePassword: map['mustChangePassword'] == true,
    );
  }

  /// Serialization tuân thủ 100% hợp đồng AUTH_CONTRACT:
  /// Tuyệt đối KHÔNG lưu trữ trường password trong Realtime Database
  Map<String, dynamic> toMap() => {
    'uid': uid,
    'username': username,
    'fullName': fullName,
    'roleId': roleId,
    'isRootOwner': isRootOwner,
    'customPermissions': customPermissions,
    'isActive': isActive,
    'phone': phone,
    if (createdAt != null) 'createdAt': createdAt,
    if (lastLoginAt != null) 'lastLoginAt': lastLoginAt,
    'mustChangePassword': mustChangePassword,
  };

  UserModel copyWith({
    String? uid,
    String? username,
    String? fullName,
    String? password,
    String? roleId,
    bool? isRootOwner,
    List<String>? customPermissions,
    bool? isActive,
    String? phone,
    int? createdAt,
    int? lastLoginAt,
    bool? mustChangePassword,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      password: password ?? this.password,
      roleId: roleId ?? this.roleId,
      isRootOwner: isRootOwner ?? this.isRootOwner,
      customPermissions: customPermissions ?? this.customPermissions,
      isActive: isActive ?? this.isActive,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

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
