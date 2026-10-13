/**
 * Hóa đơn "của" một tài khoản (thuần logic, tương ứng billOwnedBy ở app_flutter/lib/core/domain/shift_scope.dart):
 * người thu tiền (staffUid / staffUsername) hoặc người gửi bếp / thêm món (actionLogs) hoặc người gọi món (items.orderedBy).
 * Dùng cho "Đơn của tôi" — mọi vai trò xem được lịch sử đơn do CHÍNH MÌNH lập.
 */
export interface BillOwnerFields {
  staffUid?: string;
  staffUsername?: string;
  username?: string;
  createdBy?: string;
  actionLogs?: { action?: string; staffUsername?: string }[];
  items?: { orderedBy?: string }[];
}

const norm = (s?: string | null) => (s ?? "").trim().toLowerCase();
const ORDER_ACTIONS = new Set(["SEND_KITCHEN", "ADD_ITEMS", "ADD_ITEM", "WEB_ORDER"]);

export function billOwnedBy(b: BillOwnerFields, who: { uid?: string; username?: string }): boolean {
  const u = norm(who.username);
  if (b.staffUid && who.uid) {
    if (b.staffUid === who.uid) return true;
  } else if (u && (norm(b.staffUsername) === u || norm(b.username) === u || norm(b.createdBy) === u)) {
    return true;
  }
  if (!u) return false;
  if ((b.actionLogs ?? []).some((l) => ORDER_ACTIONS.has(String(l.action)) && norm(l.staffUsername) === u)) return true;
  return (b.items ?? []).some((i) => norm(i.orderedBy) === u);
}

export function scopeOwnBills<T extends BillOwnerFields>(bills: readonly T[], who: { uid?: string; username?: string }): T[] {
  return bills.filter((b) => billOwnedBy(b, who));
}
