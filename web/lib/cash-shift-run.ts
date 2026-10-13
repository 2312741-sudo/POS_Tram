/**
 * Phần có Firebase của lib/cash-shift.ts: đọc ca của tài khoản, cộng doanh số khi thanh toán trên Web.
 */
import { equalTo, get, orderByChild, query, ref, runTransaction, type Database } from "firebase/database";
import { applyShiftDelta, findOwnOpenShift, paymentKindOf, type ShiftLike } from "./cash-shift";

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
