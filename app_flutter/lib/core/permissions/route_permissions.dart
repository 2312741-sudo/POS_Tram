// lib/core/permissions/route_permissions.dart
import 'app_permissions.dart';

/// Quyền cần có để mở từng màn hình (đường dẫn go_router) — kiểm tra tập trung ở bộ chuyển hướng
/// của AppRouter, nên gõ thẳng đường dẫn / deep-link cũng không vượt được phân quyền.
/// Mỗi mục là danh sách "một trong các quyền" (any-of). Đường dẫn không có trong bảng: mọi người dùng
/// đã đăng nhập đều mở được (ví dụ /tables, /printer-settings là cấu hình CỤC BỘ của máy).
class RoutePermissions {
  RoutePermissions._();

  static const Map<String, List<String>> _byPath = {
    '/kitchen': [AppPermissions.viewKitchen, AppPermissions.sendKitchen],
    '/order-list': [AppPermissions.openTable, AppPermissions.viewMenu],
    '/order-cart': [AppPermissions.openTable],
    '/promotions': [
      AppPermissions.managePromotions,
      AppPermissions.createCampaign,
      AppPermissions.editCampaign,
      AppPermissions.manageCodes,
    ],
    '/campaigns': [
      AppPermissions.managePromotions,
      AppPermissions.createCampaign,
      AppPermissions.editCampaign,
      AppPermissions.manageCodes,
    ],
    '/campaign-form': [AppPermissions.createCampaign, AppPermissions.editCampaign, AppPermissions.managePromotions],
    '/voucher-management': [AppPermissions.manageCodes, AppPermissions.managePromotions],
    '/audit-logs': [AppPermissions.viewAuditLogs],
    '/permissions-matrix': [AppPermissions.manageRolesPermissions],
    '/user-management': [AppPermissions.manageUsers],
    '/menu-management': [AppPermissions.viewMenu],
    '/category-management': [AppPermissions.manageMenu, AppPermissions.editMenu],
    '/zone-management': [AppPermissions.manageTables],
    '/online-orders': [AppPermissions.viewOnlineOrders],
    '/online-order-detail': [AppPermissions.viewOnlineOrders],
    '/dashboard': [AppPermissions.viewReports],
    '/reports-hub': [AppPermissions.viewReports],
    '/end-of-day-report': [AppPermissions.viewReports],
    '/cash-shifts': [AppPermissions.viewCashShifts, AppPermissions.viewReports, AppPermissions.manageCashShift],
    '/customers': [AppPermissions.viewCustomers, AppPermissions.viewReports],
    '/inventory': [AppPermissions.viewInventory],
    '/purchase-receipt': [AppPermissions.viewInventory],
    '/stock-card': [AppPermissions.viewInventory],
    '/inventory-report': [AppPermissions.viewInventory],
    '/promotion-report': [AppPermissions.managePromotions, AppPermissions.viewReports],
    '/history': [
      AppPermissions.createBill,
      AppPermissions.viewReports,
      AppPermissions.reprintBill,
      AppPermissions.cancelBill,
    ],
  };

  /// Quyền (any-of) cần cho [path]; null = không yêu cầu quyền cụ thể.
  static List<String>? requiredFor(String path) => _byPath[path];

  /// [can] trả lời "người dùng hiện tại có quyền này không".
  static bool allowed(String path, bool Function(String permission) can) {
    final required = _byPath[path];
    if (required == null) return true;
    return required.any(can);
  }
}
