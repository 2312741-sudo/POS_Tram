/**
 * Trạng thái bàn dùng chung giữa web và Flutter POS.
 *
 * HỢP ĐỒNG (chung với Flutter): nút bàn có thể có
 *   prePrintedAt: number (epoch ms) — thời điểm in phiếu tạm tính
 *   prePrintedBy?: string           — username người in
 * Bàn đang có khách + có prePrintedAt ⇒ "Chờ thanh toán".
 * Trường bị XÓA (ghi null) khi: thanh toán, trả/hủy bàn, và mỗi khi danh sách món thay đổi sau khi in.
 */
import type { RawOrderLine } from "./order-math";

export type TableStatus = "EMPTY" | "IN_USE" | "RESERVED" | "AWAITING_PAYMENT";

export interface TableStatusSource {
  inUse?: boolean | unknown;
  isReserved?: boolean | unknown;
  prePrintedAt?: number | string | null | unknown;
}

/** Thời điểm in tạm tính hợp lệ (epoch ms > 0), ngược lại null */
export function prePrintedAtOf(t: TableStatusSource): number | null {
  const n = Number(t.prePrintedAt);
  return Number.isFinite(n) && n > 0 ? n : null;
}

export function deriveTableStatus(t: TableStatusSource): TableStatus {
  if (t.inUse === true) return prePrintedAtOf(t) != null ? "AWAITING_PAYMENT" : "IN_USE";
  if (t.isReserved === true) return "RESERVED";
  return "EMPTY";
}

/** Nhãn + token màu (định nghĩa trong app/globals.css, có bản sáng/tối) cho từng trạng thái */
export const TABLE_STATUS_META: Record<TableStatus, { label: string; color: string; bg: string }> = {
  EMPTY: { label: "Trống", color: "var(--table-empty)", bg: "var(--table-empty-bg)" },
  IN_USE: { label: "Có khách", color: "var(--table-in-use)", bg: "var(--table-in-use-bg)" },
  RESERVED: { label: "Đặt trước", color: "var(--table-reserved)", bg: "var(--table-reserved-bg)" },
  AWAITING_PAYMENT: { label: "Chờ thanh toán", color: "var(--table-awaiting)", bg: "var(--table-awaiting-bg)" },
};

export const TABLE_STATUS_ORDER: TableStatus[] = ["EMPTY", "IN_USE", "RESERVED", "AWAITING_PAYMENT"];

/** Payload xóa đánh dấu in tạm tính (null trong update() RTDB = xóa trường) */
export const CLEAR_PRE_PRINT = { prePrintedAt: null, prePrintedBy: null } as const;

/** Payload đánh dấu đã in tạm tính */
export function prePrintPayload(now: number, username?: string | null): { prePrintedAt: number; prePrintedBy: string | null } {
  const by = (username || "").trim();
  return { prePrintedAt: now, prePrintedBy: by ? by : null };
}

/** So sánh nội dung danh sách món (theo JSON chuẩn hóa) */
export function orderItemsChanged(prev: RawOrderLine[], next: RawOrderLine[]): boolean {
  return JSON.stringify(prev) !== JSON.stringify(next);
}

/**
 * Payload ghi danh sách món mới cho bàn. Nếu món thay đổi thì luôn xóa đánh dấu in tạm tính
 * (phiếu đã in không còn khớp). Trả về null nếu không có gì thay đổi.
 */
export function buildOrderItemsPayload(
  prev: RawOrderLine[],
  next: RawOrderLine[]
): Record<string, unknown> | null {
  if (!orderItemsChanged(prev, next)) return null;
  return { currentOrderJson: JSON.stringify(next), ...CLEAR_PRE_PRINT };
}
