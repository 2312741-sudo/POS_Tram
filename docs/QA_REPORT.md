# BÁO CÁO KIỂM THỬ TOÀN DIỆN & RÀ SOÁT BẢO MẬT (QA & SECURITY AUDIT REPORT)
**Dự án:** POS Trạm (Hệ thống Điểm bán lẻ F&B Đa nền tảng)  
**Nhánh tích hợp:** `integration/v1`  
**Ngày thực hiện:** 05/10/2026  
**Trạng thái kiểm thử:** **100% PASS** (110/110 Flutter Tests, 30/30 Web Vitest Tests, 21/21 Web Static Pages Build)

---

## 1. TỔNG QUAN TÍCH HỢP HỆ THỐNG (INTEGRATION OVERVIEW)

Toàn bộ 5 nhánh phát triển độc lập của Pha 1 đã được hợp nhất thành công vào nhánh `integration/v1`:
1. **`agent/auth-flutter` (Agent 1):** Chuyển đổi toàn diện sang Firebase Authentication ({username}.{storeCode}@tram.local), loại bỏ hoàn toàn tài khoản cứng trong mã nguồn, màn hình đăng nhập bảo mật có khóa tạm 5 lần sai, đối thoại đổi mật khẩu lần đầu bắt buộc và tự đổi mật khẩu, phân hệ quản trị tài khoản nhân viên đa chi nhánh, bảo vệ bất khả xâm phạm cho Chủ Quán (`isRootOwner`).
2. **`agent/auth-web` (Agent 2):** Xác thực Firebase Auth đồng bộ trên Web Admin, quản trị người dùng phân quyền chi tiết, chặn Sidebar và chuyển hướng route theo vai trò, quản lý tài khoản qua Secondary Firebase App Instance không làm gián đoạn phiên làm việc của quản lý.
3. **`agent/printer` (Agent 5):** Thư viện Bluetooth hiện đại `print_bluetooth_thermal` tương thích Android 12+ (không cần quyền vị trí) và iOS; hỗ trợ chuẩn khổ giấy 58mm và 80mm; cơ chế in đồ họa Raster Image cho tiếng Việt có dấu; dịch vụ hàng đợi in lại `PrintQueueService` bảo vệ hóa đơn khi mất kết nối.
4. **`agent/report-flutter` (Agent 3):** Động cơ tính toán tài chính thuần Dart độc lập framework (`ReportCalculator`); 12 mẫu báo cáo quản trị; đối soát 100% khớp chuẩn dữ liệu vàng `docs/report_golden.json`; xuất Excel và PDF chuyên nghiệp chuẩn tiếng Việt.
5. **`agent/report-web` (Agent 4):** Động cơ báo cáo pure TypeScript độc lập React (`lib/reports.ts`); giao diện báo cáo chuyên sâu tại Dashboard; hỗ trợ xem toàn chuỗi (ALL stores) hoặc chi nhánh; bổ sung quản lý giá vốn `costPrice` cho sản phẩm; xuất file kế toán tiêu chuẩn.

---

## 2. KẾT QUẢ KIỂM THỬ TỰ ĐỘNG (AUTOMATED TEST RESULTS)

### 2.1. Phân hệ Di động (Flutter POS)
- **Công cụ chạy:** `flutter test` & `dart analyze --no-fatal-warnings`
- **Kết quả:** **110 / 110 tests PASS (100%)**
- **Thời gian chạy:** 1.8 giây
- **Chi tiết các bộ test:**
  - `auth_test.dart` (18 tests): Chuẩn hóa email ảo, cơ chế khóa tạm 5 lần sai, kiểm tra quyền và bảo vệ tài khoản Chủ Quán `isRootOwner`.
  - `report_golden_test.dart` (13 tests): Kiểm thử đối soát 13 chỉ tiêu tài chính với `docs/report_golden.json`. Kết quả khớp từng đồng:
    - Doanh thu gộp: `1.045.000 đ`
    - Tổng giảm giá: `100.000 đ`
    - Doanh thu thuần: `945.000 đ`
    - Doanh thu sau hoàn trả: `900.000 đ`
    - Thuế VAT: `72.000 đ`
    - Lợi nhuận gộp: `540.000 đ` (Tỷ suất lãi gộp: `60.0%`)
  - `printer_test.dart` (15 tests): Kiểm thử sinh byte ESC/POS 58mm/80mm, định dạng phiếu bếp, thuật toán chuyển ảnh raster bitmap hỗ trợ tiếng Việt có dấu, mô hình hàng đợi `PrintQueueService` tự lưu và thử lại đơn in thất bại.
  - `pricing_engine_test.dart` (21 tests): Công cụ tính giá, áp dụng khuyến mãi, phân bổ giảm giá hóa đơn theo dòng sản phẩm.
  - `promotion_migration_test.dart` (11 tests): Khả năng tương thích ngược và chuyển dịch schema khuyến mãi giữa Web và POS.
  - `manager_hub_test.dart` (14 tests): Chuyển đổi chi nhánh và vòng đời quản lý ca két.
  - `fnb_system_test.dart` (17 tests): Nghiệp vụ bàn, đơn hàng, tách/gộp bàn.
  - `widget_test.dart` (1 test): Smoke test ứng dụng.

