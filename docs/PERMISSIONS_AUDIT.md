# Rà soát phân quyền POS Trạm (PERMISSIONS_AUDIT)

Phạm vi: Flutter (`app_flutter/lib/features/**`), Web (`web/app/dashboard/**`), Cloud Functions, `database.rules.json`.
Nguồn sự thật cho mã quyền: `app_flutter/lib/core/permissions/app_permissions.dart` (Flutter) và
`web/lib/permission-catalog.ts` + `web/lib/auth.tsx` (`ROLE_PERMISSIONS`) (Web). Hai bản **phải giống hệt** về mã quyền,
nhãn và quyền mặc định theo vai trò — được khóa bằng test `web/test/permission-parity.test.ts` (đọc thẳng file Dart).

## 1. Vai trò sau khi gộp

| Vai trò | Mã chuẩn | Nhãn | Mã cũ vẫn được chấp nhận (alias) |
|---|---|---|---|
| Chủ quán | `ROLE_OWNER` / `owner` | Chủ quán | `chu`, `admin`, `isRootOwner` |
| Quản lý | `ROLE_MANAGER` | Quản lý | `manager`, `manager_1`, `manager_2`, `ROLE_MANAGER_1`, `ROLE_MANAGER_2`, `ql`… |
| Nhân viên | `ROLE_STAFF` | Nhân viên (Thu ngân / Phục vụ) | `staff`, `employee`, `cashier`, `ROLE_CASHIER`, `waiter`, `ROLE_WAITER`… |
| Bếp / Bar | `ROLE_KITCHEN` | Bếp / Bar | `kitchen`, `daubep` |

- Chuẩn hóa: `normalizeRoleId` (Dart `app_permissions.dart`, web `lib/roles.ts`, functions `permissions.ts`). Ghi mới luôn mã chuẩn.
- Nhãn "Nhân viên" nằm trong **một hằng số mỗi nơi**: `kStaffRoleLabel` (Dart), `STAFF_ROLE_LABEL` (web `lib/roles.ts`), `STAFF_ROLE_LABEL` (functions).
- Quyền mặc định = **HỢP** quyền của hai vai trò cũ (không ai mất quyền).
- `customPermissions` của từng người chỉ **cộng thêm**; quyền mặc định của vai trò **không trừ bớt được** (vai trò lưu trong RTDB cũng chỉ cộng).

## 2. Ma trận mã quyền × vai trò (mặc định)

