# HƯỚNG DẪN QUY TRÌNH PHÁT HÀNH AN TOÀN (RELEASE CHECKLIST)
## HỆ THỐNG POS TRẠM F&B (PHIÊN BẢN 2.1.0)

> **Mục tiêu:** Đảm bảo quá trình triển khai cập nhật phân quyền bảo mật, Cloud Functions và di chuyển dữ liệu người dùng diễn ra suôn sẻ, an toàn 100%, không làm gián đoạn hệ thống quán đang kinh doanh và **tuyệt đối không ảnh hưởng đến ứng dụng Chấm công Trạm**.

---

## 📌 BẢNG TỔNG HỢP CÁC GIAI ĐOẠN TRIỂN KHAI

| Giai đoạn | Nội dung công việc | Rủi ro | Người phụ trách |
| :---: | :--- | :---: | :---: |
| **Giai đoạn 0** | Chuẩn bị, bật gói Blaze, tải bản sao lưu (Backup) | Rất thấp | Kỹ thuật viên / Chủ quán |
| **Giai đoạn 1** | Thử nghiệm trên Firebase Project thử nghiệm | Không có | Kỹ thuật viên |
| **Giai đoạn 2** | Chạy Migrate tài khoản trên Project thật (Dry-run $\rightarrow$ Apply) | Trung bình | Kỹ thuật viên |
| **Giai đoạn 3** | Triển khai Firebase Cloud Functions | Thấp | Kỹ thuật viên |
| **Giai đoạn 4** | Triển khai Firebase Security Rules | Trung bình | Kỹ thuật viên |
| **Giai đoạn 5** | Build và cập nhật ứng dụng Web Admin & Flutter POS | Thấp | Kỹ thuật viên |
| **Giai đoạn 6** | Nghiệm thu sau phát hành & Thử nghiệm app Chấm công | Không có | Quản lý & Nhân viên |
| **Quay lui (Rollback)**| Phương án phục hồi khẩn cấp nếu gặp sự cố | Khẩn cấp | Toàn bộ đội ngũ |

---

## GIAI ĐOẠN 0: CHUẨN BỊ TRƯỚC PHÁT HÀNH