### 2.2. Phân hệ Quản trị Web (Next.js Admin)
- **Công cụ chạy:** `npx vitest run` & `next build --webpack`
- **Kết quả Test:** **30 / 30 tests PASS (100%)**
- **Kết quả Build:** **21 / 21 Static Pages generated thành công (0 lỗi)**
- **Chi tiết các bộ test:**
  - `test/auth.test.ts` (17 tests): Chuẩn hóa username, quy tắc email định danh chi nhánh, phân quyền trang theo ma trận vai trò (`owner`, `manager`, `cashier`, `kitchen`).
  - `test/reports.test.ts` (13 tests): Kiểm thử đối soát động cơ pure TypeScript với `docs/report_golden.json`, tính toán doanh thu, nhóm hàng, món ăn, nhân viên, khung giờ nhiệt 24h, chênh lệch ca két, khử trùng lặp đơn hàng `deduplicateBills`.

---

## 3. RÀ SOÁT ĐỒNG BỘ SỐ LIỆU (FLUTTER VS WEB CONSISTENCY)

| Chỉ số / Báo cáo | Quy tắc tính toán | Flutter POS | Web Admin | Đánh giá |
| :--- | :--- | :--- | :--- | :--- |
| **Múi giờ hạch toán** | Múi giờ chuẩn Việt Nam (UTC+7) | `DateTime.toUtc().add(Duration(hours: 7))` | `new Date(ts + 7 * 3600 * 1000)` | **Đồng bộ 100%** |
| **Doanh thu gộp (Gross)** | Tổng tiền món chưa trừ giảm giá | `sum(price * quantity)` | `sum(price * quantity)` | **Đồng nhất** |
| **Giảm giá (Discount)** | Giảm giá món + Giảm giá đơn hàng | `itemDiscounts + billDiscounts` | `itemDiscounts + billDiscounts` | **Đồng nhất** |
| **Doanh thu thuần (Net)** | Doanh thu sau chiết khấu trước VAT | `gross - discounts` | `gross - discounts` | **Đồng nhất** |
| **Đơn hủy (Cancelled)** | Đơn trạng thái CANCELLED | Không tính vào doanh thu bán hàng; tính riêng vào chỉ số tổn thất | Không tính vào doanh thu bán hàng; tính riêng vào chỉ số tổn thất | **Đồng nhất** |
| **Khử trùng lặp đơn** | Khử trùng lặp theo `id` | Giữ bản ghi mới nhất theo timestamp/status | Giữ bản ghi mới nhất theo timestamp/status | **Đồng nhất** |
| **Giá vốn & Lãi gộp** | `costPrice` của sản phẩm | Món chưa có giá vốn: hiển thị "Chưa nhập giá vốn", không tự tính bằng 0 | Món chưa có giá vốn: hiển thị "Chưa nhập giá vốn", không tự tính bằng 0 | **Đồng nhất** |
| **Định dạng tiền tệ** | Tiền đồng Việt Nam | `1.000.000 đ` (Dấu chấm hàng nghìn) | `1.000.000 đ` (Dấu chấm hàng nghìn) | **Đồng nhất** |

---

## 4. RÀ SOÁT BẢO MẬT & FIREBASE RULES (`database.rules.json`)

Chúng tôi đã thiết kế và thẩm định tệp `database.rules.json` tại gốc repo:
1. **Cô lập dữ liệu theo Chi nhánh (`stores/{storeCode}`):**
   - Người dùng chỉ có quyền đọc/ghi dữ liệu trong cửa hàng mà họ được phân quyền (`stores/{storeCode}/users/{auth.uid}.exists()`).
   - Ngăn chặn triệt để tình trạng nhân viên quán này đọc trộm số liệu doanh thu của quán khác.
2. **Bảo vệ tuyệt đối tài khoản Chủ Quán (`isRootOwner`):**
   - Quy tắc quy định `isRootOwner` không thể bị chỉnh sửa, hạ quyền, khóa hoặc xóa bởi bất kỳ tài khoản nào khác (kể cả tài khoản có vai trò `owner`).
3. **Chống lộ lọt mật khẩu:**
   - Trường `.validate` cấm tuyệt đối ghi nhận trường `password` vào cơ sở dữ liệu (`!newData.hasChild('password')`). Mật khẩu chỉ được quản lý an toàn qua Firebase Auth.
4. **Phòng chống tấn công dò mật khẩu (Brute-force Protection):**
   - Cơ chế theo dõi số lần đăng nhập thất bại tại `stores/{storeCode}/login_attempts/{username}`. Sau 5 lần nhập sai liên tiếp, hệ thống khóa đăng nhập tạm thời trong 15 phút.
