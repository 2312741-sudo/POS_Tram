# Báo Cáo Triệt Tiêu Dual-Sync (Ghi Song Song Vào Nút Gốc)

Tài liệu này ghi nhận toàn bộ các vị trí đã loại bỏ cơ chế ghi song song (dual-sync) vào các nút gốc cũ, chuyển dịch 100% các thao tác ghi dữ liệu về nhánh cửa hàng độc lập: `stores/{storeCode}/...`.

---

## 1. Web Admin (`web/lib/data-context.tsx`)

| Hàm / Thao tác | Nút gốc đã loại bỏ | Đường dẫn mới (Store-scoped) |
|---|---|---|
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
| `addStore` / `updateStore` / `deleteStore` | `audit_logs/{logId}` | `stores/{storeCode}/audit_logs/{logId}` |

---

## 2. Flutter POS Mobile (`app_flutter/lib/data/repositories/`)

### Trong `order_repository.dart`:
1. **`saveTable`**: Loại bỏ `_root.child('tables').child(...).set(...)`. Chỉ ghi vào `tablesRef` (`stores/{storeCode}/tables`).
2. **`deleteTable`**: Loại bỏ `_root.child('tables').child(...).remove()`. Chỉ xóa tại `tablesRef`.
3. **`checkoutBill`**: Loại bỏ `_root.child('history').child(bill.id).set(...)`. Ghi vào `billsRef` và `stores/{storeCode}/history`.
4. **`cancelBillOnTable`**: Loại bỏ `_root.child('history').child(cancelBillId).set(...)`. Ghi vào `billsRef` và `stores/{storeCode}/history`.
5. **`cancelBill`**: Loại bỏ `_root.child('history').child(bill.id).set(...)`. Ghi vào `billsRef` và `stores/{storeCode}/history`.
6. **`deleteBill`**: Loại bỏ `_root.child('history').child(bill.id).remove()`. Xóa tại `billsRef` và `stores/{storeCode}/history`.
7. **`saveZone`**: Loại bỏ `_root.child('zones').child(...).set(...)`. Chỉ ghi vào `zonesRef` (`stores/{storeCode}/zones`).
8. **`deleteZone`**: Loại bỏ `_root.child('zones').child(...).remove()`. Chỉ xóa tại `zonesRef`.
9. **`updateOnlineOrderStatus`**: Loại bỏ `_root.child('online_orders').child(...).update(...)`. Chỉ cập nhật tại `onlineOrdersRef` (`stores/{storeCode}/online_orders`).

### Trong `auth_repository.dart`:
- Xác nhận không có bất kỳ lệnh ghi nào vào node gốc `users`.
- Cơ chế `saveUser` ghi vào `usersRef` theo UID (`stores/{storeCode}/users/{uid}`).

---

## 3. Công Cụ Hỗ Trợ Kiểm Tra

- Script `scripts/verify_dual_sync/verify.js` đã sẵn sàng để kiểm tra đối chiếu dữ liệu giữa các nút gốc cũ và `stores/{storeCode}` nhằm phục vụ việc kiểm toán dữ liệu hoặc sao lưu trước khi tắt phân quyền nút gốc.
