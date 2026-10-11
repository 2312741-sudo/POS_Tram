// lib/core/permissions/app_permissions.dart

/// Mã vai trò CHUẨN (ghi vào RTDB). Mọi mã cũ vẫn được chấp nhận khi đọc (xem [normalizeRoleId]).
///  - Quản lý 1 + Quản lý 2  => ROLE_MANAGER ("Quản lý")
///  - Thu ngân + Phục vụ     => ROLE_STAFF   ("Nhân viên")
/// Nguồn song song: functions/src/permissions.ts, web/lib/roles.ts — giữ đồng bộ.
const String kRoleOwner = 'ROLE_OWNER';
const String kRoleManager = 'ROLE_MANAGER';
const String kRoleStaff = 'ROLE_STAFF';
const String kRoleKitchen = 'ROLE_KITCHEN';

/// Tên hiển thị vai trò gộp Thu ngân/Phục vụ — đổi tên chỉ cần sửa các hằng số này.
const String kStaffRoleLabel = 'Nhân viên';
const String kStaffRoleDescription = 'Thu ngân / Phục vụ';
const String kManagerRoleLabel = 'Quản lý';
const String kOwnerRoleLabel = 'Chủ cửa hàng';
const String kKitchenRoleLabel = 'Bếp / Bar';

const Set<String> _ownerAliases = {
  'owner', 'role_owner', 'chu', 'chu_cua_hang', 'chủ', 'chủ_cửa_hàng', 'admin',
};
const Set<String> _managerAliases = {
  'manager', 'role_manager', 'manager_1', 'manager_2', 'role_manager_1', 'role_manager_2',
  'manager1', 'manager2', 'legacymanager', 'legacy_manager',
  'ql', 'ql1', 'ql2', 'ql_1', 'ql_2', 'quan_ly', 'quan_ly_1', 'quan_ly_2',
  'quan_ly_cap_1', 'quan_ly_cap_2',
};
const Set<String> _staffAliases = {
  'role_staff', 'staff', 'employee', 'role_employee', 'cashier', 'role_cashier',
  'waiter', 'role_waiter', 'nhan_vien', 'nv', 'thu_ngan', 'phuc_vu',
};
const Set<String> _kitchenAliases = {'role_kitchen', 'kitchen', 'daubep', 'bep'};

/// Chuẩn hóa mã vai trò về mã chuẩn: ROLE_OWNER / ROLE_MANAGER / ROLE_STAFF / ROLE_KITCHEN.
/// Mã lạ giữ nguyên (đã trim); null/rỗng => ''.
String normalizeRoleId(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  final clean = trimmed.toLowerCase().replaceAll('-', '_').replaceAll(RegExp(r'\s+'), '_');
  if (_ownerAliases.contains(clean)) return kRoleOwner;
  if (_managerAliases.contains(clean)) return kRoleManager;
  if (_staffAliases.contains(clean)) return kRoleStaff;
  if (_kitchenAliases.contains(clean)) return kRoleKitchen;
  return trimmed;
}

/// Tên hiển thị tiếng Việt của một mã vai trò (kể cả mã cũ).
String roleDisplayLabel(String? raw) {
  switch (normalizeRoleId(raw)) {
    case kRoleOwner:
      return kOwnerRoleLabel;
    case kRoleManager:
      return kManagerRoleLabel;
    case kRoleStaff:
      return kStaffRoleLabel;
    case kRoleKitchen:
      return kKitchenRoleLabel;
    default:
      return (raw == null || raw.trim().isEmpty) ? kStaffRoleLabel : raw;
  }
}

/// Vai trò POS sau khi gộp: Chủ quán, Quản lý, Nhân viên (Thu ngân + Phục vụ), Bếp/Bar.
enum UserRole {
  owner,
  manager,
  staff,
  kitchen;

  // Tên cũ giữ lại để mã gọi cũ biên dịch được — tất cả trỏ về vai trò đã gộp.
  static const UserRole manager1 = UserRole.manager;
  static const UserRole manager2 = UserRole.manager;
  static const UserRole legacyManager = UserRole.manager;
  static const UserRole employee = UserRole.staff;

  bool get isOwner => this == UserRole.owner;
  bool get isManager => this == UserRole.manager;
  bool get isStaff => this == UserRole.staff;
  bool get isKitchen => this == UserRole.kitchen;
  bool get isEmployee => this == UserRole.staff;