| Mã quyền | Tên | Nhóm | Chủ | Quản lý | Nhân viên | Bếp | Mới |
|---|---|---|:-:|:-:|:-:|:-:|:-:|
| `VIEW_MENU` | Xem thực đơn | Thực đơn & Giá bán | ✓ | ✓ | ✓ | ✓ |  |
| `EDIT_MENU` | Thêm & Sửa món ăn | Thực đơn & Giá bán | ✓ | ✓ |  |  |  |
| `DELETE_MENU` | Xóa món ăn | Thực đơn & Giá bán | ✓ |  |  |  |  |
| `CHANGE_PRICE` | Chỉnh sửa giá bán | Thực đơn & Giá bán | ✓ | ✓ |  |  |  |
| `MENU_MANAGEMENT` | Quản lý thực đơn & Topping | Thực đơn & Giá bán | ✓ | ✓ |  |  |  |
| `OPEN_TABLE` | Mở bàn & Gọi món | Bàn & Gọi món | ✓ | ✓ | ✓ |  |  |
| `CHANGE_TABLE` | Đổi bàn / Chuyển khu vực | Bàn & Gọi món | ✓ | ✓ | ✓ |  |  |
| `MERGE_SPLIT_TABLE` | Ghép bàn & Tách bàn | Bàn & Gọi món | ✓ | ✓ |  |  |  |
| `SEND_KITCHEN` | Gửi bếp / Pha chế | Bàn & Gọi món | ✓ | ✓ | ✓ | ✓ |  |
| `CANCEL_KITCHEN_ITEM` | Hủy món đã gửi bếp | Bàn & Gọi món | ✓ | ✓ |  |  |  |
| `CREATE_BILL` | Tạo hóa đơn & Thanh toán | Hóa đơn & Thanh toán | ✓ | ✓ | ✓ |  |  |
| `EDIT_BILL` | Chỉnh sửa hóa đơn | Hóa đơn & Thanh toán | ✓ | ✓ |  |  |  |
| `APPLY_PROMOTION` | Áp dụng mã Voucher/CTKM | Hóa đơn & Thanh toán | ✓ | ✓ | ✓ |  |  |
| `MANUAL_DISCOUNT` | Chiết khấu thủ công | Hóa đơn & Thanh toán | ✓ | ✓ |  |  |  |
| `DISCOUNT_ITEM` | Giảm giá món | Hóa đơn & Thanh toán | ✓ | ✓ |  |  |  |
| `CANCEL_BILL` | Hủy hóa đơn đã thanh toán | Hóa đơn & Thanh toán | ✓ | ✓ |  |  |  |
| `PRINT_BILL` | In hóa đơn | Hóa đơn & Thanh toán | ✓ | ✓ | ✓ |  |  |
| `REPRINT_BILL` | In lại hóa đơn cũ | Hóa đơn & Thanh toán | ✓ | ✓ |  |  |  |
| `MANAGE_CASH_SHIFT` | Quản lý ca két tiền | Ca làm việc & Két tiền | ✓ | ✓ | ✓ |  |  |
| `ADJUST_CASH_SHIFT` | Thu/Chi két tiền mặt | Ca làm việc & Két tiền | ✓ | ✓ |  |  |  |
| `VIEW_REPORTS` | Xem báo cáo doanh thu | Báo cáo & Thao tác log | ✓ | ✓ |  |  |  |
| `VIEW_AUDIT_LOGS` | Xem lịch sử kiểm soát | Báo cáo & Thao tác log | ✓ | ✓ |  |  |  |
| `MANAGE_USERS` | Quản lý tài khoản nhân sự | Quản trị hệ thống & Cài đặt | ✓ |  |  |  |  |
| `MANAGE_ROLES_PERMISSIONS` | Cấu hình vai trò & phân quyền | Quản trị hệ thống & Cài đặt | ✓ |  |  |  |  |
| `MANAGE_PROMOTIONS` | Cài đặt khuyến mãi | Quản trị hệ thống & Cài đặt | ✓ | ✓ |  |  |  |
| `MANAGE_STORE_SETTINGS` | Cài đặt cấu hình cửa hàng | Quản trị hệ thống & Cài đặt | ✓ |  |  |  |  |
| `VIEW_INVENTORY` | Xem tồn kho | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `EDIT_CATALOG_ITEM` | Thêm & Sửa hàng kho | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `VIEW_COST_PRICE` | Xem giá vốn | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `MANAGE_RECIPES` | Quản lý công thức chế biến | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `IMPORT_CATALOG` | Nhập dữ liệu hàng hóa | Kho hàng & Nguyên vật liệu | ✓ |  |  |  |  |
| `VIEW_SUPPLIERS` | Xem nhà cung cấp | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `EDIT_SUPPLIERS` | Thêm & Sửa nhà cung cấp | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `CREATE_RECEIPT` | Tạo phiếu nhập hàng | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `INVENTORY_STOCK_IN` | Nhập kho (Stock In) | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `COMPLETE_RECEIPT` | Duyệt phiếu nhập | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `CANCEL_RECEIPT` | Hủy phiếu nhập | Nhà cung cấp & Nhập hàng | ✓ |  |  |  |  |
| `CREATE_PURCHASE_RETURN` | Trả hàng nhập | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `RECORD_SUPPLIER_PAYMENT` | Thanh toán công nợ NCC | Nhà cung cấp & Nhập hàng | ✓ | ✓ |  |  |  |
| `CREATE_STOCKTAKE` | Tạo phiếu kiểm kho | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `APPROVE_STOCKTAKE` | Duyệt cân bằng kho | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `CREATE_TRANSFER` | Tạo phiếu chuyển hàng | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `RECEIVE_TRANSFER` | Nhận hàng chuyển kho | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `CREATE_WASTE` | Tạo phiếu xuất hủy | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `INVENTORY_WASTE` | Hủy kho (Stock Waste) | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `CREATE_INTERNAL_USE` | Xuất dùng nội bộ | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `INVENTORY_STOCK_OUT` | Xuất kho (Stock Out) | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `CREATE_PRODUCTION` | Tạo phiếu sản xuất | Kho hàng & Nguyên vật liệu | ✓ | ✓ |  |  |  |
| `CREATE_CAMPAIGN` | Tạo chương trình khuyến mãi | Khuyến mãi nâng cao | ✓ | ✓ |  |  |  |
| `EDIT_CAMPAIGN` | Sửa chương trình khuyến mãi | Khuyến mãi nâng cao | ✓ | ✓ |  |  |  |
| `ACTIVATE_CAMPAIGN` | Bật/tắt chương trình | Khuyến mãi nâng cao | ✓ | ✓ |  |  |  |
| `MANAGE_CODES` | Quản lý mã voucher | Khuyến mãi nâng cao | ✓ | ✓ |  |  |  |
| `EXPORT_CODES` | Xuất danh sách mã | Khuyến mãi nâng cao | ✓ |  |  |  |  |
| `OVERRIDE_MANUAL_DISCOUNT` | Chiết khấu vượt quy định | Khuyến mãi nâng cao | ✓ |  |  |  |  |
| `COPY_MENU` | Sao chép thực đơn giữa các quán | Thực đơn & Giá bán | ✓ | ✓ |  |  | mới |
| `DELETE_ITEM` | Xóa món chưa gửi bếp | Bàn & Gọi món | ✓ | ✓ | ✓ |  | mới |
| `MANAGE_TABLES` | Quản lý bàn & khu vực | Bàn & Gọi món | ✓ | ✓ |  |  | mới |
| `REDEEM_POINTS` | Đổi điểm tích lũy | Khách hàng & Tích điểm | ✓ | ✓ | ✓ |  | mới |
| `VIEW_CUSTOMERS` | Xem khách hàng | Khách hàng & Tích điểm | ✓ | ✓ | ✓ |  | mới |
| `MANAGE_CUSTOMERS` | Thêm & Sửa khách hàng | Khách hàng & Tích điểm | ✓ | ✓ | ✓ |  | mới |
| `ADJUST_POINTS` | Chỉnh điểm khách hàng | Khách hàng & Tích điểm | ✓ | ✓ |  |  | mới |
| `MANAGE_LOYALTY` | Cấu hình tích điểm & hạng | Khách hàng & Tích điểm | ✓ |  |  |  | mới |
| `EXPORT_REPORTS` | Xuất báo cáo | Báo cáo & Thao tác log | ✓ | ✓ |  |  | mới |
| `EXPORT_AUDIT_LOGS` | Xuất lịch sử kiểm soát | Báo cáo & Thao tác log | ✓ | ✓ |  |  | mới |
| `EXPORT_DATA` | Xuất dữ liệu Excel | Quản trị hệ thống & Cài đặt | ✓ | ✓ |  |  | mới |
| `VIEW_CASH_SHIFTS` | Xem lịch sử ca & két | Ca làm việc & Két tiền | ✓ | ✓ | ✓ |  | mới |
| `VIEW_ONLINE_ORDERS` | Xem đơn online | Vận hành & Thiết bị | ✓ | ✓ | ✓ |  | mới |
| `MANAGE_ONLINE_ORDERS` | Xử lý đơn online | Vận hành & Thiết bị | ✓ | ✓ | ✓ |  | mới |
| `VIEW_KITCHEN` | Xem màn hình Bếp/Bar | Vận hành & Thiết bị | ✓ | ✓ | ✓ | ✓ | mới |
| `MANAGE_MANAGER_PIN` | Đặt PIN duyệt quản lý | Quản trị hệ thống & Cài đặt | ✓ | ✓ |  |  | mới |
| `MANAGE_CHAMCONG_LINK` | Liên kết Chấm Công Trạm | Quản trị hệ thống & Cài đặt | ✓ |  |  |  | mới |
| `CREATE_SAMPLE_DATA` | Tạo dữ liệu mẫu | Quản trị hệ thống & Cài đặt | ✓ | ✓ |  |  | mới |

