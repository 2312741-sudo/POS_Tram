// test/auth_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/permissions/app_permissions.dart';
import 'package:tram_flutter/core/services/auth_service.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  group('Auth Contract Tests (docs/AUTH_CONTRACT.md)', () {
    // =========================================================================
    // 1. CHUẨN HÓA USERNAME & SINH EMAIL FIREBASE AUTH
    // =========================================================================
    group('1. Username Normalization & Email Synthesis', () {
      test('Hợp lệ: chữ thường, số, gạch dưới, gạch ngang (3-30 ký tự)', () {
        expect(AuthUtils.isValidUsername('thungan1'), isTrue);
        expect(AuthUtils.isValidUsername('admin'), isTrue);
        expect(AuthUtils.isValidUsername('bep_truong'), isTrue);
        expect(AuthUtils.isValidUsername('ql-kho'), isTrue);
        expect(AuthUtils.isValidUsername('staff_01'), isTrue);
        expect(AuthUtils.isValidUsername('abc'), isTrue); // độ dài tối thiểu 3
        expect(AuthUtils.isValidUsername('a12345678901234567890123456789'), isTrue); // độ dài 30
      });

      test('Không hợp lệ: dấu cách, dấu chấm, tiếng Việt có dấu, ký tự đặc biệt, quá ngắn/quá dài', () {
        expect(AuthUtils.isValidUsername('thu ngan'), isFalse); // Chứa dấu cách
        expect(AuthUtils.isValidUsername('thu.ngan'), isFalse); // Chứa dấu chấm (xung đột tách chuỗi)
        expect(AuthUtils.isValidUsername('thu_ngân'), isFalse); // Tiếng Việt có dấu
        expect(AuthUtils.isValidUsername('ab'), isFalse); // Quá ngắn (< 3 ký tự)
        expect(AuthUtils.isValidUsername(''), isFalse); // Rỗng
        expect(AuthUtils.isValidUsername('a' * 31), isFalse); // Quá dài (> 30 ký tự)
        expect(AuthUtils.isValidUsername('admin@'), isFalse); // Ký tự đặc biệt
        expect(AuthUtils.isValidUsername('admin#123'), isFalse); // Ký tự đặc biệt
      });

      test('Sinh Email Firebase Auth theo đúng hợp đồng: {username}.{storeCode}@tram.local', () {
        // Case 1: TRAM01 + thungan1 -> thungan1.tram01@tram.local
        expect(
          AuthUtils.buildAuthEmail('thungan1', 'TRAM01'),
          equals('thungan1.tram01@tram.local'),
        );

        // Case 2: TRAM01 + admin -> admin.tram01@tram.local
        expect(
          AuthUtils.buildAuthEmail('admin', 'TRAM01'),
          equals('admin.tram01@tram.local'),
        );

        // Case 3: TRAM02 + bep_truong -> bep_truong.tram02@tram.local
        expect(
          AuthUtils.buildAuthEmail('bep_truong', 'TRAM02'),
          equals('bep_truong.tram02@tram.local'),
        );

        // Case 4: storeCode và username viết hoa hoặc có khoảng trắng được tự động chuẩn hóa
        expect(
          AuthUtils.buildAuthEmail(' QL-KHO ', ' tram01 '),
          equals('ql-kho.tram01@tram.local'),
        );
      });
    });

    // =========================================================================
    // 2. KHÓA TẠM THỜI SAU 5 LẦN SAI (BRUTE-FORCE LOCKOUT)
    // =========================================================================
    group('2. Brute-Force Temporary Lockout Logic', () {
      test('Quy định ngưỡng: tối đa 5 lần sai, khóa trong 15 phút (900.000 ms)', () {
        expect(AuthService.maxFailedAttempts, equals(5));
        expect(AuthService.lockoutDurationMs, equals(15 * 60 * 1000));
      });

      test('isLockoutActive xác định đúng trạng thái khóa', () {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Đang trong thời gian khóa (lockedUntil trong tương lai)
        final futureLock = now + 10 * 60 * 1000;
        expect(AuthService.isLockoutActive(futureLock, now), isTrue);

        // Đã hết hạn khóa (lockedUntil trong quá khứ)
        final pastLock = now - 1000;
        expect(AuthService.isLockoutActive(pastLock, now), isFalse);

        // Chưa từng bị khóa (lockedUntil == null hoặc 0)
        expect(AuthService.isLockoutActive(null, now), isFalse);
        expect(AuthService.isLockoutActive(0, now), isFalse);
      });

      test('calculateRemainingLockoutSeconds tính chính xác số giây còn lại', () {
        final now = 1771900000000;

        // Khóa còn 900 giây (15 phút)
        final lockedUntil = now + 900 * 1000;
        expect(AuthService.calculateRemainingLockoutSeconds(lockedUntil, now), equals(900));

        // Khóa còn 45.2 giây -> làm tròn lên 46 giây
        final partialLock = now + 45200;
        expect(AuthService.calculateRemainingLockoutSeconds(partialLock, now), equals(46));

        // Đã hết hạn khóa -> trả về 0
        final expiredLock = now - 5000;
        expect(AuthService.calculateRemainingLockoutSeconds(expiredLock, now), equals(0));
        expect(AuthService.calculateRemainingLockoutSeconds(null, now), equals(0));
      });
    });

    // =========================================================================
    // 3. USER MODEL & BẢO MẬT (TUYỆT ĐỐI KHÔNG LƯU PASSWORD)
    // =========================================================================
    group('3. UserModel Schema & Security Rule Compliance', () {
      test('toMap() không bao giờ chứa trường password (tuân thủ RTDB validate rule)', () {
        final user = UserModel(
          uid: 'uid_test_123',
          username: 'thungan1',
          fullName: 'Nguyễn Thu Ngân',
          password: 'some_sensitive_password', // constructor nhận để tương thích
          roleId: 'ROLE_CASHIER',
          isRootOwner: false,
          customPermissions: ['MANUAL_DISCOUNT'],
          isActive: true,
          phone: '0912345678',
          createdAt: 1771900000000,
          lastLoginAt: 1771902000000,
          mustChangePassword: true,
        );

        final map = user.toMap();

        // TUYỆT ĐỐI KHÔNG CÓ TRƯỜNG PASSWORD
        expect(map.containsKey('password'), isFalse);
        expect(map['uid'], equals('uid_test_123'));
        expect(map['username'], equals('thungan1'));
        expect(map['fullName'], equals('Nguyễn Thu Ngân'));
        expect(map['roleId'], equals('ROLE_CASHIER'));
        expect(map['isRootOwner'], isFalse);
        expect(map['customPermissions'], equals(['MANUAL_DISCOUNT']));
        expect(map['isActive'], isTrue);
        expect(map['phone'], equals('0912345678'));
        expect(map['createdAt'], equals(1771900000000));
        expect(map['lastLoginAt'], equals(1771902000000));
        expect(map['mustChangePassword'], isTrue);
      });

      test('fromMap() parse đầy đủ các trường mới và tương thích ngược UID fallback', () {
        final dbMap = {
          'uid': 'firebase_uid_abc',
          'username': 'qlkho',
          'fullName': 'Trần Quản Kho',
          'roleId': 'ROLE_MANAGER_1',
          'isRootOwner': false,
          'customPermissions': ['APPROVE_STOCKTAKE'],
          'isActive': true,
          'phone': '0988776655',
          'createdAt': 1771900100000,
          'lastLoginAt': 1771900500000,
          'mustChangePassword': false,
        };

        final parsed = UserModel.fromMap(dbMap);
        expect(parsed.uid, equals('firebase_uid_abc'));
        expect(parsed.username, equals('qlkho'));
        expect(parsed.fullName, equals('Trần Quản Kho'));
        expect(parsed.roleId, equals('ROLE_MANAGER_1'));
        expect(parsed.createdAt, equals(1771900100000));
        expect(parsed.lastLoginAt, equals(1771900500000));
        expect(parsed.mustChangePassword, isFalse);

        // Fallback UID khi node cũ chưa có trường uid bên trong
        final legacyMap = {
          'username': 'legacy_user',
          'fullName': 'Người Dùng Cũ',
          'roleId': 'ROLE_CASHIER',
        };
        final legacyParsed = UserModel.fromMap(legacyMap, 'fallback_key_uid');
        expect(legacyParsed.uid, equals('fallback_key_uid'));
        expect(legacyParsed.mustChangePassword, isFalse);
      });

      test('copyWith() cập nhật đúng thuộc tính', () {
        final user = UserModel(
          uid: 'uid_1',
          username: 'user1',
          fullName: 'User One',
          roleId: 'ROLE_CASHIER',
          mustChangePassword: true,
        );

        final updated = user.copyWith(
          fullName: 'User One Updated',
          mustChangePassword: false,
          lastLoginAt: 1771909999000,
        );

        expect(updated.fullName, equals('User One Updated'));
        expect(updated.mustChangePassword, isFalse);
        expect(updated.lastLoginAt, equals(1771909999000));
        expect(updated.username, equals('user1')); // giữ nguyên
        expect(updated.uid, equals('uid_1')); // giữ nguyên
      });
    });

    // =========================================================================
    // 4. KIỂM TRA PHÂN QUYỀN (RBAC & SOVEREIGN OWNER RULE)
    // =========================================================================
    group('4. RBAC & Sovereign Owner Rule Permissions', () {
      test('Chủ quán tối cao (isRootOwner == true) luôn có mọi quyền', () {
        final rootOwner = UserModel(
          uid: 'owner_uid',
          username: 'chutram',
          fullName: 'Chủ Quán Trạm',
          roleId: 'ROLE_OWNER',
          isRootOwner: true,
        );

        expect(rootOwner.isOwner, isTrue);
        expect(rootOwner.can(AppPermissions.manageUsers), isTrue);
        expect(rootOwner.can(AppPermissions.cancelBill), isTrue);
        expect(rootOwner.can(AppPermissions.cancelKitchenItem), isTrue);
        expect(rootOwner.can(AppPermissions.overrideManualDiscount), isTrue);
        expect(rootOwner.can(AppPermissions.viewCostPrice), isTrue);
        expect(rootOwner.can('ANY_UNKNOWN_FUTURE_PERMISSION'), isTrue); // Sovereign rule
      });

      test('Quản lý 1 (ROLE_MANAGER_1): có quyền chiết khấu, hủy món, kho hàng nhưng không có MANAGE_USERS', () {
        final manager1 = UserModel(
          uid: 'm1_uid',
          username: 'quanly1',
          fullName: 'Quản Lý Cấp 1',
          roleId: 'ROLE_MANAGER_1',
          isRootOwner: false,
        );

        expect(manager1.can(AppPermissions.viewMenu), isTrue);
        expect(manager1.can(AppPermissions.editMenu), isTrue);
        expect(manager1.can(AppPermissions.manualDiscount), isTrue);
        expect(manager1.can(AppPermissions.cancelKitchenItem), isTrue);
        expect(manager1.can(AppPermissions.viewInventory), isTrue);
        expect(manager1.can(AppPermissions.viewReports), isTrue);

        // Không có quyền quản trị người dùng tối cao
        expect(manager1.can(AppPermissions.manageUsers), isFalse);
      });

      test('Quản lý 2 (ROLE_MANAGER_2): giám sát ca, không có quyền hủy món hay sửa menu', () {
        final manager2 = UserModel(
          uid: 'm2_uid',
          username: 'quanly2',
          fullName: 'Quản Lý Cấp 2',
          roleId: 'ROLE_MANAGER_2',
          isRootOwner: false,
        );

        expect(manager2.can(AppPermissions.openTable), isTrue);
        expect(manager2.can(AppPermissions.changeTable), isTrue);
        expect(manager2.can(AppPermissions.createBill), isTrue);
        expect(manager2.can(AppPermissions.manageCashShift), isTrue);
        expect(manager2.can(AppPermissions.viewReports), isTrue);

        // Không có quyền nhạy cảm
        expect(manager2.can(AppPermissions.editMenu), isFalse);
        expect(manager2.can(AppPermissions.cancelKitchenItem), isFalse);
        expect(manager2.can(AppPermissions.manualDiscount), isFalse);
      });

      test('Nhân viên thông thường (ROLE_CASHIER / employee): chỉ có quyền bán hàng cơ bản', () {
        final cashier = UserModel(
          uid: 'cashier_uid',
          username: 'thungan1',
          fullName: 'Thu Ngân 1',
          roleId: 'ROLE_CASHIER',
          isRootOwner: false,
        );

        expect(cashier.can(AppPermissions.viewMenu), isTrue);
        expect(cashier.can(AppPermissions.openTable), isTrue);
        expect(cashier.can(AppPermissions.createBill), isTrue);
        expect(cashier.can(AppPermissions.printBill), isTrue);
        expect(cashier.can(AppPermissions.applyPromotion), isTrue);

        // Không có quyền hủy hóa đơn, chiết khấu tay hay quản lý ca
        expect(cashier.can(AppPermissions.cancelBill), isFalse);
        expect(cashier.can(AppPermissions.manualDiscount), isFalse);
        expect(cashier.can(AppPermissions.manageCashShift), isFalse);
        expect(cashier.can(AppPermissions.viewReports), isFalse);
      });

      test('Quyền riêng biệt (customPermissions) ghi đè và bổ sung quyền cho nhân viên', () {
        final cashierWithDiscount = UserModel(
          uid: 'cashier_special_uid',
          username: 'thungan_vip',
          fullName: 'Thu Ngân VIP',
          roleId: 'ROLE_CASHIER',
          isRootOwner: false,
          customPermissions: [AppPermissions.manualDiscount, AppPermissions.viewReports],
        );

        // Được cấp thêm qua customPermissions
        expect(cashierWithDiscount.can(AppPermissions.manualDiscount), isTrue);
        expect(cashierWithDiscount.can(AppPermissions.viewReports), isTrue);

        // Quyền chưa được cấp vẫn là false
        expect(cashierWithDiscount.can(AppPermissions.cancelBill), isFalse);
      });
    });
  });
}
