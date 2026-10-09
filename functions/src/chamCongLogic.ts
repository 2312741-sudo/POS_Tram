/**
 * Logic thuần cho "Đăng nhập bằng Chấm Công Trạm" (SSO từ project Firebase `chamcongtram`).
 * Không phụ thuộc Firebase runtime → unit test 100% (xem chamCongLogic.test.ts).
 * Phần I/O (verify token, đọc Firestore chấm công, ghi RTDB) nằm ở chamCong.ts.
 */
import { UserProfile, isManagerRole, isOwnerRole } from "./permissions";

/** Nhóm vai trò bên Chấm Công sau khi chuẩn hóa. */
export type ChamCongRoleKind = "owner" | "manager1" | "manager2" | "employee";

/** Vai trò POS tương ứng (khớp app_permissions.dart / web/lib/auth.tsx / database.rules.json). */
export const POS_ROLE_OWNER = "owner";
export const POS_ROLE_MANAGER_1 = "manager_1";
export const POS_ROLE_MANAGER_2 = "manager_2";
/** Vai trò thấp nhất của POS (Nhân viên phục vụ). KHÔNG dùng "employee" vì rules coi "employee" = Thu ngân. */
export const POS_ROLE_LOWEST = "ROLE_WAITER";

export const AUTH_PROVIDER_CHAMCONG = "chamcong";
export const DEACTIVATED_BY_CHAMCONG = "chamcong";

const OWNER_ALIASES = new Set(["owner", "chu", "role_owner", "chu_cua_hang"]);
const MANAGER1_ALIASES = new Set([
  "manager_1", "manager1", "manager", "legacymanager", "legacy_manager",
  "role_manager", "role_manager_1", "ql", "ql1", "ql_1", "quan_ly", "quan_ly_1",
]);
const MANAGER2_ALIASES = new Set(["manager_2", "manager2", "role_manager_2", "ql2", "ql_2", "quan_ly_2"]);

/** Chuẩn hóa vai trò Chấm Công (owner|manager1|manager_1|manager2|manager_2|employee + legacy 'manager','legacyManager','chu'). */
export function normalizeChamCongRole(raw: unknown): ChamCongRoleKind {
  const clean = typeof raw === "string" ? raw.trim().toLowerCase().replace(/[-\s]+/g, "_") : "";
  if (OWNER_ALIASES.has(clean)) return "owner";
  if (MANAGER1_ALIASES.has(clean)) return "manager1";
  if (MANAGER2_ALIASES.has(clean)) return "manager2";
  return "employee";
}

export function posRoleForChamCongRole(kind: ChamCongRoleKind): string {
  switch (kind) {
    case "owner":
      return POS_ROLE_OWNER;
    case "manager1":
      return POS_ROLE_MANAGER_1;
    case "manager2":
      return POS_ROLE_MANAGER_2;
    default:
      return POS_ROLE_LOWEST;
  }
}

/**
 * Chính sách vai trò POS:
 * - Lần đầu: theo bảng ánh xạ (nhân viên → ROLE_WAITER).
 * - Các lần sau: Chủ/Quản lý bên chấm công → luôn đặt vai trò ánh xạ;
 *   Nhân viên bên chấm công mà POS đang là chủ/quản lý → hạ về ROLE_WAITER;
 *   còn lại giữ vai trò chủ quán đã chọn trong POS (thu ngân, bếp...).
 */
export function decidePosRole(kind: ChamCongRoleKind, existingRoleId: string | null | undefined): string {
  if (existingRoleId == null || existingRoleId === "") return posRoleForChamCongRole(kind);
  if (kind !== "employee") return posRoleForChamCongRole(kind);
  if (isOwnerRole(existingRoleId) || isManagerRole(existingRoleId)) return POS_ROLE_LOWEST;
  return existingRoleId;
}

// ---------------------------------------------------------------------------
// Username
// ---------------------------------------------------------------------------

const USERNAME_MAX = 24;

/** Slug an toàn cho username POS: chỉ [a-z0-9_-] (khớp regex staffSignIn). */
export function slugifyUsername(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw
    .trim()
    .toLowerCase()
    .replace(/đ/g, "d")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, "")
    .replace(/[^a-z0-9_-]/g, "")
    .slice(0, USERNAME_MAX);
}

