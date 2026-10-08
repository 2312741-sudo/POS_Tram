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
      // + Kho hàng, NCC, khuyến mãi nâng cao
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
        // Kho hàng
        AppPermissions.viewInventory,
        AppPermissions.editCatalogItem,
        AppPermissions.viewCostPrice,
        AppPermissions.manageRecipes,
        // NCC & Nhập hàng
        AppPermissions.viewSuppliers,
        AppPermissions.editSuppliers,
        AppPermissions.createReceipt,
        AppPermissions.inventoryStockIn,
        AppPermissions.completeReceipt,
        AppPermissions.createPurchaseReturn,
        // Kiểm kho & Vận hành
        AppPermissions.createStocktake,
        AppPermissions.approveStocktake,
        AppPermissions.createTransfer,
        AppPermissions.receiveTransfer,
        AppPermissions.createWaste,
        AppPermissions.inventoryWaste,
        AppPermissions.createInternalUse,
        AppPermissions.inventoryStockOut,
        AppPermissions.createProduction,
        // Thực đơn & Topping
        AppPermissions.manageMenu,
        // Chiết khấu & Giảm giá món
        AppPermissions.discountItem,
        // Khuyến mãi nâng cao
        AppPermissions.createCampaign,
        AppPermissions.editCampaign,
        AppPermissions.activateCampaign,
        AppPermissions.manageCodes,
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
        AppPermissions.discountItem,
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
  static const String catInventory = 'Kho hàng & Nguyên vật liệu';
  static const String catSupplier = 'Nhà cung cấp & Nhập hàng';
  static const String catPromoAdvanced = 'Khuyến mãi nâng cao';

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
  ];
}
