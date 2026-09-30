// lib/core/permissions/app_permissions.dart

/// 4 VAI TRÒ GỐC TỪ HỆ SINH THÁI TRẠM (CHẤM CÔNG TRẠM)
/// Theo mục 3.1 & 3.2 của BO_QUY_TAC_CHUNG_HE_SINH_THAI_TRAM.md
enum UserRole {
  owner,
  manager1,
  manager2,
  legacyManager,
  employee;

  bool get isOwner => this == UserRole.owner;
  bool get isManager1 => this == UserRole.manager1;
  bool get isManager2 => this == UserRole.manager2;
  bool get isLegacyManager => this == UserRole.legacyManager;
  bool get isManager =>
      this == UserRole.manager1 ||
      this == UserRole.manager2 ||
      this == UserRole.legacyManager;
  bool get isEmployee => this == UserRole.employee;

  String get label {
    switch (this) {
      case UserRole.owner:
        return 'Chủ cửa hàng';
      case UserRole.manager1:
        return 'Quản lý 1';
      case UserRole.manager2:
        return 'Quản lý 2';
      case UserRole.legacyManager:
        return 'Quản lý';
      case UserRole.employee:
        return 'Nhân viên';
    }
  }

  String get value {
    switch (this) {
      case UserRole.owner:
        return 'owner';
      case UserRole.manager1:
        return 'manager_1';
      case UserRole.manager2:
        return 'manager_2';
      case UserRole.legacyManager:
        return 'manager';
      case UserRole.employee:
        return 'employee';
    }
  }

  /// Parser siêu bền bỉ: Chống mọi lỗi định dạng chuỗi từ database theo chuẩn Hệ sinh thái Trạm
  static UserRole fromString(String? value) {
    if (value == null || value.trim().isEmpty) return UserRole.employee;
    final clean = value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    switch (clean) {
      case 'owner':
      case 'role_owner':
      case 'chu':
      case 'chu_cua_hang':
      case 'chủ':
      case 'chủ_cửa_hàng':
      case 'admin':
        return UserRole.owner;

      case 'manager_1':
      case 'manager1':
      case 'role_manager_1':
      case 'ql1':
      case 'ql_1':
      case 'quan_ly_1':
      case 'quan_ly_cap_1':
        return UserRole.manager1;

      case 'manager_2':
      case 'manager2':
      case 'role_manager_2':
      case 'ql2':
      case 'ql_2':
      case 'quan_ly_2':
      case 'quan_ly_cap_2':
        return UserRole.manager2;

      case 'manager':
      case 'role_manager':
      case 'ql':
      case 'quan_ly':
      case 'legacy_manager':
        return UserRole.legacyManager;

      case 'employee':
      case 'role_employee':
      case 'staff':
      case 'nhan_vien':
      case 'nv':
      default:
        return UserRole.employee;
    }
  }

  /// Kiểm tra quyền mặc định của vai trò trong môi trường F&B POS KiotViet
  bool hasDefaultPermission(String permKey) {
    if (isOwner) return true; // Chủ quán toàn quyền tối cao

    if (isManager1) {
      // Quản lý 1: Điều hành bán hàng, két tiền, duyệt hủy món, xem báo cáo, chiết khấu
      return [
        AppPermissions.viewMenu,
        AppPermissions.editMenu,
        AppPermissions.changePrice,
        AppPermissions.openTable,
        AppPermissions.changeTable,
        AppPermissions.mergeSplitTable,
        AppPermissions.sendKitchen,
        AppPermissions.cancelKitchenItem,
        AppPermissions.createBill,
        AppPermissions.editBill,
        AppPermissions.applyPromotion,
        AppPermissions.manualDiscount,
        AppPermissions.cancelBill,
        AppPermissions.printBill,
        AppPermissions.reprintBill,
        AppPermissions.manageCashShift,
        AppPermissions.viewReports,
        AppPermissions.viewAuditLogs,
      ].contains(permKey);
    }

    if (isManager2) {
      // Quản lý 2: Giám sát ca, mở bàn, đổi bàn, in bill, xem ca két
      return [
        AppPermissions.viewMenu,
        AppPermissions.openTable,
        AppPermissions.changeTable,
        AppPermissions.mergeSplitTable,
        AppPermissions.sendKitchen,
        AppPermissions.createBill,
        AppPermissions.applyPromotion,
        AppPermissions.printBill,
        AppPermissions.manageCashShift,
        AppPermissions.viewReports,
      ].contains(permKey);
    }

    // Nhân viên phục vụ / Thu ngân thông thường
    return [
      AppPermissions.viewMenu,
      AppPermissions.openTable,
      AppPermissions.changeTable,
      AppPermissions.sendKitchen,
      AppPermissions.createBill,
      AppPermissions.applyPromotion,
      AppPermissions.printBill,
    ].contains(permKey);
  }
}

