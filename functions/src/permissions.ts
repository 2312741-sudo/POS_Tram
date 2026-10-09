/**
 * Logic kiểm tra quyền hạn thuần túy cho Cloud Functions
 * Độc lập với Firebase runtime, có thể unit test 100%.
 */

export interface UserProfile {
  username?: string;
  fullName?: string;
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
  return clean === "owner" || clean === "role_owner" || clean === "chu";
}

export function isManagerRole(roleId?: string): boolean {
  if (!roleId) return false;
  const clean = roleId.toLowerCase();
  return (
    clean === "manager" ||
    clean === "role_manager" ||
    clean === "manager_1" ||
    clean === "manager_2" ||
    clean === "role_manager_1" ||
    clean === "role_manager_2" ||
    clean === "ql"
  );
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
    // Quản lý không được đổi mật khẩu của chủ quán
    return !isOwnerRole(target.roleId);
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
    // Quản lý không được khóa chủ quán
    return !isOwnerRole(target.roleId);
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

/** Vai trò Thu ngân (khớp database.rules.json: cashier / ROLE_CASHIER / employee). */
export function isCashierRole(roleId?: string): boolean {
  if (!roleId) return false;
  const clean = roleId.toLowerCase();
  return clean === "cashier" || clean === "role_cashier" || clean === "employee";
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
