// lib/core/permissions/role_catalog.dart
import '../../data/models/role_model.dart';
import 'app_permissions.dart';

/// Danh sách vai trò hiển thị trong màn Phân quyền / Quản lý nhân sự.
///
/// Chỉ còn 4 vai trò hệ thống (mã chuẩn): Chủ quán, Quản lý (gộp QL1+QL2), Nhân viên (gộp Thu ngân+Phục vụ),
/// Bếp / Bar; cộng các vai trò TỰ TẠO của quán. Bản ghi vai trò cũ trong RTDB (ROLE_MANAGER_1, ROLE_CASHIER...)
/// được GỘP vào vai trò mới bằng HỢP quyền để không ai mất quyền đã được cấp.
List<RoleModel> buildRoleCatalog(List<RoleModel> stored) {
  RoleModel system(String id, String name, String description) {
    final perms = <String>{};
    var hasStored = false;
    for (final r in stored) {
      if (normalizeRoleId(r.id) == id) {
        hasStored = true;
        perms.addAll(r.permissions);
      }
    }
    if (id == kRoleOwner) {
      perms
        ..clear()
        ..addAll(AppPermissions.allPermissions.map((p) => p.key));
    } else if (!hasStored) {
      perms.addAll(AppPermissions.rolePresets[id] ?? const []);
    }
    return RoleModel(
      id: id,
      name: name,
      description: description,
      permissions: perms.toList(),
      isSystemRole: true,
    );
  }

  final systemIds = {kRoleOwner, kRoleManager, kRoleStaff, kRoleKitchen};
  final custom = stored.where((r) => !systemIds.contains(normalizeRoleId(r.id))).toList();

  return [
    system(kRoleOwner, 'Chủ Quán (Toàn quyền)', 'Toàn quyền quản trị mọi chi nhánh và phân quyền'),
    system(kRoleManager, kManagerRoleLabel, 'Điều hành ca, kho, khuyến mãi, két tiền, chiết khấu, báo cáo'),
    system(kRoleStaff, '$kStaffRoleLabel ($kStaffRoleDescription)', 'Mở bàn, gọi món, gửi bếp, tính tiền, in hóa đơn'),
    system(kRoleKitchen, kKitchenRoleLabel, 'Màn hình bếp / pha chế (KDS)'),
    ...custom,
  ];
}

/// Tìm vai trò của một mã (kể cả mã cũ) trong danh sách đã dựng bằng [buildRoleCatalog].
RoleModel? findRoleById(List<RoleModel> roles, String? roleId) {
  final target = normalizeRoleId(roleId);
  for (final r in roles) {
    if (r.id == roleId || normalizeRoleId(r.id) == target) return r;
  }
  return null;
}