/// Danh sách quyền hạn chi tiết trong hệ thống nhà hàng F&B
class AppPermission {
  final String key;
  final String label;
  final String category;
  final String description;

  const AppPermission({
    required this.key,
    required this.label,
    required this.category,
    required this.description,
  });
}

class AppPermissions {
  // Danh mục nhóm quyền
  static const String catMenu = 'Thực đơn & Giá bán';
  static const String catTableOrder = 'Bàn & Gọi món';
  static const String catBilling = 'Hóa đơn & Thanh toán';
  static const String catShift = 'Ca làm việc & Két tiền';
  static const String catReports = 'Báo cáo & Thao tác log';
  static const String catAdmin = 'Quản trị hệ thống & Cài đặt';

  // 1. Thực đơn & Giá
  static const String viewMenu = 'VIEW_MENU';
  static const String editMenu = 'EDIT_MENU';
  static const String deleteMenu = 'DELETE_MENU';
  static const String changePrice = 'CHANGE_PRICE';

  // 2. Bàn & Gọi món
  static const String openTable = 'OPEN_TABLE';
  static const String changeTable = 'CHANGE_TABLE';
  static const String mergeSplitTable = 'MERGE_SPLIT_TABLE';
  static const String sendKitchen = 'SEND_KITCHEN';
  static const String cancelKitchenItem = 'CANCEL_KITCHEN_ITEM'; // Nhạy cảm chống gian lận

  // 3. Hóa đơn & Thanh toán
  static const String createBill = 'CREATE_BILL';
  static const String editBill = 'EDIT_BILL';
  static const String applyPromotion = 'APPLY_PROMOTION';
  static const String manualDiscount = 'MANUAL_DISCOUNT'; // Nhạy cảm
  static const String cancelBill = 'CANCEL_BILL'; // Nhạy cảm
  static const String printBill = 'PRINT_BILL';
  static const String reprintBill = 'REPRINT_BILL'; // Nhạy cảm

  // 4. Ca làm việc & Két tiền (KiotViet Cash Shift)
  static const String manageCashShift = 'MANAGE_CASH_SHIFT'; // Mở ca, chốt két tiền mặt
  static const String adjustCashShift = 'ADJUST_CASH_SHIFT'; // Thu/Chi phát sinh trong két

  // 5. Báo cáo & Lịch sử
  static const String viewReports = 'VIEW_REPORTS';
  static const String viewAuditLogs = 'VIEW_AUDIT_LOGS';

  // 6. Quản trị & Cài đặt
  static const String manageUsers = 'MANAGE_USERS';
  static const String manageRolesPermissions = 'MANAGE_ROLES_PERMISSIONS';
  static const String managePromotions = 'MANAGE_PROMOTIONS';
  static const String manageStoreSettings = 'MANAGE_STORE_SETTINGS';

  static bool isSensitive(String permKey) {
    const sensitive = {
      cancelBill,
      cancelKitchenItem,
      manualDiscount,
      reprintBill,
      manageRolesPermissions,
      manageUsers,
      manageStoreSettings,
      viewAuditLogs,
      adjustCashShift,
    };
    return sensitive.contains(permKey);
  }

