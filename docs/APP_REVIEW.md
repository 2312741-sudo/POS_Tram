# Ghi chú cho Apple App Review — POS Trạm

## 1. Xóa tài khoản trong ứng dụng (Guideline 5.1.1(v))

**Đường dẫn trong ứng dụng**

- **Quản lý / Chủ quán:** Trung tâm quản lý (Manager Hub) → nút menu ⋮ (góc trên bên phải) → **Xóa tài khoản của tôi**.
- **Thu ngân / Phục vụ:** Màn hình Bàn → nút **Menu chức năng** (tooltip "Menu chức năng") → **Xóa tài khoản của tôi** (nằm ngay dưới mục Đổi Mật Khẩu).

**Luồng**

1. Hộp thoại giải thích hậu quả: mất quyền truy cập tại mọi chi nhánh; hồ sơ cá nhân bị xóa; lịch sử bán hàng và nhật ký được giữ lại nhưng ẩn danh; không thể hoàn tác.
2. Người dùng gõ `XOA` để xác nhận. Nút **Xóa tài khoản** chỉ bật khi nội dung khớp.
3. Ứng dụng gọi Cloud Function `deleteMyAccount` (vùng asia-southeast1). Máy chủ:
   - ẩn danh hóa hồ sơ tại từng chi nhánh (giữ uid, vai trò và mốc thời gian; xóa họ tên, SĐT, email, ảnh, quyền riêng, liên kết Chấm Công);
   - gỡ quyền truy cập và ghi nhật ký `DELETE_OWN_ACCOUNT` (chỉ chứa uid);
   - xóa tài khoản đăng nhập Firebase Auth.
4. Thành công: ứng dụng đăng xuất và quay về màn hình đăng nhập với thông báo "Tài khoản đã được xóa."

**Ngoại lệ: Chủ quán gốc**

Chủ quán gốc (root owner) của một chi nhánh không tự xóa được tài khoản trong ứng dụng. Lý do: tài khoản gốc là điểm kiểm soát duy nhất của chuỗi cửa hàng; nếu xóa, chi nhánh có thể mất hoàn toàn quyền quản trị dữ liệu. Khi người dùng thử, ứng dụng hiển thị:

> Chủ quán gốc không thể tự xóa tài khoản. Vui lòng liên hệ đơn vị vận hành để chuyển quyền trước khi xóa.

Đơn vị vận hành sẽ chuyển quyền chủ quán gốc sang người khác (hoặc xác minh yêu cầu) trước khi tài khoản được xóa. Đây là ngoại lệ có chủ đích và được giải thích ngay trong ứng dụng.

**Lưu ý cho người duyệt**

- Tài khoản nhân viên được tạo qua "Đăng nhập bằng Chấm Công Trạm" cũng xóa được theo cùng luồng.
- Dữ liệu bán hàng không bị xóa cứng (yêu cầu kế toán và pháp lý); chỉ thông tin nhận dạng cá nhân bị xóa.

## 2. Trạng thái còn mở

- Vai trò **Bếp** (màn hình Bếp `features/kitchen/`) chưa có lối vào "Xóa tài khoản của tôi". Cần bổ sung trước khi nộp nếu tài khoản bếp có thể tự tạo/đăng nhập.
