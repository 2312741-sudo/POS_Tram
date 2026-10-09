/**
 * Logic thuần cho "Quản lý duyệt bằng PIN" (độc lập Firebase runtime, unit test được).
 *
 * - PIN của từng quản lý/chủ quán được lưu dạng băm scrypt + salt tại
 *   manager_pins/{storeCode}/{uid} — nút GỐC, ngoài stores/{storeCode}, nên không client nào
 *   đọc/ghi được (rules gốc .read/.write = false; chỉ Admin SDK truy cập).
 * - Người duyệt phải là chủ quán / quản lý đang hoạt động VÀ có quyền tương ứng hành động
 *   (bảng quyền khớp web/lib/auth.tsx ROLE_PERMISSIONS + customPermissions).
 */
import { randomBytes, scryptSync, timingSafeEqual } from "crypto";
import { UserProfile, isManagerRole, isOwnerRole } from "./permissions";

/** Hành động được phép duyệt bằng PIN */
export const APPROVABLE_ACTIONS = ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"] as const;
export type ApprovableAction = (typeof APPROVABLE_ACTIONS)[number];

/** Thời gian hiệu lực của một lần duyệt */
export const APPROVAL_TTL_MS = 5 * 60 * 1000;

const SCRYPT_KEYLEN = 32;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1 };

export interface StoredPin {
  algo: "scrypt";
  salt: string; // hex
  hash: string; // hex
  updatedAt?: number;
}

export function isApprovableAction(a: unknown): a is ApprovableAction {
  return typeof a === "string" && (APPROVABLE_ACTIONS as readonly string[]).includes(a);
}

/** PIN 4–8 chữ số, không chấp nhận dãy toàn một chữ số (VD 0000, 1111) */
export function validatePinFormat(pin: unknown): string | null {
  if (typeof pin !== "string" || !/^\d{4,8}$/.test(pin)) return "PIN phải gồm 4–8 chữ số.";
  if (/^(\d)\1+$/.test(pin)) return "PIN không được là dãy một chữ số lặp lại.";
  return null;
}

export function hashPin(pin: string, saltHex?: string): StoredPin {
  const salt = saltHex ? Buffer.from(saltHex, "hex") : randomBytes(16);
  const hash = scryptSync(pin, salt, SCRYPT_KEYLEN, SCRYPT_OPTS);
  return { algo: "scrypt", salt: salt.toString("hex"), hash: hash.toString("hex") };
}

export function verifyPinHash(pin: string, stored: StoredPin | null | undefined): boolean {
  if (!stored || stored.algo !== "scrypt" || typeof stored.salt !== "string" || typeof stored.hash !== "string") {
    return false;
  }
  const expected = Buffer.from(stored.hash, "hex");
  if (expected.length !== SCRYPT_KEYLEN) return false;
  const actual = scryptSync(pin, Buffer.from(stored.salt, "hex"), SCRYPT_KEYLEN, SCRYPT_OPTS);
  return timingSafeEqual(actual, expected);
}

/** Quyền theo vai trò — chỉ các quyền liên quan tới duyệt PIN (khớp web/lib/auth.tsx) */
const ROLE_APPROVAL_PERMS: Record<string, ApprovableAction[]> = {
  role_manager_1: ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"],
  manager_1: ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"],
  role_manager_2: ["DISCOUNT_ITEM"],
  manager_2: ["DISCOUNT_ITEM"],
  role_manager: ["DISCOUNT_ITEM"],
  manager: ["DISCOUNT_ITEM"],
  ql: ["DISCOUNT_ITEM"],
};

/** Hồ sơ có thể làm người duyệt (chủ quán / quản lý đang hoạt động) */
export function isApproverEligible(p: UserProfile | null | undefined): boolean {
  if (!p || p.isActive === false) return false;
  return isOwnerRole(p.roleId, p.isRootOwner) || isManagerRole(p.roleId);
}

/** Người duyệt có quyền thực hiện hành động này không */
export function approverHasPermission(p: UserProfile | null | undefined, action: ApprovableAction): boolean {
  if (!isApproverEligible(p)) return false;
  const profile = p as UserProfile;
  if (isOwnerRole(profile.roleId, profile.isRootOwner)) return true;
  const custom = Array.isArray(profile.customPermissions) ? profile.customPermissions : [];
  if (custom.includes(action)) return true;
  // DISCOUNT_ITEM có alias MANUAL_DISCOUNT (giống web hasPermission)
  if (action === "DISCOUNT_ITEM" && custom.includes("MANUAL_DISCOUNT")) return true;
  const perms = ROLE_APPROVAL_PERMS[(profile.roleId || "").toLowerCase()] || [];
  return perms.includes(action);
}

export interface PinCandidate {
  uid: string;
  profile: UserProfile;
  stored: StoredPin | null | undefined;
}

export type PinMatchResult =
  | { ok: true; uid: string; profile: UserProfile }
  | { ok: false; reason: "NO_MATCH" | "AMBIGUOUS" | "NOT_PERMITTED" };

/**
 * Tìm người duyệt khớp PIN. approverUid (nếu có) giới hạn chỉ so với người đó.
 * Không chọn người duyệt: nhiều quản lý trùng PIN ⇒ AMBIGUOUS (yêu cầu chọn người duyệt).
 * Người khớp PIN nhưng thiếu quyền ⇒ NOT_PERMITTED (vẫn tính là một lần thử).
 */
export function matchApprover(
  candidates: PinCandidate[],
  pin: string,
  action: ApprovableAction,
  approverUid?: string | null
): PinMatchResult {
  const pool = candidates.filter((c) => isApproverEligible(c.profile) && (!approverUid || c.uid === approverUid));
  const matched = pool.filter((c) => verifyPinHash(pin, c.stored));
  if (matched.length === 0) return { ok: false, reason: "NO_MATCH" };
  const permitted = matched.filter((c) => approverHasPermission(c.profile, action));
  if (permitted.length === 0) return { ok: false, reason: "NOT_PERMITTED" };
  if (permitted.length > 1) return { ok: false, reason: "AMBIGUOUS" };
  return { ok: true, uid: permitted[0].uid, profile: permitted[0].profile };
}

export const ACTION_LABELS: Record<ApprovableAction, string> = {
  DISCOUNT_ITEM: "Giảm giá món",
  CANCEL_KITCHEN_ITEM: "Hủy/giảm món đã gửi bếp",
};

/** Cắt ngắn mô tả ngữ cảnh do client gửi (chỉ để ghi nhật ký) */
export function sanitizeContext(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 200);
}
