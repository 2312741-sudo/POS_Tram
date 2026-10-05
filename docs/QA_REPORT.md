# BÁO CÁO KIỂM THỬ TOÀN DIỆN & RÀ SOÁT BẢO MẬT (QA & SECURITY AUDIT REPORT)
**Dự án:** POS Trạm (Hệ thống Điểm bán lẻ F&B Đa nền tảng)  
**Phiên bản:** 2.2.0 (Đồng nhất Dự án Firebase gốc `tramapp-36f53`, Cắt triệt để Dual-Sync & Phân quyền RBAC Hoàn thiện)  
**Ngày thực hiện:** 05/10/2026  
**Trạng thái kiểm thử:** **100% PASS TOÀN BỘ HỆ THỐNG**  
- Flutter: **110 / 110** unit/widget tests PASS (`flutter test`)
- Web Admin: **30 / 30** Vitest tests PASS, **21 / 21** Next.js Static Pages Build PASS
- Cloud Functions: **5 / 5** Vitest tests PASS, TypeScript compilation clean (`tsc`)
- Security Rules: **12 / 12** Rules Unit Tests PASS (`@firebase/rules-unit-testing`)
- Dual-Sync Elimination: **0** thao tác ghi vào nút gốc (Toàn bộ đã chuyển sang `stores/{storeCode}/...`)

---

## 1. TỔNG KẾT CÁC LỖ HỔNG & LỖI ĐÃ KHẮC PHỤC

| STT | Vấn đề / Lỗ hổng kỹ thuật | Giải pháp khắc phục | Trạng thái |
| :---: | :--- | :--- | :--- |
| 1 | **Các nút gốc cũ mở tự do:** Các nút POS cũ (`users`, `tables`, `products`, `categories`, `zones`, `history`, `audit_logs`, `online_orders`, `kitchen_orders`) mở `.read/.write: auth != null`. | Đóng vĩnh viễn nút không dùng (`online_orders`, `kitchen_orders` $\rightarrow$ `false`). Các nút POS cũ chỉ cho phép người dùng có `userIndex/{auth.uid}`. | **ĐÃ KHẮC PHỤC** |
| 2 | **Ghi hai đầu song song (Dual-Sync):** Web Admin và Flutter vẫn ghi đồng thời vào cả nút gốc lẫn `stores/{mã quán}`. | Cắt triệt để toàn bộ các lệnh ghi vào nút gốc trong `data-context.tsx` và `order_repository.dart`. Xóa hoàn toàn việc lưu `password` thô trong `saveUser`. | **ĐÃ KHẮC PHỤC** |
| 3 | **Lỗ hổng bảo mật `login_attempts`:** Mở `.read/.write: true` cho mọi client, dẫn đến nguy cơ đọc trộm lịch sử thử sai mật khẩu hoặc tự reset khóa brute-force. | Khóa hoàn toàn `.read: false, .write: false` với client; chỉ Cloud Functions/Admin SDK được ghi nhận. | **ĐÃ KHẮC PHỤC** |
| 4 | **Lỗ hổng kiểm tra `audit_logs`:** Điều kiện ghi thêm `!data.exists()` chưa có schema validation. | Bổ sung `.validate` bắt buộc bản ghi có `timestamp` (số, `<= now`), `action` (chuỗi không rỗng), và `username` (chuỗi không rỗng). | **ĐÃ KHẮC PHỤC** |
| 5 | **Không khớp cấu hình đa dự án Firebase:** Flutter khai `chamcongtram` trong khi databaseURL trỏ về `tramapp-36f53`. | Thiết lập `.firebaserc` với default `tramapp-36f53`, thêm bộ kiểm tra startup check trên Flutter và Web để phát hiện cấu hình lệch. | **ĐÃ KHẮC PHỤC** |
| 6 | **Nguy cơ xóa 13 hàm của app Chấm công:** Lệnh `firebase deploy --only functions` mặc định coi hàm khác là thừa. | Đặt `codebase: "pos"` trong `firebase.json` và quy định lệnh deploy chuẩn: `firebase deploy --only functions:pos --project tramapp-36f53`. | **ĐÃ KHẮC PHỤC** |
| 7 | **Tài khoản bị khóa vẫn đăng nhập được:** Khóa tài khoản chỉ cập nhật trường `isActive` trên DB mà không khóa tài khoản Firebase Auth. | Triển khai `setStaffDisabled` cập nhật song song Auth `disabled: true`, thu hồi refresh token và cập nhật `isActive: false` trên RTDB. | **ĐÃ KHẮC PHỤC** |
| 8 | **Bảo tồn tuyệt đối 2 ứng dụng dùng chung Firebase:** Nguy cơ Security Rules khóa nhầm các nút của app Chấm công Trạm (`/cham_cong`, `/timekeeping`, `/employees`, `/shifts`) và `/kmt_customers`. | Giữ nguyên 100% cấu hình `.read: auth != null, .write: auth != null` cho tất cả các nút của hệ thống Chấm công và kmt_customers. | **BẢO ĐẢM 100%** |

