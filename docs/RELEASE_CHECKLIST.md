# HƯỚNG DẪN QUY TRÌNH PHÁT HÀNH AN TOÀN (RELEASE CHECKLIST)
## HỆ THỐNG POS TRẠM F&B (PHIÊN BẢN 2.2.0 - DỰ ÁN GỐC TRAMAPP-36F53)

> **Mục tiêu:** Đảm bảo quá trình thống nhất hệ thống POS về một project Firebase gốc duy nhất (`tramapp-36f53`), cắt triệt để dual-sync vào các nút gốc cũ, triển khai Cloud Functions với codebase "pos" độc lập và **tuyệt đối không xóa hay ảnh hưởng đến 13 Cloud Functions cùng hạ tầng của app Chấm công Trạm**.

---

## 📌 BẢNG TỔNG HỢP CÁC GIAI ĐOẠN TRIỂN KHAI

| Giai đoạn | Nội dung công việc | Rủi ro | Người phụ trách |
| :---: | :--- | :--- :--- | :---: |
| **Giai đoạn 0** | Chuẩn bị, bật gói Blaze, tải bản sao lưu (Backup) | Rất thấp | Kỹ thuật viên / Chủ quán |
| **Giai đoạn 1** | Thử nghiệm trên Firebase Project thử nghiệm (Staging) | Không có | Kỹ thuật viên |
| **Giai đoạn 2** | Chạy Migrate tài khoản trên Project thật (Dry-run $\rightarrow$ Apply) | Trung bình | Kỹ thuật viên |
| **Giai đoạn 3** | Triển khai Firebase Cloud Functions (codebase `pos` độc lập) | Thấp | Kỹ thuật viên |
| **Giai đoạn 4** | Triển khai Firebase Security Rules | Trung bình | Kỹ thuật viên |
| **Giai đoạn 5** | Build và cập nhật ứng dụng Web Admin & Flutter POS | Thấp | Kỹ thuật viên |
| **Giai đoạn 6** | Nghiệm thu sau phát hành & Thử nghiệm app Chấm công | Không có | Quản lý & Nhân viên |
| **Quay lui (Rollback)**| Phương án phục hồi khẩn cấp nếu gặp sự cố | Khẩn cấp | Toàn bộ đội ngũ |

---

## GIAI ĐOẠN 0: CHUẨN BỊ TRƯỚC PHÁT HÀNH

- [ ] **0.1. Sao lưu dữ liệu Realtime Database từ Firebase Console (BẮT BUỘC):**
  1. Mở [Firebase Console](https://console.firebase.google.com/) $\rightarrow$ Chọn dự án `tramapp-36f53`.
  2. Vào mục **Build** $\rightarrow$ **Realtime Database** $\rightarrow$ Chọn thẻ **Data**.
  3. Bấm vào biểu tượng ba chấm $\vdots$ ở góc phải $\rightarrow$ Chọn **Export JSON**.
  4. Lưu tệp JSON tải về vào máy tính với tên dạng: `backup_rtdb_truoc_khi_update_YYYYMMDD.json`.
- [ ] **0.2. Lưu trữ rules hiện tại:**
  - Copy rules đang chạy trên Firebase Console tab Rules vào `docs/rules_hien_tai_tramapp.json`.
- [ ] **0.3. Kiểm tra gói dịch vụ Firebase (Blaze Plan):**
  - Cloud Functions v2 yêu cầu project phải ở gói **Blaze (Pay-as-you-go)**.
  - Gói Blaze áp dụng cho cả project `tramapp-36f53`. Hạn mức miễn phí hàng tháng vẫn áp dụng bình thường.
- [ ] **0.4. Tải khóa Service Account Key (khi cần chạy script):**
  1. Vào ⚙️ **Project settings** $\rightarrow$ Thẻ **Service accounts**.
  2. Nhấp **Generate new private key** (Tạo khóa riêng tư mới).
  3. Đặt file tải về vào thư mục gốc với tên: `service-account.json`. *(File này đã nằm trong `.gitignore`, không lo bị đẩy lên Git).*

---

## GIAI ĐOẠN 1: THỬ NGHIỆM TRÊN PROJECT THỬ (STAGING)

- [ ] **1.1.** Tạo 1 project Firebase phụ (ví dụ: `tramapp-staging`).
- [ ] **1.2.** Import file dữ liệu thử nghiệm vào Realtime Database của project phụ.
- [ ] **1.3.** Triển khai rules và functions lên project phụ:
  ```bash
  firebase deploy --only functions:pos,database --project tramapp-staging
  ```
- [ ] **1.4.** Chạy thử script migrate tài khoản và script verify dual-sync trên project phụ.

---

## GIAI ĐOẠN 2: CHẠY MIGRATE TÀI KHOẢN TRÊN PROJECT THẬT

> **Lưu ý:** Nên thực hiện vào khung giờ quán vắng khách hoặc sau giờ đóng cửa (sau 22:30).

- [ ] **2.1. Chạy thử kiểm tra (Dry-Run - Tuyệt đối không ghi dữ liệu):**
  ```bash
  cd scripts/migrate_legacy_users
  npm run dry-run
  ```
- [ ] **2.2. Áp dụng chuyển đổi thật (--apply):**
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

> [!CAUTION]
> **CẢNH BÁO BẢO MẬT HẠ TẦNG CHÙNG DÙNG:**
> Tuyệt đối KHÔNG chạy `firebase deploy --only functions` vì sẽ xóa 13 Cloud Functions của app Chấm công!
> Luôn chỉ định codebase `functions:pos`!

- [ ] **3.1. Kiểm tra biên dịch code Functions:**
  ```bash
  cd functions
  npm test
  npm run build
  ```
  - Đảm bảo 5/5 unit tests PASS và `tsc` chạy không có lỗi.
- [ ] **3.2. Triển khai Functions an toàn:**
  ```bash
  firebase deploy --only functions:pos --project tramapp-36f53
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
  - Đảm bảo 12/12 tests PASS.
- [ ] **4.3. Triển khai Rules lên Firebase:**
  ```bash
  firebase deploy --only database --project tramapp-36f53
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
  - Đảm bảo 30/30 tests PASS và biên dịch thành công 21/21 trang static.
- [ ] Deploy bản web mới lên Vercel / Firebase Hosting / Server sản xuất.

### 5.2. Cập nhật ứng dụng Flutter POS
- [ ] Chạy kiểm thử:
  ```bash
  cd app_flutter
  flutter test
  ```
  - Đảm bảo 110/110 tests PASS.
- [ ] Sinh lại cấu hình nếu cần đồng nhất:
  ```bash
  cd app_flutter
  flutterfire configure --project=tramapp-36f53
  ```
- [ ] Build bản phát hành cho máy POS:
  ```bash
  flutter build apk --release
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

### Tình huống 1: Security Rules gây lỗi Permission Denied cho các nghiệp vụ đang chạy
1. Khôi phục nhanh bằng cách deploy lại rules:
   ```bash
   firebase deploy --only database --project tramapp-36f53
   ```
2. Kiểm tra log trên Firebase Realtime Database để xác định node nào bị chặn sai rule.

### Tình huống 2: Script Migrate ghi sai dữ liệu người dùng
1. Mở thư mục `migration_output/`.
2. Tìm file sao lưu trước khi migrate: `backup_pre_migration_[timestamp].json`.
3. Dùng Firebase Console $\rightarrow$ Realtime Database $\rightarrow$ Nhấp ba chấm $\vdots$ $\rightarrow$ **Import JSON** $\rightarrow$ Chọn file backup để phục hồi nguyên trạng 100% dữ liệu cũ.
