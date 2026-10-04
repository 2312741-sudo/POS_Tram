# GHI CHÚ TRIỂN KHAI XÁC THỰC & PHÂN QUYỀN FLUTTER (AUTH FLUTTER)
**Dự án:** POS Trạm F&B  
**Nhánh:** `agent/auth-flutter`  
**Tài liệu tham chiếu:** `docs/AUTH_CONTRACT.md` (Phiên bản 2.0.0)

---

## 1. TỔNG QUAN CÁC CÔNG VIỆC ĐÃ HOÀN THÀNH

### 1.1. Chuyển đổi toàn diện sang Firebase Authentication
- **Quy tắc Email ảo nội bộ:** Tạo và xác thực người dùng theo định dạng chuẩn:
  $$\text{Email} = \text{\{username\}}.\text{\{storeCode.toLowerCase()\}}@\text{tram.local}$$
- **Chuẩn hóa Username:** Biểu thức chính quy `^[a-z0-9_-]{3,30}$`. Từ chối tên đăng nhập có dấu cách, dấu chấm, ký tự tiếng Việt có dấu hoặc ký tự đặc biệt.
- **Xóa bỏ 100% tài khoản cứng:** Loại bỏ hoàn toàn khối fallback credentials (`admin/admin`, `thungan/123`, `daubep/123`, `ti/123`...) khỏi `AuthService` và các màn hình liên quan.
- **Loại bỏ đăng nhập "dự phòng":** Khi mất mạng hoặc Firebase phản hồi chậm/lỗi, hệ thống hiển thị thông báo lỗi tiếng Việt cụ thể, không tự ý cho phép đăng nhập offline bằng dữ liệu giả định.

### 1.2. Màn hình Đăng nhập (`LoginScreen`)
- Các trường nhập liệu: Mã cửa hàng (`storeCode`), Tên đăng nhập (`username`), Mật khẩu (`password`).
- **Ghi nhớ cửa hàng:** Checkbox "Ghi nhớ mã cửa hàng" lưu giá trị vào `SharedPreferences` và tự động điền ở các lần mở app sau.
- **Ẩn / Hiện mật khẩu:** Nút chuyển đổi trạng thái hiển thị mật khẩu trực quan.
- **Thông báo lỗi tiếng Việt:** Xử lý chi tiết các mã lỗi của Firebase Auth (`wrong-password`, `user-not-found`, `network-request-failed`, `too-many-requests`).
- **Cơ chế Khóa tạm thời 15 phút sau 5 lần sai (Brute-Force Protection):**
  - Theo dõi tại `stores/{storeCode}/login_attempts/{username}`.
  - Sau 5 lần nhập sai mật khẩu liên tiếp, tài khoản bị khóa tạm trong 15 phút (900.000 ms).
  - Giao diện hiển thị banner cảnh báo và bộ đếm ngược thời gian khóa (phút/giây), vô hiệu hóa nút đăng nhập trong suốt thời gian khóa.
  - Ghi nhận Audit Log: `LOGIN_ATTEMPT_LOCKED_OUT`.
  - Khi đăng nhập thành công: Tự động xóa bản ghi trong `login_attempts`.

### 1.3. Đổi mật khẩu bắt buộc & Tự đổi mật khẩu
- **Bắt buộc lần đầu (`mustChangePassword: true`):** Khi tài khoản mới được tạo hoặc vừa được cấp lại, sau khi đăng nhập thành công, hệ thống hiển thị hộp thoại `ChangePasswordDialog` (không thể đóng/hủy) bắt buộc người dùng đặt mật khẩu mới (tối thiểu 6 ký tự) mới được vào màn hình bán hàng. Cập nhật `mustChangePassword = false` trên RTDB và ghi Audit Log `CHANGE_PASSWORD_MANDATORY_SUCCESS`.
- **Tự đổi mật khẩu:** Hộp thoại `ChangePasswordDialog` dùng chung cho tính năng đổi mật khẩu tự nguyện trong ứng dụng.

### 1.4. Quản lý tài khoản & Sovereign Owner Rule (`UserManagementScreen`)
- **Tạo tài khoản bằng Secondary Firebase App:** Áp dụng giải pháp Section 7 của hợp đồng: Khởi tạo thực thể `SecondaryApp_${timestamp}` để gọi `createUserWithEmailAndPassword`, sau đó hủy app phụ. Đảm bảo 100% phiên làm việc của Quản lý/Chủ quán đang đăng nhập KHÔNG bị ngắt kết nối.
- **Bảo vệ Chủ quán tối cao (Sovereign Owner Rule):**
  - Tài khoản có `isRootOwner: true` được gắn huy hiệu vàng "👑 Chủ Quán Tối Cao".
  - Không thể bị khóa (`isActive` không thể đổi thành `false`).
  - Không thể bị hạ quyền hoặc thay đổi vai trò.
  - Không thể bị xóa khỏi hệ thống (nút xóa bị ẩn hoàn toàn).