  String get label {
    switch (this) {
      case UserRole.owner:
        return kOwnerRoleLabel;
      case UserRole.manager:
        return kManagerRoleLabel;
      case UserRole.staff:
        return kStaffRoleLabel;
      case UserRole.kitchen:
        return kKitchenRoleLabel;
    }
  }

  /// Mã vai trò chuẩn để ghi vào cơ sở dữ liệu.
  String get value {
    switch (this) {
      case UserRole.owner:
        return 'owner';
      case UserRole.manager:
        return kRoleManager;
      case UserRole.staff:
        return kRoleStaff;
      case UserRole.kitchen:
        return kRoleKitchen;
    }
  }

  /// Mã vai trò chuẩn dùng tra bảng quyền ([AppPermissions.rolePresets]).
  String get presetId {
    switch (this) {
      case UserRole.owner:
        return kRoleOwner;
      case UserRole.manager:
        return kRoleManager;
      case UserRole.staff:
        return kRoleStaff;
      case UserRole.kitchen:
        return kRoleKitchen;
    }
  }

  /// Parser chịu lỗi: mọi biến thể mã (kể cả mã cũ Quản lý 1/2, Thu ngân, Phục vụ) về vai trò đã gộp.
  static UserRole fromString(String? value) {
    switch (normalizeRoleId(value)) {
      case kRoleOwner:
        return UserRole.owner;
      case kRoleManager:
        return UserRole.manager;
      case kRoleKitchen:
        return UserRole.kitchen;
      default:
        return UserRole.staff;
    }
  }

  /// Quyền mặc định của vai trò (Chủ quán: toàn quyền; còn lại theo [AppPermissions.rolePresets]).
  bool hasDefaultPermission(String permKey) {
    if (isOwner) return true;
    return AppPermissions.rolePresets[presetId]?.contains(permKey) ?? false;
  }
}