  /// Toàn bộ danh sách 20 quyền chi tiết
  static const List<AppPermission> allPermissions = [
    // Menu
    AppPermission(
      key: viewMenu,
      label: 'Xem thực đơn',
      category: catMenu,
      description: 'Cho phép xem danh sách món ăn, giá và danh mục.',
    ),
    AppPermission(
      key: editMenu,
      label: 'Thêm & Sửa món ăn',
      category: catMenu,
      description: 'Thêm món mới, cập nhật tên, mô tả, danh mục, topping.',
    ),
    AppPermission(
      key: deleteMenu,
      label: 'Xóa món ăn',
      category: catMenu,
      description: 'Xóa vĩnh viễn món ăn khỏi thực đơn quán.',
    ),
    AppPermission(
      key: changePrice,
      label: 'Chỉnh sửa giá bán',
      category: catMenu,
      description: 'Quyền thay đổi giá niêm yết của các món ăn.',
    ),

    // Table & Order
    AppPermission(
      key: openTable,
      label: 'Mở bàn & Gọi món',
      category: catTableOrder,
      description: 'Chọn bàn và thêm món cho khách.',
    ),
    AppPermission(
      key: changeTable,
      label: 'Đổi bàn / Chuyển khu vực',
      category: catTableOrder,
      description: 'Chuyển toàn bộ order từ bàn này sang bàn trống khác.',
    ),
    AppPermission(
      key: mergeSplitTable,
      label: 'Ghép bàn & Tách bàn',
      category: catTableOrder,
      description: 'Ghép nhiều bàn thanh toán chung hoặc tách order ra bàn mới.',
    ),
    AppPermission(
      key: sendKitchen,
      label: 'Gửi bếp / Pha chế',
      category: catTableOrder,
      description: 'Báo đơn chế biến đến màn hình KDS Bếp/Bar.',
    ),
    AppPermission(
      key: cancelKitchenItem,
      label: 'Hủy món đã gửi bếp',
      category: catTableOrder,
      description: 'Hủy món khi bếp đã nhận (Thao tác nhạy cảm - sẽ ghi log).',
    ),

    // Billing
    AppPermission(
      key: createBill,
      label: 'Tạo hóa đơn & Thanh toán',
      category: catBilling,
      description: 'Tính tiền, in bill, thu tiền khách.',
    ),
    AppPermission(
      key: editBill,
      label: 'Chỉnh sửa hóa đơn',
      category: catBilling,
      description: 'Sửa các mục trước khi in bill.',
    ),
    AppPermission(
      key: applyPromotion,
      label: 'Áp dụng mã Voucher/CTKM',
      category: catBilling,
      description: 'Chọn chương trình khuyến mãi cho hóa đơn.',
    ),
    AppPermission(
      key: manualDiscount,
      label: 'Chiết khấu thủ công',
      category: catBilling,
      description: 'Tự nhập % hoặc số tiền bớt cho khách (Cần giám sát).',
    ),
    AppPermission(
      key: cancelBill,
      label: 'Hủy hóa đơn đã thanh toán',
      category: catBilling,
      description: 'Hủy hoặc hoàn tiền hóa đơn (Cực kỳ nhạy cảm - ghi log).',
    ),
    AppPermission(
      key: printBill,
      label: 'In hóa đơn',
      category: catBilling,
      description: 'Gửi lệnh in ra máy in nhiệt LAN / Bluetooth.',
    ),
    AppPermission(
      key: reprintBill,
      label: 'In lại hóa đơn cũ',
      category: catBilling,
      description: 'In lại phiếu hóa đơn đã thanh toán trước đó (Cảnh báo gian lận).',
    ),

    // Cash Shift
    AppPermission(
      key: manageCashShift,
      label: 'Quản lý ca két tiền',
      category: catShift,
      description: 'Khai báo tiền đầu ca và chốt sổ tiền mặt cuối ca.',
    ),
    AppPermission(
      key: adjustCashShift,
      label: 'Thu/Chi két tiền mặt',
      category: catShift,
      description: 'Ghi nhận các khoản rút hoặc nộp tiền mặt phát sinh trong ca.',
    ),

    // Reports
    AppPermission(
      key: viewReports,
      label: 'Xem báo cáo doanh thu',
      category: catReports,
      description: 'Xem tổng kết doanh số ca, ngày, tháng.',
    ),
    AppPermission(
      key: viewAuditLogs,
      label: 'Xem lịch sử kiểm soát',
      category: catReports,
      description: 'Xem toàn bộ lịch sử thao tác của nhân viên để chống gian lận.',
    ),

    // Admin
    AppPermission(
      key: manageUsers,
      label: 'Quản lý tài khoản nhân sự',
      category: catAdmin,
      description: 'Thêm mới, khóa tài khoản nhân viên.',
    ),
    AppPermission(
      key: manageRolesPermissions,
      label: 'Cấu hình vai trò & phân quyền',
      category: catAdmin,
      description: 'Tùy chỉnh ma trận quyền cho từng nhân sự.',
    ),
    AppPermission(
      key: managePromotions,
      label: 'Cài đặt khuyến mãi',
      category: catAdmin,
      description: 'Tạo mã voucher, giảm giá món hoặc chiết khấu bill.',
    ),
    AppPermission(
      key: manageStoreSettings,
      label: 'Cài đặt cấu hình cửa hàng',
      category: catAdmin,
      description: 'Thông tin quán, số tài khoản VietQR, IP máy in.',
    ),
  ];
}
