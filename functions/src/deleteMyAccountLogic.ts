/**
 * Logic thuần cho "Xóa tài khoản của tôi" (deleteMyAccount) — KHÔNG truy cập RTDB/Auth.
 * Quy tắc:
 *   - Chủ quán gốc (isRootOwner) ở BẤT KỲ chi nhánh nào → từ chối (ROOT_OWNER).
 *   - Còn lại: ẩn danh hóa hồ sơ từng chi nhánh (giữ uid, roleId, mốc thời gian), không xóa cứng lịch sử.
 */

export const DELETE_CONFIRM_WORD = "XOA";
export const ROOT_OWNER_CODE = "ROOT_OWNER";
export const ROOT_OWNER_MESSAGE =
  "Chủ quán gốc không thể tự xóa tài khoản. Vui lòng liên hệ đơn vị vận hành để chuyển quyền trước khi xóa.";
export const DELETE_OWN_ACCOUNT_ACTION = "DELETE_OWN_ACCOUNT";
const CC_PREFIX = "cc_";

/** Các khóa được GIỮ khi ẩn danh hóa (không phải dữ liệu cá nhân). Mọi khóa khác bị loại bỏ. */
export const KEPT_PROFILE_KEYS = ["uid", "roleId", "isRootOwner", "createdAt", "lastLoginAt", "updatedAt"] as const;

export type ProfileLike = Record<string, unknown>;

export function isConfirmed(value: unknown): boolean {
  return value === DELETE_CONFIRM_WORD;
}

/** userIndex/{uid} = { storeCode: true } → danh sách mã cửa hàng (bỏ qua dữ liệu lạ). */
export function storeCodesFromIndex(index: unknown): string[] {
  if (!index || typeof index !== "object" || Array.isArray(index)) return [];
  return Object.keys(index as Record<string, unknown>);
}

/** Placeholder username không định danh được người dùng: "deleted_<8 ký tự đầu của uid>". */
export function placeholderUsername(uid: string): string {
  return `deleted_${uid.slice(0, 8)}`;
}

/** Các chi nhánh mà hồ sơ người gọi có isRootOwner = true. */
export function findRootOwnerStores(profiles: Record<string, ProfileLike | null | undefined>): string[] {
  return Object.entries(profiles)
    .filter(([, p]) => !!p && typeof p === "object" && p.isRootOwner === true)
    .map(([storeCode]) => storeCode);
}

export type StoreAction = "ANONYMISE" | "SKIP";

/** Có hồ sơ tại chi nhánh → ẩn danh hóa; không có (index mồ côi) → bỏ qua. */
export function decideStoreAction(profile: ProfileLike | null | undefined): StoreAction {
  return profile && typeof profile === "object" ? "ANONYMISE" : "SKIP";
}

export type DeletionPlan =
  | { kind: "ROOT_OWNER"; rootStores: string[] }
  | { kind: "OK"; anonymiseStores: string[]; skippedStores: string[]; indexStores: string[] };

/**
 * Kế hoạch xóa: kiểm tra chủ quán gốc trước; nếu an toàn trả về cửa hàng cần ẩn danh hóa.
 * indexStores: mọi khóa trong userIndex/{uid} (sẽ bị gỡ, kể cả index mồ côi).
 */
export function planAccountDeletion(
  indexStores: string[],
  profiles: Record<string, ProfileLike | null | undefined>
): DeletionPlan {
  const rootStores = findRootOwnerStores(profiles);
  if (rootStores.length > 0) return { kind: "ROOT_OWNER", rootStores };

  const anonymiseStores: string[] = [];
  const skippedStores: string[] = [];
  for (const storeCode of indexStores) {
    if (decideStoreAction(profiles[storeCode]) === "ANONYMISE") anonymiseStores.push(storeCode);
    else skippedStores.push(storeCode);
  }
  return { kind: "OK", anonymiseStores, skippedStores, indexStores: [...indexStores] };
}

/** Mã uid trong chamcong_links/users/{storeCode}/{ccUid}: lấy từ hồ sơ, hoặc suy ra từ uid "cc_<ccUid>". */
export function chamCongUidOf(profile: ProfileLike | null | undefined, posUid: string): string | null {
  const fromProfile = profile?.chamCongUid;
  if (typeof fromProfile === "string" && fromProfile.trim()) return fromProfile.trim();
  if (posUid.startsWith(CC_PREFIX) && posUid.length > CC_PREFIX.length) return posUid.slice(CC_PREFIX.length);
  return null;
}

/** Hồ sơ ẩn danh: chỉ giữ khóa không cá nhân; ghi đè toàn bộ node (loại email, SĐT, tên, avatar, quyền riêng...). */
export function buildAnonymisedProfile(profile: ProfileLike, uid: string, now: number): ProfileLike {
  const kept: ProfileLike = {};
  for (const key of KEPT_PROFILE_KEYS) {
    if (profile[key] !== undefined) kept[key] = profile[key];
  }
  kept.uid = uid;
  return {
    ...kept,
    username: placeholderUsername(uid),
    isActive: false,
    deactivatedBy: "self",
    deletedAt: now,
  };
}

/** Bản ghi audit: chỉ có uid (không tên, không SĐT, không email). */
export function buildSelfDeleteAudit(uid: string, roleId: unknown, now: number): Record<string, unknown> {
  return {
    timestamp: now,
    action: DELETE_OWN_ACCOUNT_ACTION,
    username: placeholderUsername(uid),
    userRole: typeof roleId === "string" ? roleId : "",
    targetType: "USER",
    targetId: uid,
    isSuspicious: false,
    details: "Người dùng tự xóa tài khoản (hồ sơ đã ẩn danh hóa)",
  };
}
