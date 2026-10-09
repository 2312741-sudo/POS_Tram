/**
 * "Quản lý duyệt bằng PIN" — phần thuần (không gọi Firebase) để dùng chung và unit test.
 *
 * PIN KHÔNG BAO GIỜ được đọc về client: web gọi callable verifyManagerPin (functions/src/managerPin.ts),
 * máy chủ so PIN (băm scrypt, lưu ngoài stores/{storeCode}), giới hạn số lần thử, tự ghi audit log
 * MANAGER_PIN_APPROVED và trả về một lần duyệt ngắn hạn. Web gắn thông tin người duyệt vào metadata
 * dòng món + audit log của thao tác.
 */
import type { RawOrderLine } from "./order-math";

export type ApprovalAction = "DISCOUNT_ITEM" | "CANCEL_KITCHEN_ITEM";

export interface ManagerApproval {
  approvalId: string;
  approverUid: string;
  approverName: string;
  approverUsername?: string | null;
  action: ApprovalAction;
  approvedAt: number;
  expiresAt: number;
}

export const APPROVAL_ACTION_LABELS: Record<ApprovalAction, string> = {
  DISCOUNT_ITEM: "Giảm giá món",
  CANCEL_KITCHEN_ITEM: "Hủy/giảm món đã gửi bếp",
};

/** Kiểm tra dữ liệu callable trả về có đúng hình dạng */
export function parseApproval(raw: unknown): ManagerApproval | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.approvalId !== "string" || typeof r.approverUid !== "string") return null;
  if (r.action !== "DISCOUNT_ITEM" && r.action !== "CANCEL_KITCHEN_ITEM") return null;
  const approvedAt = Number(r.approvedAt);
  const expiresAt = Number(r.expiresAt);
  if (!Number.isFinite(approvedAt) || !Number.isFinite(expiresAt)) return null;
  return {
    approvalId: r.approvalId,
    approverUid: r.approverUid,
    approverName: typeof r.approverName === "string" && r.approverName ? r.approverName : "Quản lý",
    approverUsername: typeof r.approverUsername === "string" ? r.approverUsername : null,
    action: r.action,
    approvedAt,
    expiresAt,
  };
}

/** Lần duyệt còn hiệu lực cho đúng hành động */
export function isApprovalValid(a: ManagerApproval | null | undefined, action: ApprovalAction, now = Date.now()): a is ManagerApproval {
  return !!a && a.action === action && a.expiresAt > now;
}

const APPROVAL_LINE_FIELDS = ["discountApprovedBy", "discountApprovedByName", "discountApprovalId", "discountApprovedAt"] as const;

/**
 * Gắn (hoặc gỡ, khi approval = null hoặc dòng không còn giảm giá) metadata người duyệt vào dòng món.
 * Lưu ý: POS Flutter hiện không đọc các trường này và sẽ bỏ chúng khi lưu lại đơn — nguồn sự thật là audit log.
 */
export function withApprovalMeta<T extends RawOrderLine>(line: T, approval: ManagerApproval | null, hasDiscount: boolean): T {
  const next: T = { ...line };
  for (const f of APPROVAL_LINE_FIELDS) delete next[f];
  if (approval && hasDiscount) {
    Object.assign(next, {
      discountApprovedBy: approval.approverUid,
      discountApprovedByName: approval.approverName,
      discountApprovalId: approval.approvalId,
      discountApprovedAt: approval.approvedAt,
    });
  }
  return next;
}

/** Trường bổ sung cho audit log của thao tác được duyệt */
export function approvalAuditFields(a: ManagerApproval | null | undefined): Record<string, unknown> {
  if (!a) return {};
  return { approvedBy: a.approverUid, approvedByName: a.approverName, approvalId: a.approvalId };
}

/** Hậu tố mô tả trong nhật ký, VD " — QL Lan duyệt bằng PIN" */
export function approvalSuffix(a: ManagerApproval | null | undefined): string {
  return a ? ` — ${a.approverName} duyệt bằng PIN` : "";
}

/** Thông báo lỗi tiếng Việt từ lỗi callable */
export function mapApprovalError(err: unknown): string {
  const e = err as { code?: string; message?: string } | null;
  const code = String(e?.code || "").replace(/^functions\//, "");
  const msg = typeof e?.message === "string" ? e.message : "";
  switch (code) {
    case "resource-exhausted":
    case "permission-denied":
    case "failed-precondition":
    case "invalid-argument":
      return msg || "PIN không hợp lệ.";
    case "unauthenticated":
      return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
    case "not-found":
    case "unimplemented":
      return "Máy chủ chưa triển khai chức năng duyệt bằng PIN (verifyManagerPin).";
    case "unavailable":
    case "deadline-exceeded":
      return "Không kết nối được máy chủ. Vui lòng thử lại.";
    default:
      return msg || "Không xác minh được PIN.";
  }
}

/** Danh sách người có thể duyệt (để chọn trong hộp thoại) — chỉ là gợi ý, máy chủ mới quyết định */
export interface ApproverOption {
  uid: string;
  name: string;
  hasPin: boolean;
}

interface ApproverSource {
  uid?: unknown;
  fullName?: unknown;
  username?: unknown;
  roleId?: unknown;
  role?: unknown;
  isRootOwner?: unknown;
  isActive?: unknown;
  hasApprovalPin?: unknown;
  customPermissions?: unknown;
}

const OWNER_ROLES = ["owner", "role_owner", "chu"];
const MANAGER_ROLES = ["manager", "role_manager", "manager_1", "manager_2", "role_manager_1", "role_manager_2", "ql"];
const ROLE_APPROVAL: Record<string, ApprovalAction[]> = {
  role_manager_1: ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"],
  manager_1: ["DISCOUNT_ITEM", "CANCEL_KITCHEN_ITEM"],
};

/** Khớp managerPinLogic.approverHasPermission phía máy chủ */
export function canUserApprove(u: ApproverSource, action: ApprovalAction): boolean {
  if (u.isActive === false) return false;
  const role = String(u.roleId || u.role || "").toLowerCase();
  if (u.isRootOwner === true || OWNER_ROLES.includes(role)) return true;
  if (!MANAGER_ROLES.includes(role)) return false;
  const custom = Array.isArray(u.customPermissions) ? (u.customPermissions as unknown[]) : [];
  if (custom.includes(action) || (action === "DISCOUNT_ITEM" && custom.includes("MANUAL_DISCOUNT"))) return true;
  if (action === "DISCOUNT_ITEM") return true; // mọi vai trò quản lý đều có DISCOUNT_ITEM
  return (ROLE_APPROVAL[role] || []).includes(action);
}

export function approverOptions(users: ApproverSource[], action: ApprovalAction, excludeUid?: string | null): ApproverOption[] {
  return users
    .filter((u) => typeof u.uid === "string" && u.uid && u.uid !== excludeUid && canUserApprove(u, action))
    .map((u) => ({
      uid: String(u.uid),
      name: String(u.fullName || u.username || u.uid),
      hasPin: u.hasApprovalPin === true,
    }))
    .sort((a, b) => Number(b.hasPin) - Number(a.hasPin) || a.name.localeCompare(b.name, "vi"));
}