5. **Tương thích 100% với ứng dụng "Chấm công Trạm":**
   - Các nhánh dữ liệu độc lập của hệ thống chấm công: `/cham_cong`, `/timekeeping`, `/employees`, `/shifts` được thiết lập quyền riêng biệt, hoàn toàn không bị ảnh hưởng hay phong tỏa bởi các quy tắc của POS.

---

## 5. HƯỚNG DẪN KIỂM THỬ THỦ CÔNG (MANUAL TEST CASES)

### 5.1. Ca kiểm thử Đăng nhập & Quản lý tài khoản
- **TC-AUTH-01 (Đăng nhập đúng):** Nhập mã CH `TRAM01`, tên `admin`, mật khẩu hợp lệ -> Đăng nhập thành công, chuyển hướng vào màn hình Bàn / Dashboard.
- **TC-AUTH-02 (Khóa tạm sau 5 lần sai):** Nhập sai mật khẩu 5 lần liên tiếp -> Hệ thống hiển thị cảnh báo đỏ tiếng Việt và khóa tài khoản trong 15 phút.
- **TC-AUTH-03 (Đổi mật khẩu lần đầu):** Đăng nhập tài khoản nhân viên mới được tạo có cờ `mustChangePassword` -> Hệ thống tự động bật hộp thoại bắt buộc đổi mật khẩu trước khi cho phép sử dụng.
- **TC-AUTH-04 (Bảo vệ Chủ quán):** Đăng nhập bằng tài khoản Quản lý, vào trang quản lý người dùng -> Nút Khóa / Xóa đối với tài khoản Chủ quán (`isRootOwner`) bị vô hiệu hóa hoặc ẩn.

### 5.2. Ca kiểm thử In nhiệt Bluetooth
- **TC-PRINT-01 (Quét thiết bị):** Mở màn hình "Cài Đặt Máy In" trong Drawer -> Hệ thống xin quyền Bluetooth (Nearby Devices trên Android 12+), sau khi cấp quyền thì hiển thị danh sách máy in đã ghép đôi.
- **TC-PRINT-02 (Chọn khổ giấy 58mm/80mm):** Chọn khổ 58mm -> Đường gạch phân cách căn 32 cột; chọn khổ 80mm -> Đường gạch phân cách căn 48 cột.
- **TC-PRINT-03 (In tiếng Việt có dấu):** Nhấn in thử -> Phiếu in ra thể hiện đúng chữ tiếng Việt sắc nét, không bị lỗi font nhờ chế độ Raster Image.
- **TC-PRINT-04 (Hàng đợi in khi mất kết nối):** Tắt nguồn máy in, bấm thanh toán hóa đơn -> Hóa đơn không bị mất, hiển thị trong "Hàng Đợi In Lại (Print Queue)" với trạng thái chờ in; bật nguồn máy in và bấm "In lại" -> Hóa đơn được in thành công.

### 5.3. Ca kiểm thử Báo cáo & Đối soát
- **TC-REP-01 (Đối soát tổng quan):** Mở Trung tâm báo cáo trên Flutter POS và Web Admin cùng một mốc thời gian -> Doanh thu gộp, giảm giá, doanh thu thuần, VAT và số đơn khớp chính xác 100%.
- **TC-REP-02 (Xuất Excel & PDF):** Nhấn nút xuất file Báo cáo cuối ngày (Z-Report) -> Tệp Excel sinh ra với tên chuẩn `BC_CUOINGAY_Z_TRAM01_[Date]_[Time].xlsx` có đầy đủ thông tin cửa hàng và định dạng kế toán.

---

## 6. RỦI RO CÒN LẠI & KHUYẾN NGHỊ VẬN HÀNH (REMAINING RISKS & ADVICE)

1. **Triển khai Firebase Security Rules:**
   - Tệp `database.rules.json` đã được tạo hoàn chỉnh trong mã nguồn. Trước khi áp dụng lên Production, vui lòng kiểm tra trên project Firebase staging để xác nhận không xung đột với các logic ghi dữ liệu cũ.
2. **Kế hoạch di chuyển tài khoản cũ (Legacy Users Migration):**
   - Nếu cơ sở dữ liệu hiện tại đang chứa người dùng lưu mật khẩu thô trong RTDB, hãy chạy script tạo tài khoản Firebase Auth tương ứng và gán cờ `mustChangePassword: true`, sau đó tiến hành xóa bỏ trường mật khẩu cũ để đảm bảo an toàn tuyệt đối.
3. **Cấp quyền Bluetooth trên thiết bị iOS:**
   - Cần đảm bảo thiết bị iOS đã được ghép đôi với máy in Bluetooth trước trong phần Cài đặt Bluetooth của hệ điều hành iOS (hoặc sử dụng máy in hỗ trợ Bluetooth Low Energy).