/** Username gốc: mã nhân viên (viết thường) → slug họ tên → "nv" + 6 ký tự uid. */
export function buildUsernameBase(employeeCode: unknown, fullName: unknown, chamCongUid: string): string {
  const fromCode = slugifyUsername(employeeCode);
  if (fromCode.length >= 3) return fromCode;
  const fromName = slugifyUsername(fullName);
  if (fromName.length >= 3) return fromName;
  const fromUid = slugifyUsername(chamCongUid).slice(0, 6);
  return `nv${fromUid || "user"}`;
}

/** Chọn username chưa bị dùng trong quán: base, base-2, base-3... (so sánh không phân biệt hoa thường). */
export function pickUniqueUsername(base: string, taken: Iterable<string>): string {
  const used = new Set<string>();
  for (const t of taken) if (typeof t === "string") used.add(t.trim().toLowerCase());
  if (!used.has(base)) return base;
  for (let i = 2; i < 10000; i++) {
    const suffix = `-${i}`;
    const candidate = `${base.slice(0, USERNAME_MAX - suffix.length)}${suffix}`;
    if (!used.has(candidate)) return candidate;
  }
  return `${base.slice(0, 14)}-${Date.now().toString(36)}`;
}

// ---------------------------------------------------------------------------
// Membership
// ---------------------------------------------------------------------------

export type MemberStatus = "active" | "pending" | "kicked" | "missing";

export interface ChamCongMembership {
  chamCongStoreId: string;
  status: MemberStatus;
  roleKind: ChamCongRoleKind;
  name: string;
  phone: string;
  avatarUrl: string;
  employeeCode: string;
}

const str = (v: unknown): string => (typeof v === "string" ? v.trim() : "");

function normalizeStatus(raw: unknown): MemberStatus {
  const s = str(raw).toLowerCase();
  if (s === "active" || s === "pending" || s === "kicked") return s;
  return "missing";
}

/**
 * Gộp dữ liệu Firestore chấm công thành map storeId → membership.
 * - memberDocs: kết quả collectionGroup('members').where('userId','==',uid) (kèm storeId cha).
 * - ownedStoreIds: các store có ownerId === uid → luôn coi là Chủ đang hoạt động.
 */
export function buildMemberships(
  memberDocs: Array<{ storeId: string; data: Record<string, unknown> }>,
  ownedStoreIds: Iterable<string>,
  fallbackName = ""
): Map<string, ChamCongMembership> {
  const out = new Map<string, ChamCongMembership>();
  for (const { storeId, data } of memberDocs) {
    out.set(storeId, {
      chamCongStoreId: storeId,
      status: normalizeStatus(data.status),
      roleKind: normalizeChamCongRole(data.role),
      name: str(data.name) || fallbackName,
      phone: str(data.phone),
      avatarUrl: str(data.avatarUrl),
      employeeCode: str(data.employeeCode),
    });
  }
  for (const storeId of ownedStoreIds) {
    const prev = out.get(storeId);
    out.set(storeId, {
      chamCongStoreId: storeId,
      status: "active",
      roleKind: "owner",
      name: prev?.name || fallbackName,
      phone: prev?.phone || "",
      avatarUrl: prev?.avatarUrl || "",
      employeeCode: prev?.employeeCode || "",
    });
  }
  return out;
}

export type SignInDecision =
  | { kind: "PROCEED"; storeCode: string; membership: ChamCongMembership; revokeStoreCodes: string[] }
  | { kind: "CHOOSE"; storeCodes: string[]; revokeStoreCodes: string[] }
  | { kind: "DENY"; code: "NOT_LINKED" | "NOT_ACTIVE_MEMBER"; revokeStoreCodes: string[] };

/**
 * Quyết định đăng nhập.
 * @param links storeCode POS → chamCongStoreId (chamcong_links/stores)
 * @param memberships map từ buildMemberships
 * @param previouslyProvisioned storeCode đã từng cấp tài khoản cho user này (chamcong_links/users/{sc}/{ccUid}):
 *        nếu member doc bị xóa hẳn → coi như "missing" (không hoạt động) để khóa tài khoản POS.
 * @param requestedStoreCode storeCode client gửi (tùy chọn, đã chuẩn hóa UPPERCASE)
 */
