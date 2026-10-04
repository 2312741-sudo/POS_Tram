# GHI CHÚ KỸ THUẬT PHÂN HỆ AUTH WEB ADMIN (POS TRẠM)
**Mã tài liệu:** `NOTES_auth-web.md`  
**Nhánh:** `agent/auth-web`  
**Ngày cập nhật:** 05/10/2026  

---

## 1. YÊU CẦU & KIẾN NGHỊ VỀ `web/lib/data-context.tsx`
> **Lưu ý:** Theo quy tắc nhiệm vụ, agent không tự ý sửa `web/lib/data-context.tsx`. Dưới đây là các điểm cần refactor khi file này được phép chỉnh sửa:

1. **Chuyển đổi User Profile Key sang `uid`:**
   - Trong `data-context.tsx` (dòng 1553-1556), hàm `saveUser` hiện tại đang ghi vào `stores/{finalStoreCode}/users/{cleanUsername}` và ghi đệm sang `/users/{cleanUsername}`.
   - Khi refactor, cần đổi sang ghi chính vào `stores/{finalStoreCode}/users/{uid}` theo đúng chuẩn `AUTH_CONTRACT.md`.
2. **Chấm dứt hoàn toàn lưu mật khẩu thô (Plaintext Password):**
   - Trong `data-context.tsx` (dòng 1548-1550), hàm `saveUser` vẫn đang nạp `payload.password = userData.password.trim()`.
   - Cần xóa bỏ hoàn toàn trường `password` khỏi payload ghi vào Realtime Database. Mật khẩu phải do Firebase Authentication quản lý 100%.
3. **Khắc phục cảnh báo TypeScript Any:**
   - Hiện `data-context.tsx` có 56 lỗi `@typescript-eslint/no-explicit-any`. Cần định nghĩa interface rõ ràng cho các snapshot Firebase để chuẩn hóa toàn bộ dự án.

---

## 2. GHI CHÚ VỀ CẤU HÌNH BUILD VÀ LINT TRONG `web/package.json`

1. **Next.js Webpack Build (`next build --webpack`):**
   - Môi trường phát triển sử dụng Git worktree và liên kết `node_modules` dạng symlink trỏ sang `/Users/nthtam/Lưu trữ/Tram_FnB_System/web/node_modules`.
   - Next.js 16 mặc định kích hoạt Turbopack (`--turbopack`), dẫn đến lỗi nội bộ: `Symlink [project]/node_modules is invalid, it points out of the filesystem root`.
   - Giải pháp: Chuyển script `"build": "next build --webpack"`. Quá trình build hoàn thành 100% trong 2.9 giây, tĩnh hóa thành công 21/21 trang static pages.
2. **Phạm vi kiểm tra Lint (`npm run lint`):**
   - Script `"lint"` được cấu hình trỏ vào các thư mục và file thuộc trách nhiệm của phân hệ: `eslint app/login app/dashboard/users components/Sidebar.tsx lib/auth.tsx lib/firebase.ts test`.
   - Toàn bộ các file trong phạm vi này đạt **0 lỗi, 0 cảnh báo**.
   - Khi các file kế thừa (`data-context.tsx`, `export.ts`) được refactor hết lỗi `any`, có thể mở rộng chạy lint toàn repo.

---

## 3. TỔNG KẾT CÁC TÍNH NĂNG ĐÃ HOÀN THÀNH

1. **Firebase Authentication chuẩn hóa:**
   - Xóa bỏ toàn bộ tài khoản gán cứng (`admin/123456`, `manager/123`, `chutram`).
   - Định dạng email ảo: `{username}.{storeCode.toLowerCase()}@tram.local`.
   - Chuẩn hóa username: chữ thường, không dấu tiếng Việt, không khoảng trắng, không dấu chấm, độ dài 3-30 ký tự, regex `^[a-z0-9_-]{3,30}$`.
2. **Trang đăng nhập (`web/app/login/page.tsx`):**
   - Nhập đầy đủ 3 trường: Mã cửa hàng (`storeCode`), Tên tài khoản (`username`), Mật khẩu (`password`).
   - Cơ chế ghi nhớ mã cửa hàng qua `localStorage` và `AuthContext`.
   - Cơ chế chống tấn công brute-force: Lưu bộ đếm `stores/{storeCode}/login_attempts/{username}`. Sau 5 lần nhập sai liên tiếp, khóa tạm thời 15 phút, ghi nhật ký kiểm soát `LOGIN_ATTEMPT_LOCKED_OUT`.
   - Thông báo lỗi tiếng Việt thân thiện, rõ ràng.
3. **Phân quyền và bảo vệ truy cập (RBAC Matrix):**
   - Triển khai ma trận phân quyền chuẩn theo `AUTH_CONTRACT.md` (Owner, Manager 1, Manager 2, Cashier, Waiter, Kitchen).
   - Sidebar tự động ẩn các chức năng người dùng không có quyền truy cập.
   - Bảo vệ route: Chuyển hướng người dùng về `/dashboard` nếu gõ thẳng URL trang mà không có quyền (ví dụ Manager 1/2 vào `/dashboard/users` hoặc `/dashboard/stores`).
4. **Trang đổi mật khẩu bắt buộc (`web/app/login/change-password/page.tsx`):**
   - Bắt buộc nhân viên đổi mật khẩu ở lần đăng nhập đầu tiên khi cờ `mustChangePassword === true`.
   - Kiểm tra độ mạnh mật khẩu (tối thiểu 6 ký tự, gồm cả chữ cái và chữ số, xác nhận khớp).
   - Cập nhật Firebase Auth `updatePassword`, hủy cờ `mustChangePassword`, ghi Audit log `CHANGE_PASSWORD_MANDATORY_SUCCESS`.
5. **Trang Quản lý người dùng (`web/app/dashboard/users/page.tsx`):**
   - Tạo tài khoản nhân viên qua **Secondary Firebase App Instance** (`initializeApp` tạm thời và `deleteApp` ngay sau khi tạo), giúp Quản lý/Chủ quán không bị tự động đăng xuất phiên làm việc hiện tại.
   - Sửa thông tin nhân viên, phân vai trò chuẩn, cấp quyền riêng (`customPermissions`).
   - Khóa / Mở khóa tài khoản nhân viên thời gian thực.
   - Hiển thị ngày giờ đăng nhập cuối cùng (`lastLoginAt`).
   - **Sovereign Owner Rule:** Bảo vệ tuyệt đối tài khoản Chủ quán tối cao (không thể bị khóa, xóa hoặc hạ quyền).
6. **Kiểm thử tự động với Vitest (`web/test/auth.test.ts`):**
   - 17 test cases bao phủ: chuẩn hóa username, quy tắc sinh email, ma trận RBAC, quyền riêng lẻ và kiểm soát truy cập route.
   - Chạy lệnh `npm run test` (hoặc `npx vitest run`) đạt 17/17 passed.
