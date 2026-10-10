/**
 * Chuyển bàn / Gộp bàn — hàm thuần, khớp Flutter:
 *   app_flutter/lib/data/repositories/order_repository.dart (transferTable / mergeTables)
 *   app_flutter/lib/core/domain/order_integrity.dart (OrderLineMerger)
 *
 * Ghi bằng MỘT update() đa đường dẫn tại gốc (bàn nguồn + bàn đích + audit log) — không bao giờ
 * áp dụng một nửa. Web chỉ ghi các TRƯỜNG đơn hàng (không ghi đè cả nút bàn như Flutter), nên
 * các trường khác của bàn (capacity, đặt trước...) được giữ nguyên.
 *
 * prePrintedAt ("Chờ thanh toán"):
 *   - Chuyển bàn: đi theo đơn sang bàn đích.
 *   - Gộp bàn: xóa ở bàn nguồn (đã trả) và XÓA ở bàn đích (món đã đổi, phiếu cũ không còn khớp).
 */
import {
  lineDiscountTotal,
  lineDiscountedQuantity,
  lineQuantity,
  parseOrderJson,
  toppingLabel,
  type RawOrderLine,
} from "./order-math";
import { CLEAR_PRE_PRINT, prePrintedAtOf } from "./table-status";
import { mergeDeletedItemsJson } from "./item-deletion";

function int(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}
function str(v: unknown): string {
  return v == null ? "" : String(v);
}

/** Chế độ giảm giá dòng giống Flutter OrderItemModel.discountMode */
function discountModeOf(it: RawOrderLine): string {
  if (int(it.discountPercent) > 0) return "PERCENT";
  if (int(it.discountUnitAmount) > 0) return "AMOUNT";
  const stored = it.lineDiscountTotal != null ? int(it.lineDiscountTotal) : int(it.discountAmount);
  if (stored > 0) return "FIXED";
  return "NONE";
}

/**
 * Khóa cấu hình dòng món (port OrderLineMerger.lineKey): chỉ các dòng có khóa giống nhau mới được
 * cộng dồn số lượng. Gồm món, giá, size, đường, đá, topping (đã sắp xếp), ghi chú, cấu hình giảm giá
 * dòng (chế độ / % / đ mỗi phần / lý do) và trạng thái đã gửi bếp.
 */
export function orderLineKey(it: RawOrderLine): string {
  const productId = Number.isFinite(Number(it.productId)) && it.productId != null ? int(it.productId) : int(it.id);
  const toppings = (Array.isArray(it.selectedToppings) ? it.selectedToppings : []).map(toppingLabel).sort();
  return JSON.stringify([
    productId,
    int(it.price),
    str(it.selectedSize),
    int(it.sizeExtraPrice),
    str(it.selectedSugar),
    str(it.selectedIce),
    toppings,
    int(it.toppingPrice),
    str(it.note).trim(),
    discountModeOf(it),
    int(it.discountPercent),
    int(it.discountUnitAmount),
    str(it.discountReason),
    it.isSentKitchen === true,
  ]);
}

/**
 * Gộp source vào target (port OrderLineMerger.merge). Không sửa mảng đầu vào.
 * Dòng trùng khóa: cộng số lượng, số phần được giảm và tổng giảm ĐÃ LƯU (không tính lại),
 * để tổng tiền sau gộp đúng bằng tổng 2 dòng trước gộp.
 */
