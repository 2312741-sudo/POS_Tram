/**
 * Danh mục MÃ QUYỀN (permission) dùng chung với app POS Flutter
 * (nguồn: app_flutter/lib/core/permissions/app_permissions.dart — giữ đồng bộ khi thêm quyền mới)
 * và MÃ HÀNH ĐỘNG ghi trong nhật ký thao tác (audit_logs.action).
 */

export interface PermissionCode {
  key: string;
  label: string;
  category: string;
  description: string;
}

export const PERMISSION_CATALOG: PermissionCode[] = [
  { key: "VIEW_MENU", label: "Xem thực đơn", category: "Thực đơn & Giá bán", description: "Cho phép xem danh sách món ăn, giá và danh mục." },
  { key: "EDIT_MENU", label: "Thêm & Sửa món ăn", category: "Thực đơn & Giá bán", description: "Thêm món mới, cập nhật tên, mô tả, danh mục, topping." },
  { key: "DELETE_MENU", label: "Xóa món ăn", category: "Thực đơn & Giá bán", description: "Xóa vĩnh viễn món ăn khỏi thực đơn quán." },
  { key: "CHANGE_PRICE", label: "Chỉnh sửa giá bán", category: "Thực đơn & Giá bán", description: "Quyền thay đổi giá niêm yết của các món ăn." },
  { key: "MENU_MANAGEMENT", label: "Quản lý thực đơn & Topping", category: "Thực đơn & Giá bán", description: "Quản lý toàn diện danh sách món, mã SKU, danh mục và topping." },
  { key: "OPEN_TABLE", label: "Mở bàn & Gọi món", category: "Bàn & Gọi món", description: "Chọn bàn và thêm món cho khách." },
  { key: "CHANGE_TABLE", label: "Đổi bàn / Chuyển khu vực", category: "Bàn & Gọi món", description: "Chuyển toàn bộ order từ bàn này sang bàn trống khác." },
  { key: "MERGE_SPLIT_TABLE", label: "Ghép bàn & Tách bàn", category: "Bàn & Gọi món", description: "Ghép nhiều bàn thanh toán chung hoặc tách order ra bàn mới." },
  { key: "SEND_KITCHEN", label: "Gửi bếp / Pha chế", category: "Bàn & Gọi món", description: "Báo đơn chế biến đến màn hình KDS Bếp/Bar." },
  { key: "CANCEL_KITCHEN_ITEM", label: "Hủy món đã gửi bếp", category: "Bàn & Gọi món", description: "Hủy món khi bếp đã nhận (Thao tác nhạy cảm - sẽ ghi log)." },
  { key: "CREATE_BILL", label: "Tạo hóa đơn & Thanh toán", category: "Hóa đơn & Thanh toán", description: "Tính tiền, in bill, thu tiền khách." },
  { key: "EDIT_BILL", label: "Chỉnh sửa hóa đơn", category: "Hóa đơn & Thanh toán", description: "Sửa các mục trước khi in bill." },
  { key: "APPLY_PROMOTION", label: "Áp dụng mã Voucher/CTKM", category: "Hóa đơn & Thanh toán", description: "Chọn chương trình khuyến mãi cho hóa đơn." },
  { key: "MANUAL_DISCOUNT", label: "Chiết khấu thủ công", category: "Hóa đơn & Thanh toán", description: "Tự nhập % hoặc số tiền bớt cho khách (Cần giám sát)." },
  { key: "DISCOUNT_ITEM", label: "Giảm giá món", category: "Hóa đơn & Thanh toán", description: "Chiết khấu / giảm giá trực tiếp từng món ăn trên hóa đơn." },
  { key: "CANCEL_BILL", label: "Hủy hóa đơn đã thanh toán", category: "Hóa đơn & Thanh toán", description: "Hủy hoặc hoàn tiền hóa đơn (Cực kỳ nhạy cảm - ghi log)." },
  { key: "PRINT_BILL", label: "In hóa đơn", category: "Hóa đơn & Thanh toán", description: "Gửi lệnh in ra máy in nhiệt LAN / Bluetooth." },
  { key: "REPRINT_BILL", label: "In lại hóa đơn cũ", category: "Hóa đơn & Thanh toán", description: "In lại phiếu hóa đơn đã thanh toán trước đó (Cảnh báo gian lận)." },
  { key: "MANAGE_CASH_SHIFT", label: "Quản lý ca két tiền", category: "Ca làm việc & Két tiền", description: "Khai báo tiền đầu ca và chốt sổ tiền mặt cuối ca." },
  { key: "ADJUST_CASH_SHIFT", label: "Thu/Chi két tiền mặt", category: "Ca làm việc & Két tiền", description: "Ghi nhận các khoản rút hoặc nộp tiền mặt phát sinh trong ca." },
  { key: "VIEW_REPORTS", label: "Xem báo cáo doanh thu", category: "Báo cáo & Thao tác log", description: "Xem tổng kết doanh số ca, ngày, tháng." },
  { key: "VIEW_AUDIT_LOGS", label: "Xem lịch sử kiểm soát", category: "Báo cáo & Thao tác log", description: "Xem toàn bộ lịch sử thao tác của nhân viên để chống gian lận." },
  { key: "MANAGE_USERS", label: "Quản lý tài khoản nhân sự", category: "Quản trị hệ thống & Cài đặt", description: "Thêm mới, khóa tài khoản nhân viên." },
  { key: "MANAGE_ROLES_PERMISSIONS", label: "Cấu hình vai trò & phân quyền", category: "Quản trị hệ thống & Cài đặt", description: "Tùy chỉnh ma trận quyền cho từng nhân sự." },
  { key: "MANAGE_PROMOTIONS", label: "Cài đặt khuyến mãi", category: "Quản trị hệ thống & Cài đặt", description: "Tạo mã voucher, giảm giá món hoặc chiết khấu bill." },
  { key: "MANAGE_STORE_SETTINGS", label: "Cài đặt cấu hình cửa hàng", category: "Quản trị hệ thống & Cài đặt", description: "Thông tin quán, số tài khoản VietQR, IP máy in." },
  { key: "VIEW_INVENTORY", label: "Xem tồn kho", category: "Kho hàng & Nguyên vật liệu", description: "Xem danh sách hàng kho, số lượng tồn và thẻ kho." },
  { key: "EDIT_CATALOG_ITEM", label: "Thêm & Sửa hàng kho", category: "Kho hàng & Nguyên vật liệu", description: "Tạo nguyên vật liệu, công cụ dụng cụ, hàng bán có tồn." },
  { key: "VIEW_COST_PRICE", label: "Xem giá vốn", category: "Kho hàng & Nguyên vật liệu", description: "Xem giá vốn hàng hóa (Thao tác nhạy cảm)." },
  { key: "MANAGE_RECIPES", label: "Quản lý công thức chế biến", category: "Kho hàng & Nguyên vật liệu", description: "Tạo, sửa định mức nguyên liệu cho món ăn." },
  { key: "IMPORT_CATALOG", label: "Nhập dữ liệu hàng hóa", category: "Kho hàng & Nguyên vật liệu", description: "Import danh sách hàng hóa từ file Excel." },
  { key: "VIEW_SUPPLIERS", label: "Xem nhà cung cấp", category: "Nhà cung cấp & Nhập hàng", description: "Xem danh sách nhà cung cấp và lịch sử giao dịch." },
  { key: "EDIT_SUPPLIERS", label: "Thêm & Sửa nhà cung cấp", category: "Nhà cung cấp & Nhập hàng", description: "Tạo mới, cập nhật thông tin nhà cung cấp." },
  { key: "CREATE_RECEIPT", label: "Tạo phiếu nhập hàng", category: "Nhà cung cấp & Nhập hàng", description: "Tạo phiếu nhập hàng từ nhà cung cấp." },
  { key: "INVENTORY_STOCK_IN", label: "Nhập kho (Stock In)", category: "Nhà cung cấp & Nhập hàng", description: "Tạo và hoàn thành phiếu nhập hàng, tăng tồn kho và tính giá vốn bình quân." },
  { key: "COMPLETE_RECEIPT", label: "Duyệt phiếu nhập", category: "Nhà cung cấp & Nhập hàng", description: "Hoàn thành phiếu nhập, tăng tồn kho và ghi công nợ." },
  { key: "CANCEL_RECEIPT", label: "Hủy phiếu nhập", category: "Nhà cung cấp & Nhập hàng", description: "Hủy phiếu nhập đã hoàn thành (Nhạy cảm - ảnh hưởng tồn kho)." },
  { key: "CREATE_PURCHASE_RETURN", label: "Trả hàng nhập", category: "Nhà cung cấp & Nhập hàng", description: "Tạo phiếu trả hàng cho nhà cung cấp." },
  { key: "RECORD_SUPPLIER_PAYMENT", label: "Thanh toán công nợ NCC", category: "Nhà cung cấp & Nhập hàng", description: "Ghi nhận thanh toán cho nhà cung cấp (Nhạy cảm)." },
  { key: "CREATE_STOCKTAKE", label: "Tạo phiếu kiểm kho", category: "Kho hàng & Nguyên vật liệu", description: "Kiểm đếm thực tế và tạo phiếu kiểm kho." },
  { key: "APPROVE_STOCKTAKE", label: "Duyệt cân bằng kho", category: "Kho hàng & Nguyên vật liệu", description: "Xác nhận và cân bằng tồn kho sau kiểm đếm (Nhạy cảm)." },
  { key: "CREATE_TRANSFER", label: "Tạo phiếu chuyển hàng", category: "Kho hàng & Nguyên vật liệu", description: "Chuyển hàng giữa các chi nhánh." },
  { key: "RECEIVE_TRANSFER", label: "Nhận hàng chuyển kho", category: "Kho hàng & Nguyên vật liệu", description: "Xác nhận nhận hàng từ chi nhánh khác." },
  { key: "CREATE_WASTE", label: "Tạo phiếu xuất hủy", category: "Kho hàng & Nguyên vật liệu", description: "Ghi nhận hàng hỏng, hết hạn cần xuất hủy." },
  { key: "INVENTORY_WASTE", label: "Hủy kho (Stock Waste)", category: "Kho hàng & Nguyên vật liệu", description: "Tạo và hoàn thành phiếu xuất hủy hàng hỏng, hết hạn, giảm tồn kho." },
  { key: "CREATE_INTERNAL_USE", label: "Xuất dùng nội bộ", category: "Kho hàng & Nguyên vật liệu", description: "Ghi nhận hàng dùng nội bộ (nhân viên, vệ sinh, thử món)." },
  { key: "INVENTORY_STOCK_OUT", label: "Xuất kho (Stock Out)", category: "Kho hàng & Nguyên vật liệu", description: "Tạo và hoàn thành phiếu xuất kho (nội bộ, pha chế), giảm tồn kho." },
  { key: "CREATE_PRODUCTION", label: "Tạo phiếu sản xuất", category: "Kho hàng & Nguyên vật liệu", description: "Sản xuất thành phẩm từ nguyên vật liệu theo công thức." },
  { key: "CREATE_CAMPAIGN", label: "Tạo chương trình khuyến mãi", category: "Khuyến mãi nâng cao", description: "Tạo mới chương trình giảm giá, tặng món, đồng giá." },
  { key: "EDIT_CAMPAIGN", label: "Sửa chương trình khuyến mãi", category: "Khuyến mãi nâng cao", description: "Cập nhật điều kiện, hạn mức, lịch chương trình." },
  { key: "ACTIVATE_CAMPAIGN", label: "Bật/tắt chương trình", category: "Khuyến mãi nâng cao", description: "Kích hoạt hoặc tạm dừng chương trình khuyến mãi." },
  { key: "MANAGE_CODES", label: "Quản lý mã voucher", category: "Khuyến mãi nâng cao", description: "Phát hành, hủy mã khuyến mãi (Nhạy cảm)." },
  { key: "EXPORT_CODES", label: "Xuất danh sách mã", category: "Khuyến mãi nâng cao", description: "Tải về danh sách mã voucher đã phát hành." },
  { key: "OVERRIDE_MANUAL_DISCOUNT", label: "Chiết khấu vượt quy định", category: "Khuyến mãi nâng cao", description: "Áp dụng giảm giá thủ công vượt mức giới hạn (Cực kỳ nhạy cảm)." },
];

