# Ghi Chú Dọn Dẹp Mã Nguồn & Vị Trí Dữ Liệu Cứng (docs/NOTES_misc.md)

## 1. Các việc đã thực hiện
- Đã xóa toàn bộ danh sách 4 tài khoản mẫu cứng (`admin/admin`, `thungan/123`, `phucvu/123`, `daubep/123`) trong `permissions_matrix_screen.dart`.
- Đã bổ sung giao diện trạng thái rỗng (Empty State) hiển thị thông báo rõ ràng khi hệ thống chưa có tài khoản nhân viên hoặc không tìm thấy kết quả tìm kiếm.
- Đã cập nhật `@types/node` lên `^22` trong `web/package.json` và tạo lại `package-lock.json` giúp lệnh `npm ci` chạy sạch sẽ 100% không cần cờ `--legacy-peer-deps`.
- Đã thiết lập `.github/workflows/ci.yml` kiểm thử tự động cho cả 2 nền tảng Flutter POS và Web Admin trên GitHub Actions.

## 2. Rà soát các vị trí còn liên quan đến mật khẩu và tài khoản cũ trong codebase
- `web/lib/data-context.tsx`: Dòng 129, 239, 550, 1587, 1616 còn khai báo trường `password` tùy chọn để tương thích với dữ liệu RTDB cũ trước khi chạy script chuyển đổi (migration). Cần dọn dẹp khi chuyển đổi hoàn tất.
- `app_flutter/lib/data/models/user_model.dart`: Dòng 47, 53, 91 khai báo `password = ''` làm tham số tùy chọn không bắt buộc để tránh phá vỡ các nơi gọi cũ. Hàm `toMap()` đã loại bỏ hoàn toàn việc lưu `password` lên Firebase RTDB.
- `app_flutter/lib/features/permissions/permissions_matrix_screen.dart`: Dòng 97 gọi `password: user.password` khi copy `UserModel` (tham số tùy chọn).
- Mọi chuỗi mật khẩu gán cứng như `admin`, `123`, `123456` đã được gỡ bỏ khỏi toàn bộ màn hình nghiệp vụ và chỉ còn xuất hiện trong các form nhập liệu mật khẩu của người dùng thật hoặc unit test đối soát.
