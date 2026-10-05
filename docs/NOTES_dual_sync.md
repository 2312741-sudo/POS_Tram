# Báo Cáo Triệt Tiêu Dual-Sync & Dừng Truy Cập Các Nút Gốc (Agent G2)

Tài liệu này ghi nhận toàn bộ các vị trí đã loại bỏ cơ chế ghi song song (dual-sync) và đọc dự phòng (fallback read) vào các nút gốc cũ, chuyển dịch 100% các thao tác đọc và ghi dữ liệu về nhánh cửa hàng độc lập: `stores/{storeCode}/...`.

---

## 1. Web Admin (`web/lib/data-context.tsx`)

| Hàm / Thao tác | Nút gốc đã loại bỏ | Đường dẫn mới (Store-scoped) |
|---|---|---|
| `useEffect` (Lắng nghe toàn cục) | `tables`, `history`, `products`, `categories`, `users`, `audit_logs`, `online_orders` | Gộp 100% vào `ref(db, "stores")` (chỉ đọc trong `stores/{storeCode}/...`) |
| `checkoutAndFreeTable` | `history/{billId}` | `stores/{storeCode}/history/{billId}` & `bills/{billId}` |
| `checkoutAndFreeTable` | `tables/{tableId}` | `stores/{storeCode}/tables/{tableId}` |
| `checkoutAndFreeTable` | `audit_logs/{logId}` | `stores/{storeCode}/audit_logs/{logId}` |
| `cancelAndFreeTable` | `history/{cancelBillId}` | `stores/{storeCode}/history/{cancelBillId}` & `bills/{cancelBillId}` |
| `cancelAndFreeTable` | `tables/{tableId}` | `stores/{storeCode}/tables/{tableId}` |
| `cancelAndFreeTable` | `audit_logs/{logId}` | `stores/{storeCode}/audit_logs/{logId}` |
| `saveTable` | `tables/{key}` | `stores/{storeCode}/tables/{key}` |
| `deleteTable` | `tables/{tableId}` | `stores/{storeCode}/tables/{tableId}` |
| `saveProduct` | `products/{id}` | `stores/{storeCode}/products/{id}` |
| `deleteProduct` | `products/{id}` | `stores/{storeCode}/products/{id}` |
| `saveCategory` (đổi tên) | `categories/{oldName}`, `products/{id}` | `stores/{storeCode}/categories/{name}`, `products/{id}` |
| `saveCategory` (thêm mới) | `categories/{name}` | `stores/{storeCode}/categories/{name}` |
| `deleteCategory` | `categories/{name}` | `stores/{storeCode}/categories/{name}` |
| `saveUser` | `users/{username}` & `audit_logs/{logId}` | `stores/{storeCode}/users/{username}` & `stores/{storeCode}/audit_logs/{logId}` |
| `saveUser` (Mật khẩu) | **XÓA TRIỆT ĐỂ** `payload.password` | Mật khẩu chỉ lưu an toàn trên Firebase Auth, không lưu bản thô trên RTDB |
| `deleteUser` | `users/{username}` & `audit_logs/{logId}` | `stores/{storeCode}/users/{username}` & `stores/{storeCode}/audit_logs/{logId}` |
| `cancelOrder` | `history/{orderId}` & `audit_logs/{logId}` | `stores/{storeCode}/history/{orderId}` & `bills/{orderId}`, `stores/.../audit_logs` |
| `deleteOrder` | `history/{orderId}` & `audit_logs/{logId}` | `stores/{storeCode}/history/{orderId}` & `bills/{orderId}`, `stores/.../audit_logs` |
| `createStore` (Menu copy) | Đọc `categories` và `products` ở gốc | Đọc trực tiếp từ `stores/{copyMenuFrom}/categories` và `products` |
| `addStore` / `updateStore` / `deleteStore` | `audit_logs/{logId}` | `stores/{storeCode}/audit_logs/{logId}` |

---

## 2. Flutter POS Mobile (`app_flutter/lib/data/repositories/`)

### Trong `order_repository.dart`:
1. **`tablesStream`**: Loại bỏ hoàn toàn đọc dự phòng `_root.child('tables')`. Khi dữ liệu rỗng trong store, trả về `SeedData.defaultTables` an toàn, không sinh lỗi Permission Denied.
2. **`zonesStream`**: Loại bỏ hoàn toàn đọc dự phòng `_root.child('zones')`. Khi dữ liệu rỗng trong store, trả về `SeedData.defaultZones`.
3. **`saveTable`**: Chỉ ghi vào `tablesRef` (`stores/{storeCode}/tables`).
4. **`deleteTable`**: Chỉ xóa tại `tablesRef`.
5. **`checkoutBill`**: Ghi vào `billsRef` và `stores/{storeCode}/history`.
6. **`cancelBillOnTable`**: Ghi vào `billsRef` và `stores/{storeCode}/history`.
7. **`cancelBill`**: Ghi vào `billsRef` và `stores/{storeCode}/history`.
8. **`deleteBill`**: Xóa tại `billsRef` và `stores/{storeCode}/history`.
9. **`saveZone`**: Chỉ ghi vào `zonesRef` (`stores/{storeCode}/zones`).
10. **`deleteZone`**: Chỉ xóa tại `zonesRef`.
11. **`updateOnlineOrderStatus`**: Chỉ cập nhật tại `onlineOrdersRef` (`stores/{storeCode}/online_orders`).

