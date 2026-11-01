/**
 * Reset dữ liệu bán hàng của MỘT cửa hàng (bắt đầu vận hành lại) — logic thuần, test ở test/sales-reset.test.ts.
 *
 * XÓA: hóa đơn / lịch sử, phiếu bếp, đơn online, gọi phục vụ, sự kiện thanh toán, ca két,
 *      dấu trừ kho theo hóa đơn (không đổi tồn kho); bàn đưa về TRỐNG (bàn tách tự động thì xóa hẳn).
 * GIỮ: thực đơn, bàn / khu vực, nhân viên, khách hàng, kho, khuyến mãi, nhật ký kiểm soát.
 * Bộ đếm số hóa đơn (counters/bill_seq) không xóa được theo rules — đếm theo ngày nên ngày mới tự bắt đầu từ 0001.
 *
 * Rules RTDB chỉ cho xóa từng phần tử con (vd history/{id}) nên mọi đường dẫn đều ở cấp phần tử.
 */
import { CLEARED_TABLE_FIELDS } from "./table-ops";

export interface ResetGroup {
  key: string;
  label: string;
  /** Node con dưới stores/{storeCode} */
  nodes: string[];
  /** Mặc định chọn */
  defaultOn: boolean;
}

export const RESET_GROUPS: ResetGroup[] = [
  { key: "bills", label: "Hóa đơn & lịch sử bán hàng", nodes: ["history", "bills"], defaultOn: true },
  { key: "kitchen", label: "Phiếu bếp & gọi phục vụ", nodes: ["kitchen_orders", "staff_calls"], defaultOn: true },
  { key: "online", label: "Đơn online (QR)", nodes: ["online_orders"], defaultOn: true },
  { key: "payments", label: "Sự kiện thanh toán (QR ngân hàng)", nodes: ["payment_events"], defaultOn: true },
  { key: "shifts", label: "Ca két (mở / đóng ca)", nodes: ["cash_shifts"], defaultOn: true },
  { key: "stockMarks", label: "Dấu trừ kho theo hóa đơn (không đổi tồn kho)", nodes: ["bill_stock_applied", "bill_stock_lines", "stock_retry_queue"], defaultOn: true },
  { key: "promoCounters", label: "Lượt đã dùng khuyến mãi (đếm lại từ 0)", nodes: ["campaign_counters", "customer_campaign_counters"], defaultOn: false },
];

/** Trường đưa bàn về TRỐNG: như trả bàn + bỏ đặt trước, khóa đang gọi món, giảm giá treo */
export const RESET_TABLE_FIELDS: Record<string, unknown> = {
  ...CLEARED_TABLE_FIELDS,
  discountsJson: null,
  orderingBy: null,
  orderingByName: null,
  orderingAt: null,
  isReserved: false,
  reservationCustomer: null,
  reservationPhone: null,
  reservationTime: null,
  reservationDeposit: 0,
};

type Snap = Record<string, unknown> | null | undefined;

/** Bàn tách tự động ("Bàn 01 (2)", "Mang về (2)") — khớp TableModel.isAutoSplit (Dart) */
export function isAutoSplitTable(t: Record<string, unknown>): boolean {
  return t.isSplitTable === true || /\s\(\d+\)\s*$/.test(String(t.name ?? "").trim());
}

const keysOf = (v: Snap) => (v && typeof v === "object" ? Object.keys(v) : []);

export interface ResetPlan {
  /** Đường dẫn tuyệt đối → giá trị (null = xóa) */
  updates: Record<string, unknown>;
  /** Số phần tử bị xóa theo node */
  counts: Record<string, number>;
  tablesCleared: number;
  tablesRemoved: number;
}

/**
 * Dựng các lệnh ghi: [data] = giá trị đã đọc của từng node (stores/{storeCode}/{node}), [tables] = node tables.
 */
export function buildResetPlan(storeCode: string, groupKeys: string[], data: Record<string, Snap>, tables: Snap): ResetPlan {
  const base = `stores/${storeCode}`;
  const updates: Record<string, unknown> = {};
  const counts: Record<string, number> = {};
  for (const g of RESET_GROUPS) {
    if (!groupKeys.includes(g.key)) continue;
    for (const node of g.nodes) {
      const keys = keysOf(data[node]);
      counts[node] = keys.length;
      for (const k of keys) updates[`${base}/${node}/${k}`] = null;
    }
  }
  let tablesCleared = 0;
  let tablesRemoved = 0;
  for (const k of keysOf(tables)) {
    const t = ((tables as Record<string, unknown>)[k] ?? {}) as Record<string, unknown>;
    if (isAutoSplitTable(t)) {
      updates[`${base}/tables/${k}`] = null;
      tablesRemoved++;
      continue;
    }
    for (const [f, v] of Object.entries(RESET_TABLE_FIELDS)) updates[`${base}/tables/${k}/${f}`] = v;
    tablesCleared++;
  }
  return { updates, counts, tablesCleared, tablesRemoved };
}

/** Chia lệnh ghi thành nhiều đợt (tránh một update quá lớn) */
export function chunkUpdates(updates: Record<string, unknown>, size = 400): Record<string, unknown>[] {
  const entries = Object.entries(updates);
  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < entries.length; i += size) out.push(Object.fromEntries(entries.slice(i, i + size)));
  return out;
}

/** Nhóm theo node để bàn được ghi SAU cùng (hóa đơn xóa xong mới trả bàn) */
export function orderedChunks(updates: Record<string, unknown>, size = 400): Record<string, unknown>[] {
  const isTable = (p: string) => /\/tables\//.test(p);
  const first = Object.fromEntries(Object.entries(updates).filter(([p]) => !isTable(p)));
  const last = Object.fromEntries(Object.entries(updates).filter(([p]) => isTable(p)));
  return [...chunkUpdates(first, size), ...chunkUpdates(last, size)];
}
