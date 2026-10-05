# Ghi Chú Phân Quyền & Rà Soát Nút Dữ Liệu (docs/RULES_NOTES.md)

## 1. Kết quả rà soát các nút gốc cũ trong codebase
| Nút gốc | Tình trạng trong Code | Quyết định trong Rules | Ghi chú |
| :--- | :--- | :--- | :--- |
| `users` | Còn dùng phụ trong `data-context.tsx` (dòng 1624, 1698) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Khóa với người dùng vãng lai |
| `tables` | Còn dùng phụ trong `order_repository.dart` (90, 109) & `data-context.tsx` (1201, 1432) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Đồng bộ kép TRAM01 |
| `products` | Còn dùng trong `data-context.tsx` (1479, 1506) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Đồng bộ kép TRAM01 |
| `categories` | Còn dùng trong `data-context.tsx` (1531, 1547) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Đồng bộ kép TRAM01 |
| `zones` | Còn dùng trong `order_repository.dart` (697, 709) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Đồng bộ kép TRAM01 |
| `history` | Còn dùng trong `order_repository.dart` (293, 416) & `data-context.tsx` (1192, 1357) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Hóa đơn lịch sử |
| `audit_logs` | Còn dùng trong `data-context.tsx` (1005, 1227, 1393) | Thêm mới nếu thuộc quán, cấm sửa/xóa | Không thể xóa vết audit |
| `online_orders` | Không còn dùng ở nút gốc (đã chuyển hẳn sang `stores/{code}/online_orders`) | **`.read: false, .write: false`** | Khóa hoàn toàn |
| `kitchen_orders` | Không còn dùng ở nút gốc (đã chuyển hẳn sang `stores/{code}/kitchen_orders`) | **`.read: false, .write: false`** | Khóa hoàn toàn |
| `kmt_customers` | Thuộc app khác (Chăm sóc khách hàng / KMT) | **`.read: auth != null, .write: auth != null`** | Giữ nguyên vẹn |
| `cham_cong` | Thuộc app Chấm công Trạm | **`.read: auth != null, .write: auth != null`** | Giữ nguyên vẹn |
| `timekeeping` | Thuộc app Chấm công Trạm | **`.read: auth != null, .write: auth != null`** | Giữ nguyên vẹn |
| `employees` | Thuộc app Chấm công Trạm | **`.read: auth != null, .write: auth != null`** | Giữ nguyên vẹn |
| `shifts` | Thuộc app Chấm công Trạm | **`.read: auth != null, .write: auth != null`** | Giữ nguyên vẹn |

---

## 2. Bảng phân quyền theo vai trò trong `stores/{storeCode}`
- **`userIndex/{uid}`:** Chỉ Admin SDK (Cloud Functions và script di chuyển dữ liệu) mới được ghi. Client chỉ được đọc `userIndex/{auth.uid}` của chính mình.
- **`storeInfo`:** Chỉ Chủ quán (`isRootOwner: true` hoặc `roleId: 'owner' | 'ROLE_OWNER'`).
- **`users`:**
  - Chủ quán và Quản lý được tạo và sửa nhân viên.
  - Người dùng tự sửa được hồ sơ của mình nhưng bị cấm tự sửa các trường: `roleId`, `isRootOwner`, `isActive`, `customPermissions`.
  - Quản lý không được khóa, xóa hoặc hạ quyền của Chủ quán gốc (`isRootOwner`).
  - Cấm tuyệt đối trường `password`.
- **`products`, `categories`, `zones`, `promotions`, `inventory`, `suppliers`, `receipts`:** Chỉ Chủ quán và Quản lý được ghi. Thu ngân, phục vụ, bếp chỉ được đọc.
- **`tables`:** Nhân viên thuộc quán được cập nhật trạng thái bàn (`inUse`, `guestCount`, `isReserved`...).
- **`bills` / `history`:** Nhân viên thuộc quán được tạo và sửa. Chỉ Chủ quán và Quản lý được xóa hóa đơn.
- **`kitchen_orders`:** Mọi nhân viên thuộc quán (kể cả bếp) được tạo và cập nhật trạng thái chế biến.
- **`online_orders`, `cash_shifts`:** Chủ quán, quản lý và thu ngân được ghi.
- **`audit_logs`:** Mọi nhân viên được tạo mới bản ghi (`!data.exists() && newData.exists()`), không ai được phép sửa hoặc xóa lịch sử.
- **`login_attempts`:** Giữ `.read: true, .write: true` để luồng đăng nhập phía client đếm số lần sai và kích hoạt khóa tạm thời 15 phút trước khi đăng nhập thành công.

---

## 3. Cần chủ dự án quyết định
Các nút của app bên ngoài (`kmt_customers`, `cham_cong`, `timekeeping`, `employees`, `shifts`) vẫn mở cho mọi tài khoản Firebase Auth đã đăng nhập nhằm bảo đảm 100% không làm gián đoạn ứng dụng Chấm Công Trạm. Trong tương lai, khi app Chấm công nâng cấp xác thực, có thể siết chặt các nút này.