/// Thông tin một quyền hạn trong danh mục.
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
  static const String catInventory = 'Kho hàng & Nguyên vật liệu';
  static const String catSupplier = 'Nhà cung cấp & Nhập hàng';
  static const String catPromoAdvanced = 'Khuyến mãi nâng cao';
  static const String catCustomer = 'Khách hàng & Tích điểm';
  static const String catOps = 'Vận hành & Thiết bị';

  // 1. Thực đơn & Giá
  static const String viewMenu = 'VIEW_MENU';
  static const String editMenu = 'EDIT_MENU';
  static const String deleteMenu = 'DELETE_MENU';
  static const String changePrice = 'CHANGE_PRICE';
  static const String manageMenu = 'MENU_MANAGEMENT'; // Quản lý thực đơn & Topping

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
  static const String discountItem = 'DISCOUNT_ITEM'; // Giảm giá món
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

  // 7. Kho hàng & Nguyên vật liệu
  static const String viewInventory = 'VIEW_INVENTORY';
  static const String editCatalogItem = 'EDIT_CATALOG_ITEM';
  static const String viewCostPrice = 'VIEW_COST_PRICE'; // Nhạy cảm - xem giá vốn
  static const String manageRecipes = 'MANAGE_RECIPES';
  static const String importCatalog = 'IMPORT_CATALOG';

  // 8. Nhà cung cấp & Nhập hàng
  static const String viewSuppliers = 'VIEW_SUPPLIERS';
  static const String editSuppliers = 'EDIT_SUPPLIERS';
  static const String createReceipt = 'CREATE_RECEIPT'; // Tạo phiếu nhập
  static const String inventoryStockIn = 'INVENTORY_STOCK_IN'; // Nhập kho
  static const String completeReceipt = 'COMPLETE_RECEIPT'; // Duyệt phiếu nhập
  static const String cancelReceipt = 'CANCEL_RECEIPT'; // Hủy phiếu nhập
  static const String createPurchaseReturn = 'CREATE_PURCHASE_RETURN';
  static const String recordSupplierPayment = 'RECORD_SUPPLIER_PAYMENT'; // Nhạy cảm

  // 9. Kiểm kho & Vận hành kho
  static const String createStocktake = 'CREATE_STOCKTAKE';
  static const String approveStocktake = 'APPROVE_STOCKTAKE'; // Nhạy cảm
  static const String createTransfer = 'CREATE_TRANSFER';
  static const String receiveTransfer = 'RECEIVE_TRANSFER';
  static const String createWaste = 'CREATE_WASTE';
  static const String inventoryWaste = 'INVENTORY_WASTE'; // Hủy kho
  static const String createInternalUse = 'CREATE_INTERNAL_USE';
  static const String inventoryStockOut = 'INVENTORY_STOCK_OUT'; // Xuất kho
  static const String createProduction = 'CREATE_PRODUCTION';

  // 10. Khuyến mãi nâng cao
  static const String createCampaign = 'CREATE_CAMPAIGN';
  static const String editCampaign = 'EDIT_CAMPAIGN';
  static const String activateCampaign = 'ACTIVATE_CAMPAIGN';
  static const String manageCodes = 'MANAGE_CODES'; // Phát hành/hủy mã voucher
  static const String exportCodes = 'EXPORT_CODES'; // Xuất danh sách mã
  static const String overrideManualDiscount = 'OVERRIDE_MANUAL_DISCOUNT'; // Nhạy cảm

  // Quyền bổ sung sau rà soát phân quyền (docs/PERMISSIONS_AUDIT.md)
  static const String copyMenu = 'COPY_MENU'; // Nhạy cảm
  static const String deleteItem = 'DELETE_ITEM';
  static const String manageTables = 'MANAGE_TABLES';
  static const String redeemPoints = 'REDEEM_POINTS';
  static const String viewCustomers = 'VIEW_CUSTOMERS';
  static const String manageCustomers = 'MANAGE_CUSTOMERS';
  static const String adjustPoints = 'ADJUST_POINTS'; // Nhạy cảm
  static const String manageLoyalty = 'MANAGE_LOYALTY'; // Nhạy cảm
  static const String exportReports = 'EXPORT_REPORTS';
  static const String exportAuditLogs = 'EXPORT_AUDIT_LOGS'; // Nhạy cảm
  static const String exportData = 'EXPORT_DATA';
  static const String viewCashShifts = 'VIEW_CASH_SHIFTS';
  static const String viewOnlineOrders = 'VIEW_ONLINE_ORDERS';
  static const String manageOnlineOrders = 'MANAGE_ONLINE_ORDERS';
  static const String viewKitchen = 'VIEW_KITCHEN';
  static const String manageManagerPin = 'MANAGE_MANAGER_PIN'; // Nhạy cảm
  static const String manageChamcongLink = 'MANAGE_CHAMCONG_LINK'; // Nhạy cảm
  static const String createSampleData = 'CREATE_SAMPLE_DATA';

  /// Quyền mặc định theo vai trò (mã chuẩn). Quản lý = HỢP Quản lý 1 + Quản lý 2 cũ;
  /// Nhân viên = HỢP Thu ngân + Phục vụ cũ. Chủ quán: toàn quyền (không liệt kê).
  /// Bản song song: web/lib/auth.tsx (ROLE_PERMISSIONS) — test parity ở web/test/permission-parity.test.ts.
  static const Map<String, List<String>> rolePresets = {
    'ROLE_MANAGER': [
      'VIEW_MENU', 'EDIT_MENU', 'CHANGE_PRICE', 'MENU_MANAGEMENT', 'OPEN_TABLE',
      'CHANGE_TABLE', 'MERGE_SPLIT_TABLE', 'SEND_KITCHEN', 'CANCEL_KITCHEN_ITEM',
      'CREATE_BILL', 'EDIT_BILL', 'APPLY_PROMOTION', 'MANUAL_DISCOUNT', 'DISCOUNT_ITEM',
      'CANCEL_BILL', 'PRINT_BILL', 'REPRINT_BILL', 'MANAGE_CASH_SHIFT', 'ADJUST_CASH_SHIFT',
      'VIEW_REPORTS', 'VIEW_AUDIT_LOGS', 'MANAGE_PROMOTIONS', 'VIEW_INVENTORY',
      'EDIT_CATALOG_ITEM', 'VIEW_COST_PRICE', 'MANAGE_RECIPES', 'VIEW_SUPPLIERS',
      'EDIT_SUPPLIERS', 'CREATE_RECEIPT', 'INVENTORY_STOCK_IN', 'COMPLETE_RECEIPT',
      'CREATE_PURCHASE_RETURN', 'RECORD_SUPPLIER_PAYMENT', 'CREATE_STOCKTAKE',
      'APPROVE_STOCKTAKE', 'CREATE_TRANSFER', 'RECEIVE_TRANSFER', 'CREATE_WASTE',
      'INVENTORY_WASTE', 'CREATE_INTERNAL_USE', 'INVENTORY_STOCK_OUT', 'CREATE_PRODUCTION',
      'CREATE_CAMPAIGN', 'EDIT_CAMPAIGN', 'ACTIVATE_CAMPAIGN', 'MANAGE_CODES', 'COPY_MENU',
      'DELETE_ITEM', 'MANAGE_TABLES', 'REDEEM_POINTS', 'VIEW_CUSTOMERS', 'MANAGE_CUSTOMERS',
      'ADJUST_POINTS', 'EXPORT_REPORTS', 'EXPORT_AUDIT_LOGS', 'EXPORT_DATA',
      'VIEW_CASH_SHIFTS', 'VIEW_ONLINE_ORDERS', 'MANAGE_ONLINE_ORDERS', 'VIEW_KITCHEN',
      'MANAGE_MANAGER_PIN', 'CREATE_SAMPLE_DATA',
    ],
    'ROLE_STAFF': [
      'VIEW_MENU', 'OPEN_TABLE', 'CHANGE_TABLE', 'SEND_KITCHEN', 'CREATE_BILL',
      'APPLY_PROMOTION', 'PRINT_BILL', 'DELETE_ITEM', 'REDEEM_POINTS', 'VIEW_CUSTOMERS',
      'MANAGE_CUSTOMERS', 'VIEW_ONLINE_ORDERS', 'MANAGE_ONLINE_ORDERS', 'VIEW_KITCHEN',
      'MANAGE_CASH_SHIFT', 'VIEW_CASH_SHIFTS',
    ],
    'ROLE_KITCHEN': [
      'VIEW_MENU', 'SEND_KITCHEN', 'VIEW_KITCHEN',
    ],
  };

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
      // Kho & NCC nhạy cảm
      viewCostPrice,
      approveStocktake,
      recordSupplierPayment,
      cancelReceipt,
      // KM nâng cao nhạy cảm
      overrideManualDiscount,
      manageCodes,
      copyMenu,
      adjustPoints,
      manageLoyalty,
      exportAuditLogs,
      manageManagerPin,
      manageChamcongLink,
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
    AppPermission(
      key: manageMenu,
      label: 'Quản lý thực đơn & Topping',
      category: catMenu,
      description: 'Quản lý toàn diện danh sách món, mã SKU, danh mục và topping.',
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
      key: discountItem,
      label: 'Giảm giá món',
      category: catBilling,
      description: 'Chiết khấu / giảm giá trực tiếp từng món ăn trên hóa đơn.',
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

    // Kho hàng & Nguyên vật liệu
    AppPermission(
      key: viewInventory,
      label: 'Xem tồn kho',
      category: catInventory,
      description: 'Xem danh sách hàng kho, số lượng tồn và thẻ kho.',
    ),
    AppPermission(
      key: editCatalogItem,
      label: 'Thêm & Sửa hàng kho',
      category: catInventory,
      description: 'Tạo nguyên vật liệu, công cụ dụng cụ, hàng bán có tồn.',
    ),
    AppPermission(
      key: viewCostPrice,
      label: 'Xem giá vốn',
      category: catInventory,
      description: 'Xem giá vốn hàng hóa (Thao tác nhạy cảm).',
    ),
    AppPermission(
      key: manageRecipes,
      label: 'Quản lý công thức chế biến',
      category: catInventory,
      description: 'Tạo, sửa định mức nguyên liệu cho món ăn.',
    ),
    AppPermission(
      key: importCatalog,
      label: 'Nhập dữ liệu hàng hóa',
      category: catInventory,
      description: 'Import danh sách hàng hóa từ file Excel.',
    ),

    // Nhà cung cấp & Nhập hàng
    AppPermission(
      key: viewSuppliers,
      label: 'Xem nhà cung cấp',
      category: catSupplier,
      description: 'Xem danh sách nhà cung cấp và lịch sử giao dịch.',
    ),
    AppPermission(
      key: editSuppliers,
      label: 'Thêm & Sửa nhà cung cấp',
      category: catSupplier,
      description: 'Tạo mới, cập nhật thông tin nhà cung cấp.',
    ),
    AppPermission(
      key: createReceipt,
      label: 'Tạo phiếu nhập hàng',
      category: catSupplier,
      description: 'Tạo phiếu nhập hàng từ nhà cung cấp.',
    ),
    AppPermission(
      key: inventoryStockIn,
      label: 'Nhập kho (Stock In)',
      category: catSupplier,
      description: 'Tạo và hoàn thành phiếu nhập hàng, tăng tồn kho và tính giá vốn bình quân.',
    ),
    AppPermission(
      key: completeReceipt,
      label: 'Duyệt phiếu nhập',
      category: catSupplier,
      description: 'Hoàn thành phiếu nhập, tăng tồn kho và ghi công nợ.',
    ),
    AppPermission(
      key: cancelReceipt,
      label: 'Hủy phiếu nhập',
      category: catSupplier,
      description: 'Hủy phiếu nhập đã hoàn thành (Nhạy cảm - ảnh hưởng tồn kho).',
    ),
    AppPermission(
      key: createPurchaseReturn,
      label: 'Trả hàng nhập',
      category: catSupplier,
      description: 'Tạo phiếu trả hàng cho nhà cung cấp.',
    ),
    AppPermission(
      key: recordSupplierPayment,
      label: 'Thanh toán công nợ NCC',
      category: catSupplier,
      description: 'Ghi nhận thanh toán cho nhà cung cấp (Nhạy cảm).',
    ),

    // Kiểm kho & Vận hành kho
    AppPermission(
      key: createStocktake,
      label: 'Tạo phiếu kiểm kho',
      category: catInventory,
      description: 'Kiểm đếm thực tế và tạo phiếu kiểm kho.',
    ),
    AppPermission(
      key: approveStocktake,
      label: 'Duyệt cân bằng kho',
      category: catInventory,
      description: 'Xác nhận và cân bằng tồn kho sau kiểm đếm (Nhạy cảm).',
    ),
    AppPermission(
      key: createTransfer,
      label: 'Tạo phiếu chuyển hàng',
      category: catInventory,
      description: 'Chuyển hàng giữa các chi nhánh.',
    ),
    AppPermission(
      key: receiveTransfer,
      label: 'Nhận hàng chuyển kho',
      category: catInventory,
      description: 'Xác nhận nhận hàng từ chi nhánh khác.',
    ),
    AppPermission(
      key: createWaste,
      label: 'Tạo phiếu xuất hủy',
      category: catInventory,
      description: 'Ghi nhận hàng hỏng, hết hạn cần xuất hủy.',
    ),
    AppPermission(
      key: inventoryWaste,
      label: 'Hủy kho (Stock Waste)',
      category: catInventory,
      description: 'Tạo và hoàn thành phiếu xuất hủy hàng hỏng, hết hạn, giảm tồn kho.',
    ),
    AppPermission(
      key: createInternalUse,
      label: 'Xuất dùng nội bộ',
      category: catInventory,
      description: 'Ghi nhận hàng dùng nội bộ (nhân viên, vệ sinh, thử món).',
    ),
    AppPermission(
      key: inventoryStockOut,
      label: 'Xuất kho (Stock Out)',
      category: catInventory,
      description: 'Tạo và hoàn thành phiếu xuất kho (nội bộ, pha chế), giảm tồn kho.',
    ),
    AppPermission(
      key: createProduction,
      label: 'Tạo phiếu sản xuất',
      category: catInventory,
      description: 'Sản xuất thành phẩm từ nguyên vật liệu theo công thức.',
    ),

    // Khuyến mãi nâng cao
    AppPermission(
      key: createCampaign,
      label: 'Tạo chương trình khuyến mãi',
      category: catPromoAdvanced,
      description: 'Tạo mới chương trình giảm giá, tặng món, đồng giá.',
    ),
    AppPermission(
      key: editCampaign,
      label: 'Sửa chương trình khuyến mãi',
      category: catPromoAdvanced,
      description: 'Cập nhật điều kiện, hạn mức, lịch chương trình.',
    ),
    AppPermission(
      key: activateCampaign,
      label: 'Bật/tắt chương trình',
      category: catPromoAdvanced,
      description: 'Kích hoạt hoặc tạm dừng chương trình khuyến mãi.',
    ),
    AppPermission(
      key: manageCodes,
      label: 'Quản lý mã voucher',
      category: catPromoAdvanced,
      description: 'Phát hành, hủy mã khuyến mãi (Nhạy cảm).',
    ),
    AppPermission(
      key: exportCodes,
      label: 'Xuất danh sách mã',
      category: catPromoAdvanced,
      description: 'Tải về danh sách mã voucher đã phát hành.',
    ),
    AppPermission(
      key: overrideManualDiscount,
      label: 'Chiết khấu vượt quy định',
      category: catPromoAdvanced,
      description: 'Áp dụng giảm giá thủ công vượt mức giới hạn (Cực kỳ nhạy cảm).',
    ),

    // Bổ sung sau rà soát phân quyền
    AppPermission(
      key: copyMenu,
      label: 'Sao chép thực đơn giữa các quán',
      category: catMenu,
      description: 'Sao chép món, danh mục, topping từ quán này sang quán khác (ghi đè thực đơn quán đích).',
    ),
    AppPermission(
      key: deleteItem,
      label: 'Xóa món chưa gửi bếp',
      category: catTableOrder,
      description: 'Bỏ món khỏi đơn khi chưa gửi bếp (bắt buộc nhập lý do, ghi log).',
    ),
    AppPermission(
      key: manageTables,
      label: 'Quản lý bàn & khu vực',
      category: catTableOrder,
      description: 'Thêm, sửa, xóa bàn và khu vực bàn; sắp xếp sơ đồ bàn.',
    ),
    AppPermission(
      key: redeemPoints,
      label: 'Đổi điểm tích lũy',
      category: catCustomer,
      description: 'Dùng điểm của khách để giảm giá khi thanh toán.',
    ),
    AppPermission(
      key: viewCustomers,
      label: 'Xem khách hàng',
      category: catCustomer,
      description: 'Xem danh sách khách hàng, điểm và hạng thành viên.',
    ),
    AppPermission(
      key: manageCustomers,
      label: 'Thêm & Sửa khách hàng',
      category: catCustomer,
      description: 'Tạo mới, cập nhật thông tin khách hàng (không gồm chỉnh điểm).',
    ),
    AppPermission(
      key: adjustPoints,
      label: 'Chỉnh điểm khách hàng',
      category: catCustomer,
      description: 'Cộng/trừ điểm trực tiếp cho khách (Nhạy cảm - ghi log).',
    ),
    AppPermission(
      key: manageLoyalty,
      label: 'Cấu hình tích điểm & hạng',
      category: catCustomer,
      description: 'Tỷ lệ tích/đổi điểm, mốc hạng thành viên, chia sẻ điểm toàn hệ thống (Nhạy cảm).',
    ),
    AppPermission(
      key: exportReports,
      label: 'Xuất báo cáo',
      category: catReports,
      description: 'Tải báo cáo doanh thu, ca, sản phẩm, kho, khuyến mãi ra Excel/PDF.',
    ),
    AppPermission(
      key: exportAuditLogs,
      label: 'Xuất lịch sử kiểm soát',
      category: catReports,
      description: 'Tải nhật ký thao tác nhân viên ra file (Nhạy cảm).',
    ),
    AppPermission(
      key: exportData,
      label: 'Xuất dữ liệu Excel',
      category: catAdmin,
      description: 'Xuất danh sách nhân sự, hàng hóa, khách hàng ra file Excel.',
    ),
    AppPermission(
      key: viewCashShifts,
      label: 'Xem lịch sử ca & két',
      category: catShift,
      description: 'Xem danh sách ca làm việc, tiền đầu ca/cuối ca và chênh lệch.',
    ),
    AppPermission(
      key: viewOnlineOrders,
      label: 'Xem đơn online',
      category: catOps,
      description: 'Xem danh sách đơn đặt hàng online.',
    ),
    AppPermission(
      key: manageOnlineOrders,
      label: 'Xử lý đơn online',
      category: catOps,
      description: 'Nhận, từ chối, hoàn tất đơn online.',
    ),
    AppPermission(
      key: viewKitchen,
      label: 'Xem màn hình Bếp/Bar',
      category: catOps,
      description: 'Mở màn hình KDS và cập nhật trạng thái chế biến.',
    ),
    AppPermission(
      key: manageManagerPin,
      label: 'Đặt PIN duyệt quản lý',
      category: catAdmin,
      description: 'Đặt/đổi mã PIN dùng để duyệt thao tác nhạy cảm tại quầy.',
    ),
    AppPermission(
      key: manageChamcongLink,
      label: 'Liên kết Chấm Công Trạm',
      category: catAdmin,
      description: 'Liên kết/ngắt liên kết quán với ứng dụng Chấm Công Trạm (Nhạy cảm).',
    ),
    AppPermission(
      key: createSampleData,
      label: 'Tạo dữ liệu mẫu',
      category: catAdmin,
      description: 'Sinh đơn hàng và khuyến mãi mẫu để thử hệ thống.',
    ),
  ];
}
