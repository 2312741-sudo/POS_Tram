import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/permissions/app_permissions.dart';
import 'package:tram_flutter/core/permissions/role_catalog.dart';
import 'package:tram_flutter/core/permissions/route_permissions.dart';
import 'package:tram_flutter/data/models/role_model.dart';
import 'package:tram_flutter/data/models/user_model.dart';

void main() {
  group('normalizeRoleId', () {
    test('mọi mã Quản lý cũ -> ROLE_MANAGER', () {
      for (final r in ['manager', 'manager_1', 'manager_2', 'ROLE_MANAGER', 'ROLE_MANAGER_1', 'ROLE_MANAGER_2', 'Manager-1', ' ql2 ']) {
        expect(normalizeRoleId(r), kRoleManager, reason: r);
        expect(UserRole.fromString(r), UserRole.manager, reason: r);
      }
    });
    test('Thu ngân / Phục vụ / employee -> ROLE_STAFF', () {
      for (final r in ['cashier', 'ROLE_CASHIER', 'employee', 'waiter', 'ROLE_WAITER', 'staff', 'ROLE_STAFF', 'WAITER']) {
        expect(normalizeRoleId(r), kRoleStaff, reason: r);
        expect(UserRole.fromString(r), UserRole.staff, reason: r);
      }
    });
    test('Chủ quán và Bếp giữ nguyên; mã lạ giữ nguyên; nhãn hiển thị', () {
      expect(normalizeRoleId('owner'), kRoleOwner);
      expect(normalizeRoleId('kitchen'), kRoleKitchen);
      expect(normalizeRoleId('ROLE_KITCHEN'), kRoleKitchen);
      expect(normalizeRoleId('CUSTOM_1'), 'CUSTOM_1');
      expect(normalizeRoleId(null), '');
      expect(roleDisplayLabel('ROLE_MANAGER_2'), 'Quản lý');
      expect(roleDisplayLabel('ROLE_WAITER'), kStaffRoleLabel);
      expect(roleDisplayLabel('ROLE_CASHIER'), kStaffRoleLabel);
      expect(UserRole.manager.value, 'ROLE_MANAGER');
      expect(UserRole.staff.value, 'ROLE_STAFF');
    });
  });

  group('bảng quyền mặc định', () {
    final allKeys = AppPermissions.allPermissions.map((p) => p.key).toSet();
    test('mã quyền duy nhất và mọi quyền trong preset đều có trong danh mục', () {
      expect(allKeys.length, AppPermissions.allPermissions.length);
      AppPermissions.rolePresets.forEach((role, perms) {
        for (final p in perms) {
          expect(allKeys.contains(p), isTrue, reason: '$role:$p');
        }
      });
    });
    test('Quản lý là hợp QL1 + QL2; Nhân viên giữ đủ quyền Thu ngân', () {
      final m = AppPermissions.rolePresets[kRoleManager]!.toSet();
      for (final p in [
        AppPermissions.openTable, AppPermissions.manageCashShift, AppPermissions.viewReports,
        AppPermissions.adjustCashShift, AppPermissions.managePromotions,
        AppPermissions.copyMenu,
      ]) {
        expect(m.contains(p), isTrue, reason: p);
      }
      final s = AppPermissions.rolePresets[kRoleStaff]!.toSet();
      for (final p in [
        AppPermissions.viewMenu, AppPermissions.openTable, AppPermissions.changeTable, AppPermissions.sendKitchen,
        AppPermissions.createBill, AppPermissions.applyPromotion, AppPermissions.printBill,
      ]) {
        expect(s.contains(p), isTrue, reason: p);
      }
      expect(s.contains(AppPermissions.cancelBill), isFalse);
      expect(UserRole.owner.hasDefaultPermission('ANYTHING'), isTrue);
    });
  });

  group('quy tắc vai trò (docs/ROLE_RULES.md)', () {
    Set<String> preset(String r) => AppPermissions.rolePresets[r]!.toSet();

    test('Quản lý mặc định KHÔNG hủy/xóa hóa đơn, không hủy món đã gửi bếp, không xem/xuất nhật ký thao tác', () {
      final m = preset(kRoleManager);
      for (final p in AppPermissions.ownerGrantOnly) {
        expect(m.contains(p), isFalse, reason: p);
      }
      expect(AppPermissions.ownerGrantOnly.toSet(), {
        AppPermissions.cancelBill,
        AppPermissions.cancelKitchenItem,
        AppPermissions.viewAuditLogs,
        AppPermissions.exportAuditLogs,
      });
    });

    test('Chủ cấp riêng qua customPermissions thì Quản lý dùng được (customPermissions chỉ THÊM)', () {
      final granted = UserModel(
        uid: 'm',
        username: 'ql',
        fullName: 'QL',
        roleId: 'ROLE_MANAGER',
        isRootOwner: false,
        customPermissions: [AppPermissions.cancelBill, AppPermissions.viewAuditLogs],
      );
      expect(granted.can(AppPermissions.cancelBill), isTrue);
      expect(granted.can(AppPermissions.viewAuditLogs), isTrue);
      expect(granted.can(AppPermissions.cancelKitchenItem), isFalse);
      expect(RoutePermissions.allowed('/audit-logs', granted.can), isTrue);
    });

    test('Nhân viên và Bếp không có quyền quản lý thực đơn; VIEW_MENU không đủ để vào các màn quản lý thực đơn', () {
      for (final r in [kRoleStaff, kRoleKitchen]) {
        final p = preset(r);
        expect(p.contains(AppPermissions.manageMenu), isFalse, reason: r);
        expect(p.contains(AppPermissions.editMenu), isFalse, reason: r);
        expect(p.contains(AppPermissions.deleteMenu), isFalse, reason: r);
        expect(p.contains(AppPermissions.changePrice), isFalse, reason: r);
        expect(p.contains(AppPermissions.manageTables), isFalse, reason: r);
        expect(p.contains(AppPermissions.manageNoteCatalog), isFalse, reason: r);
        final u = UserModel(uid: 'u', username: 'u', fullName: 'U', roleId: r, isRootOwner: false);
        expect(u.can(AppPermissions.viewMenu), isTrue, reason: r);
        expect(u.can(AppPermissions.manageMenu), isFalse, reason: r); // không còn alias VIEW_MENU
        for (final path in ['/menu-management', '/category-management', '/zone-management']) {
          expect(RoutePermissions.allowed(path, u.can), isFalse, reason: '$r $path');
        }
      }
      final mgr = UserModel(uid: 'm', username: 'm', fullName: 'M', roleId: 'ROLE_MANAGER', isRootOwner: false);
      expect(RoutePermissions.allowed('/menu-management', mgr.can), isTrue);
      expect(RoutePermissions.allowed('/category-management', mgr.can), isTrue);
    });

    test('Nhật ký thao tác và phiếu bàn giao ca: Nhân viên/Bếp không vào được; Quản lý vào được phiếu bàn giao', () {
      final staff = UserModel(uid: 's', username: 's', fullName: 'S', roleId: 'ROLE_STAFF', isRootOwner: false);
      final mgr = UserModel(uid: 'm', username: 'm', fullName: 'M', roleId: 'ROLE_MANAGER', isRootOwner: false);
      expect(RoutePermissions.allowed('/audit-logs', staff.can), isFalse);
      expect(RoutePermissions.allowed('/audit-logs', mgr.can), isFalse);
      expect(RoutePermissions.allowed('/cash-shifts', staff.can), isFalse);
      expect(RoutePermissions.allowed('/cash-shifts', mgr.can), isTrue);
    });

    test('Quyền mới: phân phối mặc định theo vai trò', () {
      final m = preset(kRoleManager);
      for (final p in [
        AppPermissions.viewShiftHandover, AppPermissions.viewAllShifts, AppPermissions.viewAllBillsHistory,
        AppPermissions.toggleItemAvailability, AppPermissions.manageNoteCatalog,
      ]) {
        expect(m.contains(p), isTrue, reason: p);
      }
      for (final r in [kRoleStaff, kRoleKitchen]) {
        final p = preset(r);
        expect(p.contains(AppPermissions.toggleItemAvailability), isTrue, reason: r);
        expect(p.contains(AppPermissions.viewShiftHandover), isFalse, reason: r);
        expect(p.contains(AppPermissions.viewAllShifts), isFalse, reason: r);
        expect(p.contains(AppPermissions.viewAllBillsHistory), isFalse, reason: r);
        expect(p.contains(AppPermissions.manageNoteCatalog), isFalse, reason: r);
      }
      // Chủ quán có tất cả (kể cả mã mới)
      expect(UserRole.owner.hasDefaultPermission(AppPermissions.viewShiftHandover), isTrue);
      expect(AppPermissions.allPermissions.map((p) => p.key), containsAll([
        'VIEW_SHIFT_HANDOVER', 'VIEW_ALL_SHIFTS', 'VIEW_ALL_BILLS_HISTORY', 'TOGGLE_ITEM_AVAILABILITY', 'MANAGE_NOTE_CATALOG',
      ]));
    });
  });

  group('buildRoleCatalog', () {
    test('chỉ còn 4 vai trò hệ thống; bản ghi cũ được gộp theo hợp quyền', () {
      final stored = [
        RoleModel(id: 'ROLE_MANAGER_1', name: 'QL1', permissions: ['A']),
        RoleModel(id: 'ROLE_MANAGER_2', name: 'QL2', permissions: ['B']),
        RoleModel(id: 'ROLE_CASHIER', name: 'TN', permissions: ['C']),
        RoleModel(id: 'ROLE_WAITER', name: 'PV', permissions: ['D']),
        RoleModel(id: 'ROLE_CUSTOM_1', name: 'Tự tạo', permissions: ['E']),
      ];
      final cat = buildRoleCatalog(stored);
      expect(cat.map((r) => r.id).toList(), [kRoleOwner, kRoleManager, kRoleStaff, kRoleKitchen, 'ROLE_CUSTOM_1']);
      expect(findRoleById(cat, 'ROLE_MANAGER_2')!.permissions.toSet(), {'A', 'B'});
      expect(findRoleById(cat, 'waiter')!.permissions.toSet(), {'C', 'D'});
      expect(findRoleById(cat, 'ROLE_STAFF')!.name, contains(kStaffRoleLabel));
    });
    test('quyền trong RTDB của mã cũ vẫn có hiệu lực qua UserModel.can (hợp)', () {
      // (kiểm tra gián tiếp qua findRoleById)
      final cat = buildRoleCatalog([RoleModel(id: 'ROLE_CASHIER', name: 'TN', permissions: [AppPermissions.cancelBill])]);
      expect(findRoleById(cat, 'ROLE_STAFF')!.hasPermission(AppPermissions.cancelBill), isTrue);
    });
  });

  group('phân quyền màn hình', () {
    bool Function(String) canWith(Set<String> perms) => (p) => perms.contains(p);
    test('nhân viên mở được bàn/gọi món nhưng không vào kho, người dùng, ma trận quyền', () {
      final staff = AppPermissions.rolePresets[kRoleStaff]!.toSet();
      expect(RoutePermissions.allowed('/tables', canWith(staff)), isTrue);
      expect(RoutePermissions.allowed('/order-cart', canWith(staff)), isTrue);
      expect(RoutePermissions.allowed('/kitchen', canWith(staff)), isTrue);
      expect(RoutePermissions.allowed('/inventory', canWith(staff)), isFalse);
      expect(RoutePermissions.allowed('/user-management', canWith(staff)), isFalse);
      expect(RoutePermissions.allowed('/permissions-matrix', canWith(staff)), isFalse);
      expect(RoutePermissions.allowed('/printer-settings', canWith(staff)), isTrue); // cấu hình cục bộ của máy
    });
    test('bếp chỉ vào màn hình bếp', () {
      final k = AppPermissions.rolePresets[kRoleKitchen]!.toSet();
      expect(RoutePermissions.allowed('/kitchen', canWith(k)), isTrue);
      expect(RoutePermissions.allowed('/order-cart', canWith(k)), isFalse);
      expect(RoutePermissions.allowed('/audit-logs', canWith(k)), isFalse);
    });
  });
}
