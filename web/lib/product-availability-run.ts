/**
 * Ghi trạng thái báo hết món lên RTDB + nhật ký thao tác (phần có Firebase của lib/product-availability.ts).
 */
import { ref, set, update, type Database } from "firebase/database";
import { soldOutPatch } from "./product-availability";

export interface SoldOutWriteArgs {
  storeCode: string;
  productKey: string;
  productName: string;
  soldOut: boolean;
  untilNextReset?: boolean;
  actor: { username: string; fullName?: string; role?: string };
}

export async function writeSoldOut(db: Database, a: SoldOutWriteArgs): Promise<void> {
  const now = Date.now();
  await update(
    ref(db, `stores/${a.storeCode}/products/${a.productKey}`),
    soldOutPatch({ soldOut: a.soldOut, by: a.actor.username, now, untilNextReset: a.untilNextReset })
  );
  await set(ref(db, `stores/${a.storeCode}/audit_logs/LOG_${now}`), {
    action: a.soldOut ? "SET_SOLD_OUT" : "SET_AVAILABLE",
    targetType: "PRODUCT",
    targetId: a.productName,
    productName: a.productName,
    details: a.soldOut ? `Báo hết ${a.productName}` : `Bật lại ${a.productName}`,
    timestamp: now,
    userRole: a.actor.role || "",
    username: a.actor.username,
    userFullName: a.actor.fullName || "",
    storeCode: a.storeCode,
  });
}
