/**
 * Đo tốc độ phục vụ Bếp (SOS / SLA) trên Web Admin
 * Tính toán thời gian từ lúc gửi bếp đến khi hoàn tất theo từng đơn và từng món.
 */
import { parseOrderJson, lineQuantity } from "./order-math";

export const KITCHEN_GROUP_DRINK = "drink";
export const KITCHEN_GROUP_FOOD = "food";

export function kitchenGroupOfCategory(category: string, name?: string): string {
  const c = `${category || ""} ${name || ""}`.toLowerCase();
  const foodWords = [
    "bánh",
    "banh",
    "cake",
    "ăn",
    "food",
    "snack",
    "tráng miệng",
    "dessert",
    "xôi",
    "cơm",
    "mì ",
    "phở",
    "khoai tây",
    "xúc xích",
  ];
  for (const w of foodWords) {
    if (c.includes(w)) return KITCHEN_GROUP_FOOD;
  }
  return KITCHEN_GROUP_DRINK;
}

export function kitchenGroupLabel(group?: string | null): string {
  if (group === KITCHEN_GROUP_DRINK) return "Nước";
  if (group === KITCHEN_GROUP_FOOD) return "Bánh";
  return "Chung";
}

export interface KitchenSlaItem {
  orderKey: string;
  tableName: string;
  itemName: string;
  quantity: number;
  group: string;
  sentAt: number;
  doneAt: number;
  durationMs: number;
}

export interface KitchenSlaOrder {
  orderKey: string;
  tableName: string;
  orderCode: string;
  sentAt: number;
  doneAt: number;
  durationMs: number;
  itemCount: number;
  isPartialSplit: boolean;
  isLate: boolean;
}

export interface KitchenSlaSummary {
  orders: KitchenSlaOrder[];
  items: KitchenSlaItem[];
  averageOrderMs: number;
  maxOrderMs: number;
  averageItemMs: number;
  maxItemMs: number;
  lateOrderCount: number;
  thresholdMinutes: number;
}

export function formatDurationMs(ms: number): string {
  if (ms <= 0) return "0 gi";
  const totalSeconds = Math.round(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes === 0) return `${seconds} gi`;
  return `${minutes} p ${seconds.toString().padStart(2, "0")} gi`;
}

const num = (v: unknown): number => (Number.isFinite(Number(v)) ? Number(v) : 0);

interface RawTicket {
  tableName?: string;
  orderCode?: string;
  billCode?: string;
  itemsJson?: string;
  timestamp?: number;
  doneAt?: number;
  isDone?: boolean;
  batchId?: string;
  itemGroup?: string;
}

export function computeKitchenSla(
  rawTickets: Record<string, unknown> | null | undefined,
  fromMs: number,
  toMs: number,
  thresholdMinutes: number = 15
): KitchenSlaSummary {
  if (!rawTickets || typeof rawTickets !== "object") {
    return {
      orders: [],
      items: [],
      averageOrderMs: 0,
      maxOrderMs: 0,
      averageItemMs: 0,
      maxItemMs: 0,
      lateOrderCount: 0,
      thresholdMinutes,
    };
  }

  const thresholdMs = thresholdMinutes * 60 * 1000;

  // Lọc các phiếu đã xong nằm trong khoảng thời gian báo cáo
  const finishedTickets: Array<{ key: string; data: RawTicket }> = [];
  for (const [key, raw] of Object.entries(rawTickets)) {
    if (!raw || typeof raw !== "object") continue;
    const t = raw as RawTicket;
    if (t.isDone !== true) continue;
    const doneAt = num(t.doneAt) || num(t.timestamp);
    if (doneAt >= fromMs && doneAt <= toMs) {
      finishedTickets.push({ key, data: t });
    }
  }

  // Phân rã từng dòng món
  const items: KitchenSlaItem[] = [];
  for (const { key, data } of finishedTickets) {
    const sentAt = num(data.timestamp);
    const doneAt = num(data.doneAt) || sentAt;
    const durationMs = Math.max(0, doneAt - sentAt);
    const tableName = String(data.tableName ?? "");
    const batchKey = String(data.batchId || key);

    const parsedLines = parseOrderJson(typeof data.itemsJson === "string" ? data.itemsJson : "");
    for (const l of parsedLines) {
      const cat = String(l.category ?? "");
      const name = String(l.name ?? "Món");
      const grp = String(l.kitchenGroup || data.itemGroup || kitchenGroupOfCategory(cat, name));
      items.push({
        orderKey: batchKey,
        tableName,
        itemName: name,
        quantity: Math.max(1, lineQuantity(l)),
        group: grp,
        sentAt,
        doneAt,
        durationMs,
      });
    }
  }

  // Gộp theo đơn (cùng batchId hoặc key gốc)
  const orderGroups = new Map<string, Array<{ key: string; data: RawTicket }>>();
  for (const item of finishedTickets) {
    const batchKey = String(item.data.batchId || item.key);
    const existing = orderGroups.get(batchKey) ?? [];
    existing.push(item);
    orderGroups.set(batchKey, existing);
  }

  const orders: KitchenSlaOrder[] = [];
  for (const [batchKey, tickets] of orderGroups.entries()) {
    const first = tickets[0].data;
    const tableName = String(first.tableName ?? "");
    const orderCode = String(first.orderCode ?? first.billCode ?? batchKey);

    let sentAt = Number.MAX_SAFE_INTEGER;
    let doneAt = 0;
    let totalItems = 0;

    for (const { data } of tickets) {
      const s = num(data.timestamp);
      const d = num(data.doneAt) || s;
      if (s < sentAt) sentAt = s;
      if (d > doneAt) doneAt = d;

      const lines = parseOrderJson(typeof data.itemsJson === "string" ? data.itemsJson : "");
      totalItems += lines.reduce((acc, l) => acc + Math.max(1, lineQuantity(l)), 0);
    }

    if (sentAt === Number.MAX_SAFE_INTEGER) sentAt = doneAt;
    const durationMs = Math.max(0, doneAt - sentAt);
    const isLate = durationMs > thresholdMs;

    orders.push({
      orderKey: batchKey,
      tableName,
      orderCode,
      sentAt,
      doneAt,
      durationMs,
      itemCount: totalItems,
      isPartialSplit: tickets.length > 1,
      isLate,
    });
  }

  // Sắp xếp đơn mới nhất trước
  orders.sort((a, b) => b.doneAt - a.doneAt);
  items.sort((a, b) => b.doneAt - a.doneAt);

  // Thống kê tổng hợp
  const totalOrderMs = orders.reduce((acc, o) => acc + o.durationMs, 0);
  const averageOrderMs = orders.length > 0 ? Math.round(totalOrderMs / orders.length) : 0;
  const maxOrderMs = orders.reduce((max, o) => Math.max(max, o.durationMs), 0);

  const totalItemMs = items.reduce((acc, it) => acc + it.durationMs, 0);
  const averageItemMs = items.length > 0 ? Math.round(totalItemMs / items.length) : 0;
  const maxItemMs = items.reduce((max, it) => Math.max(max, it.durationMs), 0);

  const lateOrderCount = orders.filter((o) => o.isLate).length;

  return {
    orders,
    items,
    averageOrderMs,
    maxOrderMs,
    averageItemMs,
    maxItemMs,
    lateOrderCount,
    thresholdMinutes,
  };
}