export interface ActionCode {
  code: string;
  label: string;
  group: string;
  /** Hành động nhạy cảm (đánh dấu nghi vấn trong nhật ký) */
  sensitive?: boolean;
  /** Mã quyền cần có để thực hiện (nếu có) */
  permission?: string;
}

/** Mã hành động trong nhật ký thao tác (stores/{code}/audit_logs/*.action) */
export const ACTION_CATALOG: ActionCode[] = [
  { code: "ADD_ITEM", label: "Thêm món vào đơn", group: "Gọi món", permission: "OPEN_TABLE" },
  { code: "WEB_ORDER", label: "Bấm đơn trên Web (dự phòng khi app sự cố)", group: "Gọi món", permission: "OPEN_TABLE" },
  { code: "SEND_KITCHEN", label: "Gửi phiếu bếp", group: "Gọi món", permission: "SEND_KITCHEN" },
  { code: "UPDATE_ITEM_QTY", label: "Đổi số lượng món", group: "Gọi món", permission: "OPEN_TABLE" },
  { code: "DELETE_ITEM", label: "Xóa món chưa gửi bếp (bắt buộc lý do)", group: "Hủy / Xóa" },
  { code: "CANCEL_ITEM", label: "Bỏ bớt món", group: "Hủy / Xóa" },
  { code: "CANCEL_KITCHEN_ITEM", label: "Hủy món đã gửi bếp (cần PIN duyệt nếu thiếu quyền)", group: "Hủy / Xóa", sensitive: true, permission: "CANCEL_KITCHEN_ITEM" },
  { code: "CANCEL_ORDER", label: "Hủy cả đơn hàng", group: "Hủy / Xóa", sensitive: true, permission: "CANCEL_BILL" },
  { code: "DISCOUNT_ITEM", label: "Giảm giá món (cần PIN duyệt nếu thiếu quyền)", group: "Giảm giá", permission: "DISCOUNT_ITEM" },
  { code: "DISCOUNT_BILL", label: "Giảm giá cả đơn", group: "Giảm giá", permission: "MANUAL_DISCOUNT" },
  { code: "APPLY_PROMOTION", label: "Áp dụng khuyến mãi / voucher", group: "Giảm giá", permission: "APPLY_PROMOTION" },
  { code: "REDEEM_POINTS", label: "Đổi điểm tích lũy thành giảm giá", group: "Khách hàng" },
  { code: "CUSTOMER_CREATE", label: "Tạo khách hàng mới", group: "Khách hàng" },
  { code: "ADJUST_POINTS", label: "Chủ/Quản lý chỉnh điểm khách hàng", group: "Khách hàng", sensitive: true },
  { code: "LOYALTY_TIERS_UPDATE", label: "Sửa cấu hình điểm theo hạng", group: "Khách hàng", sensitive: true },
  { code: "LOYALTY_POOL_REQUEST", label: "Đề nghị chia sẻ điểm toàn hệ thống", group: "Khách hàng" },
  { code: "LOYALTY_POOL_CONFIRM", label: "Chủ xác nhận điểm dùng chung toàn hệ thống", group: "Khách hàng", sensitive: true },
  { code: "LOYALTY_POOL_REDEEM", label: "Trừ điểm dùng chung giữa các chi nhánh", group: "Khách hàng", sensitive: true },
  { code: "SAMPLE_DATA_CREATE", label: "Tạo dữ liệu mẫu (đơn + khuyến mãi)", group: "Hệ thống" },
  { code: "TRANSFER_TABLE", label: "Chuyển bàn", group: "Bàn", permission: "CHANGE_TABLE" },
  { code: "MERGE_TABLE", label: "Gộp bàn", group: "Bàn", permission: "MERGE_SPLIT_TABLE" },
  { code: "SPLIT_BILL", label: "Tách hóa đơn", group: "Bàn", permission: "MERGE_SPLIT_TABLE" },
  { code: "ZONE_SAVE", label: "Thêm / sửa khu vực bàn", group: "Bàn" },
  { code: "ZONE_DELETE", label: "Xóa khu vực bàn", group: "Bàn" },
  { code: "PAY_BILL", label: "Thanh toán hóa đơn", group: "Thanh toán", permission: "CREATE_BILL" },
  { code: "PAYMENT", label: "Thanh toán hóa đơn (mã cũ)", group: "Thanh toán", permission: "CREATE_BILL" },
  { code: "DELETE_HISTORY", label: "Xóa hóa đơn khỏi lịch sử", group: "Thanh toán", sensitive: true, permission: "CANCEL_BILL" },
  { code: "OPEN_SHIFT", label: "Mở ca két", group: "Ca làm việc", permission: "MANAGE_CASH_SHIFT" },
  { code: "CLOSE_SHIFT", label: "Chốt két / đóng ca", group: "Ca làm việc", permission: "MANAGE_CASH_SHIFT" },
  { code: "STOCK_SET_ONHAND", label: "Nhập / điều chỉnh số lượng tồn kho", group: "Kho hàng", permission: "INVENTORY_STOCK_IN" },
  { code: "DELETE_USER", label: "Xóa tài khoản nhân sự", group: "Hệ thống", sensitive: true, permission: "MANAGE_USERS" },
  { code: "FORCE_LOGOUT", label: "Buộc đăng xuất", group: "Hệ thống", sensitive: true },
  { code: "LOGIN", label: "Đăng nhập", group: "Hệ thống" },
  { code: "LOGOUT", label: "Đăng xuất", group: "Hệ thống" },
];
