/**
 * Mã tài khoản (uid) thật của một nhân viên trong stores/{code}/users.
 *
 * Danh sách nhân viên dùng tên đăng nhập làm `id` để hiển thị; nếu dùng `id` đó làm đường dẫn
 * ghi/xóa thì lệnh nhắm vào nút không tồn tại (xóa "thành công" nhưng không xóa gì, khóa/đặt lại
 * mật khẩu báo không tìm thấy). Luôn ưu tiên trường `uid` trong hồ sơ, rồi mới tới khóa nút.
 * Với nút cũ khóa theo tên đăng nhập (không có trường uid) thì khóa nút chính là định danh.
 */
export function resolveStaffUid(nodeKey: string, record?: { uid?: unknown } | null): string {
  const fromRecord = record && typeof record.uid === "string" ? record.uid.trim() : "";
  return fromRecord || nodeKey;
}
