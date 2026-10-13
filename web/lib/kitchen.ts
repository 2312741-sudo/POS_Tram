/**
 * Màn hình Bếp trên Web — đọc/ghi stores/{code}/kitchen_orders theo hợp đồng của POS (KitchenOrderModel).
 */
import { describeSelection } from "./product-options";
import { lineQuantity, parseOrderJson } from "./order-math";

export interface KitchenLine {
  name: string;
  quantity: number;
  note: string;
  options: string;
}

export interface KitchenTicket {
  key: string;
  storeCode: string;
  tableName: string;
  orderCode: string;
  timestamp: number;
  note: string;
  orderedByName: string;
  isDone: boolean;
  lines: KitchenLine[];
}

const num = (v: unknown) => (Number.isFinite(Number(v)) ? Number(v) : 0);

/** Phiếu bếp chưa xong, cũ nhất trước (bếp làm theo thứ tự gọi) */
export function parseKitchenTickets(storeCode: string, val: unknown): KitchenTicket[] {
  if (!val || typeof val !== "object") return [];
  const out: KitchenTicket[] = [];
  for (const [key, raw] of Object.entries(val as Record<string, unknown>)) {
    if (!raw || typeof raw !== "object") continue;
    const v = raw as Record<string, unknown>;
    if (v.isDone === true) continue;
    out.push({
      key,
      storeCode,
      tableName: String(v.tableName ?? ""),
      orderCode: String(v.orderCode ?? v.billCode ?? ""),
      timestamp: num(v.timestamp),
      note: String(v.note ?? ""),
      orderedByName: String(v.orderedByName ?? v.orderedBy ?? ""),
      isDone: false,
      lines: parseOrderJson(typeof v.itemsJson === "string" ? v.itemsJson : "").map((l) => ({
        name: String(l.name ?? ""),
        quantity: lineQuantity(l),
        note: String(l.note ?? ""),
        options: describeSelection(l),
      })),
    });
  }
  return out.sort((a, b) => a.timestamp - b.timestamp || a.key.localeCompare(b.key));
}

/** Bấm "Xong": giống OrderRepository.markKitchenOrderDone (isDone, doneAt, pickedUp=false) */
export function buildMarkDoneUpdates(storeCode: string, key: string, now: number): Record<string, unknown> {
  const base = `stores/${storeCode}/kitchen_orders/${key}`;
  return { [`${base}/isDone`]: true, [`${base}/doneAt`]: now, [`${base}/pickedUp`]: false };
}

/** Thời điểm hiện tại (ms) — tách ra để không gọi Date.now trực tiếp trong component */
export const nowMs = () => Date.now();

export function waitingMinutes(ticket: Pick<KitchenTicket, "timestamp">, now: number): number {
  return Math.max(0, Math.floor((now - ticket.timestamp) / 60000));
}
