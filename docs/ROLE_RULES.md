# Quy tắc theo từng loại tài khoản (ROLE_RULES)

Tài liệu cho Chủ quán và đội vận hành: mỗi vai trò **được / không được** làm gì, mã quyền mặc định, và quy tắc được áp dụng ở đâu.
Nguồn sự thật mã quyền: `app_flutter/lib/core/permissions/app_permissions.dart` ↔ `web/lib/permission-catalog.ts` + `web/lib/auth.tsx`
(khóa bằng `web/test/permission-parity.test.ts`). Chi tiết từng mã: `docs/PERMISSIONS_AUDIT.md`.

Bốn vai trò: **Chủ quán** (`ROLE_OWNER`), **Quản lý** (`ROLE_MANAGER`), **Nhân viên** (`ROLE_STAFF` = thu ngân + phục vụ), **Bếp / Bar** (`ROLE_KITCHEN`).
Mã vai trò cũ (`manager_1`, `cashier`, `waiter`...) vẫn được chấp nhận qua `normalizeRoleId`.

## 1. Quy tắc nhanh (vòng cập nhật này)

| Yêu cầu của Chủ quán | Kết quả |
|---|---|
| Quản lý không xóa/hủy đơn, không xem lịch sử thao tác nếu chưa được cấp | Đã gỡ khỏi mặc định của Quản lý: `CANCEL_BILL`, `CANCEL_KITCHEN_ITEM`, `VIEW_AUDIT_LOGS`, `EXPORT_AUDIT_LOGS`. Chủ cấp riêng cho từng người (mục 5). |
| Nhân viên không vào được "Quản lý thực đơn" | Nhân viên/Bếp không có `MENU_MANAGEMENT`/`EDIT_MENU`; ẩn mục menu, chặn đường dẫn, chặn trang Web. Gỡ lỗi alias `VIEW_MENU` ⇒ `MENU_MANAGEMENT`. |
| Phiếu bàn giao ca ẩn với Nhân viên | Quyền `VIEW_SHIFT_HANDOVER` (chỉ Chủ, Quản lý). Route `/cash-shifts` và Web `/dashboard/shifts` yêu cầu quyền này (hoặc `VIEW_ALL_SHIFTS`/`VIEW_REPORTS`). *Phần màn hình do nhóm Ca/két thực hiện.* |
| Ca/két độc lập theo tài khoản, lịch sử hóa đơn theo tài khoản | Quyền `VIEW_ALL_SHIFTS`, `VIEW_ALL_BILLS_HISTORY` (Chủ, Quản lý); Nhân viên chỉ thấy ca/hóa đơn của chính mình. *Triển khai: nhóm Ca/két (`core/domain/shift_scope.dart`, rules `cash_shifts`).* |
| Bếp/Nhân viên bật-tắt món hết hàng | Quyền `TOGGLE_ITEM_AVAILABILITY` (Chủ, Quản lý, Nhân viên, Bếp). *Triển khai: nhóm Bếp (rules `products/{id}/isAvailable`, `soldOut*`).* |
| Danh mục note & topping | Quyền `MANAGE_NOTE_CATALOG` (Chủ, Quản lý). *Triển khai: nhóm Note/Topping.* |

## 2. Chủ quán (`ROLE_OWNER`, `isRootOwner`)

Toàn quyền: mọi mã quyền (luôn đúng trong cả Flutter lẫn Web), mọi chi nhánh mà tài khoản thuộc về.

| Được | Không |
|---|---|
| Mọi màn hình và thao tác, gồm: hủy/xóa hóa đơn, nhật ký thao tác, nhân sự, phân quyền, cài đặt quán, liên kết Chấm Công, điểm dùng chung | Không có hạn chế quyền. Chủ **gốc** (`isRootOwner`) không bị ai khóa/sửa được (rules + Functions) |
| Cấp/thu hồi quyền riêng cho từng tài khoản, **duy nhất** là người cấp được 4 quyền "Chủ-cấp-riêng" (mục 5) | |

