/**
 * Xóa món / giảm số lượng món của đơn ĐÃ LƯU trên bàn — HỢP ĐỒNG CHUNG với Flutter POS.
 *
 * - Bắt buộc chọn lý do (DELETION_REASONS); "Khác" bắt buộc nhập nội dung.
 * - Mỗi lần xóa sinh một DeletedItemEntry, nối vào nút bàn `deletedItemsJson` (chuỗi JSON mảng).
 * - Thanh toán / hủy đơn: hóa đơn + history nhận `deletedItems` (mảng), `deletedItemsCount`
 *   (tổng SỐ PHẦN bị xóa), `deletedItemsAmount` (tổng tiền); trả bàn ghi `deletedItemsJson = null`.
 *   Chuyển bàn mang theo, gộp bàn nối thêm.
 * - Audit log mỗi lần xóa: action "DELETE_ITEM", targetType "ORDER_ITEM".
 *
 * Hàm thuần — không phụ thuộc React/Firebase.
 */
import { lineDiscountTotal, lineQuantity, lineUnitPrice, type RawOrderLine } from "./order-math";

export const DELETION_REASONS = [
  "Khách đổi món",
  "Khách hủy món",
  "Nhập sai",
  "Hết món/hết nguyên liệu",
  "Khác",
] as const;

export type DeletionReason = (typeof DELETION_REASONS)[number];

export const OTHER_REASON: DeletionReason = "Khác";

export interface DeletedItemEntry {
  name: string;
  productId: number | string | null;
  quantity: number;
  /** Đơn giá một phần gồm size + topping */
  unitPrice: number;
  /** Giá trị phần bị xóa sau khi trừ phần giảm giá dòng tương ứng */
  amount: number;
  reason: string;
  staffUsername: string;
  staffFullName: string;
  timestamp: number;
  sentToKitchen: boolean;
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Chuẩn hóa lý do xóa. "Khác" → "Khác: {nội dung}" (bắt buộc nội dung).
 * Trả về { reason } hoặc { error }.
 */
export function resolveDeletionReason(choice: string | null | undefined, otherText?: string | null): { reason?: string; error?: string } {
  const c = (choice || "").trim();
  if (!c) return { error: "Vui lòng chọn lý do xóa món." };
  if (!(DELETION_REASONS as readonly string[]).includes(c)) return { error: "Lý do không hợp lệ." };
  if (c === OTHER_REASON) {
    const t = (otherText || "").trim();
    if (!t) return { error: "Vui lòng nhập lý do cụ thể khi chọn \"Khác\"." };
    return { reason: `${OTHER_REASON}: ${t}` };
  }
  return { reason: c };
}

/** Giá trị của `removeQty` phần trong dòng, sau khi trừ phần giảm giá dòng tương ứng (làm tròn) */
export function deletedAmountOf(line: RawOrderLine, removeQty: number): number {
  const qty = lineQuantity(line);
  const q = Math.min(Math.max(0, Math.trunc(removeQty)), qty);
  const gross = lineUnitPrice(line) * q;
  const discountShare = qty > 0 ? Math.round((lineDiscountTotal(line) * q) / qty) : 0;
  return Math.max(0, gross - discountShare);
}

/** Tạo bản ghi xóa món cho `removeQty` phần của dòng */
export function buildDeletionEntry(args: {
  line: RawOrderLine;
  removeQty: number;
  reason: string;
  staffUsername?: string | null;
  staffFullName?: string | null;
  now: number;
}): DeletedItemEntry {
  const { line, now } = args;
  const qty = Math.min(Math.max(1, Math.trunc(args.removeQty)), lineQuantity(line));
  const pid = line.productId ?? line.id ?? null;
  return {
    name: String(line.name ?? ""),
    productId: pid == null ? null : (pid as number | string),
    quantity: qty,
    unitPrice: lineUnitPrice(line),
    amount: deletedAmountOf(line, qty),
    reason: args.reason,
    staffUsername: (args.staffUsername || "").trim() || "admin_web",
    staffFullName: (args.staffFullName || "").trim() || "Quản trị viên Web",
    timestamp: now,
    sentToKitchen: line.isSentKitchen === true,
  };
}

/**
 * Áp dụng việc xóa `removeQty` phần của dòng `index`: trả về danh sách món mới
 * (bỏ hẳn dòng nếu xóa hết). Hàm giảm số lượng được truyền vào để dùng đúng quy tắc giảm giá dòng.
 */
export function applyLineRemoval(
  items: RawOrderLine[],
  index: number,
  removeQty: number,
  setQty: (line: RawOrderLine, q: number) => RawOrderLine
): RawOrderLine[] {
  const line = items[index];
  if (!line) return items;
  const qty = lineQuantity(line);
  const q = Math.min(Math.max(1, Math.trunc(removeQty)), qty);
  if (q >= qty) return items.filter((_, i) => i !== index);
  return items.map((it, i) => (i === index ? setQty(it, qty - q) : it));
}

/** Đọc một bản ghi xóa món thô (từ JSON / RTDB) an toàn */
export function normalizeDeletedItem(raw: unknown): DeletedItemEntry | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;
  const quantity = Math.max(0, Math.trunc(num(r.quantity ?? r.qty ?? 1)));
  const unitPrice = num(r.unitPrice ?? r.price);
  const amount = r.amount != null ? num(r.amount) : unitPrice * quantity;
  return {
    name: String(r.name ?? r.productName ?? ""),
    productId: (r.productId as number | string | null | undefined) ?? null,
    quantity,
    unitPrice,
    amount: Math.max(0, amount),
    reason: String(r.reason ?? ""),
    staffUsername: String(r.staffUsername ?? ""),
    staffFullName: String(r.staffFullName ?? r.staffUsername ?? ""),
    timestamp: num(r.timestamp),
    sentToKitchen: r.sentToKitchen === true || r.isSentKitchen === true,
  };
}

