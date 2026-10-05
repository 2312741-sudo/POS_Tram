# Lịch Sử & Tài Liệu Security Rules Firebase Realtime Database

Tài liệu này giải thích xuất xứ của các file Security Rules trong thư mục `docs/` và thư mục gốc của repository.

## 1. File `docs/rules_ban_truoc_khi_chot.json`
- **Xuất xứ**: Được đổi tên từ `docs/rules_hien_tai_tramapp.json`.
- **Bản chất**: Đây là bản rules tạm thời do các agent trước đó tổng hợp (chứa cả các khối rules tương thích ngược cho các nút gốc cũ và ứng dụng khác). **Đây không phải là bản rules gốc xuất trực tiếp từ Firebase Console.**
- **Mục đích lưu trữ**: Dùng làm điểm hoàn nguyên dự phòng (rollback target) trong trường hợp cần quay lại trạng thái mở tương thích cũ.

## 2. File `database.rules.json` (Bản chốt chính thức)
- **Bản chất**: Bản Security Rules chính thức của POS Trạm khi POS là ứng dụng duy nhất sử dụng Realtime Database trên project `tramapp-36f53`.
- **Nguyên tắc cốt lõi**:
  1. **Chặn mặc định (Default Deny)**: Ở cấp gốc (`rules/`), `.read: false` và `.write: false`. Bất kỳ nhánh nào không được khai báo luật đều bị từ chối 100%.
  2. **Chỉ mở 2 nhánh phục vụ POS**:
     - `userIndex/{$uid}`: Chỉ đọc cho chính chủ (`auth.uid === $uid`), ghi bị cấm đối với mọi client (chỉ Firebase Admin SDK / Cloud Functions được ghi).
     - `stores/{$storeCode}`: Kiểm tra người dùng có thuộc quán hay không và có đang active hay không (`userIndex/{auth.uid}/{$storeCode} === true` hoặc tồn tại hồ sơ người dùng trong store và `isActive !== false`).
  3. **Phân quyền chi tiết (RBAC) trong `stores/{$storeCode}`**:
     - `storeInfo`: Chủ quán tối cao (`isRootOwner`) hoặc vai trò `owner`/`ROLE_OWNER`.
     - `users/{$uid}`: Tự sửa hồ sơ bản thân (không đổi vai trò, không tự active, không có password). Quản lý/Chủ quán quản lý nhân viên nhưng không thể hạ quyền hay sửa `isRootOwner`.
     - `products`, `categories`, `zones`, `promotions`, `inventory`, `suppliers`, `receipts`: Chủ quán và Quản lý.
     - `tables`, `kitchen_orders`: Mọi nhân viên active trong quán.
     - `bills`, `history`: Mọi nhân viên active tạo/đọc; chỉ Quản lý/Chủ quán được xóa/sửa.
     - `online_orders`: Chủ quán, Quản lý và Thu ngân.
     - `cash_shifts`: Chủ quán, Quản lý và Thu ngân.
     - `customers`: Chủ quán, Quản lý và Thu ngân đọc/ghi; Phục vụ và Bếp bị từ chối truy cập.
     - `audit_logs`: Chỉ cho phép thêm mới (append-only), validate bắt buộc có `timestamp`, `action`, `username`. Cấm sửa và cấm xóa.
     - `login_attempts`: Bị chặn hoàn toàn đọc/ghi với client (`.read: false`, `.write: false`), chỉ Admin SDK / Cloud Functions xử lý chống brute-force.
