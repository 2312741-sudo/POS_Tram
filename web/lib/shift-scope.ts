/**
 * Ca/két tiền ĐỘC LẬP THEO TÀI KHOẢN (thuần logic, tương ứng app_flutter/lib/core/domain/shift_scope.dart).
 * - Ca thuộc tài khoản có uid == staffUid; ca cũ (không có staffUid) thuộc tài khoản có username == staffUsername.
 * - Chỉ người có VIEW_ALL_SHIFTS mới thấy ca của tài khoản khác.
 */
export interface ShiftOwnerFields {
  staffUid?: string;
  staffUsername?: string;
  staffFullName?: string;
  status?: string;
}

const norm = (s?: string | null) => (s ?? "").trim().toLowerCase();

export function shiftOwnedBy(s: ShiftOwnerFields, who: { uid?: string; username?: string }): boolean {
  if (s.staffUid) return !!who.uid && s.staffUid === who.uid;
  const u = norm(who.username);
  return u !== "" && norm(s.staffUsername) === u;
}

/** Khóa nhóm chủ ca: uid nếu có, nếu không dùng username (chữ thường). */
export function shiftOwnerKey(s: ShiftOwnerFields): string {
  return s.staffUid ? s.staffUid : norm(s.staffUsername);
}

/** Chỉ giữ ca được phép thấy; [filterOwner] (username hoặc uid) chỉ có tác dụng khi canViewAll. */
export function scopeShifts<T extends ShiftOwnerFields>(
  shifts: readonly T[],
  who: { uid?: string; username?: string },
  canViewAll: boolean,
  filterOwner?: string | null,
): T[] {
  const f = norm(filterOwner);
  return shifts.filter((s) => {
    if (!canViewAll) return shiftOwnedBy(s, who);
    if (!f) return true;
    return norm(s.staffUid) === f || norm(s.staffUsername) === f;
  });
}

export interface ShiftOwnerOption {
  value: string; // username (hoặc uid nếu thiếu username)
  label: string;
}

/** Danh sách tài khoản có ca (cho bộ lọc theo tài khoản). */
export function listShiftOwners(shifts: readonly ShiftOwnerFields[]): ShiftOwnerOption[] {
  const map = new Map<string, string>();
  for (const s of shifts) {
    const value = s.staffUsername || s.staffUid || "";
    if (!value) continue;
    map.set(value, s.staffFullName ? `${s.staffFullName} (${value})` : value);
  }
  return [...map.entries()].map(([value, label]) => ({ value, label })).sort((a, b) => a.label.localeCompare(b.label, "vi"));
}