---

## 2. BẢNG PHÂN LOẠI MỨC ĐỘ NGHIÊM TRỌNG (SEVERITY MATRIX)

| Mức độ | Lỗ hổng / Rủi ro | Mô tả tác động trước khi sửa | Biện pháp xử lý & Kiểm chứng |
| :--- | :--- | :--- | :--- |
| 🔴 **NGHIÊM TRỌNG**<br>(Critical) | Mật khẩu thô lưu trong RTDB & Nút gốc mở toàn bộ | Ai có Firebase Auth token đều có thể đọc toàn bộ danh sách tài khoản, mật khẩu nhân viên và dữ liệu nhà hàng. | Thêm cờ `!newData.hasChild('password')`, đóng nút gốc, tạo script di chuyển lên Firebase Auth, xóa trường password. Test rules ca 6 PASS. |
| 🔴 **NGHIÊM TRỌNG**<br>(Critical) | Hạ quyền / Khóa tài khoản Chủ quán gốc | Quản lý hoặc nhân viên có thể sửa `roleId` hoặc xóa `isRootOwner` của Chủ quán. | Áp dụng Sovereign Owner Rule trong Rules và Functions: Không ai ngoài Chủ quán gốc được sửa đổi hồ sơ Chủ quán gốc. Test rules ca 7 PASS, Functions test ca 3, 4 PASS. |
| 🟠 **CAO**<br>(High) | Nhân viên phục vụ/bếp sửa menu & bảng giá | Phục vụ hoặc bếp có thể gửi payload sửa giá món ăn hoặc tạo khuyến mãi 100%. | Phân quyền RBAC trong RTDB rules: chỉ `ROLE_OWNER` và `ROLE_MANAGER` được ghi vào `products`, `categories`, `promotions`. Test rules ca 3, 4 PASS. |
| 🟠 **CAO**<br>(High) | Đăng nhập tài khoản đã bị khóa | Khóa trên giao diện nhưng Firebase Auth token vẫn hợp lệ, nhân viên nghỉ việc vẫn đăng nhập được. | `setStaffDisabled` gọi `admin.auth().updateUser(uid, { disabled: true })` và `revokeRefreshTokens(uid)`. |
| 🟡 **TRUNG BÌNH**<br>(Medium) | Xung đột deploy Cloud Functions với app Chấm công | Deploy functions không có codebase sẽ xóa 13 functions của app Chấm công. | Cấu hình `codebase: "pos"` trong `firebase.json`, deploy với `--only functions:pos`. |
| 🟡 **TRUNG BÌNH**<br>(Medium) | Xung đột Rules với app Chấm công Trạm | Rules POS thắt chặt có thể làm gián đoạn việc nhân viên chấm công hàng ngày. | Cô lập hoàn toàn phạm vi rules POS trong `stores/{storeCode}`, bảo lưu nguyên vẹn các nút chấm công. |
| 🟢 **THẤP**<br>(Low) | Cảnh báo dependency & npm peer legacy | Cần cờ `--legacy-peer-deps` để cài đặt thư viện trên Web Admin, làm chậm CI/CD. | Nâng cấp `@types/node` lên `^22`, tái tạo `package-lock.json` chuẩn, `npm ci` chạy mượt mà trên GitHub Actions. |