## 3. Quản lý (`ROLE_MANAGER`)

**Được (mặc định):** điều hành ca (mở/chốt ca, thu/chi két), xem **phiếu bàn giao ca** và ca/két của mọi tài khoản, xem hóa đơn mọi tài khoản,
báo cáo doanh thu + xuất báo cáo/dữ liệu, thực đơn (xem/sửa/giá/quản lý, topping, sao chép giữa quán), bật/tắt món hết hàng, quản lý note & topping,
bàn (đổi/ghép/tách, quản lý bàn & khu vực), chiết khấu thủ công + giảm giá món (và **duyệt PIN** giảm giá món), in/in lại hóa đơn, khuyến mãi + mã voucher,
khách hàng + chỉnh điểm, kho/NCC/nhập-xuất-hủy-kiểm-chuyển-sản xuất, giá vốn, công thức, đơn online, PIN duyệt của chính mình, dữ liệu mẫu.

**Không (mặc định):**

- Hủy / xóa hóa đơn đã thanh toán (`CANCEL_BILL`); hủy món đã gửi bếp (`CANCEL_KITCHEN_ITEM`) và duyệt PIN cho việc đó.
- Xem Lịch sử thao tác / tab Giám sát / banner "thao tác nghi vấn" (`VIEW_AUDIT_LOGS`), xuất nhật ký (`EXPORT_AUDIT_LOGS`).
- Quản lý nhân sự, ma trận phân quyền, cài đặt quán, liên kết Chấm Công, cấu hình tích điểm, xóa món vĩnh viễn, nhập hàng loạt, hủy phiếu nhập, chiết khấu vượt quy định, xuất mã voucher.
- Đặt lại mật khẩu / khóa tài khoản của Quản lý khác hoặc của Chủ.

**Vẫn làm được:** hủy bàn **đang mở** chưa gửi bếp (không phải xóa/hủy hóa đơn đã chốt), xóa món chưa gửi bếp (`DELETE_ITEM`, có lý do), xóa bản ghi hóa đơn **chưa chốt** (OPEN...).

## 4. Nhân viên (`ROLE_STAFF`, thu ngân + phục vụ) và Bếp / Bar (`ROLE_KITCHEN`)

| | Nhân viên | Bếp / Bar |
|---|---|---|
| Mặc định | Xem thực đơn khi gọi món, mở bàn/gọi món, đổi bàn, gửi bếp, thanh toán (`CREATE_BILL`), áp dụng khuyến mãi, in hóa đơn, xóa món chưa gửi bếp (có lý do), đổi điểm, xem + thêm/sửa khách (không chỉnh điểm), đơn online, mở/chốt **ca của chính mình**, xem ca/hóa đơn **của mình**, bật/tắt món hết hàng, xem màn Bếp | Xem thực đơn, màn Bếp/KDS (nhận/hoàn tất món), bật/tắt món hết hàng |
| Không | Quản lý thực đơn/danh mục/khu vực/topping; phiếu bàn giao ca; ca/két và hóa đơn của người khác; hủy/xóa hóa đơn đã thanh toán; hủy món đã gửi bếp (cần Quản lý/Chủ duyệt PIN); chiết khấu thủ công; báo cáo; kho; nhật ký thao tác; nhân sự/phân quyền | Mọi thứ ngoài màn Bếp: thanh toán, khách hàng, ca/két, báo cáo, thực đơn (chỉ xem) |

## 5. Mã quyền mặc định theo vai trò (tóm tắt các mã liên quan vòng này)