export function decideSignIn(
  links: Record<string, string>,
  memberships: Map<string, ChamCongMembership>,
  previouslyProvisioned: Iterable<string>,
  requestedStoreCode?: string | null
): SignInDecision {
  const prior = new Set(previouslyProvisioned);
  const entries: Array<{ storeCode: string; membership: ChamCongMembership | null; active: boolean }> = [];
  for (const storeCode of Object.keys(links).sort()) {
    const m = memberships.get(links[storeCode]) || null;
    if (m) entries.push({ storeCode, membership: m, active: m.status === "active" });
    else if (prior.has(storeCode)) entries.push({ storeCode, membership: null, active: false });
  }

  if (requestedStoreCode) {
    const e = entries.find((x) => x.storeCode === requestedStoreCode);
    if (!e) return { kind: "DENY", code: "NOT_LINKED", revokeStoreCodes: [] };
    if (!e.active || !e.membership) return { kind: "DENY", code: "NOT_ACTIVE_MEMBER", revokeStoreCodes: [e.storeCode] };
    return { kind: "PROCEED", storeCode: e.storeCode, membership: e.membership, revokeStoreCodes: [] };
  }

  if (entries.length === 0) return { kind: "DENY", code: "NOT_LINKED", revokeStoreCodes: [] };
  const revokeStoreCodes = entries.filter((e) => !e.active).map((e) => e.storeCode);
  const actives = entries.filter((e) => e.active && e.membership);
  if (actives.length === 0) return { kind: "DENY", code: "NOT_ACTIVE_MEMBER", revokeStoreCodes };
  if (actives.length === 1) {
    return { kind: "PROCEED", storeCode: actives[0].storeCode, membership: actives[0].membership!, revokeStoreCodes };
  }
  return { kind: "CHOOSE", storeCodes: actives.map((e) => e.storeCode), revokeStoreCodes };
}

// ---------------------------------------------------------------------------
// Hồ sơ POS
// ---------------------------------------------------------------------------

export function posUidForChamCong(chamCongUid: string): string {
  return `cc_${chamCongUid}`;
}

