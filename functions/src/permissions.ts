/**
 * Logic kiểm tra quyền hạn thuần túy cho Cloud Functions
 * Độc lập với Firebase runtime, có thể unit test 100%.
 */

export interface UserProfile {
  uid?: string;
  authProvider?: string;
  username?: string;
  fullName?: string;
  employeeCode?: string;
  roleId?: string;
  isRootOwner?: boolean;
  isActive?: boolean;
  customPermissions?: string[];
  [key: string]: unknown;
}

export function isOwnerRole(roleId?: string, isRootOwner?: boolean): boolean {
  if (isRootOwner === true) return true;
  if (!roleId) return false;
  const clean = roleId.toLowerCase();
  return clean === "owner" || clean === "role_owner" || clean === "chu" || clean === "admin";
}

/** Mã vai trò chuẩn của "Quản lý" (đã gộp Quản lý 1 + Quản lý 2). */
export const ROLE_MANAGER_ID = "ROLE_MANAGER";
/** Mã vai trò chuẩn của "Nhân viên" (đã gộp Thu ngân + Phục vụ). */
export const ROLE_STAFF_ID = "ROLE_STAFF";
export const ROLE_KITCHEN_ID = "ROLE_KITCHEN";
/** Tên hiển thị của vai trò gộp Thu ngân/Phục vụ — đổi một chỗ này khi cần đổi tên. */
export const STAFF_ROLE_LABEL = "Nhân viên";
export const MANAGER_ROLE_LABEL = "Quản lý";

const norm = (raw: string) => raw.trim().toLowerCase().replace(/[-\s]+/g, "_");

/** Mọi mã cũ/biến thể của vai trò Quản lý. */
const MANAGER_ROLE_ALIASES = new Set([
  "manager", "role_manager", "manager_1", "manager_2", "role_manager_1", "role_manager_2",
  "manager1", "manager2", "legacymanager", "legacy_manager",
  "ql", "ql1", "ql2", "ql_1", "ql_2", "quan_ly", "quan_ly_1", "quan_ly_2",
]);

/** Mọi mã cũ/biến thể của vai trò Nhân viên (Thu ngân + Phục vụ + employee). */
const STAFF_ROLE_ALIASES = new Set([
  "role_staff", "staff", "employee", "role_employee", "cashier", "role_cashier",
  "waiter", "role_waiter", "nhan_vien", "nv", "thu_ngan", "phuc_vu",
]);

/**
 * Chuẩn hóa mã vai trò: mọi biến thể Quản lý → "ROLE_MANAGER"; mọi biến thể Thu ngân/Phục vụ/employee
 * → "ROLE_STAFF". Vai trò khác (owner, ROLE_KITCHEN...) giữ nguyên (đã trim).
 * Mọi bản ghi MỚI phải ghi mã đã chuẩn hóa.
 */
export function normalizeRoleId(raw?: string | null): string {
  if (raw == null) return "";
  const trimmed = String(raw).trim();
  const clean = norm(trimmed);
  if (MANAGER_ROLE_ALIASES.has(clean)) return ROLE_MANAGER_ID;
  if (STAFF_ROLE_ALIASES.has(clean)) return ROLE_STAFF_ID;
  return trimmed;
}

export function isManagerRole(roleId?: string): boolean {
  if (!roleId) return false;
  return normalizeRoleId(roleId) === ROLE_MANAGER_ID;
}

/** Vai trò Nhân viên (đã gộp Thu ngân + Phục vụ). */
export function isStaffRole(roleId?: string): boolean {
  if (!roleId) return false;
  return normalizeRoleId(roleId) === ROLE_STAFF_ID;
}

/**
 * Quyền CHỈ Chủ quán được cấp thêm (qua customPermissions) cho từng tài khoản — Quản lý mặc định KHÔNG có,
 * và Quản lý cũng không tự cấp / cấp cho người khác. Giữ đồng bộ với:
 *  - app_flutter/lib/core/permissions/app_permissions.dart (ownerGrantOnly)
 *  - web/lib/permission-catalog.ts (OWNER_GRANT_ONLY_PERMISSIONS)
 *  - database.rules.json (users/$uid/customPermissions/$i .validate — hiện chặn đủ 4 mã này)
 */
export const OWNER_GRANT_ONLY_PERMISSIONS: readonly string[] = [
  "CANCEL_BILL",
  "CANCEL_KITCHEN_ITEM",
  "VIEW_AUDIT_LOGS",
  "EXPORT_AUDIT_LOGS",
];

/**
 * Lọc danh sách quyền riêng khi tạo tài khoản: chỉ chuỗi hợp lệ; người gọi KHÔNG phải Chủ quán
 * thì bị bỏ các quyền thuộc [OWNER_GRANT_ONLY_PERMISSIONS].
 */
export function sanitizeCustomPermissions(caller: UserProfile | null, requested: unknown): string[] {
  if (!Array.isArray(requested)) return [];
  const isOwner = !!caller && isOwnerRole(caller.roleId, caller.isRootOwner);
  const out: string[] = [];
  for (const p of requested) {
    if (typeof p !== "string" || !p.trim()) continue;
    const code = p.trim();
    if (!isOwner && OWNER_GRANT_ONLY_PERMISSIONS.includes(code)) continue;
    if (!out.includes(code)) out.push(code);
  }
  return out;
}

export function canCallerManageUsers(caller: UserProfile | null): boolean {
  if (!caller || caller.isActive === false) return false;
  return isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId);
}