Chủ quán luôn có mọi quyền. Quản lý không có mặc định: `DELETE_MENU`, `MANAGE_USERS`, `MANAGE_ROLES_PERMISSIONS`, `MANAGE_STORE_SETTINGS`,
`IMPORT_CATALOG`, `CANCEL_RECEIPT`, `EXPORT_CODES`, `OVERRIDE_MANUAL_DISCOUNT`, `MANAGE_LOYALTY`, `MANAGE_CHAMCONG_LINK`.

## 3. Quyền mặc định của vai trò gộp

- **Quản lý** = QL1 ∪ QL2 (cả bộ Dart lẫn bộ Web, vốn đã lệch nhau): thực đơn (xem/sửa/giá/quản lý), bàn (đổi/ghép/tách), hủy món đã gửi bếp, hóa đơn
  (sửa/hủy/in lại), chiết khấu thủ công + giảm giá món, ca két (mở/kết/thu chi), báo cáo + nhật ký, khuyến mãi (CTKM, mã), kho/NCC/nhập-xuất-hủy-kiểm-chuyển-sản xuất,
  giá vốn, công thức, thanh toán công nợ NCC, và các quyền mới (xem bảng). Quản lý cũ mã `ROLE_MANAGER` trên Web trước đây chỉ có bộ QL2 → nay **được thêm** quyền.