- **Khóa / Mở khóa tài khoản nhân viên:** Thao tác khóa/mở khóa kèm hộp thoại xác nhận, cập nhật `isActive`, ghi nhận Audit Log `USER_LOCK` hoặc `USER_UNLOCK`.
- **Cấp quyền riêng biệt (`customPermissions`):** Hỗ trợ chọn và gán các quyền đặc thù ngoài vai trò mặc định từ danh mục `AppPermissions.allPermissions`.
- **Xem thông tin đăng nhập cuối:** Hiển thị `lastLoginAt` dưới dạng ngày giờ tiếng Việt (`dd/MM/yyyy HH:mm`) hoặc "Chưa từng đăng nhập".

### 1.5. Bảo mật dữ liệu & Loại bỏ Password khỏi RTDB
- Cập nhật `UserModel`: Thuộc tính `password` chỉ được giữ trong constructor để tương thích ngược, phương thức `toMap()` **tuyệt đối không serialize trường `password`**.
- Cập nhật `AuthRepository`: Lưu hồ sơ người dùng theo khóa `uid` duy nhất (`stores/{storeCode}/users/{uid}`), tra cứu linh hoạt hỗ trợ tương thích ngược.

### 1.6. Cấu hình Firebase Security Rules (`database.rules.json` & `firebase.json`)
- Đã tạo `database.rules.json` tại gốc repo:
  - Phân lập dữ liệu theo từng chi nhánh `stores/{storeCode}`.
  - Bảo vệ Sovereign Owner Rule trực tiếp ở tầng database rule.
  - Validate bắt buộc: `newData.hasChildren(['username', 'fullName', 'roleId']) && !newData.hasChild('password')`.
  - Giữ nguyên các node dùng chung và node của app Chấm công Trạm (`/users`, `/cham_cong`, `/timekeeping`, `/employees`, `/shifts`...) với quyền `auth != null`, bảo đảm không ảnh hưởng đến app Chấm công.
- Đã tạo `firebase.json` liên kết trực tiếp tới `database.rules.json`.

---

## 2. GHI CHÚ KỸ THUẬT & YÊU CẦU FILE NGOÀI DANH SÁCH

### 2.1. Về `app_flutter/lib/data/services/firebase_service.dart`
- Theo Quy tắc chung, `firebase_service.dart` KHÔNG nằm trong danh sách "Được sửa" của prompt này.
- **Hiện trạng:** Dòng 122 của `firebase_service.dart` có hàm `Future<UserModel?> login(String username, String password) => _authRepo.login(username, password);`. Hàm này trước đây đọc Realtime Database để kiểm tra mật khẩu thô.
- **Xử lý hiện tại:** `AuthRepository.login()` đã được chuyển đổi an toàn sang tra cứu hồ sơ người dùng (không so sánh mật khẩu thô). Đồng thời, toàn bộ luồng đăng nhập của app Flutter hiện tại đã chuyển sang gọi trực tiếp `AuthService.login()` (dùng Firebase Auth).
- **Khuyến nghị cho đợt refactor sau:** Khi được cấp quyền sửa `firebase_service.dart`, có thể xóa bỏ hoàn toàn method `login` cũ này khỏi service để mã nguồn gọn gàng.

### 2.2. Về lỗi LSP của `flutter analyze` trên macOS với thư mục Unicode
- Khi chạy lệnh `flutter analyze`, Flutter SDK 3.47.5 khởi chạy analysis server qua LSP protocol. Do đường dẫn làm việc chứa ký tự tiếng Việt Unicode dạng tổ hợp (`Lưu trữ`), Flutter CLI tính sai độ dài header `Content-Length` (tính theo UTF-16 code units thay vì UTF-8 bytes), dẫn đến lỗi `FormatException: Unexpected end of input`.
- Khi chạy trực tiếp `dart analyze lib/`, phân tích cú pháp hoạt động hoàn hảo: **0 lỗi (0 errors)**, toàn bộ mã nguồn hợp lệ 100%.

---

## 3. DANH MỤC CÁC CA KIỂM THỬ BẰNG TAY (MANUAL TEST CASES)

