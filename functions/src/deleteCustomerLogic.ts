/**
 * Logic THUẦN của callable deleteCustomer (xóa khách hàng ở một chi nhánh). Không phụ thuộc Firebase.
 * Xem deleteCustomer.ts cho phần I/O.
 */
import { UserProfile, isManagerRole, isOwnerRole } from "./permissions";
import { indexPath } from "./loyaltyLedgerQuery";
import { memberKeyFor } from "./sharedLoyalty";

type AnyMap = Record<string, unknown>;

export const DELETE_CUSTOMER_CONFIRM = "XOA";

export function isDeleteConfirmed(v: unknown): boolean {
  return typeof v === "string" && v.trim().toUpperCase() === DELETE_CUSTOMER_CONFIRM;
}

/** Chỉ Chủ quán / Quản lý ĐANG HOẠT ĐỘNG và là thành viên của quán (userIndex/{uid}/{store} === true). */
export function canCallerDeleteCustomer(caller: UserProfile | null, inStoreIndex: boolean): boolean {
  if (!caller || !inStoreIndex || caller.isActive === false) return false;
  return isOwnerRole(caller.roleId, caller.isRootOwner) || isManagerRole(caller.roleId);
}

/** "0912345678" → "...678" (không lưu đủ SĐT vào nhật ký). */
export function maskPhone(raw: unknown): string {
  const digits = String(raw ?? "").replace(/\D/g, "");
  return digits.length >= 3 ? `...${digits.slice(-3)}` : "";
}

export function buildDeleteAuditDetails(name: unknown, phone: unknown, removedMember: boolean): string {
  const n = String(name ?? "").trim() || "(không tên)";
  const p = maskPhone(phone);
  return `Xóa khách hàng ${n}${p ? ` (SĐT ${p})` : ""}${removedMember ? " - đã xóa cả điểm tích lũy" : " - giữ điểm vì khách còn ở chi nhánh khác"}`;
}

/** Số liên kết chi nhánh còn lại của member sau khi gỡ (storeCode, customerId). */
export function remainingBranchLinks(member: AnyMap | null, storeCode: string, customerId: string): number {
  const b = (member?.branches || {}) as Record<string, unknown>;
  let n = 0;
  for (const [s, customers] of Object.entries(b)) {
    if (!customers || typeof customers !== "object") continue;
    for (const [cid, v] of Object.entries(customers as AnyMap)) {
      if (!v) continue;
      if (s === storeCode && cid === customerId) continue;
      n++;
    }
  }
  return n;
}

export interface DeletePlan {
  memberKey: string;
  removedMember: boolean;
  /** Multi-path update (giá trị null = xóa) */
  updates: Record<string, null>;
}

/**
 * @param customer node stores/{s}/customers/{id}
 * @param member loyalty_members/{memberKey} hiện tại (null nếu chưa có)
 * @param ledger loyalty_ledger/{memberKey} hiện tại (opId → entry), để suy ra các khóa chỉ mục theo tháng
 */
export function planDeleteCustomer(input: {
  storeCode: string;
  customerId: string;
  customer: AnyMap;
  member: AnyMap | null;
  ledger: Record<string, AnyMap> | null;
}): DeletePlan {
  const { storeCode, customerId, customer, member, ledger } = input;
  const memberKey = memberKeyFor(customer.so_dien_thoai ?? customer.phone, storeCode, customerId);
  const updates: Record<string, null> = {
    [`stores/${storeCode}/customers/${customerId}`]: null,
  };
  if (member) updates[`loyalty_members/${memberKey}/branches/${storeCode}/${customerId}`] = null;

  const removedMember = !!member && remainingBranchLinks(member, storeCode, customerId) === 0;
  if (removedMember) {
    // Thay các lệnh gỡ liên kết bằng xóa cả nút
    delete updates[`loyalty_members/${memberKey}/branches/${storeCode}/${customerId}`];
    updates[`loyalty_members/${memberKey}`] = null;
    updates[`loyalty_ledger/${memberKey}`] = null;
    for (const [opId, e] of Object.entries(ledger || {})) {
      const at = Number(e?.at);
      if (Number.isFinite(at)) updates[indexPath(memberKey, opId, at)] = null;
    }
  }
  return { memberKey, removedMember, updates };
}