- **Nhân viên** = Thu ngân ∪ Phục vụ: `VIEW_MENU`, `OPEN_TABLE`, `CHANGE_TABLE`, `SEND_KITCHEN`, `CREATE_BILL`, `APPLY_PROMOTION`, `PRINT_BILL`
  + mới: `DELETE_ITEM`, `REDEEM_POINTS`, `VIEW_CUSTOMERS`, `MANAGE_CUSTOMERS`, `VIEW_ONLINE_ORDERS`, `MANAGE_ONLINE_ORDERS`, `VIEW_KITCHEN`, `MANAGE_CASH_SHIFT`, `VIEW_CASH_SHIFTS`.
- **Bếp**: `VIEW_MENU`, `SEND_KITCHEN`, `VIEW_KITCHEN` (Web trước đây cũng vậy; Flutter trước đây cho Bếp *thừa hưởng bộ Nhân viên* do lỗi phân loại → nay Bếp chỉ còn quyền bếp).

### Phục vụ được THÊM gì khi gộp (để Chủ quyết định)

Quyền chức năng: `CREATE_BILL` (thanh toán), `APPLY_PROMOTION`, `PRINT_BILL`, `CHANGE_TABLE`, `MANAGE_CASH_SHIFT` (mở/kết ca của mình), `REDEEM_POINTS`, `VIEW/MANAGE_CUSTOMERS`, `VIEW/MANAGE_ONLINE_ORDERS`.
Rules RTDB (xem `docs/RULES_NOTES.md` §6): ghi hóa đơn `PAID`, `cash_shifts`, `customers`, tồn kho/điểm, voucher/counters, `online_orders`.
Các giới hạn dành riêng cho Phục vụ **biến mất**: không sửa/xóa hóa đơn đã thanh toán; không đọc khách hàng; không ghi tồn kho/điểm.
Muốn giữ người chỉ gọi món ở mức thấp: gán vai trò **Bếp**, hoặc (đề xuất bổ sung) thêm trường `deniedPermissions` cho từng người.

## 4. Bảng tính năng → mã quyền → nơi áp dụng