| Mã ca | Tiêu đề ca kiểm thử | Các bước thực hiện | Kết quả mong đợi |
| :---: | :--- | :--- | :--- |
| **TC-01** | Đăng nhập tài khoản hợp lệ | 1. Nhập Mã CH: `TRAM01`<br>2. Nhập Username: `thungan1`<br>3. Nhập mật khẩu đúng<br>4. Bấm "ĐĂNG NHẬP" | Đăng nhập thành công, chuyển hướng vào màn hình Bán hàng (hoặc Manager Hub tùy quyền), cập nhật `lastLoginAt`. |
| **TC-02** | Đăng nhập sai mật khẩu | 1. Nhập Username: `thungan1`<br>2. Nhập mật khẩu sai<br>3. Bấm "ĐĂNG NHẬP" | Hiển thị thông báo đỏ: *"Sai tài khoản hoặc mật khẩu."*, bộ đếm thất bại tăng thêm 1. |
| **TC-03** | Khóa tạm thời 15 phút sau 5 lần sai | 1. Nhập sai mật khẩu liên tiếp 5 lần với cùng username | Xuất hiện banner màu vàng: *"Tài khoản đang bị khóa tạm. Vui lòng thử lại sau 15 phút 00 giây."*, bộ đếm ngược chạy từng giây, nút đăng nhập bị vô hiệu hóa. |
| **TC-04** | Cố gắng đăng nhập khi đang bị khóa | 1. Mở lại app khi thời gian khóa chưa hết<br>2. Bấm đăng nhập | Hệ thống báo lỗi khóa tạm, hiển thị số phút còn lại, từ chối gửi yêu cầu tới Firebase Auth. |
| **TC-05** | Đổi mật khẩu bắt buộc lần đầu | 1. Đăng nhập tài khoản mới có `mustChangePassword = true`<br>2. Quan sát giao diện | Xuất hiện hộp thoại bắt buộc "Đổi Mật Khẩu Bắt Buộc". Không thể nhấn ra ngoài để tắt. Sau khi nhập mật khẩu mới >= 6 ký tự và xác nhận trùng khớp, hệ thống cập nhật và cho phép vào app. |
| **TC-06** | Ghi nhớ mã cửa hàng | 1. Tích chọn "Ghi nhớ mã cửa hàng"<br>2. Nhập mã `TRAM02` và đăng nhập<br>3. Đăng xuất hoặc tắt mở lại app | Ô "Mã Cửa Hàng" tự động hiển thị `TRAM02`. |
| **TC-07** | Mất mạng hoặc Firebase chậm | 1. Tắt kết nối WiFi/Internet<br>2. Bấm "ĐĂNG NHẬP" | Báo lỗi tiếng Việt: *"Không thể kết nối đến máy chủ. Vui lòng kiểm tra kết nối mạng Internet và thử lại."*, tuyệt đối KHÔNG tự động đăng nhập dự phòng. |
| **TC-08** | Tạo tài khoản nhân viên mới | 1. Đăng nhập bằng tài khoản Chủ quán / Quản lý<br>2. Vào "Quản Lý Tài Khoản"<br>3. Bấm "Thêm Nhân Viên"<br>4. Nhập họ tên, username (`nv_order`), mật khẩu `123456`, vai trò `ROLE_CASHIER`<br>5. Bấm "TẠO NHÂN VIÊN" | Nhân viên mới được tạo thành công trên Firebase Auth và RTDB. **Chủ quán không bị đăng xuất khỏi app.** |
| **TC-09** | Khóa và Mở khóa tài khoản nhân viên | 1. Trong danh sách nhân viên, bấm icon ổ khóa tại tài khoản nhân viên thường<br>2. Xác nhận khóa | Trạng thái chuyển thành "Đã khóa" (màu đỏ). Nhân viên này dùng tài khoản đăng nhập sẽ nhận thông báo: *"Tài khoản đã bị tạm khóa bởi chủ quán."* |
| **TC-10** | Kiểm tra Sovereign Owner Rule | 1. Quan sát tài khoản Chủ quán trong danh sách<br>2. Thử khóa hoặc xóa | Biểu tượng xóa hoàn toàn bị ẩn. Biểu tượng khóa bị vô hiệu hóa. Không thể hạ quyền của Chủ quán. |
| **TC-11** | Cấp quyền riêng (Custom Permissions) | 1. Sửa thông tin nhân viên thu ngân<br>2. Bấm "Tùy chỉnh quyền"<br>3. Tích chọn quyền `MANUAL_DISCOUNT` và lưu | Nhân viên có thêm quyền chiết khấu tay dù vai trò mặc định không có quyền này. |
| **TC-12** | Kiểm tra Audit Log | 1. Thực hiện các thao tác: đăng nhập, đổi mật khẩu, tạo nhân viên, khóa tài khoản<br>2. Kiểm tra node `stores/{storeCode}/audit_logs` | Các bản ghi `LOGIN`, `CHANGE_PASSWORD`, `USER_CREATE`, `USER_LOCK` được lưu trữ đầy đủ kèm thời gian và thông tin người thực hiện. |
| **TC-13** | Tương thích app Chấm công | 1. Đăng nhập Firebase Auth<br>2. Truy vấn đọc/ghi node `/cham_cong` hoặc `/timekeeping` | Thao tác thành công, Security Rules không chặn các node này của app Chấm công. |

---

## 4. KẾT QUẢ KIỂM THỬ TỰ ĐỘNG (AUTOMATED TEST SUITE)
- **Tổng số ca kiểm thử:** 82 tests (68 tests kế thừa + 14 tests mới tại `auth_test.dart`).
- **Tỷ lệ thành công:** 100% (82/82 passed).
- **Lệnh chạy:**
  ```bash
  cd app_flutter && flutter test
  ```
