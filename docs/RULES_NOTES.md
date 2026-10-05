# Ghi Chú Phân Quyền & Rà Soát Nút Dữ Liệu (docs/RULES_NOTES.md)

## 1. Kết quả rà soát các nút gốc cũ trong codebase
| Nút gốc | Tình trạng trong Code | Quyết định trong Rules | Ghi chú |
| :--- | :--- | :--- | :--- |
| `users` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Khóa với người dùng vãng lai |
| `tables` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Không còn ghi nút gốc |
| `products` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Không còn ghi nút gốc |
| `categories` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Không còn ghi nút gốc |
| `zones` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Không còn ghi nút gốc |
| `history` | Đã cắt triệt để dual-sync (Agent G) | Cho phép đọc/ghi nếu `userIndex/{auth.uid}` tồn tại | Không còn ghi nút gốc |
| `audit_logs` | Đã cắt triệt để dual-sync (Agent G) | Thêm mới nếu thuộc quán, cấm sửa/xóa | Không thể xóa vết audit |
| `online_orders` | Đã cắt triệt để dual-sync (Agent G) | **`.read: false, .write: false`** | Khóa hoàn toàn |
| `kitchen_orders` | Đã cắt triệt để dual-sync (Agent G) | **`.read: false, .write: false`** | Khóa hoàn toàn |
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
- **`audit_logs`:**
  - Chỉ cho ghi thêm (`!data.exists() && newData.exists()`), tuyệt đối không cho sửa hoặc xóa.
  - Kiểm tra tính hợp lệ dữ liệu (validate): Bản ghi phải chứa các trường bắt buộc `timestamp` (số, `<= now`), `action` (chuỗi không rỗng), và `username` (chuỗi không rỗng).
- **`login_attempts`:**
  - **Khóa triệt để** `.read: false, .write: false` đối với toàn bộ client để ngăn chặn việc người dùng đọc được lịch sử thử sai mật khẩu của nhau hoặc tự ý chỉnh sửa bộ đếm khóa brute-force. Quản lý trạng thái khóa được thực hiện qua backend/Cloud Functions.

---

## 3. Cần chủ dự án quyết định
1. **Bảo tồn Rules của 2 app dùng chung Firebase:**
   - Các nút của app bên ngoài (`kmt_customers`, `cham_cong`, `timekeeping`, `employees`, `shifts`) vẫn mở cho mọi tài khoản Firebase Auth đã đăng nhập nhằm bảo đảm 100% không làm gián đoạn ứng dụng Chấm Công Trạm.
   - Để đảm bảo an toàn tuyệt đối trước khi deploy rules lên production: Cần đối chiếu với file `docs/rules_hien_tai_tramapp.json` (lấy từ Firebase Console của `tramapp-36f53`) để đảm bảo không bỏ sót bất kỳ node dữ liệu tùy biến nào của app Chấm công và Tích điểm.