export function mergeOrderLines(target: RawOrderLine[], source: RawOrderLine[]): RawOrderLine[] {
  const result = target.map((e) => ({ ...e }));
  const index = new Map<string, number>();
  result.forEach((it, i) => {
    const k = orderLineKey(it);
    if (!index.has(k)) index.set(k, i);
  });
  for (const item of source) {
    const k = orderLineKey(item);
    const idx = index.get(k);
    if (idx != null) {
      const existing = result[idx];
      const next: RawOrderLine = { ...existing, quantity: lineQuantity(existing) + lineQuantity(item) };
      delete next.count;
      const discount = lineDiscountTotal(existing) + lineDiscountTotal(item);
      const hadDiscountFields =
        existing.lineDiscountTotal != null || existing.discountAmount != null || item.lineDiscountTotal != null || item.discountAmount != null;
      if (discount > 0 || hadDiscountFields) {
        next.discountedQuantity = lineDiscountedQuantity(existing) + lineDiscountedQuantity(item);
        next.lineDiscountTotal = discount;
        next.discountAmount = discount;
      }
      result[idx] = next;
    } else {
      result.push({ ...item });
      index.set(k, result.length - 1);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Payload chuyển / gộp bàn
// ---------------------------------------------------------------------------

/** Nút bàn thô (đọc từ RTDB hoặc TableItem của web) */
export interface TableNode {
  name?: unknown;
  zone?: unknown;
  inUse?: unknown;
  isReserved?: unknown;
  currentOrderJson?: unknown;
  openedAt?: unknown;
  guestCount?: unknown;
  currentBillId?: unknown;
  currentOrderCode?: unknown;
  actionLogsJson?: unknown;
  actionLogs?: unknown;
  mergedIntoTable?: unknown;
  prePrintedAt?: unknown;
  prePrintedBy?: unknown;
  /** Món đã xóa khỏi đơn đang mở (chuỗi JSON mảng — hợp đồng chung với Flutter) */
  deletedItemsJson?: unknown;
  [key: string]: unknown;
}

export interface TableActor {
  username?: string | null;
  fullName?: string | null;
  roleId?: string | null;
}

export interface ActionLogEntry {
  timestamp: number;
  staffUsername: string;
  staffFullName: string;
  action: string;
  details: string;
}

const isInUse = (t: TableNode) => t.inUse === true || t.inUse === 1 || String(t.inUse).toLowerCase() === "true";
const isReserved = (t: TableNode) => t.isReserved === true || String(t.isReserved).toLowerCase() === "true";
const nameOf = (t: TableNode) => str(t.name);
const orderJsonOf = (t: TableNode) => (typeof t.currentOrderJson === "string" ? t.currentOrderJson : "");

/** Danh sách món của bàn */
export function tableItems(t: TableNode): RawOrderLine[] {
  return parseOrderJson(orderJsonOf(t));
}

function actionLogsOf(t: TableNode): unknown[] {
  if (typeof t.actionLogsJson === "string" && t.actionLogsJson) {
    try {
      const p = JSON.parse(t.actionLogsJson);
      if (Array.isArray(p)) return p;
    } catch {
      // JSON hỏng — bỏ qua nhật ký cũ
    }
    return [];
  }
  return Array.isArray(t.actionLogs) ? [...t.actionLogs] : [];
}

/** openedAt (epoch ms hoặc ISO) → ms, null nếu không hợp lệ */
export function openedAtMs(v: unknown): number | null {
  if (v == null || v === "") return null;
  if (typeof v === "number") return Number.isFinite(v) && v > 0 ? v : null;
  const s = String(v);
  const n = Number(s);
  if (Number.isFinite(n) && n > 0) return n;
  const d = Date.parse(s);
  return Number.isFinite(d) ? d : null;
}

function guestsOf(t: TableNode): number {
  const n = int(t.guestCount);
  return n > 0 ? n : 0;
}

/**
 * Chữ ký các trường quyết định của bàn — dùng để phát hiện bàn đã đổi trên thiết bị khác
 * giữa lúc người dùng mở hộp thoại và lúc ghi.
 */
export function tableSignature(t: TableNode | null | undefined): string {
  if (!t) return "null";
  return JSON.stringify([
    isInUse(t),
    isReserved(t),
    tableItems(t),
    str(t.currentBillId),
    str(t.mergedIntoTable),
    prePrintedAtOf(t),
  ]);
}

/** Đã thay đổi so với bản người dùng đang xem? */
export function tableChanged(local: TableNode, server: TableNode | null | undefined): boolean {
  return tableSignature(local) !== tableSignature(server);
}

/** Kiểm tra điều kiện chuyển bàn (bàn đích phải trống, không đặt trước) */
export function validateTransfer(source: TableNode, target: TableNode | null | undefined, sameKey = false): string | null {
  if (!target) return "Không tìm thấy bàn đích.";
  if (sameKey || (nameOf(source) === nameOf(target) && str(source.zone) === str(target.zone))) return "Bàn đích trùng bàn nguồn.";
  if (!isInUse(source)) return `${nameOf(source)} không còn khách để chuyển.`;
  if (isInUse(target)) return `${nameOf(target)} đang có khách — dùng "Gộp bàn" thay vì chuyển.`;
  if (isReserved(target)) return `${nameOf(target)} đang được đặt trước.`;
  return null;
}

/** Kiểm tra điều kiện gộp bàn (cả hai bàn đang có khách) */
export function validateMerge(source: TableNode, target: TableNode | null | undefined, sameKey = false): string | null {
  if (!target) return "Không tìm thấy bàn đích.";
  if (sameKey || (nameOf(source) === nameOf(target) && str(source.zone) === str(target.zone))) return "Bàn đích trùng bàn nguồn.";
  if (!isInUse(source)) return `${nameOf(source)} không còn khách để gộp.`;
  if (!isInUse(target)) return `${nameOf(target)} không có khách — dùng "Chuyển bàn" thay vì gộp.`;
  return null;
}

/** Trường của bàn sau khi trả bàn (giống Flutter TableModel.clearTable) */
export const CLEARED_TABLE_FIELDS = {
  inUse: false,
  currentOrderJson: "",
  openedAt: null,
  guestCount: null,
  currentBillId: null,
  currentOrderCode: null,
  mergedIntoTable: null,
  actionLogsJson: null,
  deletedItemsJson: null,
  ...CLEAR_PRE_PRINT,
} as const;

function itemNames(items: RawOrderLine[]): string {
  return items.map((e) => `${str(e.name)} (x${lineQuantity(e)})`).join(", ");
}

function actorNames(actor: TableActor) {
  return {
    username: (actor.username || "").trim() || "admin_web",
    fullName: (actor.fullName || "").trim() || "Quản trị viên Web",
    role: (actor.roleId || "").trim() || "STAFF",
  };
}

export interface TableOpPayloads {
  sourceFields: Record<string, unknown>;
  targetFields: Record<string, unknown>;
  audit: Record<string, unknown>;
}

/** Payload chuyển bàn: đơn (kèm bill/mã đơn/nhật ký/khách/giờ mở/tạm tính) sang bàn đích, dọn bàn nguồn */
export function buildTransferPayloads(args: {
  source: TableNode;
  target: TableNode;
  actor: TableActor;
  now: number;
  storeCode: string;
}): TableOpPayloads {
  const { source, target, now, storeCode } = args;
  const a = actorNames(args.actor);
  const items = tableItems(source);
  const sName = nameOf(source);
  const tName = nameOf(target);
  const logs = actionLogsOf(source);
  const entry: ActionLogEntry = {
    timestamp: now,
    staffUsername: a.username,
    staffFullName: a.fullName,
    action: "TRANSFER_TABLE",
    details: `Chuyển toàn bộ món từ ${sName} sang ${tName}`,
  };
  logs.push(entry);
  const pre = prePrintedAtOf(source);
  const preBy = str(source.prePrintedBy).trim();
  const guests = guestsOf(source);
  return {
    targetFields: {
      inUse: true,
      currentOrderJson: orderJsonOf(source),
      openedAt: source.openedAt ?? null,
      guestCount: guests > 0 ? guests : null,
      currentBillId: source.currentBillId ?? null,
      currentOrderCode: source.currentOrderCode ?? null,
      mergedIntoTable: null,
      actionLogsJson: JSON.stringify(logs),
      // Món đã xóa đi theo đơn sang bàn đích
      deletedItemsJson: typeof source.deletedItemsJson === "string" && source.deletedItemsJson ? source.deletedItemsJson : null,
      // "Chờ thanh toán" đi theo đơn sang bàn đích
      prePrintedAt: pre,
      prePrintedBy: pre != null && preBy ? preBy : null,
    },
    sourceFields: { ...CLEARED_TABLE_FIELDS },
    audit: {
      timestamp: now,
      username: a.username,
      userFullName: a.fullName,
      userRole: a.role,
      action: "TRANSFER_TABLE",
      targetType: "TABLE",
      targetId: `${sName} -> ${tName}`,
      storeCode,
      details: `${a.fullName} chuyển bàn từ ${sName} sang ${tName} (${items.length} món: ${itemNames(items)}) qua Web Admin`,
    },
  };
}

/** Payload gộp bàn: cộng dồn dòng giống hệt nhau vào bàn đích, bàn nguồn trả về trống + mergedIntoTable */
export function buildMergePayloads(args: {
  source: TableNode;
  target: TableNode;
  actor: TableActor;
  now: number;
  storeCode: string;
}): TableOpPayloads {
  const { source, target, now, storeCode } = args;
  const a = actorNames(args.actor);
  const sourceItems = tableItems(source);
  const combined = mergeOrderLines(tableItems(target), sourceItems);
  const sName = nameOf(source);
  const tName = nameOf(target);
  const names = itemNames(sourceItems);

  const guests = guestsOf(target) + guestsOf(source);
  // Giờ mở bàn = sớm nhất của 2 bàn (giữ nguyên định dạng gốc), không có thì lấy hiện tại
  const tOpen = openedAtMs(target.openedAt);
  const sOpen = openedAtMs(source.openedAt);
  let openedAt: unknown = target.openedAt ?? null;
  if (tOpen == null || (sOpen != null && sOpen < tOpen)) {
    openedAt = sOpen != null ? source.openedAt : tOpen != null ? target.openedAt : now;
  }

  const logs = actionLogsOf(target);
  const entry: ActionLogEntry = {
    timestamp: now,
    staffUsername: a.username,
    staffFullName: a.fullName,
    action: "MERGE_TABLE",
    details: `Gộp ${sName} vào ${tName}: chuyển ${sourceItems.length} món (${names})`,
  };
  logs.push(entry);

  return {
    targetFields: {
      inUse: true,
      currentOrderJson: JSON.stringify(combined),
      guestCount: guests > 0 ? guests : null,
      openedAt,
      actionLogsJson: JSON.stringify(logs),
      // Món đã xóa của bàn nguồn nối vào bàn đích
      deletedItemsJson: mergeDeletedItemsJson(target.deletedItemsJson, source.deletedItemsJson),
      // Đơn gộp khác phiếu tạm tính cũ → bàn đích quay về "Có khách"
      ...CLEAR_PRE_PRINT,
    },
    sourceFields: { ...CLEARED_TABLE_FIELDS, mergedIntoTable: tName },
    audit: {
      timestamp: now,
      username: a.username,
      userFullName: a.fullName,
      userRole: a.role,
      action: "MERGE_TABLE",
      targetType: "TABLE",
      targetId: `${sName} -> ${tName}`,
      storeCode,
      details: `${a.fullName} gộp ${sName} vào ${tName} (chuyển ${sourceItems.length} món: ${names} sang ${tName}) qua Web Admin`,
    },
  };
}

/** Ghép payload thành map update() đa đường dẫn tại gốc DB */
export function buildTableOpUpdates(args: {
  storeCode: string;
  sourceKeys: string[];
  targetKeys: string[];
  payloads: TableOpPayloads;
  logId: string;
}): Record<string, unknown> {
  const { storeCode, sourceKeys, targetKeys, payloads, logId } = args;
  const overlap = sourceKeys.some((k) => targetKeys.includes(k));
  if (overlap) throw new Error("Bàn nguồn và bàn đích trùng khóa.");
  const updates: Record<string, unknown> = {};
  const put = (keys: string[], fields: Record<string, unknown>) => {
    for (const key of keys) {
      for (const [f, v] of Object.entries(fields)) updates[`stores/${storeCode}/tables/${key}/${f}`] = v;
    }
  };
  put(sourceKeys, payloads.sourceFields);
  put(targetKeys, payloads.targetFields);
  updates[`stores/${storeCode}/audit_logs/${logId}`] = payloads.audit;
  return updates;
}