### Trong `auth_repository.dart`:
1. **`getUserByUsername`**: Loại bỏ đọc dự phòng từ `_root.child('users').child(username)`. Chỉ tra cứu trong `usersRef` (`stores/{storeCode}/users`).
2. **`getUsers`**: Loại bỏ đọc dự phòng từ `_root.child('users')`. Chỉ tra cứu trong `usersRef`.
3. Xác nhận không có bất kỳ lệnh ghi nào vào node gốc `users`.

### Trong `report_repository.dart`:
1. **`customersRef`**: Chuyển từ `_root.child('kmt_customers')` sang `storeRef.child('customers')` (`stores/{storeCode}/customers`).
2. **`logAction`**: Loại bỏ 2 câu lệnh ghi vào `_root.child('audit_logs')`. Chỉ ghi vào `auditLogsRef` (`stores/{storeCode}/audit_logs`).
3. **Cờ cấu hình Firestore CRM (`useFirestoreCustomers = false`)**:
   - Trước đây POS gọi Firestore (collection `kmt_customers`) trỏ vào project cũ `chamcongtram`.
   - Hiện tại toàn bộ hệ thống POS (Auth, RTDB, Functions) đã thống nhất về project `tramapp-36f53`.
   - Do đó, các dòng gọi Firestore được bọc lại sau cờ `static bool useFirestoreCustomers = false;` để POS độc lập 100% trên Realtime Database. Mã nguồn Firestore được bảo lưu nguyên vẹn, không bị xóa.

---

## 3. Công Cụ Hỗ Trợ Migrate & Kiểm Tra

1. **`scripts/migrate_customers/` (Mới)**:
   - Script Node.js dùng Firebase Admin SDK để di chuyển khách hàng từ `/kmt_customers` sang `stores/{storeCode}/customers`.
   - Mặc định chạy thử (`dry-run`), chỉ ghi khi có cờ `--apply`.
   - Tự động xuất bản sao lưu dạng JSON vào thư mục `migration_output/backup_customers_*.json` trước khi ghi.
   - Idempotent: chạy nhiều lần không tạo trùng lặp.
   - Tuyệt đối không xóa node gốc `/kmt_customers`.
2. **`scripts/verify_dual_sync/verify.js`**:
   - Kiểm tra đối chiếu dữ liệu giữa các nút gốc cũ và `stores/{storeCode}`.
3. **`scripts/migrate_legacy_users/migrate.js`**:
   - Chuyển đổi tài khoản cũ sang Firebase Auth và userIndex.

---

## 4. Danh Sách Nút Gốc Đã Hết Được Sử Dụng (Dành Cho Agent F2)

Toàn bộ ứng dụng Flutter và Web Admin đã ngừng đọc và ghi vào các nút gốc sau đây. Agent F2 có thể cấu hình chặn mặc định toàn bộ ở gốc (`.read: false`, `.write: false`) và xóa bỏ hoàn toàn các khối rules của chúng:

| Nút gốc cũ | Trạng thái trong POS | Ghi chú |
|---|---|---|
| `/users` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/users` |
| `/tables` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/tables` |
| `/products` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/products` |
| `/categories` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/categories` |
| `/zones` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/zones` |
| `/history` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/history` (và `bills`) |
| `/audit_logs` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/audit_logs` |
| `/kmt_customers` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/customers` |
| `/online_orders` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/online_orders` |
| `/kitchen_orders` | ĐÃ DỪNG 100% | Đã chuyển sang `stores/{storeCode}/kitchen_orders` |
| `/cham_cong` | ĐÃ DỪNG 100% | Không thuộc POS (thuộc app khác trước đây, đã xác nhận không dùng) |
| `/timekeeping` | ĐÃ DỪNG 100% | Không thuộc POS |
| `/employees` | ĐÃ DỪNG 100% | Không thuộc POS |
| `/shifts` | ĐÃ DỪNG 100% | Không thuộc POS (POS dùng `cash_shifts`) |

Hai nhánh duy nhất mở cho Client POS là:
1. `userIndex/{auth.uid}` (Chỉ đọc cho chính chủ `auth.uid === $uid`, Admin SDK ghi).
2. `stores/{$storeCode}` (Kiểm tra quyền thành viên và vai trò RBAC).
Mọi đường dẫn khác bị chặn mặc định ở gốc.
