/**
 * Phần có Firebase của lib/cash-shift.ts: đọc ca của tài khoản, cộng doanh số khi thanh toán trên Web.
 */
import { equalTo, get, limitToLast, orderByChild, orderByKey, query, ref, runTransaction, type Database } from "firebase/database";
import { applyShiftDelta, billShiftPortions, findBillShift, findOwnOpenShift, isShiftOpen, paymentKindOf, type ShiftBillLike, type ShiftLike } from "./cash-shift";

/** Ca đang mở của tài khoản tại chi nhánh (đọc theo staffUid — rules đã khai báo .indexOn) */
export async function fetchOwnOpenShift(db: Database, storeCode: string, who: { uid: string; username: string }): Promise<ShiftLike | null> {
  if (!who.uid) return null;
  const snap = await get(query(ref(db, `stores/${storeCode}/cash_shifts`), orderByChild("staffUid"), equalTo(who.uid)));
  const list: ShiftLike[] = [];
  snap.forEach((c) => {
    const v = c.val();
    if (v && typeof v === "object") list.push({ ...(v as ShiftLike), id: c.key as string });
  });
  return findOwnOpenShift(list, who, storeCode);
}

/**
 * Cộng doanh số hóa đơn vừa thanh toán vào ca đang mở của người thanh toán (giống recordCashShiftSale của POS).
 * Không có ca mở → bỏ qua. Không bao giờ ném lỗi (không làm hỏng việc thanh toán): trả về true nếu đã ghi.
 */
export async function recordShiftSale(
  db: Database,
  storeCode: string,
  who: { uid: string; username: string },
  paymentMethod: string | undefined,
  amount: number
): Promise<boolean> {
  try {
    if (!(amount > 0)) return false;
    const shift = await fetchOwnOpenShift(db, storeCode, who);
    if (!shift) return false;
    const kind = paymentKindOf(paymentMethod);
    const delta = kind === "QR" ? { qr: amount } : kind === "CARD" ? { card: amount } : { cash: amount };
    const res = await runTransaction(ref(db, `stores/${storeCode}/cash_shifts/${shift.id}`), (cur) => applyShiftDelta(cur, delta));
    return res.committed && res.snapshot.exists();
  } catch (e) {
    console.warn("recordShiftSale:", e);
    return false;
  }
}

const toShifts = (snap: { forEach: (cb: (c: { key: string | null; val: () => unknown }) => boolean | void) => unknown }): ShiftLike[] => {
  const list: ShiftLike[] = [];
  snap.forEach((c) => {
    const v = c.val();
    if (v && typeof v === "object") list.push({ ...(v as ShiftLike), id: c.key as string });
  });
  return list;
};

/**
 * HỦY / XÓA HÓA ĐƠN ĐÃ THANH TOÁN TRÊN WEB: trừ tiền ở ĐÚNG CA ĐÃ THU TIỀN hóa đơn (nhân viên thu tiền), dù Chủ / Quản lý
 * hủy hộ — tiền mặt / chuyển khoản / thẻ tách đúng từng phần. Ca đó đã chốt / không tìm thấy / không ghi được: phần
 * TIỀN MẶT hoàn cho khách ghi thành khoản CHI của ca đang mở của người hủy. Không bao giờ ném lỗi; trả về mô tả.
 * Giống ReportRepository.reverseBillFromShift của POS.
 */
export async function reverseShiftForBill(
  db: Database,
  storeCode: string,
  bill: ShiftBillLike & { billCode?: string },
  actor: { uid: string; username: string }
): Promise<string> {
  const p = billShiftPortions(bill);
  if (p.cash + p.qr + p.card <= 0) return "không có tiền cần trừ ở ca";
  const base = `stores/${storeCode}/cash_shifts`;
  let target: ShiftLike | null = null;
  try {
    const sid = String(bill.shiftId ?? "").trim();
    if (sid) {
      const snap = await get(ref(db, `${base}/${sid}`));
      const v = snap.val();
      if (v && typeof v === "object") target = { ...(v as ShiftLike), id: sid };
    }
    if (!target) {
      const uid = String(bill.staffUid ?? "").trim();
      const snap = await get(uid && !sid ? query(ref(db, base), orderByChild("staffUid"), equalTo(uid)) : query(ref(db, base), orderByKey(), limitToLast(300)));
      target = findBillShift(bill, toShifts(snap));
      if (!target && uid && !sid) target = findBillShift(bill, toShifts(await get(query(ref(db, base), orderByKey(), limitToLast(300)))));
    }
  } catch {
    target = null;
  }
  const money = [p.cash > 0 && `TM ${p.cash}đ`, p.qr > 0 && `CK ${p.qr}đ`, p.card > 0 && `thẻ ${p.card}đ`].filter(Boolean).join(" ");
  const code = (s: ShiftLike) => s.shiftCode || s.id;
  let why: string;
  if (target && isShiftOpen(target)) {
    try {
      const res = await runTransaction(ref(db, `${base}/${target.id}`), (cur) => applyShiftDelta(cur, { cash: -p.cash, qr: -p.qr, card: -p.card }));
      if (res.committed && res.snapshot.exists()) return `trừ ${money} khỏi ca ${code(target)} (${target.staffFullName || target.staffUsername || ""})`;
      why = `ca ${code(target)} đã chốt`;
    } catch {
      why = `không ghi được ca ${code(target)}`;
    }
  } else {
    why = target ? `ca ${code(target)} đã chốt` : "không tìm thấy ca đã thu tiền";
  }
  if (p.cash <= 0) return `${why} — không có tiền mặt cần hoàn từ két`;
  try {
    const own = await fetchOwnOpenShift(db, storeCode, actor);
    if (!own || own.id === target?.id) return `${why} — người hủy không có ca mở, chưa ghi khoản chi ${p.cash}đ`;
    const res = await runTransaction(ref(db, `${base}/${own.id}`), (cur) => applyShiftDelta(cur, { cashOut: p.cash }));
    return res.committed && res.snapshot.exists() ? `${why} — ghi CHI hoàn tiền ${p.cash}đ vào ca ${code(own)}` : `${why} — chưa ghi được khoản chi ${p.cash}đ`;
  } catch {
    return `${why} — lỗi ghi khoản chi ${p.cash}đ`;
  }
}
