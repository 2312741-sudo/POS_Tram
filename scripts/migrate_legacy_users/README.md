# Hướng dẫn chạy Script Migrate tài khoản người dùng cũ (POS Trạm)

Tài liệu này hướng dẫn cách di chuyển an toàn toàn bộ tài khoản nhân viên từ hệ thống cũ (lưu mật khẩu dạng văn bản thô trong Realtime Database) sang Firebase Authentication chuẩn mực.

---

## 1. Mục tiêu và cơ chế hoạt động

- **Loại bỏ mật khẩu thô**: Xóa vĩnh viễn trường `password` khỏi Firebase Realtime Database.
- **Tạo Firebase Auth Account**: Sinh email ảo theo hợp đồng `{username}.{storeCode.toLowerCase()}@tram.local`.
- **Bảo toàn mật khẩu nhân viên**:
  - Nếu mật khẩu cũ dài $\ge$ 6 ký tự: Giữ nguyên để nhân viên không bị đổi mật khẩu bất ngờ.
  - Nếu mật khẩu cũ < 6 ký tự hoặc không có: Tự động sinh mật khẩu ngẫu nhiên 8 ký tự và xuất ra file CSV.
- **Đánh dấu bắt buộc đổi mật khẩu**: Bật cờ `mustChangePassword = true` để nhân viên đổi mật khẩu ngay lần đăng nhập đầu tiên.
- **Cập nhật User Index**: Ghi `userIndex/{uid}/{storeCode} = true` để hỗ trợ bảo vệ dữ liệu theo Security Rules.
- **An toàn dữ liệu tuyệt đối**:
  - Mặc định chỉ chạy thử (**DRY-RUN**), in danh sách chi tiết các tài khoản và thao tác dự kiến.
  - Khi chạy chế độ thực thi (`--apply`), script **tự động sao lưu** toàn bộ dữ liệu người dùng ra file JSON trước khi thực hiện bất kỳ thao tác ghi nào.

---

## 2. Chuẩn bị

### Bước 2.1: Tải Service Account Key từ Firebase Console
1. Truy cập [Firebase Console](https://console.firebase.google.com/).
2. Chọn dự án POS Trạm (ví dụ: `tramapp-36f53` hoặc `chamcongtram`).
3. Nhấp vào biểu tượng bánh răng ⚙️ (Cài đặt dự án) > Chọn thẻ **Tài khoản dịch vụ** (Service accounts).
4. Nhấp vào nút **Tạo khóa riêng tư mới** (Generate new private key).
5. Tải file JSON về máy tính và đổi tên thành `service-account.json`.
6. Đặt file `service-account.json` vào thư mục gốc của dự án `Tram_FnB_System/`.  
   *(File này đã được cấu hình trong `.gitignore` để không bao giờ bị commit lên Git).*

### Bước 2.2: Cài đặt thư viện
Di chuyển vào thư mục script và cài đặt thư viện cần thiết:
```bash
cd scripts/migrate_legacy_users
npm install
```

---

## 3. Thực hiện di chuyển

### Bước 3.1: Chạy thử kiểm tra (DRY-RUN - An toàn, không ghi dữ liệu)
Chạy lệnh sau để kiểm tra danh sách tài khoản:
```bash
npm run dry-run
```
Hoặc chỉ định đường dẫn file service account:
```bash
node migrate.js --service-account=/duong/dan/service-account.json
```
Script sẽ in ra danh sách:
- Tên tài khoản, chi nhánh
- Email Firebase Auth dự kiến
- Quyết định mật khẩu: Giữ nguyên hay sinh mới
- Số lượng tài khoản có trường `password` thô cần xử lý.

### Bước 3.2: Áp dụng thay đổi thật (--apply)
Sau khi kiểm tra kết quả dry-run chính xác, chạy với cờ `--apply`:
```bash
npm run apply
```
Hoặc:
```bash
node migrate.js --apply --service-account=/duong/dan/service-account.json
```

---

## 4. Kết quả sau khi chạy

Sau khi hoàn tất, kiểm tra thư mục `migration_output/`:
1. `backup_pre_migration_<timestamp>.json`: Bản sao lưu JSON của toàn bộ dữ liệu người dùng trước khi sửa đổi.
2. `migrated_users_<timestamp>.csv`: Danh sách tài khoản đã di chuyển, chứa mật khẩu tạm (dành cho các tài khoản được cấp mật khẩu mới).

---

## 5. Dọn dẹp sau khi hoàn tất (BẮT BUỘC)

Vì lý do an toàn bảo mật thông tin:
1. Gửi file CSV mật khẩu tạm cho quản lý chi nhánh hoặc nhân viên liên quan.
2. **Xóa ngay file `service-account.json`** trên máy tính hoặc cất vào két bảo mật (Password Manager).
3. **Xóa hoặc lưu trữ an toàn file CSV** trong `migration_output/`.