- [ ] **0.1. Sao lưu dữ liệu Realtime Database từ Firebase Console (BẮT BUỘC):**
  1. Mở [Firebase Console](https://console.firebase.google.com/) $\rightarrow$ Chọn dự án `chamcongtram` (hoặc `tramapp-36f53`).
  2. Vào mục **Build** $\rightarrow$ **Realtime Database** $\rightarrow$ Chọn thẻ **Data**.
  3. Bấm vào biểu tượng ba chấm $\vdots$ ở góc phải $\rightarrow$ Chọn **Export JSON**.
  4. Lưu tệp JSON tải về vào máy tính với tên dạng: `backup_rtdb_truoc_khi_update_YYYYMMDD.json`.
- [ ] **0.2. Kiểm tra gói dịch vụ Firebase (Blaze Plan):**
  - Cloud Functions v2 yêu cầu project phải ở gói **Blaze (Pay-as-you-go)**.
  - Kiểm tra góc dưới bên trái Firebase Console xem đã hiện "Blaze" chưa. Nếu là "Spark", nhấp **Upgrade** và gắn thẻ thanh toán.
- [ ] **0.3. Tải khóa Service Account Key:**
  1. Vào ⚙️ **Project settings** $\rightarrow$ Thẻ **Service accounts**.
  2. Nhấp **Generate new private key** (Tạo khóa riêng tư mới).
  3. Đặt file tải về vào thư mục gốc với tên: `service-account.json`. *(File này đã nằm trong `.gitignore`, không lo bị đẩy lên Git).*

---

## GIAI ĐOẠN 1: THỬ NGHIỆM TRÊN PROJECT THỬ (STAGING)

*(Khuyến nghị thực hiện trên project phụ trước khi áp dụng vào giờ quán đang bán)*
- [ ] **1.1.** Tạo 1 project Firebase phụ miễn phí (ví dụ: `trampos-test`).
- [ ] **1.2.** Import file dữ liệu thử nghiệm vào Realtime Database của project phụ.
- [ ] **1.3.** Triển khai rules và functions lên project phụ:
  ```bash
  firebase deploy --only database,functions --project trampos-test
  ```
- [ ] **1.4.** Chạy thử script migrate tài khoản trên project phụ để quan sát log.

---

## GIAI ĐOẠN 2: CHẠY MIGRATE TÀI KHOẢN TRÊN PROJECT THẬT

> **Lưu ý:** Nên thực hiện vào khung giờ quán vắng khách hoặc sau giờ đóng cửa (sau 22:30).

- [ ] **2.1. Chạy thử kiểm tra (Dry-Run - Tuyệt đối không ghi dữ liệu):**
  ```bash
  cd scripts/migrate_legacy_users
  npm run dry-run
  ```
  - Kiểm tra màn hình terminal:
    - Tổng số tài khoản quét được.
    - Danh sách email sẽ tạo: `{username}.{storeCode.toLowerCase()}@tram.local`.
    - Các tài khoản giữ mật khẩu cũ ($\ge$ 6 ký tự) và tài khoản sinh mật khẩu mới (8 ký tự).
- [ ] **2.2. Áp dụng chuyển đổi thật (--apply):**
  Sau khi xác nhận danh sách ở bước 2.1 chính xác:
  ```bash
  npm run apply
  ```
  - Script sẽ tự động:
    1. Xuất file backup JSON vào thư mục `migration_output/backup_pre_migration_*.json`.
    2. Tạo/cập nhật user trên Firebase Auth.
    3. Ghi `userIndex/{uid}/{storeCode} = true`.
    4. Xóa vĩnh viễn trường `password` thô khỏi RTDB.
    5. Xuất file `migrated_users_*.csv` chứa mật khẩu tạm của các tài khoản được sinh mới.
- [ ] **2.3. Bàn giao mật khẩu tạm:**
  - Gửi các tài khoản có mật khẩu mới trong file CSV cho Chủ quán / Quản lý để bàn giao cho nhân viên.

---

## GIAI ĐOẠN 3: TRIỂN KHAI CLOUD FUNCTIONS

- [ ] **3.1. Kiểm tra biên dịch code Functions:**
  ```bash
  cd functions
  npm test
  npm run build
  ```
  - Đảm bảo 5/5 unit tests PASS và `tsc` chạy không có lỗi.
- [ ] **3.2. Triển khai Functions lên Firebase:**
  ```bash
  firebase deploy --only functions
  ```
  - Kiểm tra xem 3 hàm callable sau đã online trên vùng `asia-southeast1`:
    - `createStaffAccount`
    - `resetStaffPassword`
    - `setStaffDisabled`

---

## GIAI ĐOẠN 4: TRIỂN KHAI FIREBASE SECURITY RULES

- [ ] **4.1. Kiểm tra nội dung database.rules.json:**
  - Đảm bảo các nút của app Chấm công Trạm (`/cham_cong`, `/timekeeping`, `/employees`, `/shifts`) và `/kmt_customers` vẫn mở đầy đủ:
    ```json
    "cham_cong": { ".read": "auth != null", ".write": "auth != null" },
    "timekeeping": { ".read": "auth != null", ".write": "auth != null" },
    "employees": { ".read": "auth != null", ".write": "auth != null" },
    "shifts": { ".read": "auth != null", ".write": "auth != null" },
    "kmt_customers": { ".read": "auth != null", ".write": "auth != null" }
    ```
- [ ] **4.2. Chạy test bộ rules:**
  ```bash
  cd tests/rules
  npm test
  ```
  - Đảm bảo 10/10 tests PASS.
- [ ] **4.3. Triển khai Rules lên Firebase:**
  ```bash
  firebase deploy --only database
  ```
  - Thông báo hiển thị: `✔  Deploy complete!`

---

## GIAI ĐOẠN 5: BUILD VÀ CẬP NHẬT ỨNG DỤNG CLIENT

### 5.1. Cập nhật Web Admin (Next.js)
- [ ] Chạy kiểm thử lần cuối:
  ```bash
  cd web
  npm test
  npm run build
  ```
- [ ] Deploy bản web mới lên Vercel / Firebase Hosting / Server sản xuất.

### 5.2. Cập nhật ứng dụng Flutter POS
- [ ] Chạy kiểm thử:
  ```bash
  cd app_flutter
  flutter test
  ```
- [ ] Build bản phát hành cho máy POS:
  ```bash
  flutter build apk --release
  # hoặc flutter build appbundle / windows tuỳ nền tảng
  ```
- [ ] Cài đặt file APK mới lên thiết bị POS tại cửa hàng.

---

## GIAI ĐOẠN 6: NGHIỆM THU SAU PHÁT HÀNH (POST-RELEASE VERIFICATION)

Thực hiện kiểm thử thực tế trên thiết bị:
- [ ] **6.1. Đăng nhập Chủ Quán:**
  - Đăng nhập bằng tài khoản Chủ quán gốc (`admin`).
  - Kiểm tra xem toàn bộ danh mục, bàn, doanh thu có nạp bình thường không.
- [ ] **6.2. Đăng nhập Nhân Viên Thu Ngân / Phục Vụ:**
  - Đăng nhập bằng tài khoản thu ngân (`thungan1`).
  - Thử mở bàn, gọi món gửi bếp, in hóa đơn tạm tính $\rightarrow$ Thành công.
  - Thử mở cài đặt sửa giá sản phẩm $\rightarrow$ Bị chặn hoặc ẩn nút.
- [ ] **6.3. Thử tạo nhân viên mới qua Cloud Function:**
  - Dùng tài khoản Chủ quán trên Web hoặc POS $\rightarrow$ Bấm "Thêm nhân viên".
  - Nhập thông tin và tạo $\rightarrow$ Kiểm tra nhân viên mới đăng nhập được ngay.
- [ ] **6.4. Thử tính năng Đặt lại mật khẩu:**
  - Bấm nút icon chìa khóa 🔑 "Đặt lại mật khẩu" trên một nhân viên.
  - Nhập mật khẩu mới $\rightarrow$ Dùng tài khoản đó đăng nhập $\rightarrow$ Hệ thống bắt buộc đổi mật khẩu mới.
- [ ] **6.5. KIỂM TRA ỨNG DỤNG CHẤM CÔNG TRẠM (QUAN TRỌNG):**
  - Mở ứng dụng Chấm công Trạm trên điện thoại nhân viên.
  - Thực hiện chấm công vào ca / ra ca thử nghiệm.
  - **Xác nhận:** Chấm công ghi nhận bình thường, không bị báo lỗi quyền truy cập Realtime Database (`Permission Denied`).
- [ ] **6.6. DỌN DẸP BẢO MẬT:**
  - Xóa file `service-account.json` khỏi thư mục dự án.
  - Xóa hoặc cất giữ bảo mật file CSV mật khẩu tạm trong `migration_output/`.

---

## 🚨 KẾ HOẠCH QUAY LUI KHẨN CẤP (ROLLBACK PLAN)

Nếu trong quá trình triển khai xảy ra sự cố nghiêm trọng (ví dụ: nhân viên không thể mở bàn, hoặc ứng dụng Chấm công bị từ chối truy cập):

### Tình huống 1: Security Rules gây lỗi Permission Denied cho các nghiệp vụ đang chạy
1. Khôi phục nhanh bằng cách deploy lại file rules tạm thời mở cho tài khoản đã đăng nhập:
   ```bash
   # Trong database.rules.json, tạm thời chỉnh lại:
   # ".read": "auth != null", ".write": "auth != null" cho stores/$storeCode
   firebase deploy --only database
   ```
2. Kiểm tra log trên Firebase Realtime Database để xác định node nào bị chặn sai rule.

### Tình huống 2: Script Migrate ghi sai dữ liệu người dùng
1. Mở thư mục `migration_output/`.
2. Tìm file sao lưu trước khi migrate: `backup_pre_migration_[timestamp].json`.
3. Dùng Firebase Console $\rightarrow$ Realtime Database $\rightarrow$ Nhấp ba chấm $\vdots$ $\rightarrow$ **Import JSON** $\rightarrow$ Chọn file backup để phục hồi nguyên trạng 100% dữ liệu cũ.
