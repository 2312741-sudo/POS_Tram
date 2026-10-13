/**
 * Ca / két tiền trên Web — cùng hợp đồng dữ liệu với POS Flutter (CashShiftModel + ReportRepository):
 *  stores/{code}/cash_shifts/{id} = { id, shiftCode, shiftName, storeCode, staffUid, staffUsername, staffFullName,
 *    openedAt, closedAt?, initialCash, totalCashSales, totalQrSales, totalCardSales, cashIn, cashOut,
 *    actualCash?, difference?, status: "OPEN"|"CLOSED", notes }
 * Mỗi tài khoản có ca độc lập (xem shift-scope.ts). Rules: nhân viên chỉ ghi ca CỦA MÌNH khi ca chưa chốt.
 */
import { shiftOwnedBy, type ShiftOwnerFields } from "./shift-scope";

export interface ShiftLike extends ShiftOwnerFields {
  id: string;
  shiftCode?: string;
  storeCode?: string;
  openedAt?: number;
  closedAt?: number | null;
  initialCash?: number;
  totalCashSales?: number;
  totalQrSales?: number;
  totalCardSales?: number;
  cashIn?: number;
  cashOut?: number;
}

export interface ShiftActor {
  uid: string;
  username: string;
  fullName?: string;
  role?: string;
}

const n = (v: unknown) => (Number.isFinite(Number(v)) ? Math.trunc(Number(v)) : 0);

export function isShiftOpen(s: ShiftLike): boolean {
  return (s.status ?? "").toUpperCase().trim() === "OPEN" && !s.closedAt && n(s.openedAt) > 0;
}

/** Ca đang mở của CHÍNH tài khoản (mới nhất) trong một chi nhánh */
export function findOwnOpenShift(shifts: readonly ShiftLike[], who: { uid?: string; username?: string }, storeCode?: string): ShiftLike | null {
  const own = shifts
    .filter((s) => isShiftOpen(s) && shiftOwnedBy(s, who) && (!storeCode || !s.storeCode || s.storeCode === storeCode))
    .sort((a, b) => n(b.openedAt) - n(a.openedAt));
  return own[0] ?? null;
}

/** Tiền mặt kỳ vọng = đầu ca + bán tiền mặt + nộp thêm − chi vặt */
export function expectedCash(s: ShiftLike): number {
  return n(s.initialCash) + n(s.totalCashSales) + n(s.cashIn) - n(s.cashOut);
}

export function totalRevenue(s: ShiftLike): number {
  return n(s.totalCashSales) + n(s.totalQrSales) + n(s.totalCardSales);
}

const pad = (v: number) => String(v).padStart(2, "0");

