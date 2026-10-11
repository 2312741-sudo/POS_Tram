/**
 * Chốt chặn quyền XUẤT file (Excel/PDF/in). AuthProvider cập nhật theo người đang đăng nhập;
 * các hàm xuất trong lib/export.ts gọi guardExport() trước khi tạo file.
 *  - EXPORT_REPORTS     : báo cáo doanh thu / ca / sản phẩm / khuyến mãi / hóa đơn
 *  - EXPORT_AUDIT_LOGS  : nhật ký thao tác nhân viên
 *  - EXPORT_DATA        : danh sách nhân sự, hàng hóa, khách hàng
 * Chưa khởi tạo (ví dụ khi chạy test) → cho phép, để không chặn nhầm.
 */

export type ExportPermission = "EXPORT_REPORTS" | "EXPORT_AUDIT_LOGS" | "EXPORT_DATA";

let grants: Partial<Record<ExportPermission, boolean>> | null = null;

export function setExportGrants(next: Partial<Record<ExportPermission, boolean>> | null): void {
  grants = next;
}

export function canExportNow(permission: ExportPermission): boolean {
  return grants === null || grants[permission] === true;
}

const LABELS: Record<ExportPermission, string> = {
  EXPORT_REPORTS: "xuất báo cáo",
  EXPORT_AUDIT_LOGS: "xuất lịch sử kiểm soát",
  EXPORT_DATA: "xuất dữ liệu",
};

/** true = được phép; false = đã báo lỗi tiếng Việt cho người dùng, hàm gọi phải dừng. */
export function guardExport(permission: ExportPermission): boolean {
  if (canExportNow(permission)) return true;
  if (typeof window !== "undefined") window.alert(`Bạn không có quyền ${LABELS[permission]}. Liên hệ Chủ quán để được cấp quyền.`);
  return false;
}
