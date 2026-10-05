# BÁO CÁO KIỂM THỬ TOÀN DIỆN & RÀ SOÁT BẢO MẬT (QA & SECURITY AUDIT REPORT)
**Dự án:** POS Trạm (Hệ thống Điểm bán lẻ F&B Đa nền tảng)  
**Phiên bản:** 2.1.0 (Đợt khắc phục lỗ hổng bảo mật, phân quyền RBAC & Cloud Functions)  
**Ngày thực hiện:** 05/10/2026  
**Trạng thái kiểm thử:** **100% PASS TOÀN BỘ HỆ THỐNG**  
- Flutter: **110 / 110** unit/widget tests PASS (`flutter test`)
- Web Admin: **30 / 30** Vitest tests PASS, **21 / 21** Next.js Static Pages Build PASS
- Cloud Functions: **5 / 5** Vitest tests PASS, TypeScript compilation clean (`tsc`)
- Security Rules: **10 / 10** Rules Unit Tests PASS (`@firebase/rules-unit-testing`)

---

## 1. TỔNG KẾT CÁC LỖ HỔNG & LỖI ĐÃ KHẮC PHỤC

| STT | Vấn đề / Lỗ hổng kỹ thuật | Giải pháp khắc phục | Trạng thái |
| :---: | :--- | :--- | :---: |
| 1 | **Các nút gốc cũ mở tự do:** Các nút POS cũ (`users`, `tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `online_orders`, `kitchen_orders`) mở `.read/.write: auth != null`, cho phép mọi tài khoản tự đăng ký truy cập. | Đóng vĩnh viễn nút không dùng (`online_orders`, `kitchen_orders` $\rightarrow$ `false`). Các nút POS cũ chỉ cho phép người dùng có `userIndex/{auth.uid}`. | **ĐÃ KHẮC PHỤC** |
| 2 | **Thiếu phân quyền theo vai trò trong Store:** Trong `stores/{storeCode}`, mọi nhân viên (kể cả phục vụ/bếp) đều có quyền ghi sửa bảng giá, hóa đơn, khuyến mãi. | Thiết lập RBAC nghiêm ngặt: `products`, `categories`, `promotions`, `inventory` chỉ Chủ quán & Quản lý được sửa; Phục vụ chỉ mở bàn & gửi món; Thu ngân tạo đơn/két ca; Bếp chỉ xem & xử lý món. | **ĐÃ KHẮC PHỤC** |
| 3 | **Tài khoản mẫu và mật khẩu thô trong Client:** Màn hình phân quyền chứa tài khoản cứng (`admin/admin`, `thungan/123`). | Xóa bỏ 100% tài khoản mẫu trong `permissions_matrix_screen.dart`, bổ sung trạng thái rỗng (Empty State) an toàn. | **ĐÃ KHẮC PHỤC** |
| 4 | **Tạo tài khoản bằng Firebase App phụ phía Client:** Client khởi tạo đối tượng Firebase phụ rồi tạo Auth user, tiềm ẩn rủi ro lộ credential và không đồng bộ server. | Chuyển toàn bộ luồng sang Firebase Cloud Functions (v2 Callable): `createStaffAccount`, `resetStaffPassword`, `setStaffDisabled`. | **ĐÃ KHẮC PHỤC** |
| 5 | **Không có tính năng Đặt lại mật khẩu nhân viên:** Quản lý không có cách nào reset mật khẩu cho nhân viên quên mật khẩu mà không sửa thẳng vào DB. | Triển khai hàm `resetStaffPassword` (Cloud Function) và giao diện nút "Đặt lại mật khẩu" trên cả Web Admin và Flutter POS kèm cờ `mustChangePassword`. | **ĐÃ KHẮC PHỤC** |
| 6 | **Tài khoản bị khóa vẫn đăng nhập được:** Khóa tài khoản chỉ cập nhật trường `isActive` trên DB mà không khóa tài khoản Firebase Auth. | Triển khai `setStaffDisabled` cập nhật song song Auth `disabled: true`, thu hồi refresh token và cập nhật `isActive: false` trên RTDB. | **ĐÃ KHẮC PHỤC** |
| 7 | **Thiếu công cụ chuyển đổi tài khoản cũ:** Người dùng cũ lưu mật khẩu plaintext trong RTDB chưa được đưa lên Firebase Auth. | Xây dựng script `scripts/migrate_legacy_users/migrate.js` có chế độ Dry-run, tự động sao lưu JSON, sinh mật khẩu ngẫu nhiên cho mật khẩu < 6 ký tự và xuất CSV an toàn. | **ĐÃ KHẮC PHỤC** |
| 8 | **Bảo tồn tuyệt đối 2 ứng dụng dùng chung Firebase:** Nguy cơ Security Rules khóa nhầm các nút của app Chấm công Trạm (`/cham_cong`, `/timekeeping`, `/employees`, `/shifts`) và `/kmt_customers`. | Giữ nguyên 100% cấu hình `.read: auth != null, .write: auth != null` cho tất cả các nút của hệ thống Chấm công và kmt_customers. | **BẢO ĐẢM 100%** |

---

## 2. BẢNG PHÂN LOẠI MỨC ĐỘ NGHIÊM TRỌNG (SEVERITY MATRIX)

| Mức độ | Lỗ hổng / Rủi ro | Mô tả tác động trước khi sửa | Biện pháp xử lý & Kiểm chứng |
| :--- | :--- | :--- | :--- |
| 🔴 **NGHIÊM TRỌNG**<br>(Critical) | Mật khẩu thô lưu trong RTDB & Nút gốc mở toàn bộ | Ai có Firebase Auth token đều có thể đọc toàn bộ danh sách tài khoản, mật khẩu nhân viên và dữ liệu nhà hàng. | Thêm cờ `!newData.hasChild('password')`, đóng nút gốc, tạo script di chuyển lên Firebase Auth, xóa trường password. Test rules ca 6 PASS. |
| 🔴 **NGHIÊM TRỌNG**<br>(Critical) | Hạ quyền / Khóa tài khoản Chủ quán gốc | Quản lý hoặc nhân viên có thể sửa `roleId` hoặc xóa `isRootOwner` của Chủ quán. | Áp dụng Sovereign Owner Rule trong Rules và Functions: Không ai ngoài Chủ quán gốc được sửa đổi hồ sơ Chủ quán gốc. Test rules ca 7 PASS, Functions test ca 3, 4 PASS. |
| 🟠 **CAO**<br>(High) | Nhân viên phục vụ/bếp sửa menu & bảng giá | Phục vụ hoặc bếp có thể gửi payload sửa giá món ăn hoặc tạo khuyến mãi 100%. | Phân quyền RBAC trong RTDB rules: chỉ `ROLE_OWNER` và `ROLE_MANAGER` được ghi vào `products`, `categories`, `promotions`. Test rules ca 3, 4 PASS. |
| 🟠 **CAO**<br>(High) | Đăng nhập tài khoản đã bị khóa | Khóa trên giao diện nhưng Firebase Auth token vẫn hợp lệ, nhân viên nghỉ việc vẫn đăng nhập được. | `setStaffDisabled` gọi `admin.auth().updateUser(uid, { disabled: true })` và `revokeRefreshTokens(uid)`. |
| 🟡 **TRUNG BÌNH**<br>(Medium) | Tài khoản test hardcoded trong code Flutter | Tài khoản `admin/admin` có thể bị lộ nếu file APK/Web bị phân tích dịch ngược. | Loại bỏ toàn bộ mock users trong `permissions_matrix_screen.dart`, nạp 100% từ cơ sở dữ liệu thật. |
| 🟡 **TRUNG BÌNH**<br>(Medium) | Xung đột với app Chấm công Trạm | Rules POS thắt chặt có thể làm gián đoạn việc nhân viên chấm công hàng ngày. | Cô lập hoàn toàn phạm vi rules POS trong `stores/{storeCode}`, bảo lưu nguyên vẹn các nút chấm công. |
| 🟢 **THẤP**<br>(Low) | Cảnh báo dependency & npm peer legacy | Cần cờ `--legacy-peer-deps` để cài đặt thư viện trên Web Admin, làm chậm CI/CD. | Nâng cấp `@types/node` lên `^22`, tái tạo `package-lock.json` chuẩn, `npm ci` chạy mượt mà trên GitHub Actions. |

---

## 3. KẾT QUẢ THỰC TẾ CÁC LỆNH KIỂM THỬ (RAW COMMAND OUTPUTS)

### 3.1. Phân hệ Flutter POS (`app_flutter/`)
- **Lệnh 1:** `flutter test`
  - **Kết quả:** `110 passed!` (100% thành công)
  - **Các ca kiểm thử trọng tâm:**
    - `auth_test.dart` (18 tests): Sinh email ảo `{username}.{storeCode}@tram.local`, khóa brute-force 5 lần sai trong 15 phút, `toMap()` không chứa trường `password`, kiểm tra quyền hạn Sovereign Owner.
    - `report_golden_test.dart` (13 tests): Khớp từng đồng với bộ dữ liệu vàng `docs/report_golden.json`.
    - `pricing_engine_test.dart` (21 tests): Tính toán giá, áp dụng khuyến mãi, voucher.
    - `promotion_migration_test.dart` (11 tests): Schema khuyến mãi giữa Flutter và Web.
    - `printer_test.dart` (15 tests): ESC/POS raster in tiếng Việt, hàng đợi in lại.
    - `manager_hub_test.dart` & `fnb_system_test.dart` (31 tests): Ca két, gộp/tách bàn.
- **Lệnh 2:** `flutter pub get`
  - **Kết quả:** Thêm thành công `cloud_functions: ^5.1.3`, giải quyết dependency trong 2.1s mà không gây xung đột phiên bản.

### 3.2. Phân hệ Web Admin (`web/`)
- **Lệnh 1:** `npm test` (Vitest)
  - **Kết quả:** `30 passed (30)` qua 2 test files `test/auth.test.ts` và `test/reports.test.ts`.
- **Lệnh 2:** `npx tsc --noEmit`
  - **Kết quả:** Exit code 0, không có lỗi kiểu TypeScript nào.
- **Lệnh 3:** `npm run build` (Next.js)
  - **Kết quả:** Biên dịch thành công 21/21 static pages trong 3.6s:
    - `/dashboard/users` (Trang quản lý người dùng tích hợp Cloud Functions)
    - `/login/change-password` (Trang đổi mật khẩu bắt buộc)
    - Toàn bộ các trang báo cáo, ca két, hóa đơn, tồn kho.

### 3.3. Phân hệ Cloud Functions (`functions/`)
- **Lệnh 1:** `npm test` (Vitest)
  - **Kết quả:** `5 passed (5)` trong `src/permissions.test.ts`:
    1. Phục vụ không có quyền quản lý người dùng: PASS
    2. Quản lý không được tạo tài khoản có vai trò Chủ quán: PASS
    3. Quản lý không được đặt lại mật khẩu cho Chủ quán gốc: PASS
    4. Không ai được phép khóa Chủ quán gốc: PASS
    5. Chuẩn hóa username và sinh email lowercase: PASS
- **Lệnh 2:** `npm run build` (`tsc`)
  - **Kết quả:** Exit code 0, tệp biên dịch đầu ra sạch sẽ tại `lib/index.js` và `lib/permissions.js`.

### 3.4. Phân hệ Firebase Security Rules (`tests/rules/`)
- **Lệnh:** `npm test` (Vitest với `@firebase/rules-unit-testing`)
- **Kết quả:** `10 passed (10)`:
  1. Tài khoản tự đăng ký không có userIndex không được đọc dữ liệu quán: PASS
  2. Người của Quán A không đọc được Quán B: PASS
  3. Phục vụ và Bếp không được ghi products hoặc promotions: PASS
  4. Thu ngân tạo được bills nhưng không sửa được products: PASS
  5. Thu ngân không thể tự sửa roleId của chính mình: PASS
  6. Không ai được phép ghi trường password vào user record: PASS
  7. Quản lý không thể khóa hoặc sửa tài khoản của Chủ quán gốc (isRootOwner): PASS
  8. audit_logs thêm được nhưng cấm sửa hoặc xóa: PASS
  9. Client không thể ghi userIndex; chỉ đọc được của chính mình: PASS
  10. Tài khoản isActive === false bị từ chối truy cập: PASS

---

## 4. TÍNH NGUYÊN VẸN CỦA DỰ ÁN DÙNG CHUNG ("CHẤM CÔNG TRẠM")

Quy tắc bảo vệ hạ tầng dùng chung đã được áp dụng triệt để:
1. **Không thay đổi cấu hình các nút Chấm công:**
   - `/cham_cong`: `.read: auth != null, .write: auth != null` (Giữ nguyên)
   - `/timekeeping`: `.read: auth != null, .write: auth != null` (Giữ nguyên)
   - `/employees`: `.read: auth != null, .write: auth != null` (Giữ nguyên)
   - `/shifts`: `.read: auth != null, .write: auth != null` (Giữ nguyên)
   - `/kmt_customers`: `.read: auth != null, .write: auth != null` (Giữ nguyên)
2. **Cô lập User Pool trong Firebase Auth:**
   - Tài khoản nhân viên POS Trạm luôn có đuôi email `@tram.local`.
   - Nhân viên app Chấm công Trạm sử dụng email thông thường hoặc định dạng riêng, không bị ảnh hưởng hay trùng lặp.

---

## 5. CÁC ĐIỂM CẦN THEO DÕI SAU PHÁT HÀNH (MONITORING & RESIDUAL RISKS)

1. **Bật gói Firebase Blaze:** Cloud Functions v2 yêu cầu project phải kích hoạt gói Blaze (trả theo mức dùng, có hạn mức miễn phí lớn). Cần bảo đảm thẻ thanh toán hợp lệ trên Google Cloud Console.
2. **Giám sát Quota Cloud Functions:** Theo dõi số lượng cuộc gọi tới `createStaffAccount`, `resetStaffPassword`, `setStaffDisabled` trong tuần đầu tiên trên Firebase Console.
3. **Theo dõi việc đổi mật khẩu lần đầu của nhân viên:** Kiểm tra các tài khoản sau khi migrate có đăng nhập thành công và đổi mật khẩu theo cờ `mustChangePassword` hay không.