---

## 3. KẾT QUẢ THỰC TẾ CÁC LỆNH KIỂM THỬ (RAW COMMAND OUTPUTS)

### 3.1. Phân hệ Flutter POS (`app_flutter/`)
- **Lệnh 1:** `flutter test`
  - **Kết quả:** `110 passed!` (100% thành công)
  - **Trọng tâm kiểm tra:**
    - `auth_test.dart` (18 tests): Sinh email ảo `{username}.{storeCode}@tram.local`, khóa brute-force 5 lần sai trong 15 phút, `toMap()` không chứa trường `password`, kiểm tra quyền hạn Sovereign Owner.
    - `report_golden_test.dart` (13 tests): Khớp từng đồng với bộ dữ liệu vàng `docs/report_golden.json`.
    - `pricing_engine_test.dart` (21 tests): Tính toán giá, áp dụng khuyến mãi, voucher.
    - `promotion_migration_test.dart` (11 tests): Schema khuyến mãi giữa Flutter và Web.
    - `printer_test.dart` (15 tests): ESC/POS raster in tiếng Việt, hàng đợi in lại.
    - `manager_hub_test.dart` & `fnb_system_test.dart` (31 tests): Ca két, gộp/tách bàn.
- **Lệnh 2:** `flutter pub get`
  - **Kết quả:** Hoàn tất không phát sinh lỗi hoặc cảnh báo xung đột.

### 3.2. Phân hệ Web Admin (`web/`)
- **Lệnh 1:** `npm test` (Vitest)
  - **Kết quả:** `30 passed (30)` qua 2 test files `test/auth.test.ts` và `test/reports.test.ts`.
- **Lệnh 2:** `npx tsc --noEmit`
  - **Kết quả:** Exit code 0, không có lỗi kiểu TypeScript nào.
- **Lệnh 3:** `npm run build` (Next.js)
  - **Kết quả:** Biên dịch tối ưu thành công 21/21 static pages trong 2.9s.

### 3.3. Phân hệ Cloud Functions (`functions/`)
- **Lệnh 1:** `npm test` (Vitest)
  - **Kết quả:** `5 passed (5)` trong `src/permissions.test.ts`.
- **Lệnh 2:** `npm run build` (`tsc`)
  - **Kết quả:** Exit code 0, tệp biên dịch đầu ra sạch sẽ tại `lib/index.js` và `lib/permissions.js`.

### 3.4. Phân hệ Firebase Security Rules (`tests/rules/`)
- **Lệnh:** `npm test` (Vitest với `@firebase/rules-unit-testing`)
- **Kết quả:** `12 passed (12)`:
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
  11. login_attempts bị khóa cả đọc lẫn ghi đối với client: PASS
  12. audit_logs phải thỏa mãn validate rule (timestamp, action, username): PASS

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
3. **Cô lập Cloud Functions:**
   - Codebase "pos" tách bạch hoàn toàn với các hàm nền của app Chấm công trong cùng project `tramapp-36f53`.

---

## 5. CÁC ĐIỂM CẦN THEO DÕI SAU PHÁT HÀNH (MONITORING & RESIDUAL RISKS)

1. **Bật gói Firebase Blaze:** Cloud Functions v2 yêu cầu project phải kích hoạt gói Blaze (trả theo mức dùng, có hạn mức miễn phí lớn). Cần bảo đảm thẻ thanh toán hợp lệ trên Google Cloud Console.
2. **Lệnh Deploy đúng cú pháp:** Luôn sử dụng `firebase deploy --only functions:pos --project tramapp-36f53`.
3. **Theo dõi việc đổi mật khẩu lần đầu của nhân viên:** Kiểm tra các tài khoản sau khi migrate có đăng nhập thành công và đổi mật khẩu theo cờ `mustChangePassword` hay không.