/** Mã ca: CA-yyMMdd-HHmmss theo giờ Việt Nam */
export function shiftCodeFor(now: number): string {
  const d = new Date(now + 7 * 3600_000);
  return `CA-${pad(d.getUTCFullYear() % 100)}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
}

function auditLog(storeCode: string, now: number, actor: ShiftActor, action: string, targetId: string, details: string, suspicious = false) {
  return {
    [`stores/${storeCode}/audit_logs/log_${now}_shift_${action}`]: {
      timestamp: now,
      username: actor.username,
      userFullName: actor.fullName || actor.username,
      userRole: actor.role || "",
      action,
      targetType: "SHIFT",
      targetId,
      storeCode,
      details,
      isSuspicious: suspicious,
    },
  };
}

export type ShiftBuildResult = { error: string } | { updates: Record<string, unknown>; shiftId: string };

/**
 * Mở ca: tài khoản phải chưa có ca đang mở Ở BẤT KỲ CỬA HÀNG NÀO (nhân viên xoay ca nhiều cửa hàng phải chốt ca
 * cửa hàng này mới mở ca cửa hàng khác). `existing` gồm ca của tài khoản ở mọi cửa hàng đã đọc được.
 */
export function buildOpenShift(args: {
  storeCode: string;
  actor: ShiftActor;
  initialCash: number;
  existing: readonly ShiftLike[];
  now: number;
  shiftName?: string;
}): ShiftBuildResult {
  const { storeCode, actor, now } = args;
  if (!actor.uid) return { error: "Không xác định được tài khoản đang đăng nhập" };
  if (!Number.isInteger(args.initialCash) || args.initialCash < 0) return { error: "Tiền đầu ca phải là số nguyên ≥ 0" };
  if (args.initialCash > 1_000_000_000) return { error: "Tiền đầu ca quá lớn" };
  const open = findOwnOpenShift(args.existing, { uid: actor.uid, username: actor.username });
  if (open) {
    const where = open.storeCode && open.storeCode !== storeCode ? ` tại cửa hàng ${open.storeCode}` : "";
    return { error: `Bạn đang có ca ${open.shiftCode || open.id}${where} chưa chốt. Hãy chốt ca đó trước khi mở ca mới.` };
  }

  const shiftId = `SHIFT_${now}_${actor.uid.slice(0, 6)}`;
  const code = shiftCodeFor(now);
  const base = `stores/${storeCode}/cash_shifts`;
  const updates: Record<string, unknown> = {
    [`${base}/${shiftId}`]: {
      id: shiftId,
      shiftCode: code,
      shiftName: args.shiftName?.trim() || "",
      storeCode,
      staffUid: actor.uid,
      staffUsername: actor.username,
      staffFullName: actor.fullName || actor.username,
      openedAt: now,
      initialCash: args.initialCash,
      totalCashSales: 0,
      totalQrSales: 0,
      totalCardSales: 0,
      cashIn: 0,
      cashOut: 0,
      status: "OPEN",
      notes: "",
    },
    ...auditLog(storeCode, now, actor, "OPEN_SHIFT", code, `Mở ca bán hàng ${code} trên Web, tiền đầu ca: ${args.initialCash}đ`),
  };
  return { updates, shiftId };
}

/** Chốt ca: chỉ chủ ca (người có VIEW_ALL_SHIFTS được đóng bắt buộc ca của người khác) */
export function buildCloseShift(args: {
  storeCode: string;
  actor: ShiftActor;
  shift: ShiftLike;
  actualCash: number;
  notes: string;
  canForceClose?: boolean;
  now: number;
}): ShiftBuildResult {
  const { storeCode, actor, shift, now } = args;
  if (!isShiftOpen(shift)) return { error: "Ca này đã được chốt" };
  const own = shiftOwnedBy(shift, { uid: actor.uid, username: actor.username });
  if (!own && !args.canForceClose) return { error: "Bạn không thể chốt ca của tài khoản khác" };
  if (!Number.isInteger(args.actualCash) || args.actualCash < 0) return { error: "Tiền mặt kiểm đếm phải là số nguyên ≥ 0" };
  const expected = expectedCash(shift);
  const diff = args.actualCash - expected;
  const forced = !own;
  const code = shift.shiftCode || shift.id;
  const path = `stores/${storeCode}/cash_shifts/${shift.id}`;
  const updates: Record<string, unknown> = {
    // Chỉ các trường chốt ca — không ghi đè doanh số do máy khác cộng dồn
    [`${path}/status`]: "CLOSED",
    [`${path}/closedAt`]: now,
    [`${path}/actualCash`]: args.actualCash,
    [`${path}/difference`]: diff,
    [`${path}/notes`]: args.notes.trim(),
    ...(forced ? { [`${path}/forceClosedByUid`]: actor.uid, [`${path}/forceClosedByUsername`]: actor.username } : {}),
    ...auditLog(
      storeCode,
      now,
      actor,
      forced ? "FORCE_CLOSE_SHIFT" : "CLOSE_SHIFT",
      code,
      `${forced ? `Đóng bắt buộc ca ${code} của ${shift.staffUsername}` : `Chốt ca ${code}`}: Doanh số ${totalRevenue(shift)}đ, Lệch: ${diff}đ`,
      forced
    ),
  };
  return { updates, shiftId: shift.id };
}

export type SalePaymentKind = "CASH" | "QR" | "CARD";

/** Phân loại phương thức thanh toán của hóa đơn vào nhóm doanh số ca (giống deductCashShiftSale của POS) */
export function paymentKindOf(method: string | undefined): SalePaymentKind {
  const m = (method ?? "").toUpperCase();
  if (m.includes("QR") || m.includes("TRANSFER")) return "QR";
  if (m.includes("CARD") || m.includes("THẺ")) return "CARD";
  return "CASH";
}

/** Hàm cộng dồn doanh số / thu chi vào một node ca — dùng trong transaction (cur=null: để SDK chạy lại với dữ liệu thật) */
export function applyShiftDelta(
  cur: unknown,
  d: { cash?: number; qr?: number; card?: number; cashIn?: number; cashOut?: number }
): Record<string, unknown> | null | undefined {
  if (cur === null) return null;
  if (typeof cur !== "object") return undefined;
  const m = { ...(cur as Record<string, unknown>) };
  if (String(m.status ?? "").toUpperCase() === "CLOSED" || m.closedAt) return undefined; // ca đã chốt: không cộng thêm
  const add = (k: string, v = 0) => {
    m[k] = Math.max(0, n(m[k]) + v);
  };
  add("totalCashSales", d.cash);
  add("totalQrSales", d.qr);
  add("totalCardSales", d.card);
  add("cashIn", d.cashIn);
  add("cashOut", d.cashOut);
  return m;
}