/** UID Firebase tối đa 128 ký tự → uid chấm công tối đa 125 để còn tiền tố "cc_". */
export function isValidChamCongUid(uid: unknown): uid is string {
  return typeof uid === "string" && uid.length > 0 && uid.length <= 125 && !/[/.#$\[\]]/.test(uid);
}

export type ProfileDecision =
  | { kind: "CONFLICT" }
  | { kind: "DISABLED" }
  | {
      kind: "WRITE";
      isNew: boolean;
      /** Hồ sơ đầy đủ (isNew) hoặc patch các trường (null = xóa trường). */
      values: Record<string, unknown>;
      roleId: string;
      roleChange: { from: string; to: string } | null;
      reactivated: boolean;
    };

export function decideProfile(params: {
  existing: UserProfile | null;
  membership: ChamCongMembership;
  posUid: string;
  chamCongUid: string;
  takenUsernames: Iterable<string>;
  now: number;
}): ProfileDecision {
  const { existing, membership, posUid, chamCongUid, now } = params;

  if (!existing) {
    const roleId = posRoleForChamCongRole(membership.roleKind);
    const username = pickUniqueUsername(
      buildUsernameBase(membership.employeeCode, membership.name, chamCongUid),
      params.takenUsernames
    );
    return {
      kind: "WRITE",
      isNew: true,
      roleId,
      roleChange: null,
      reactivated: false,
      values: {
        uid: posUid,
        username,
        fullName: membership.name || username,
        phone: membership.phone,
        avatarUrl: membership.avatarUrl,
        roleId,
        isRootOwner: false,
        isActive: true,
        authProvider: AUTH_PROVIDER_CHAMCONG,
        chamCongUid,
        chamCongStoreId: membership.chamCongStoreId,
        mustChangePassword: false,
        customPermissions: [],
        createdAt: now,
      },
    };
  }

  // Không bao giờ ghi đè tài khoản POS gốc (không phải do chấm công cấp)
  if (existing.authProvider !== AUTH_PROVIDER_CHAMCONG) return { kind: "CONFLICT" };

  // Bị quản lý POS khóa thủ công → từ chối. Bị khóa do chấm công (kick/pending) → mở lại khi đã active.
  const deactivatedByChamCong = existing.deactivatedBy === DEACTIVATED_BY_CHAMCONG;
  if (existing.isActive === false && !deactivatedByChamCong) return { kind: "DISABLED" };

  const currentRole = typeof existing.roleId === "string" ? existing.roleId : "";
  if (existing.isRootOwner === true) {
    // Không đụng vào hồ sơ chủ quán gốc
    return { kind: "WRITE", isNew: false, values: {}, roleId: currentRole, roleChange: null, reactivated: false };
  }

  const values: Record<string, unknown> = {};
  if (membership.name && existing.fullName !== membership.name) values.fullName = membership.name;
  if (membership.phone && existing.phone !== membership.phone) values.phone = membership.phone;
  if (membership.avatarUrl && existing.avatarUrl !== membership.avatarUrl) values.avatarUrl = membership.avatarUrl;
  if (existing.chamCongStoreId !== membership.chamCongStoreId) values.chamCongStoreId = membership.chamCongStoreId;

  const roleId = decidePosRole(membership.roleKind, currentRole);
  let roleChange: { from: string; to: string } | null = null;
  if (roleId !== currentRole) {
    values.roleId = roleId;
    roleChange = { from: currentRole, to: roleId };
  }

  let reactivated = false;
  if (existing.isActive === false && deactivatedByChamCong) {
    values.isActive = true;
    values.deactivatedBy = null;
    values.chamCongRevokedAt = null;
    reactivated = true;
  }
  return { kind: "WRITE", isNew: false, values, roleId, roleChange, reactivated };
}

/** Patch khóa hồ sơ POS khi thành viên bị kick/pending/xóa bên chấm công. null = không cần ghi. */
export function buildRevokePatch(existing: UserProfile | null, now: number): Record<string, unknown> | null {
  if (!existing) return null;
  if (existing.authProvider !== AUTH_PROVIDER_CHAMCONG) return null;
  if (existing.isRootOwner === true) return null;
  if (existing.isActive === false) return null;
  return { isActive: false, deactivatedBy: DEACTIVATED_BY_CHAMCONG, chamCongRevokedAt: now };
}

// ---------------------------------------------------------------------------
// Liên kết cửa hàng
// ---------------------------------------------------------------------------

export interface ChamCongStoreSummary {
  chamCongStoreId: string;
  name: string;
  code: string;
}

/** Người dùng token là Chủ của store chấm công: store.ownerId === uid HOẶC member role owner/chu đang active. */
export function isChamCongStoreOwner(
  store: Record<string, unknown> | null,
  member: Record<string, unknown> | null,
  uid: string
): boolean {
  if (store && store.ownerId === uid) return true;
  if (!member) return false;
  return normalizeStatus(member.status) === "active" && normalizeChamCongRole(member.role) === "owner";
}

export function summarizeChamCongStore(storeId: string, data: Record<string, unknown> | null): ChamCongStoreSummary {
  return { chamCongStoreId: storeId, name: str(data?.name) || storeId, code: str(data?.code) };
}

/** Kiểm tra store chấm công đã liên kết với POS khác chưa. */
export function decideLink(existingPosStoreForChamCong: string | null, targetStoreCode: string): "OK" | "ALREADY_LINKED" {
  if (existingPosStoreForChamCong && existingPosStoreForChamCong !== targetStoreCode) return "ALREADY_LINKED";
  return "OK";
}

// ---------------------------------------------------------------------------
// Định dạng phản hồi
// ---------------------------------------------------------------------------

export function buildOkResponse(p: { customToken: string; storeCode: string; uid: string; roleId: string; isNewAccount: boolean }) {
  return {
    status: "OK" as const,
    customToken: p.customToken,
    storeCode: p.storeCode,
    uid: p.uid,
    roleId: p.roleId,
    isNewAccount: p.isNewAccount,
  };
}

export function buildChooseStoreResponse(storeCodes: string[], storeNames: Record<string, string>) {
  return {
    status: "CHOOSE_STORE" as const,
    stores: storeCodes.map((storeCode) => ({ storeCode, storeName: storeNames[storeCode] || storeCode })),
  };
}

export const CHAMCONG_ERROR_MESSAGES = {
  INVALID_TOKEN: "Phiên đăng nhập Chấm Công Trạm không hợp lệ hoặc đã hết hạn. Vui lòng đăng nhập lại.",
  NOT_LINKED: "Cửa hàng Chấm Công của bạn chưa được liên kết với POS Trạm. Vui lòng liên hệ chủ quán.",
  NOT_ACTIVE_MEMBER: "Bạn chưa được duyệt hoặc đã bị xóa khỏi cửa hàng trên Chấm Công Trạm.",
  POS_ACCOUNT_DISABLED: "Tài khoản POS của bạn đã bị chủ quán tạm khóa.",
  POS_ACCOUNT_CONFLICT: "Tài khoản POS trùng mã với tài khoản sẵn có. Vui lòng liên hệ chủ quán.",
  ALREADY_LINKED: "Cửa hàng Chấm Công này đã được liên kết với một cửa hàng POS khác.",
} as const;