| Tính năng / hành động | Mã quyền | Vai trò mặc định | Nơi áp dụng (file) |
|---|---|---|---|
| Xem thực đơn / sửa món / sửa giá / quản lý topping | `VIEW_MENU`, `EDIT_MENU`, `CHANGE_PRICE`, `MENU_MANAGEMENT` | QL; NV xem | Flutter route `/menu-management`, `/category-management` (`route_permissions.dart`); Web `/dashboard/products` (`auth.tsx canAccessRoute`); rules `products/categories` (Chủ+Quản lý) |
| Xóa món khỏi thực đơn | `DELETE_MENU` | Chủ | UI menu |
| **Sao chép thực đơn giữa quán** | `COPY_MENU` (mới) | Chủ, QL | Flutter `menu_management_screen.dart` (`_canCopyMenu`); Web `lib/menu-copy.ts canCopyMenu` + `products/page.tsx`; rules (ghi `products` chỉ Chủ+QL) |
| Mở bàn, gọi món | `OPEN_TABLE` | QL, NV | Flutter route `/order-list`,`/order-cart`; Web `/dashboard/tables`, `WebOrderDialog` |
| Đổi bàn / ghép-tách bàn | `CHANGE_TABLE`, `MERGE_SPLIT_TABLE` | QL (+NV đổi bàn) | `order_cart_screen.dart`; Web `tables/page.tsx` |
| Gửi bếp | `SEND_KITCHEN` | QL, NV, Bếp | Flutter/Web tables |
| Xóa món chưa gửi bếp (bắt buộc lý do) | `DELETE_ITEM` (mới) | QL, NV | Flutter `order_cart_screen.dart` (`_ensureCanDeleteSaved`); Web `tables/page.tsx openRemoval` |
| Hủy món đã gửi bếp | `CANCEL_KITCHEN_ITEM` (+PIN QL) | QL | `order_cart_screen.dart`, Web tables; functions `managerPinLogic` |
| Thanh toán, in hóa đơn | `CREATE_BILL`, `PRINT_BILL` | QL, NV | `order_cart_screen.dart`; rules `bills/history` |
| In lại hóa đơn cũ | `REPRINT_BILL` | QL | `history_screen.dart` |
| Hủy/hoàn hóa đơn đã thanh toán, xóa lịch sử | `CANCEL_BILL` | QL | `history_screen.dart`, `bill_detail_sheet.dart`; rules xóa bill chỉ Chủ+QL |
| Chiết khấu thủ công / giảm giá món | `MANUAL_DISCOUNT`, `DISCOUNT_ITEM` (+PIN QL) | QL | `order_cart_screen.dart`; Web `LineDiscountDialog` |
| Áp dụng voucher/CTKM | `APPLY_PROMOTION` | QL, NV | `order_cart_screen.dart` |
| Đổi điểm tích lũy khi thanh toán | `REDEEM_POINTS` (mới) | QL, NV | `order_cart_screen.dart _showUsePointsDialog` |
| CRUD khuyến mãi / bật-tắt / mã voucher / hủy mã | `MANAGE_PROMOTIONS`, `CREATE/EDIT/ACTIVATE_CAMPAIGN`, `MANAGE_CODES`, `EXPORT_CODES` | QL (trừ `EXPORT_CODES`) | Flutter routes `/promotions`,`/campaigns`,`/campaign-form`,`/voucher-management`; Web `/dashboard/promotions` |
| Mở/kết ca két | `MANAGE_CASH_SHIFT` | QL, NV | `cash_shift_dialog.dart` (`_openShift`,`_closeShift`) |
| Thu/chi két phát sinh | `ADJUST_CASH_SHIFT` | QL | `cash_shift_dialog.dart` (`_addAdjustment`) |
| Xem lịch sử ca / phiếu bàn giao | `VIEW_CASH_SHIFTS` (mới) | QL, NV | Flutter route `/cash-shifts`; Web `/dashboard/shifts` |
| Báo cáo doanh thu, cuối ngày, sản phẩm, KM, khách | `VIEW_REPORTS` | QL | Flutter routes `/dashboard`,`/reports-hub`,`/end-of-day-report`; Web `canAccessRoute` |
| Xuất báo cáo Excel/PDF/in | `EXPORT_REPORTS` (mới) | QL | Flutter `report_export_service.dart` (+`revenue_tab`,`bills_tab`); Web `lib/export.ts` + `export-guard.ts` |
| Xem / xuất nhật ký thao tác | `VIEW_AUDIT_LOGS`, `EXPORT_AUDIT_LOGS` (mới) | QL | Flutter route `/audit-logs`; Web `/dashboard/audit` + `export.ts exportAuditLogs` |
| Khách hàng CRM: xem | `VIEW_CUSTOMERS` (mới) | QL, NV | Flutter route `/customers`; Web `customers/page.tsx` (kèm điều kiện rules) |
| Khách hàng: thêm/sửa | `MANAGE_CUSTOMERS` (mới) | QL, NV | rules `customers` (Chủ/QL/NV); mã hành động `CUSTOMER_CREATE` |
| Chỉnh điểm trực tiếp | `ADJUST_POINTS` (mới) | QL | Web `customers/page.tsx` (`canAdjust`); rules `customers` |
| Tỷ lệ tích/đổi điểm, mốc hạng, điểm dùng chung | `MANAGE_LOYALTY` (mới) | Chủ | Flutter `customer_management_screen.dart`; Web `customers/page.tsx`; rules `storeInfo` (chỉ Chủ); functions pooled loyalty (chủ xác nhận) |
| Xuất Excel nhân sự / hàng hóa / khách hàng | `EXPORT_DATA` (mới) | QL | Web `export.ts` (`exportUsers/Products/CustomersList`); Flutter `report_export_service.dart` (mã `CRM_*`) |
| Nhập Excel hàng hóa | `IMPORT_CATALOG` | Chủ | `excel_import_dialog.dart` |
| Kho: xem / thêm-sửa hàng / giá vốn / công thức | `VIEW_INVENTORY`, `EDIT_CATALOG_ITEM`, `VIEW_COST_PRICE`, `MANAGE_RECIPES` | QL | `inventory_screen.dart`, `stock_card_screen.dart`; Web `/dashboard/inventory` |
| Phiếu nhập/xuất/hủy/kiểm/chuyển/sản xuất | `CREATE_RECEIPT`/`INVENTORY_STOCK_IN`…, `APPROVE_STOCKTAKE`, `CANCEL_RECEIPT` | QL | `purchase_receipt_screen.dart`, `inventory_screen.dart`; Web inventory page |
| NCC, công nợ NCC | `VIEW_SUPPLIERS`, `EDIT_SUPPLIERS`, `RECORD_SUPPLIER_PAYMENT` | QL | `inventory_screen.dart` |
| Quản lý bàn & khu vực | `MANAGE_TABLES` (mới) | QL | Flutter FAB "Thêm Bàn" + route `/zone-management`; Web `tables/page.tsx` (ZoneSetup) |
| Đơn online | `VIEW_ONLINE_ORDERS`, `MANAGE_ONLINE_ORDERS` (mới) | QL, NV | Flutter route `/online-orders`; rules `online_orders` |
| Màn hình Bếp/KDS | `VIEW_KITCHEN` (mới) | QL, NV, Bếp | Flutter route `/kitchen` |
| Quản lý nhân sự (tạo/khóa/xóa/đặt lại mật khẩu) | `MANAGE_USERS` | Chủ | Flutter route `/user-management`; Web `/dashboard/users`; functions `canCallerManageUsers`/`canCallerResetPassword` |
| Ma trận vai trò & quyền | `MANAGE_ROLES_PERMISSIONS` | Chủ | Flutter route `/permissions-matrix` |
| Cài đặt cửa hàng / chi nhánh | `MANAGE_STORE_SETTINGS` | Chủ | Web `/dashboard/stores`; rules `storeInfo` |
| PIN duyệt quản lý (đặt PIN) | `MANAGE_MANAGER_PIN` (mới) | Chủ, QL | Flutter `manager_hub_screen.dart`; Web `tables/page.tsx`; functions `setManagerPin` (QL/Chủ) |
| Liên kết Chấm Công Trạm | `MANAGE_CHAMCONG_LINK` (mới) | Chủ | Flutter `chamcong_link_screen.dart`, hub; Web `stores/page.tsx`; functions `linkChamCongStore` (chủ cửa hàng chấm công) |
| Dữ liệu mẫu (đơn + khuyến mãi) | `CREATE_SAMPLE_DATA` (mới) | Chủ, QL | Web `orders/page.tsx` |
| Cài đặt máy in / giao diện sáng-tối | *(không cần mã quyền)* | mọi người | Cấu hình **cục bộ của máy** (Bluetooth/LAN, theme); việc *in* được gác bởi `PRINT_BILL`/`REPRINT_BILL` |
| Đổi mật khẩu của chính mình | *(không cần mã quyền)* | mọi người | `change_password_dialog.dart`, Web `change-password` |

