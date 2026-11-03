/**
 * Màn hình Bếp trên Web — đọc/ghi stores/{code}/kitchen_orders theo hợp đồng của POS (KitchenOrderModel).
 */
import { describeSelectionNoTopping } from "./product-options";
import { groupToppings } from "./topping-utils";
import { lineQuantity, parseOrderJson } from "./order-math";

export interface KitchenLine {
  name: string;
  quantity: number;
  note: string;
  /** Size / đường / đá (không gồm topping) */
  options: string;
  /** Topping tách riêng, mỗi topping một dòng kèm số phần */
  toppings: { name: string; count: number }[];
  /** Số phần đã bị huỷ (nhân viên xóa món đã gửi bếp) */
  cancelledQty: number;
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
  cancelledAt: number;
  /** Có món bị huỷ (một phần hoặc toàn bộ) */
  hasCancellation: boolean;
  /** Toàn bộ món đã bị huỷ → bếp chỉ cần bấm "Đã biết" */
  fullyCancelled: boolean;
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
    const lines: KitchenLine[] = parseOrderJson(typeof v.itemsJson === "string" ? v.itemsJson : "").map((l) => ({
      name: String(l.name ?? ""),
      quantity: lineQuantity(l),
      note: String(l.note ?? ""),
      options: describeSelectionNoTopping(l),
      toppings: Array.isArray(l.selectedToppings) ? groupToppings(l.selectedToppings) : [],
      cancelledQty: Math.max(0, Math.trunc(num((l as Record<string, unknown>).cancelledQty))),
    }));
    out.push({
      key,
      storeCode,
      tableName: String(v.tableName ?? ""),
      orderCode: String(v.orderCode ?? v.billCode ?? ""),
      timestamp: num(v.timestamp),
      note: String(v.note ?? ""),
      orderedByName: String(v.orderedByName ?? v.orderedBy ?? ""),
      isDone: false,
      lines,
      cancelledAt: num(v.cancelledAt),
      hasCancellation: lines.some((l) => l.cancelledQty > 0),
      fullyCancelled: lines.length > 0 && lines.every((l) => l.cancelledQty >= l.quantity),
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

const itemKey = (m: Record<string, unknown>): string => {
  const tops = Array.isArray(m.selectedToppings) ? m.selectedToppings.map(String).sort() : [];
  return `${String(m.productId ?? "")}|${String(m.selectedSize ?? "")}|${String(m.selectedSugar ?? "")}|${String(m.selectedIce ?? "")}|${tops.join(",")}`;
};

/**
 * Báo bếp HUỶ món: ghi `cancelledQty` vào món tương ứng của các phiếu bếp CHƯA XONG của bàn (mới nhất trước).
 * Khớp Flutter OrderRepository.cancelKitchenItems / cancelKitchenOrdersForTable.
 *  - line + removeQty: huỷ removeQty phần của đúng dòng món (cùng món/size/đường/đá/topping)
 *  - line = null: huỷ TOÀN BỘ món của phiếu (hủy cả đơn / dọn bàn)
 * orderCode rỗng thì khớp theo tên bàn.
 */
export function planKitchenCancel(args: {
  storeCode: string;
  kitchenVal: unknown;
  tableName: string;
  orderCode?: string;
  line: Record<string, unknown> | null;
  removeQty: number;
  now: number;
}): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  if (!args.kitchenVal || typeof args.kitchenVal !== "object") return updates;
  const entries = Object.entries(args.kitchenVal as Record<string, unknown>)
    .filter(([, raw]) => raw && typeof raw === "object")
    .map(([key, raw]) => ({ key, v: raw as Record<string, unknown> }))
    .filter(({ v }) => v.isDone !== true && String(v.tableName ?? "") === args.tableName)
    .filter(({ v }) => !args.orderCode || String(v.orderCode ?? "") === args.orderCode)
    .sort((a, b) => num(b.v.timestamp) - num(a.v.timestamp));
  const want = args.line ? itemKey(args.line) : "";
  let left = args.line ? args.removeQty : Infinity;
  for (const { key, v } of entries) {
    if (left <= 0) break;
    let items: unknown;
    try {
      items = JSON.parse(typeof v.itemsJson === "string" ? v.itemsJson : "[]");
    } catch {
      continue;
    }
    if (!Array.isArray(items)) continue;
    let changed = false;
    for (const raw of items) {
      if (left <= 0) break;
      if (!raw || typeof raw !== "object") continue;
      const it = raw as Record<string, unknown>;
      if (args.line && itemKey(it) !== want) continue;
      const qty = Math.max(1, Math.trunc(num(it.quantity)) || 1);
      const cancelled = Math.max(0, Math.trunc(num(it.cancelledQty)));
      const take = Math.min(qty - cancelled, left);
      if (take <= 0) continue;
      it.cancelledQty = cancelled + take;
      if (args.line) left -= take;
      changed = true;
    }
    if (changed) {
      updates[`stores/${args.storeCode}/kitchen_orders/${key}/itemsJson`] = JSON.stringify(items);
      updates[`stores/${args.storeCode}/kitchen_orders/${key}/cancelledAt`] = args.now;
    }
  }
  return updates;
}
