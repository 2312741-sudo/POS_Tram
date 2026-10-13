/**
 * Một nhân viên làm ở NHIỀU cửa hàng: một tài khoản (một mật khẩu), mỗi cửa hàng một hồ sơ + vai trò riêng.
 * Logic thuần (không Firebase) — dùng bởi assignStaffToStore / setStaffDisabled, có unit test.
 */
import { isOwnerRole, type UserProfile } from "./permissions";

/** Vai trò được gán theo từng cửa hàng (Chủ quán KHÔNG gán qua API này) */
export const ASSIGNABLE_ROLES = ["ROLE_MANAGER", "ROLE_STAFF", "ROLE_KITCHEN"] as const;
export type AssignableRole = (typeof ASSIGNABLE_ROLES)[number];

export function isAssignableRole(r: unknown): r is AssignableRole {
  return typeof r === "string" && (ASSIGNABLE_ROLES as readonly string[]).includes(r);
}

/** Chỉ Chủ quán / Admin (isRootOwner hoặc vai trò chủ) ở CẢ cửa hàng nguồn và đích mới được gán */
export function canAssignAcrossStores(callerAtSource: UserProfile | null, callerAtTarget: UserProfile | null): boolean {
  const ok = (c: UserProfile | null) => !!c && c.isActive !== false && isOwnerRole(c.roleId, c.isRootOwner);
  return ok(callerAtSource) && ok(callerAtTarget);
}

export function buildAssignedProfile(
  source: UserProfile,
  authUid: string,
  roleId: AssignableRole,
  by: { username?: string; storeCode: string },
  now: number
): Record<string, unknown> {
  return {
    uid: authUid,
    username: source.username,
    fullName: source.fullName,
    roleId,
    isRootOwner: false,
    isActive: true,
    phone: typeof source.phone === "string" ? source.phone : "",
    customPermissions: [], // quyền riêng không sao chép sang cửa hàng khác
    createdAt: now,
    mustChangePassword: false,
    assignedFromStore: by.storeCode,
    assignedBy: by.username ?? "",
  };
}

/**
 * Khóa tài khoản đăng nhập (Auth) CHỈ khi nhân viên thuộc 1 cửa hàng. Thuộc nhiều cửa hàng:
 * chỉ tắt isActive ở cửa hàng đang thao tác, các cửa hàng khác vẫn làm việc bình thường.
 */
export function shouldDisableAuthAccount(storeCount: number): boolean {
  return storeCount <= 1;
}

/** Số cửa hàng có userIndex = true */
export function countIndexedStores(userIndex: unknown): number {
  if (!userIndex || typeof userIndex !== "object") return 0;
  return Object.values(userIndex as Record<string, unknown>).filter((v) => v === true).length;
}
