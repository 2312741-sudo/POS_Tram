# Hướng Dẫn Migrate Khách Hàng CRM POS Trạm

Script di chuyển dữ liệu khách hàng tích điểm từ node gốc `/kmt_customers` sang nhánh dữ liệu quán chuẩn: `stores/{storeCode}/customers`.

## 1. Nguyên Tắc An Toàn
1. **Mặc định chạy thử (`dry-run`)**: Script chỉ phân tích và in kế hoạch chuyển đổi, không ghi bất kỳ dữ liệu nào vào database nếu không có cờ `--apply`.
2. **Tự động sao lưu**: Trước khi ghi bất kỳ dữ liệu nào, bản sao lưu toàn bộ `/kmt_customers` và `stores/{storeCode}/customers` được lưu vào thư mục `migration_output/backup_customers_*.json` (đã nằm trong `.gitignore`).
3. **Idempotent (Chạy lại nhiều lần an toàn)**: Script kiểm tra các key đã tồn tại và chỉ chép bù những khách hàng chưa có, không ghi đè mất mát thông tin mới.
4. **Không xóa node gốc**: Node `/kmt_customers` được giữ nguyên vẹn để bảo đảm an toàn dữ liệu.

## 2. Cách Chạy

### Cài đặt dependencies
```bash
cd scripts/migrate_customers
npm install
```

### Chạy thử (Dry-run - Mặc định)
```bash
node migrate.js
# Hoặc chỉ định chi nhánh
node migrate.js --store=TRAM01
```

### Chạy thực tế (Ghi dữ liệu)
```bash
node migrate.js --apply --store=TRAM01
```

### Tùy chọn tham số
- `--apply`: Bật chế độ ghi dữ liệu thực tế vào Realtime Database.
- `--store=<MÃ_QUÁN>`: Chỉ định mã quán đích (mặc định: `TRAM01`).
- `--service-account=<ĐƯỜNG_DẪN>`: Đường dẫn tới file JSON Service Account Key của project `tramapp-36f53`.
- `--database-url=<URL>`: URL Realtime Database (mặc định trỏ về `tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app`).
