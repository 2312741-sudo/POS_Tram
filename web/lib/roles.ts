/**
 * Định danh & nhãn vai trò dùng chung toàn Web (nguồn: functions/src/permissions.ts và
 * app_flutter/lib/core/permissions/app_permissions.dart — giữ đồng bộ).
 *
 * Quản lý 1 + Quản lý 2  → ROLE_MANAGER ("Quản lý")
 * Thu ngân + Phục vụ     → ROLE_STAFF   ("Nhân viên")
 * Mọi mã cũ vẫn được chấp nhận (alias) khi đọc; bản ghi MỚI luôn ghi mã chuẩn.
 */

export const ROLE_OWNER = "ROLE_OWNER";
export const ROLE_MANAGER = "ROLE_MANAGER";
export const ROLE_STAFF = "ROLE_STAFF";
export const ROLE_KITCHEN = "ROLE_KITCHEN";

/** Tên hiển thị vai trò gộp Thu ngân/Phục vụ — đổi tên chỉ cần sửa hằng số này. */
export const STAFF_ROLE_LABEL = "Nhân viên";
export const STAFF_ROLE_DESCRIPTION = "Thu ngân / Phục vụ";
export const MANAGER_ROLE_LABEL = "Quản lý";
export const OWNER_ROLE_LABEL = "Chủ quán";
export const KITCHEN_ROLE_LABEL = "Bếp / Bar";

const clean = (raw: string) => raw.trim().toLowerCase().replace(/[-\s]+/g, "_");

const OWNER_ALIASES = new Set(["owner", "role_owner", "chu", "chu_cua_hang", "admin"]);
const MANAGER_ALIASES = new Set([
  "manager", "role_manager", "manager_1", "manager_2", "role_manager_1", "role_manager_2",
  "manager1", "manager2", "legacymanager", "legacy_manager",
  "ql", "ql1", "ql2", "ql_1", "ql_2", "quan_ly", "quan_ly_1", "quan_ly_2",
]);
const STAFF_ALIASES = new Set([
  "role_staff", "staff", "employee", "role_employee", "cashier", "role_cashier",
  "waiter", "role_waiter", "nhan_vien", "nv", "thu_ngan", "phuc_vu",
]);
const KITCHEN_ALIASES = new Set(["role_kitchen", "kitchen", "daubep", "bep"]);

/**
 * Chuẩn hóa mã vai trò về mã chuẩn: ROLE_OWNER / ROLE_MANAGER / ROLE_STAFF / ROLE_KITCHEN.
 * Mã lạ giữ nguyên (đã trim). Chuỗi rỗng → "".
 */
export function normalizeRoleId(raw?: string | null): string {
  if (raw == null) return "";
  const trimmed = String(raw).trim();
  const c = clean(trimmed);
  if (OWNER_ALIASES.has(c)) return ROLE_OWNER;
  if (MANAGER_ALIASES.has(c)) return ROLE_MANAGER;
  if (STAFF_ALIASES.has(c)) return ROLE_STAFF;
  if (KITCHEN_ALIASES.has(c)) return ROLE_KITCHEN;
  return trimmed;
}

export const isOwnerRoleId = (raw?: string | null) => normalizeRoleId(raw) === ROLE_OWNER;
export const isManagerRoleId = (raw?: string | null) => normalizeRoleId(raw) === ROLE_MANAGER;
export const isStaffRoleId = (raw?: string | null) => normalizeRoleId(raw) === ROLE_STAFF;
export const isKitchenRoleId = (raw?: string | null) => normalizeRoleId(raw) === ROLE_KITCHEN;

/** Tên hiển thị tiếng Việt của một mã vai trò (kể cả mã cũ). */
export function roleLabel(raw?: string | null): string {
  switch (normalizeRoleId(raw)) {
    case ROLE_OWNER:
      return OWNER_ROLE_LABEL;
    case ROLE_MANAGER:
      return MANAGER_ROLE_LABEL;
    case ROLE_STAFF:
      return STAFF_ROLE_LABEL;
    case ROLE_KITCHEN:
      return KITCHEN_ROLE_LABEL;
    default:
      return raw ? String(raw) : STAFF_ROLE_LABEL;
  }
}

/** Danh sách vai trò cho bộ chọn (tạo/sửa nhân viên, bộ lọc). Chủ quán gốc không gán được qua đây. */
export const ASSIGNABLE_ROLES: { id: string; label: string; description: string }[] = [
  { id: ROLE_MANAGER, label: MANAGER_ROLE_LABEL, description: "Điều hành ca, kho, khuyến mãi, báo cáo" },
  { id: ROLE_STAFF, label: `${STAFF_ROLE_LABEL} (${STAFF_ROLE_DESCRIPTION})`, description: "Gọi món, gửi bếp, thanh toán" },
  { id: ROLE_KITCHEN, label: KITCHEN_ROLE_LABEL, description: "Màn hình bếp / pha chế" },
];