export function canCallerCreateRole(caller: UserProfile, targetRoleId: string, targetIsRootOwner?: boolean): boolean {
  if (caller.isActive === false) return false;
  if (targetIsRootOwner === true) return false; // Không ai được tạo thêm root owner qua API

  const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
  if (callerIsOwner) return true;

  const callerIsManager = isManagerRole(caller.roleId);
  if (callerIsManager) {
    // Quản lý không được tạo chủ quán
    return !isOwnerRole(targetRoleId);
  }

  return false;
}

export function canCallerResetPassword(caller: UserProfile, target: UserProfile, isSelf: boolean): boolean {
  if (caller.isActive === false) return false;
  if (isSelf) return true;

  if (target.isRootOwner === true) {
    // Mật khẩu chủ quán gốc chỉ chính chủ mới đặt lại được
    return false;
  }

  const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
  if (callerIsOwner) return true;

  const callerIsManager = isManagerRole(caller.roleId);
  if (callerIsManager) {
    // Quản lý chỉ đặt lại mật khẩu cho Nhân viên / Bếp; không đụng tới Chủ quán hay Quản lý khác
    return !isOwnerRole(target.roleId, target.isRootOwner) && !isManagerRole(target.roleId);
  }

  return false;
}

export function canCallerSetDisabled(caller: UserProfile, target: UserProfile, targetUid: string, callerUid: string): boolean {
  if (caller.isActive === false) return false;
  if (callerUid === targetUid) return false; // Không được tự khóa chính mình
  if (target.isRootOwner === true) return false; // Không bao giờ được khóa chủ quán gốc

  const callerIsOwner = isOwnerRole(caller.roleId, caller.isRootOwner);
  if (callerIsOwner) return true;

  const callerIsManager = isManagerRole(caller.roleId);
  if (callerIsManager) {
    // Quản lý không được khóa Chủ quán hoặc Quản lý khác
    return !isOwnerRole(target.roleId, target.isRootOwner) && !isManagerRole(target.roleId);
  }

  return false;
}

export function normalizeUsername(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/[^a-z0-9_.-]/g, "");
}

export function buildSyntheticEmail(username: string, storeCode: string): string {
  const cleanUser = normalizeUsername(username);
  const cleanStore = storeCode.trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  return `${cleanUser}.${cleanStore}@tram.local`;
}

/** @deprecated Thu ngân đã gộp vào Nhân viên — giữ tên cũ cho mã gọi cũ. */
export function isCashierRole(roleId?: string): boolean {
  return isStaffRole(roleId);
}

/**
 * Nhập khách hàng từ Firestore kmt_customers vào RTDB của quán (importCustomerToStore):
 * người gọi phải là thành viên ĐANG HOẠT ĐỘNG của quán (userIndex/{uid}/{store} === true)
 * với vai trò Thu ngân trở lên.
 */
export function canCallerImportCustomer(caller: UserProfile | null, inStoreIndex: boolean): boolean {
  if (!caller || !inStoreIndex || caller.isActive === false) return false;
  return isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId) || isCashierRole(caller.roleId);
}

/** UID Firebase Auth thật của nhân viên: trường `uid` trong hồ sơ, nếu không có thì khóa nút. */
export function resolveStaffAuthUid(nodeKey: string, record?: { uid?: unknown } | null): string {
  const fromRecord = record && typeof record.uid === "string" ? record.uid.trim() : "";
  return fromRecord || nodeKey;
}

/** Tài khoản tự tạo khi đăng nhập bằng Chấm Công Trạm (không có mật khẩu POS). */
export function isChamCongAccount(nodeKey: string, record?: { authProvider?: unknown } | null): boolean {
  return (record && record.authProvider === "chamcong") || nodeKey.startsWith("cc_");
}

/**
 * Tự động cấp hoặc kiểm tra mã nhân viên (NV01, NV02, ...)
 * Hỗ trợ quét toàn bộ danh sách nhân viên hiện có để tìm số thứ tự lớn nhất tiếp theo.
 */
export function resolveEmployeeCode(
  providedCode: unknown,
  existingUsers: Array<{ employeeCode?: unknown; staffCode?: unknown }> | Record<string, { employeeCode?: unknown; staffCode?: unknown }> | null
): { code: string; error?: string } {
  const usersList = existingUsers
    ? Array.isArray(existingUsers)
      ? existingUsers
      : Object.values(existingUsers)
    : [];

  const existingCodes = new Set(
    usersList
      .map((u) => {
        const val = u?.employeeCode ?? u?.staffCode;
        return typeof val === "string" ? val.trim().toUpperCase() : "";
      })
      .filter((c) => c.length > 0)
  );

  if (typeof providedCode === "string" && providedCode.trim().length > 0) {
    const clean = providedCode.trim().toUpperCase();
    if (!/^[A-Z0-9_-]{2,20}$/.test(clean)) {
      return { code: "", error: "Mã nhân viên chỉ gồm 2-20 ký tự chữ cái không dấu, số, gạch dưới hoặc gạch ngang." };
    }
    if (existingCodes.has(clean)) {
      return { code: "", error: `Mã nhân viên "${clean}" đã tồn tại trong chi nhánh.` };
    }
    return { code: clean };
  }

  // Tự động sinh mã tiếp theo: NV01, NV02, ...
  let maxNum = 0;
  for (const c of existingCodes) {
    const match = /^NV(\d+)$/i.exec(c);
    if (match) {
      const num = parseInt(match[1], 10);
      if (!isNaN(num) && num > maxNum) {
        maxNum = num;
      }
    }
  }

  let nextNum = maxNum + 1;
  let candidate = `NV${String(nextNum).padStart(2, "0")}`;
  while (existingCodes.has(candidate)) {
    nextNum++;
    candidate = `NV${String(nextNum).padStart(2, "0")}`;
  }

  return { code: candidate };
}