| Mã | Chủ | Quản lý | Nhân viên | Bếp |
|---|:-:|:-:|:-:|:-:|
| `CANCEL_BILL` Hủy/xóa hóa đơn đã thanh toán | ✓ | cấp riêng | cấp riêng | |
| `CANCEL_KITCHEN_ITEM` Hủy món đã gửi bếp | ✓ | cấp riêng | cấp riêng | |
| `VIEW_AUDIT_LOGS` Xem lịch sử thao tác | ✓ | cấp riêng | — (rules không cho) | — |
| `EXPORT_AUDIT_LOGS` Xuất nhật ký | ✓ | cấp riêng | | |
| `MENU_MANAGEMENT` / `EDIT_MENU` / `CHANGE_PRICE` | ✓ | ✓ | | |
| `MANAGE_TABLES` Bàn & khu vực | ✓ | ✓ | | |
| `VIEW_SHIFT_HANDOVER` Phiếu bàn giao ca | ✓ | ✓ | | |
| `VIEW_ALL_SHIFTS` Ca/két tài khoản khác | ✓ | ✓ | | |
| `VIEW_ALL_BILLS_HISTORY` Hóa đơn mọi tài khoản | ✓ | ✓ | | |
| `TOGGLE_ITEM_AVAILABILITY` Bật/tắt món hết hàng | ✓ | ✓ | ✓ | ✓ |
| `MANAGE_NOTE_CATALOG` Danh mục note & topping | ✓ | ✓ | | |

Danh sách đầy đủ mã × vai trò: `docs/PERMISSIONS_AUDIT.md` §2.

## 6. Quy tắc được thực thi ở đâu

| Quy tắc | Giao diện (ẩn/khóa) | Xử lý (handler/route) | Rules RTDB | Cloud Functions |
|---|---|---|---|---|
| Hủy/xóa hóa đơn đã thanh toán cần `CANCEL_BILL` | Flutter `history_screen`, `bill_detail_sheet`, `order_cart_screen` (hủy đơn có món đã gửi bếp); Web `orders/page.tsx` (nút ẩn) | Flutter kiểm tra `can(cancelBill)`; Web `data-context.cancelOrder/deleteOrder` trả lỗi nếu thiếu quyền | `bills/$id` và `history/$id`: xóa = Chủ, hoặc Quản lý có `CANCEL_BILL` trong `customPermissions`, hoặc bản ghi chưa chốt; ghi đè PAID/REFUNDED → CANCELLED = Chủ hoặc người có `CANCEL_BILL` | — |
| Hủy món đã gửi bếp cần `CANCEL_KITCHEN_ITEM` hoặc Quản lý có quyền duyệt PIN | `order_cart_screen`, Web `tables/page.tsx` | PIN duyệt: `managerPinLogic.approverHasPermission` (Quản lý mặc định chỉ duyệt `DISCOUNT_ITEM`) | Không thể (món nằm trong bàn/phiếu bếp) | `verifyManagerPin` |
| Lịch sử thao tác cần `VIEW_AUDIT_LOGS` | Flutter: ẩn mục menu, tab "Giám sát", nút tắt, banner nghi vấn; Web: ẩn Sidebar + chặn trang | Route `/audit-logs`; Web `canAccessRoute` + cổng trang trong `dashboard/layout.tsx`; `audit_tab` không đăng ký luồng dữ liệu | `audit_logs/.read` = Chủ, hoặc Quản lý có `VIEW_AUDIT_LOGS`. Nhân viên/Bếp **không bao giờ** đọc. **Ghi** vẫn mở cho mọi thành viên đang hoạt động (thao tác tự ghi log; không sửa/xóa) | — |
| Chỉ Chủ cấp 4 quyền Chủ-cấp-riêng | Flutter `user_management` + `permissions_matrix` (khóa), Web `users/page.tsx` (ẩn) | — | `users/$uid/customPermissions/$i` chặn ghi `CANCEL_BILL`, `CANCEL_KITCHEN_ITEM`, `VIEW_AUDIT_LOGS`, `EXPORT_AUDIT_LOGS` nếu người ghi không phải Chủ | `createStaffAccount` lọc bằng `sanitizeCustomPermissions` |
| Quản lý thực đơn cần `MENU_MANAGEMENT`/`EDIT_MENU` | Menu Flutter ẩn "Quản Lý Thực Đơn"; Web Sidebar | Flutter `RoutePermissions` (`/menu-management`, `/category-management`, `/zone-management`) trong `go_router.redirect` (cả gõ thẳng đường dẫn / deep link); Web `canAccessRoute('/dashboard/products')` + cổng trang | `products`, `categories`, `product_notes`... ghi chỉ Chủ + Quản lý (ngoại lệ hẹp `isAvailable`/`soldOut*` cho Bếp/Nhân viên) | — |
| Phiếu bàn giao ca cần `VIEW_SHIFT_HANDOVER` | Flutter menu; Web Sidebar | Route `/cash-shifts`; Web `canAccessRoute('/dashboard/shifts')` | `cash_shifts`: Nhân viên chỉ ghi ca của mình (nhóm Ca/két) | — |