## 5. Khoảng trống đã tìm thấy và đã xử lý

1. Danh mục quyền Dart/Web **lệch nhau** và preset QL1/QL2/Thu ngân khác nhau giữa Dart và Web (Web `ROLE_MANAGER` = QL2; Flutter `legacyManager`/Bếp = Nhân viên) → thống nhất 4 vai trò, thêm test parity.
2. Chỉ kiểm tra vai trò cứng (`isManager`, `isOwner`) ở CRM, ca két, hub, PIN, liên kết Chấm Công, tạo dữ liệu mẫu, điểm khách → chuyển sang mã quyền.
3. Không có kiểm tra quyền cho: màn Bếp, đơn online, khách hàng, lịch sử ca, quản lý bàn/khu vực, thu-chi két, mở/kết ca, đổi điểm, xóa món đã lưu, xuất báo cáo/nhật ký/dữ liệu → thêm mã + chặn ở route (Flutter, `RoutePermissions` trong `go_router.redirect`), nút, và handler.
4. Truy cập màn hình bằng đường dẫn trực tiếp ở Flutter không bị chặn → bộ chuyển hướng tập trung.
5. Xuất file Excel/PDF trên Web/Flutter không bị chặn → `export-guard.ts` (Web), `ReportExportService.ensureCanExport` (Flutter).
6. Mã hành động trong nhật ký (`ACTION_CATALOG`) thiếu liên kết quyền cho `DELETE_ITEM`, `CANCEL_ITEM`, `REDEEM_POINTS`, `CUSTOMER_CREATE`, `ADJUST_POINTS`, `LOYALTY_*`, `SAMPLE_DATA_CREATE`, `ZONE_*`, `FORCE_LOGOUT` → đã gán.
7. Trang Nhân viên (Web) tạo nút `users/{tên-đăng-nhập}` mồ côi mỗi lần sửa hồ sơ → chỉ đồng bộ khi nút đó đã tồn tại.

