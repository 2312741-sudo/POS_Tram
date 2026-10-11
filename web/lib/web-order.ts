/**
 * Bấm đơn trên Web Admin (dự phòng khi app POS của cửa hàng gặp sự cố).
 *
 * Ghi CÙNG hợp đồng dữ liệu với app Flutter để hai bên đọc lẫn nhau:
 *  - tables/{khóa}: inUse, openedAt (ms), guestCount, currentOrderJson (mảng OrderItemModel),
 *    currentOrderCode, actionLogsJson, xóa prePrintedAt/By khi món thay đổi
 *  - kitchen_orders/{key}: phiếu bếp { tableName, orderCode, billCode, itemsJson, timestamp, isDone,
 *    orderedBy, orderedByName, pickedUp } — chỉ các món chưa gửi bếp
 *  - audit_logs: ghi nhật ký thao tác
 */
import { lineQuantity, setLineQuantity, type RawOrderLine } from "./order-math";
import { CLEAR_PRE_PRINT } from "./table-status";

export interface OrderableProduct {
  id: string;
  name: string;
  price: number;
  category?: string;
  unit?: string;
  isTopping?: boolean;
}

export interface OrderActor {
  username: string;
  fullName?: string;
  role?: string;
}

/** Id món trên RTDB thường là số (Flutter dùng int) — giữ số khi có thể */
export function productIdValue(id: string): number | string {
  const n = Number(id);
  return Number.isInteger(n) && String(n) === id.trim() ? n : id;
}

/** Tạo dòng món mới (chưa gửi bếp) giống OrderItemModel.toMap() */
export function makeOrderLine(product: OrderableProduct, quantity: number, note: string, actor: OrderActor, now: number): RawOrderLine {
  const q = Math.max(1, Math.trunc(quantity) || 1);
  const line: RawOrderLine = {
    productId: productIdValue(product.id),
    name: product.name,
    price: Math.max(0, Math.trunc(product.price) || 0),
    quantity: q,
    note: note.trim(),
    isSentKitchen: false,
    discountAmount: 0,
    lineDiscountTotal: 0,
    discountedQuantity: 0,
    orderedBy: actor.username,
    orderedByName: actor.fullName || actor.username,
    orderedAt: now,
  };
  if (product.category) line.category = product.category;
  if (product.unit) line.unit = product.unit;
  return line;
}

/**
 * Thêm dòng vào đơn: cộng dồn vào dòng CHƯA GỬI BẾP cùng món + cùng ghi chú + không giảm giá
 * (món đã gửi bếp luôn tạo dòng mới để phiếu bếp lần sau chỉ chứa phần mới).
 */
export function addLineToOrder(lines: RawOrderLine[], line: RawOrderLine): RawOrderLine[] {
  const idx = lines.findIndex(
    (l) =>
      l.isSentKitchen !== true &&
      String(l.productId) === String(line.productId) &&
      String(l.note ?? "") === String(line.note ?? "") &&
      !(Number(l.lineDiscountTotal ?? l.discountAmount ?? 0) > 0)
  );
  if (idx < 0) return [...lines, line];
  return lines.map((l, i) => (i === idx ? setLineQuantity(l, lineQuantity(l) + lineQuantity(line)) : l));
}

export function unsentLines(lines: RawOrderLine[]): RawOrderLine[] {
  return lines.filter((l) => l.isSentKitchen !== true);
}

/** Mã đặt món OD-yyMMdd-HHmmss-XXXX giống FormatUtils.orderCode() của POS (giờ Việt Nam) */
export function generateOrderCode(now: number, random: () => number = Math.random): string {
  const d = new Date(now + 7 * 3600_000);
  const p = (n: number) => String(n).padStart(2, "0");
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let suffix = "";
  for (let i = 0; i < 4; i++) suffix += chars[Math.floor(random() * chars.length) % chars.length];
  return `OD-${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}-${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}-${suffix}`;
}

export interface SubmitOrderArgs {
  storeCode: string;
  /** Các khóa nút bàn cần ghi (khóa chính + khóa chuẩn nếu có) */
  tableKeys: string[];
  table: {
    name: string;
    zone?: string;
    inUse?: boolean;
    openedAt?: unknown;
    guestCount?: number;
    currentOrderCode?: string | null;
    currentBillId?: string | null;
    actionLogsJson?: string | null;
  };
  /** Danh sách món hiện có trên server (đã parse) */
  existingLines: RawOrderLine[];
  /** Món mới thêm lần này (chưa gửi bếp) */
  newLines: RawOrderLine[];
  sendKitchen: boolean;
  guestCount?: number;
  kitchenNote?: string;
  actor: OrderActor;
  now: number;
  /** Khóa push cho phiếu bếp (truyền vào để test) */
  kitchenKey?: string;
  nonce?: string;
}