## 7. Cách cấp thêm quyền cho từng tài khoản

`customPermissions` của từng người **chỉ cộng thêm** vào quyền mặc định của vai trò (không trừ bớt).

- **Web (Chủ quán):** `Nhân viên và phân quyền` → chọn tài khoản → mục *Quyền bổ sung riêng lẻ* → tích quyền (ví dụ "Hủy hóa đơn đã thanh toán", "Xem lịch sử kiểm soát") → Lưu. Chỉ Chủ thấy 4 quyền Chủ-cấp-riêng.
- **Flutter (Chủ quán):** `Nhân viên và phân quyền` → sửa tài khoản → *Tùy chỉnh quyền*, hoặc `Ma Trận Phân Quyền Chi Tiết` → bật ô quyền của người đó. Có hiệu lực ngay sau lần đồng bộ hồ sơ kế tiếp (đăng nhập lại để chắc chắn).
- **Thu hồi:** bỏ tích quyền (đối với quyền Chủ-cấp-riêng, quyền thu hồi ngay cả ở rules).
- Giới hạn kỹ thuật: rules RTDB chỉ nhìn **40 quyền riêng đầu tiên** của mỗi tài khoản. Đừng cấp quá 40 quyền riêng cho một người.
- Vai trò tự tạo (Danh sách vai trò) và bản ghi `roles/*` cũ chỉ ảnh hưởng **giao diện**, không ảnh hưởng rules; muốn rules công nhận một quyền Chủ-cấp-riêng phải cấp qua `customPermissions`.

## 8. Thay đổi hành vi cần báo cho Chủ quán

1. Tài khoản Quản lý **đang dùng** mất ngay các quyền ở mục 3 (hủy/xóa hóa đơn, hủy món đã gửi bếp, xem/xuất nhật ký) sau khi cập nhật ứng dụng/web — quyền mặc định tính lúc chạy, không cần di trú dữ liệu.
2. Nhân viên cần hủy món đã gửi bếp: phải có Chủ (hoặc Quản lý được cấp `CANCEL_KITCHEN_ITEM`) nhập PIN duyệt.
3. Nhân viên/Bếp mất mọi đường vào "Quản lý thực đơn" (trước đây Nhân viên vào được do alias lỗi).
4. Quản lý không còn xóa được hóa đơn đã thanh toán ngay cả khi gọi thẳng cơ sở dữ liệu (rules).
5. Ứng dụng bản cũ chưa cập nhật sẽ vẫn hiện nút; thao tác bị từ chối bởi rules (hiện báo lỗi quyền).

## 9. Giới hạn đã biết

- Rules không đọc được `roles/*` hay mảng quyền dài; chỉ `customPermissions` (40 vị trí đầu) được rules đối chiếu. Hủy **món đã gửi bếp** và các quyền khác chỉ gác ở UI + handler (+ PIN qua Functions), không thể gác bằng rules.
- Bếp/Nhân viên có thể ghi vào một số nút vận hành theo vai trò (bàn, phiếu bếp...) – xem `docs/RULES_NOTES.md`.
- Nhân viên được cấp riêng `VIEW_AUDIT_LOGS` sẽ thấy menu nhưng rules từ chối đọc (có chủ ý: nhật ký chỉ cho Chủ/Quản lý).