/** Parse giá trị deletedItemsJson / deletedItems (chuỗi JSON, mảng, hoặc object chỉ mục của RTDB) */
export function parseDeletedItems(v: unknown): DeletedItemEntry[] {
  let arr: unknown[] = [];
  if (typeof v === "string") {
    if (!v) return [];
    try {
      const p = JSON.parse(v);
      if (Array.isArray(p)) arr = p;
    } catch {
      return [];
    }
  } else if (Array.isArray(v)) {
    arr = v;
  } else if (v && typeof v === "object") {
    arr = Object.values(v as Record<string, unknown>);
  }
  return arr.map(normalizeDeletedItem).filter((e): e is DeletedItemEntry => e !== null);
}

/** Nối các bản ghi mới vào chuỗi deletedItemsJson hiện có */
export function appendDeletedItemsJson(existing: unknown, add: DeletedItemEntry[]): string {
  return JSON.stringify([...parseDeletedItems(existing), ...add]);
}

/** Gộp deletedItemsJson của bàn đích + bàn nguồn (gộp bàn); null nếu cả hai rỗng */
export function mergeDeletedItemsJson(target: unknown, source: unknown): string | null {
  const all = [...parseDeletedItems(target), ...parseDeletedItems(source)];
  return all.length > 0 ? JSON.stringify(all) : null;
}

/** Tổng hợp các trường ghi lên hóa đơn khi thanh toán / hủy */
export function billDeletionFields(entries: DeletedItemEntry[]): {
  deletedItems: DeletedItemEntry[];
  deletedItemsCount: number;
  deletedItemsAmount: number;
} {
  return {
    deletedItems: entries,
    deletedItemsCount: entries.reduce((s, e) => s + e.quantity, 0),
    deletedItemsAmount: entries.reduce((s, e) => s + e.amount, 0),
  };
}

const fmt = (n: number) => new Intl.NumberFormat("vi-VN").format(Math.round(n));

/** Nội dung audit chuẩn: "Xóa {qty} x {name} ({amount}đ) bàn {table} — Lý do: {reason}" */
export function deletionDetails(entry: DeletedItemEntry, tableName: string): string {
  return `Xóa ${entry.quantity} x ${entry.name} (${fmt(entry.amount)}đ) bàn ${tableName} — Lý do: ${entry.reason}`;
}

/** Payload audit log DELETE_ITEM cho một lần xóa */
export function buildDeletionAuditLog(args: {
  entry: DeletedItemEntry;
  tableName: string;
  orderCode?: string | null;
  storeCode: string;
  userRole?: string | null;
  extra?: Record<string, unknown>;
}): Record<string, unknown> {
  const { entry, tableName, storeCode } = args;
  return {
    timestamp: entry.timestamp,
    username: entry.staffUsername,
    userFullName: entry.staffFullName,
    userRole: (args.userRole || "").trim() || "STAFF",
    action: "DELETE_ITEM",
    targetType: "ORDER_ITEM",
    targetId: tableName,
    storeCode,
    details: deletionDetails(entry, tableName),
    productName: entry.name,
    productId: entry.productId,
    quantity: entry.quantity,
    unitPrice: entry.unitPrice,
    amount: entry.amount,
    reason: entry.reason,
    tableName,
    orderCode: args.orderCode || "",
    sentToKitchen: entry.sentToKitchen,
    ...(args.extra || {}),
  };
}

// ---------------------------------------------------------------------------
// Báo cáo xóa món
// ---------------------------------------------------------------------------

export interface DeletionRow extends DeletedItemEntry {
  tableName: string;
  billCode: string;
  storeCode?: string;
}

