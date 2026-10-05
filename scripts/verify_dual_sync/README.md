# Công Cụ Kiểm Tra Đối Chiếu Dữ Liệu Nút Gốc & Cửa Hàng (Verify Dual Sync)

Script Node.js dùng để đọc và so sánh số lượng bản ghi cũng như các trường dữ liệu giữa các nút gốc cũ (`tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `users`, `kitchen_orders`, `online_orders`) và nhánh cửa hàng `stores/{storeCode}` (mặc định `TRAM01`).

Đây là công cụ **CHỈ ĐỌC (READ-ONLY)**, tuyệt đối không chỉnh sửa hay ghi đè bất kỳ dữ liệu nào.

---

## Cài đặt

```bash
cd scripts/verify_dual_sync
npm install
```

## Cách sử dụng

### 1. Phân tích từ file sao lưu JSON (Khuyến nghị - An toàn tuyệt đối)
Nếu bạn đã xuất dữ liệu từ Firebase Console (Realtime Database -> Export JSON):
```bash
node verify.js --file /duong/dan/toi/database_export.json
```
Hoặc chỉ định mã quán khác (mặc định là `TRAM01`):
```bash
node verify.js --file /duong/dan/toi/database_export.json --store TRAM02
```

### 2. Phân tích trực tiếp từ Firebase Emulator
Khi đang chạy emulator ở local:
```bash
FIREBASE_DATABASE_EMULATOR_HOST="127.0.0.1:9000" node verify.js
```

### 3. Phân tích trực tiếp với Firebase Admin SDK (Chỉ đọc)
```bash
GOOGLE_APPLICATION_CREDENTIALS="/duong/dan/toi/serviceAccountKey.json" node verify.js
```

---

## Đầu ra mẫu

```text
======================================================
BÁO CÁO ĐỐI CHIẾU DỮ LIỆU: Nút Gốc vs stores/TRAM01
======================================================
Nút Dữ Liệu                    | Số lượng Gốc    | Số lượng TRAM01    | Chênh lệch      | Đánh giá            
-------------------------------+-----------------+--------------------+-----------------+---------------------
Bàn (tables)                   | 15              | 15                 | 0               | Đồng bộ hoàn toàn   
Món ăn/sản phẩm (products)     | 48              | 48                 | 0               | Đồng bộ hoàn toàn   
Danh mục (categories)          | 6               | 6                  | 0               | Đồng bộ hoàn toàn   
Khu vực (zones)                | 3               | 3                  | 0               | Đồng bộ hoàn toàn   
Hóa đơn (history -> bills)     | 120             | 120                | 0               | Đồng bộ hoàn toàn   
Nhật ký hệ thống (audit_logs)  | 54              | 54                 | 0               | Đồng bộ hoàn toàn   
Người dùng (users)             | 5               | 5                  | 0               | Đồng bộ hoàn toàn   
-------------------------------+-----------------+--------------------+-----------------+---------------------
```
