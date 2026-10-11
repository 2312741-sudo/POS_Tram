# Gộp điểm các chi nhánh -> `loyalty_members`

Gom `stores/{s}/customers/{id}` theo SĐT chuẩn hóa, CỘNG `điểm hiện tại` và `tổng điểm tích lũy`, ghi `loyalty_members/{SĐT}`
và sổ cái số dư đầu kỳ `loyalty_ledger/{SĐT}/opening_{chi nhánh}_{mã khách}`; cập nhật cache điểm trên các node chi nhánh.

```bash
cd scripts/migrate_shared_loyalty && npm install
node migrate.js --service-account=KEY.json              # DRY-RUN (mặc định, không ghi)
node migrate.js --service-account=KEY.json --apply      # ghi thật (đóng cửa hàng trước)
```
Tùy chọn: `--stores=A,B` (giới hạn), `--database-url=`, `--force` (chạy bù khi đã có marker; bản ghi đã có không bị ghi đè).
Khách không có SĐT hợp lệ không gộp: mỗi người một bản ghi `L_{chi nhánh}_{mã khách}`. KHÔNG chạy với production khi chưa đọc dry-run.