export interface DeletionGroup {
  key: string;
  label: string;
  count: number;
  quantity: number;
  amount: number;
}

export interface DeletionReport {
  /** Số lần xóa */
  entries: number;
  /** Tổng số phần bị xóa */
  quantity: number;
  amount: number;
  rows: DeletionRow[];
  byReason: DeletionGroup[];
  byStaff: DeletionGroup[];
}

/** Nhóm lý do "Khác: ..." về "Khác" khi thống kê */
export function reasonGroupOf(reason: string): string {
  const r = (reason || "").trim();
  if (!r) return "Không rõ";
  if (r === OTHER_REASON || r.startsWith(`${OTHER_REASON}:`)) return OTHER_REASON;
  return r;
}

function group(rows: DeletionRow[], keyOf: (r: DeletionRow) => { key: string; label: string }): DeletionGroup[] {
  const map = new Map<string, DeletionGroup>();
  for (const r of rows) {
    const { key, label } = keyOf(r);
    const g = map.get(key) || { key, label, count: 0, quantity: 0, amount: 0 };
    g.count += 1;
    g.quantity += r.quantity;
    g.amount += r.amount;
    map.set(key, g);
  }
  return Array.from(map.values()).sort((a, b) => b.amount - a.amount || b.quantity - a.quantity);
}

/** Tổng hợp danh sách dòng xóa món (từ hóa đơn hoặc audit log) */
export function summarizeDeletions(rows: DeletionRow[]): DeletionReport {
  const sorted = [...rows].sort((a, b) => b.timestamp - a.timestamp);
  return {
    entries: sorted.length,
    quantity: sorted.reduce((s, r) => s + r.quantity, 0),
    amount: sorted.reduce((s, r) => s + r.amount, 0),
    rows: sorted,
    byReason: group(sorted, (r) => {
      const g = reasonGroupOf(r.reason);
      return { key: g, label: g };
    }),
    byStaff: group(sorted, (r) => {
      const key = r.staffUsername || r.staffFullName || "—";
      return { key, label: r.staffFullName || r.staffUsername || "—" };
    }),
  };
}

interface BillLike {
  status?: string;
  deletedItems?: unknown;
  deletedItemsJson?: unknown;
  tableName?: string;
  billCode?: string;
  orderCode?: string;
  id?: string;
  storeCode?: string;
  [key: string]: unknown;
}

/** Các món đã xóa của một hóa đơn */
export function billDeletedItems(bill: BillLike): DeletedItemEntry[] {
  return parseDeletedItems(bill.deletedItems ?? bill.deletedItemsJson);
}

/** Báo cáo xóa món từ hóa đơn PAID + CANCELLED */
export function deletionReportFromBills(bills: BillLike[]): DeletionReport {
  const rows: DeletionRow[] = [];
  const seen = new Set<string>();
  for (const b of bills) {
    if (b.id) {
      if (seen.has(b.id)) continue;
      seen.add(b.id);
    }
    const status = String(b.status || "PAID").toUpperCase();
    if (status !== "PAID" && status !== "CANCELLED") continue;
    for (const e of billDeletedItems(b)) {
      rows.push({
        ...e,
        tableName: b.tableName || "",
        billCode: b.billCode || b.orderCode || b.id || "",
        storeCode: b.storeCode,
      });
    }
  }
  return summarizeDeletions(rows);
}

interface AuditLike {
  action?: string;
  timestamp?: number | string;
  username?: string;
  userFullName?: string;
  storeCode?: string;
  [key: string]: unknown;
}

/** Báo cáo xóa món từ audit log DELETE_ITEM (gồm cả bàn đang mở) */
export function deletionReportFromAuditLogs(logs: AuditLike[]): DeletionReport {
  const rows: DeletionRow[] = [];
  for (const l of logs) {
    if (l.action !== "DELETE_ITEM") continue;
    const ts = typeof l.timestamp === "number" ? l.timestamp : Date.parse(String(l.timestamp ?? "")) || 0;
    const quantity = Math.max(0, Math.trunc(num(l.quantity ?? 1)));
    rows.push({
      name: String(l.productName ?? ""),
      productId: (l.productId as number | string | null | undefined) ?? null,
      quantity,
      unitPrice: num(l.unitPrice),
      amount: Math.max(0, num(l.amount)),
      reason: String(l.reason ?? ""),
      staffUsername: String(l.username ?? ""),
      staffFullName: String(l.userFullName ?? l.username ?? ""),
      timestamp: ts,
      sentToKitchen: l.sentToKitchen === true,
      tableName: String(l.tableName ?? l.targetId ?? ""),
      billCode: String(l.orderCode ?? ""),
      storeCode: l.storeCode,
    });
  }
  return summarizeDeletions(rows);
}