export type SubmitOrderResult =
  | { ok: false; error: string }
  | { ok: true; updates: Record<string, unknown>; mergedLines: RawOrderLine[]; sentCount: number; orderCode: string };

export function buildWebOrderUpdates(a: SubmitOrderArgs): SubmitOrderResult {
  if (a.newLines.length === 0) return { ok: false, error: "Chưa chọn món nào" };
  if (a.tableKeys.length === 0) return { ok: false, error: "Không xác định được bàn" };

  let merged = a.existingLines;
  for (const l of a.newLines) merged = addLineToOrder(merged, l);

  const orderCode = a.table.currentOrderCode || generateOrderCode(a.now);
  const toKitchen = a.sendKitchen ? unsentLines(merged) : [];
  if (a.sendKitchen) merged = merged.map((l) => (l.isSentKitchen === true ? l : { ...l, isSentKitchen: true }));

  const opening = a.table.inUse !== true;
  const summary = a.newLines.map((l) => `${lineQuantity(l)} x ${String(l.name ?? "")}`).join(", ");
  const logs: unknown[] = (() => {
    try {
      const p = a.table.actionLogsJson ? JSON.parse(a.table.actionLogsJson) : [];
      return Array.isArray(p) ? p : [];
    } catch {
      return [];
    }
  })();
  logs.push({
    timestamp: a.now,
    staffUsername: a.actor.username,
    staffFullName: a.actor.fullName || a.actor.username,
    action: a.sendKitchen ? "SEND_KITCHEN" : "ADD_ITEM",
    details: `${opening ? "Mở bàn & g" : "G"}ọi món qua Web Admin: ${summary}${a.sendKitchen ? " (đã gửi bếp)" : ""}`,
  });

  const payload: Record<string, unknown> = {
    inUse: true,
    currentOrderJson: JSON.stringify(merged),
    currentOrderCode: orderCode,
    actionLogsJson: JSON.stringify(logs),
    ...CLEAR_PRE_PRINT,
  };
  if (opening) {
    payload.openedAt = a.now;
    payload.guestCount = Math.max(1, Math.trunc(a.guestCount ?? 1) || 1);
    payload.isReserved = false;
  }

  const base = `stores/${a.storeCode}`;
  const updates: Record<string, unknown> = {};
  for (const key of a.tableKeys) {
    for (const [field, value] of Object.entries(payload)) updates[`${base}/tables/${key}/${field}`] = value;
  }

  if (toKitchen.length > 0) {
    const key = a.kitchenKey ?? `web_${a.now}_${a.nonce ?? Math.floor(Math.random() * 1e6)}`;
    updates[`${base}/kitchen_orders/${key}`] = {
      tableName: a.table.name,
      orderCode,
      ...(a.table.currentBillId ? { billCode: a.table.currentBillId } : {}),
      itemsJson: JSON.stringify(toKitchen),
      timestamp: a.now,
      isDone: false,
      pickedUp: false,
      ...(a.kitchenNote?.trim() ? { note: a.kitchenNote.trim() } : {}),
      orderedBy: a.actor.username,
      orderedByName: a.actor.fullName || a.actor.username,
    };
  }

  updates[`${base}/audit_logs/log_${a.now}_wo_${a.nonce ?? Math.floor(Math.random() * 1e6)}`] = {
    timestamp: a.now,
    username: a.actor.username,
    userFullName: a.actor.fullName || a.actor.username,
    userRole: a.actor.role || "",
    action: "WEB_ORDER",
    targetType: "TABLE",
    targetId: a.table.name,
    storeCode: a.storeCode,
    details: `${opening ? "Mở bàn & g" : "G"}ọi món bàn ${a.table.name} qua Web Admin (dự phòng POS): ${summary}${a.sendKitchen ? " — đã gửi phiếu bếp" : ""}`,
  };

  return { ok: true, updates, mergedLines: merged, sentCount: toKitchen.length, orderCode };
}