## 6. Còn tồn tại / rủi ro (cần Chủ quyết định)

- **Không trừ quyền được**: `customPermissions` và vai trò lưu trong RTDB chỉ *cộng*. Siết quyền một vai trò (ví dụ Nhân viên không thanh toán) cần thêm cơ chế `deniedPermissions` — chưa làm.
- **Thu/chi két** (`ADJUST_CASH_SHIFT`) nay yêu cầu quyền; Nhân viên **mặc định không có** (trước đây ứng dụng không chặn). Cấp riêng qua quyền riêng nếu cần.
- **Thêm bàn** (FAB) nay cần `MANAGE_TABLES` (trước: `OPEN_TABLE`) → Nhân viên không còn tự thêm bàn.
- **Bếp** trên Flutter mất bộ quyền Nhân viên (đã nói ở trên). Rules vẫn cho Bếp ghi một số nút vận hành.
- Chức năng chia nhỏ theo từng loại báo cáo (doanh thu/kho/KM/điểm) dùng chung `VIEW_REPORTS`; kho dùng `VIEW_INVENTORY`, KM dùng `MANAGE_PROMOTIONS`. Chưa tách mã riêng cho từng báo cáo.
- Người có `customPermissions` chứa `VIEW_REPORTS` nhưng chưa có `EXPORT_REPORTS`/`VIEW_CUSTOMERS` (cho trang khách: `VIEW_REPORTS` vẫn được chấp nhận) sẽ **mất khả năng xuất file** cho tới khi được cấp `EXPORT_REPORTS`.
- Rules RTDB **không** thay đổi để gác theo mã quyền (rules chỉ biết nhóm vai trò) → kẻ có token có thể bỏ qua kiểm tra giao diện; các quyền nhạy cảm (xóa/hủy bill, điểm, kho) đã được rules giới hạn theo nhóm Chủ/QL/NV.
- Quản lý **không còn** đặt lại mật khẩu / khóa tài khoản của Quản lý khác (trước đây được) — chống chiếm quyền ngang hàng; Chủ quán vẫn làm được.
