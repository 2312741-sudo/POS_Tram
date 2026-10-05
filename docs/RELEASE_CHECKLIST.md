# HƯỚNG DẪN QUY TRÌNH PHÁT HÀNH THỰC TẾ (RELEASE CHECKLIST)
## HỆ THỐNG POS TRẠM F&B (CHỐT DỰ ÁN GỐC TRAMAPP-36F53 & CHẶN NÚT GỐC)

> **Mục tiêu:** Triển khai các bước phát hành thực tế theo đúng thứ tự kỹ thuật an toàn để đưa hệ thống POS lên hoạt động độc lập, bảo vệ dữ liệu và không gây gián đoạn hoạt động của quán.

---

## 📋 THỨ TỰ CÁC BƯỚC TRIỂN KHAI THỰC TẾ (DO CHỦ DỰ ÁN THỰC HIỆN)

### Bước 1: Xuất bản sao lưu toàn bộ Realtime Database từ Console
- [ ] Vào [Firebase Console](https://console.firebase.google.com/) $\rightarrow$ Chọn dự án `tramapp-36f53`.
- [ ] Vào mục **Realtime Database** $\rightarrow$ Tab **Data**.
- [ ] Nhấp vào biểu tượng ba chấm $\vdots$ ở góc trên bên phải $\rightarrow$ Chọn **Export JSON**.
- [ ] Lưu trữ file JSON an toàn vào máy tính cá nhân để làm bản hoàn nguyên khi cần.

---

### Bước 2: Chạy kiểm tra dữ liệu với `scripts/verify_dual_sync` (Chỉ đọc)
- [ ] Chạy script kiểm tra (script này chỉ đọc, không ghi bất kỳ dữ liệu nào):
  ```bash
  cd scripts/verify_dual_sync
  node verify.js
  ```
- [ ] Đọc kỹ kết quả đối soát. Nếu nhánh `stores/TRAM01` còn thiếu dữ liệu danh mục, bàn, hoặc sản phẩm so với các nút gốc cũ, bổ sung hoặc sao chép trước khi tiếp tục.

---

### Bước 3: Di chuyển dữ liệu khách hàng CRM (`scripts/migrate_customers`)
- [ ] **Chạy thử nghiệm (Dry-run):**
  ```bash
  cd scripts/migrate_customers
  node migrate.js --store=TRAM01
  ```
  *Đọc kỹ tổng kết: số khách hàng tìm thấy, số bản ghi dự kiến copy, đường dẫn file backup.*
- [ ] **Áp dụng ghi thực tế (--apply):**
  ```bash
  node migrate.js --apply --store=TRAM01
  ```
  *Toàn bộ dữ liệu `/kmt_customers` sẽ được sao chép sang `stores/TRAM01/customers`. Node cũ được giữ nguyên vẹn.*

---

### Bước 4: Di chuyển tài khoản nhân viên cũ (`scripts/migrate_legacy_users`)
- [ ] **Chạy thử nghiệm (Dry-run):**
  ```bash
  cd scripts/migrate_legacy_users
  node migrate.js
  ```
- [ ] **Áp dụng ghi thực tế (--apply):**
  ```bash
  node migrate.js --apply
  ```
  *Tạo tài khoản Firebase Auth, cập nhật `userIndex/{uid}`, xóa trường `password` thô trong database.*

---

### Bước 5: Triển khai Cloud Functions cho POS
- [ ] Triển khai các hàm Cloud Functions với codebase `pos` độc lập:
  ```bash
  firebase deploy --only functions:pos --project tramapp-36f53
  ```
  *(Lưu ý: Chỉ deploy codebase `pos`, không xóa hay ảnh hưởng đến bất kỳ hàm nào khác).*

---

### Bước 6: Phát hành bản ứng dụng mới cho nhân viên
- [ ] **Quan trọng:** Bản app cũ vẫn còn cơ chế đọc các nút gốc. Do đó, cần cập nhật đồng loạt phiên bản mới cho toàn bộ nhân viên (cả ứng dụng Flutter trên điện thoại và bản Web Admin) trước khi triển khai rules mới.
- [ ] Build và triển khai Web Admin:
  ```bash
  cd web && npm run build
  ```
- [ ] Build bản cài đặt Flutter POS mới cho nhân viên (Android APK / iOS).

---

### Bước 7: Triển khai Security Rules mới (`database.rules.json`)
- [ ] Deploy bộ rules mới đã chốt:
  ```bash
  firebase deploy --only database --project tramapp-36f53
  ```
- [ ] **Kiểm tra đăng nhập thử nghiệm:**
  - Mở app Flutter và Web Admin, đăng nhập thử từng vai trò:
    - **Chủ quán (`owner`):** Xem và sửa được toàn bộ cấu hình quán, menu, báo cáo.
    - **Quản lý (`manager`):** Xem và sửa menu, ca két, hóa đơn; không sửa được chủ quán gốc.
    - **Thu ngân (`cashier`):** Tạo hóa đơn, quản lý két tiền, tra cứu khách hàng; không sửa giá menu.
    - **Phục vụ (`waiter`):** Xem bàn, tạo order bàn; không sửa menu hay khách hàng.
    - **Bếp (`kitchen`):** Xem và cập nhật danh sách chế biến món.

---

### Bước 8: Tắt tính năng đăng ký tài khoản tự do (Sign-up Lock)
- [ ] Vào Firebase Console $\rightarrow$ **Authentication** $\rightarrow$ Tab **Settings** $\rightarrow$ Mục **User actions**.
- [ ] Bỏ chọn **"Enable create (sign-up)"** (Tắt đăng ký tự do).
- [ ] *Lưu ý:* Chỉ thực hiện khi chắc chắn Authentication của project `tramapp-36f53` không có app nào khác cần đăng ký tự do. Nhân viên mới vẫn được tạo bình thường vì việc tạo tài khoản đi qua Cloud Functions (`createStaffAccount`).

---

### Bước 9: Phương án khẩn cấp khi cần quay lại (Rollback Plan)
Nếu phát sinh bất kỳ sự cố ngoài ý muốn:
1. **Khôi phục Security Rules:**
   ```bash
   firebase database:rules:set docs/rules_ban_truoc_khi_chot.json --project tramapp-36f53
   ```
2. **Khôi phục dữ liệu Database:**
   - Vào Firebase Console $\rightarrow$ **Realtime Database** $\rightarrow$ Tab **Data** $\rightarrow$ Biểu tượng $\vdots$ $\rightarrow$ **Import JSON** $\rightarrow$ Chọn bản sao lưu đã tải về ở Bước 1.
