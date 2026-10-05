# Ghi Chú Security Rules POS Trạm (Chốt Chính Thức)

> **LƯU Ý QUAN TRỌNG:**
> Bộ Security Rules này (`database.rules.json`) được thiết kế và áp dụng cho project Firebase mà **POS Trạm là ứng dụng duy nhất sử dụng Realtime Database** (`tramapp-36f53`).
> Cấp gốc (`rules/`) được cấu hình chặn mặc định (`.read: false, .write: false`), triệt tiêu hoàn toàn mọi nút gốc cũ.

---

## 1. Phân Quyền Theo Nhánh Dữ Liệu

| Nhánh dữ liệu | Quyền Đọc (`.read`) | Quyền Ghi (`.write`) | Ghi chú bảo mật |
| :--- | :--- | :--- | :--- |
| **Gốc (`/`)** | ❌ Chặn (`false`) | ❌ Chặn (`false`) | Chặn mặc định mọi truy cập không xác định |
| **`userIndex/{uid}`** | Chỉ chính chủ (`auth.uid === $uid`) | ❌ Chặn (`false`) | Chỉ Cloud Functions & Admin SDK được ghi |
| **`stores/{storeCode}`** | Thành viên quán đang `isActive !== false` | (Theo chi tiết từng nút con bên dưới) | Kiểm tra `userIndex` hoặc hồ sơ người dùng trong store |
| `├── storeInfo` | Kế thừa từ store | Chủ quán (`isRootOwner` / `owner`) | Thông tin cấu hình chi nhánh |
| `├── users/{uid}` | Kế thừa từ store | - Chính chủ (không đổi role/status)<br>- Quản lý/Chủ quán (quản lý nhân viên) | - Cấm trường `password`<br>- Cấm hạ quyền `isRootOwner` |
| `├── products` | Kế thừa từ store | Chủ quán & Quản lý | Menu món ăn, đồ uống |
| `├── categories` | Kế thừa từ store | Chủ quán & Quản lý | Nhóm thực đơn |
| `├── zones` | Kế thừa từ store | Chủ quán & Quản lý | Khu vực bàn |
| `├── promotions` | Kế thừa từ store | Chủ quán & Quản lý | Chương trình khuyến mãi, voucher |
| `├── inventory` | Kế thừa từ store | Chủ quán & Quản lý | Quản lý kho nguyên vật liệu |
| `├── suppliers` | Kế thừa từ store | Chủ quán & Quản lý | Nhà cung cấp |
| `├── receipts` | Kế thừa từ store | Chủ quán & Quản lý | Phiếu nhập kho |
| `├── tables` | Kế thừa từ store | Toàn bộ nhân viên active | Trạng thái bàn |
| `├── bills` | Kế thừa từ store | - Thêm/sửa: Nhân viên active<br>- Xóa: Quản lý & Chủ quán | Hóa đơn bán lẻ |
| `├── history` | Kế thừa từ store | - Thêm/sửa: Nhân viên active<br>- Xóa: Quản lý & Chủ quán | Lịch sử đơn hàng |
| `├── kitchen_orders` | Kế thừa từ store | Toàn bộ nhân viên active (kể cả bếp) | Báo món và trạng thái chế biến |
| `├── online_orders` | Kế thừa từ store | Chủ quán, Quản lý & Thu ngân | Đơn hàng trực tuyến |
| `├── cash_shifts` | Kế thừa từ store | Chủ quán, Quản lý & Thu ngân | Quản lý két tiền đầu/cuối ca |
| `├── customers` | Chủ quán, Quản lý & Thu ngân | Chủ quán, Quản lý & Thu ngân | Phục vụ và Bếp bị từ chối truy cập |
| `├── audit_logs` | Kế thừa từ store | Thêm mới (`!data.exists() && newData.exists()`) | Append-only; cấm sửa/xóa; validate timestamp, action, username |
| `└── login_attempts` | ❌ Chặn (`false`) | ❌ Chặn (`false`) | Chống brute-force; chỉ Functions/Admin SDK xử lý |

---

## 2. Danh Sách Nút Gốc Đã Xóa Bỏ
Toàn bộ các khối rules của các nút gốc sau đã được gỡ bỏ khỏi file rules và bị chặn mặc định bởi rule gốc:
- `users`, `tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `online_orders`, `kitchen_orders`, `kmt_customers`, `cham_cong`, `timekeeping`, `employees`, `shifts`.
