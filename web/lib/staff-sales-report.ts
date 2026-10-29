/**
 * Trung tâm báo cáo — phần "ai bán món gì" (logic thuần, test ở test/staff-sales-report.test.ts).
 *
 *  - soldItemRows: mỗi món đã bán (hóa đơn hoàn thành) một dòng, kèm người order món + người thu tiền.
 *  - staffItemSummary: gộp theo (nhân viên order × món): số lượng, doanh thu, số hóa đơn.
 *  - inReportRange / resolveReportRange: lọc theo NGÀY KINH DOANH (giờ bắt đầu ngày của cửa hàng, UTC+7).
 */
import { resolveProductCode, type CodeLine, type ProductCodeMap } from "./product-code";
import { splitLineParts, type ToppingLookup } from "./topping-split";
import {
  billStatusOf,
  deduplicateBills,
  extractBillItems,
  getBillTimestamp,
  getBusinessBillTimestamp,
  getUTC7Date,
  type HistoryOrder,
  type OrderItem,
} from "./reports";

// ==================== KHOẢNG NGÀY ====================

export type ReportRangePreset = "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM";

export interface ReportRange {
  /** yyyy-MM-dd (ngày kinh doanh, gồm cả 2 đầu) */
  from: string;
  to: string;
}

const pad = (n: number) => String(n).padStart(2, "0");
const ymdUtc = (d: Date) => `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
const addDays = (ymd: string, n: number) => {
  const [y, m, d] = ymd.split("-").map(Number);
  return ymdUtc(new Date(Date.UTC(y, m - 1, d + n)));
};

/** Ngày kinh doanh hiện tại (UTC+7, lùi theo giờ bắt đầu ngày [cutoffMinutes]) */
export function businessToday(nowMs: number, cutoffMinutes = 0): string {
  return ymdUtc(getUTC7Date(nowMs - cutoffMinutes * 60_000));
}

export function resolveReportRange(
  preset: ReportRangePreset,
  nowMs: number,
  cutoffMinutes = 0,
  custom?: { from?: string; to?: string }
): ReportRange {
  const today = businessToday(nowMs, cutoffMinutes);
  const [y, m] = today.split("-").map(Number);
  switch (preset) {
    case "TODAY":
      return { from: today, to: today };
    case "YESTERDAY": {
      const d = addDays(today, -1);
      return { from: d, to: d };
    }
    case "7DAYS":
      return { from: addDays(today, -6), to: today };
    case "THIS_MONTH":
      return { from: `${y}-${pad(m)}-01`, to: today };
    case "LAST_MONTH": {
      const first = ymdUtc(new Date(Date.UTC(y, m - 2, 1)));
      const last = ymdUtc(new Date(Date.UTC(y, m - 1, 0)));
      return { from: first, to: last };
    }
    case "CUSTOM": {
      const from = custom?.from || today;
      const to = custom?.to && custom.to >= from ? custom.to : from;
      return { from, to };
    }
  }
}

/** Ngày kinh doanh của hóa đơn (yyyy-MM-dd) */
export function billBusinessDate(bill: HistoryOrder): string {
  return ymdUtc(getUTC7Date(getBusinessBillTimestamp(bill)));
}

export function inReportRange(bill: HistoryOrder, range: ReportRange): boolean {
  if (!getBillTimestamp(bill)) return false;
  const d = billBusinessDate(bill);
  return d >= range.from && d <= range.to;
}

export function formatRangeLabel(range: ReportRange): string {
  const show = (s: string) => s.split("-").reverse().join("/");
  return range.from === range.to ? `Ngày ${show(range.from)}` : `Từ ${show(range.from)} đến ${show(range.to)}`;
}

// ==================== MÓN ĐÃ BÁN THEO NHÂN VIÊN ====================

export interface SoldItemRow {
  billId: string;
  billCode: string;
  tableName: string;
  zone: string;
  /** Giờ gọi món (thiếu thì lấy giờ hóa đơn) */
  orderedAt: number;
  paidAt: number;
  productCode: string;
  productName: string;
  category: string;
  options: string;
  note: string;
  quantity: number;
  unitPrice: number;
  grossAmount: number;
  discountAmount: number;
  netAmount: number;
  /** Nhân viên order món (username / mã) — dùng để gộp */
  orderStaffId: string;
  orderStaffName: string;
  cashierName: string;
  paymentMethod: string;
}

const UNKNOWN_STAFF = "Không rõ";

function toMs(v: unknown): number {
  if (typeof v === "number") return v;
  if (typeof v === "string" && v) {
    const n = Number(v);
    if (Number.isFinite(n) && n > 0) return n;
    const t = new Date(v).getTime();
    return Number.isFinite(t) ? t : 0;
  }
  return 0;
}

function itemOptions(it: OrderItem, withToppings = true): string {
  if (withToppings && it.optionsSummary) return String(it.optionsSummary);
  const parts = [
    it.selectedSize ? `Size ${it.selectedSize}` : "",
    it.selectedSugar || "",
    it.selectedIce || "",
    withToppings && Array.isArray(it.selectedToppings) && it.selectedToppings.length ? `+ ${it.selectedToppings.map(String).join(", ")}` : "",
  ].filter(Boolean);
  return parts.join(" • ");
}

/** Mỗi món của mỗi hóa đơn HOÀN THÀNH một dòng (đơn hủy không tính doanh thu nên không có ở đây) */
export function soldItemRows(
  bills: HistoryOrder[],
  productsMap?: ProductCodeMap,
  categoryOf?: (it: OrderItem) => string,
  lookupTopping?: (name: string) => ToppingLookup | undefined
): SoldItemRow[] {
  const rows: SoldItemRow[] = [];
  for (const b of deduplicateBills(bills)) {
    if (billStatusOf(b) !== "PAID") continue;
    const paidAt = getBillTimestamp(b);
    const billCode = b.billCode || b.orderCode || String(b.id || "").slice(0, 8);
    const cashier = b.cashierName || b.staffFullName || b.staffUsername || UNKNOWN_STAFF;
    for (const it of extractBillItems(b)) {
      const staffName = String(it.orderedByName || b.orderStaff || "").trim() || String(it.orderedBy || "").trim() || UNKNOWN_STAFF;
      const staffId = String(it.orderedBy || "").trim() || staffName;
      const base = {
        billId: String(b.id || ""),
        billCode,
        tableName: b.tableName || "",
        zone: b.zone || "",
        orderedAt: toMs(it.orderedAt) || paidAt,
        paidAt,
        note: it.note || "",
        orderStaffId: staffId,
        orderStaffName: staffName,
        cashierName: cashier,
        paymentMethod: b.paymentMethod || "",
      };
      // Topping tách thành dòng riêng (số bán + doanh thu riêng, không gộp vào món gốc)
      for (const part of splitLineParts(it, lookupTopping)) {
        const net = Math.max(0, part.grossRevenue - part.itemDiscount);
        rows.push({
          ...base,
          productCode: part.isTopping ? part.code : resolveProductCode(it as unknown as CodeLine, productsMap),
          productName: part.name,
          category: part.isTopping ? part.category : (categoryOf ? categoryOf(it) : "") || it.category || "Khác",
          options: part.isTopping ? `Topping (kèm ${part.parentName})` : itemOptions(it, false),
          note: part.isTopping ? "" : base.note,
          quantity: part.quantity,
          unitPrice: part.quantity > 0 ? Math.round(part.grossRevenue / part.quantity) : 0,
          grossAmount: part.grossRevenue,
          discountAmount: part.itemDiscount,
          netAmount: net,
        });
      }
    }
  }
  return rows.sort((a, b) => a.orderedAt - b.orderedAt);
}

export interface StaffItemSummaryRow {
  orderStaffName: string;
  productCode: string;
  productName: string;
  category: string;
  quantity: number;
  grossAmount: number;
  discountAmount: number;
  netAmount: number;
  billCount: number;
}

export interface StaffTotalRow {
  orderStaffName: string;
  itemCount: number;
  netAmount: number;
  billCount: number;
}

/** Gộp theo nhân viên order × món. Sắp xếp: nhân viên doanh thu cao trước, trong đó món bán chạy trước. */
export function staffItemSummary(rows: SoldItemRow[]): { items: StaffItemSummaryRow[]; staff: StaffTotalRow[] } {
  const byKey = new Map<string, StaffItemSummaryRow & { bills: Set<string>; staffId: string }>();
  const byStaff = new Map<string, StaffTotalRow & { bills: Set<string> }>();
  for (const r of rows) {
    const key = `${r.orderStaffId}\u0000${r.productCode || r.productName}`;
    let e = byKey.get(key);
    if (!e) {
      e = {
        staffId: r.orderStaffId, orderStaffName: r.orderStaffName, productCode: r.productCode, productName: r.productName,
        category: r.category, quantity: 0, grossAmount: 0, discountAmount: 0, netAmount: 0, billCount: 0, bills: new Set(),
      };
      byKey.set(key, e);
    }
    e.quantity += r.quantity;
    e.grossAmount += r.grossAmount;
    e.discountAmount += r.discountAmount;
    e.netAmount += r.netAmount;
    e.bills.add(r.billId || r.billCode);

    let s = byStaff.get(r.orderStaffId);
    if (!s) {
      s = { orderStaffName: r.orderStaffName, itemCount: 0, netAmount: 0, billCount: 0, bills: new Set() };
      byStaff.set(r.orderStaffId, s);
    }
    s.itemCount += r.quantity;
    s.netAmount += r.netAmount;
    s.bills.add(r.billId || r.billCode);
  }
  const staffRank = new Map([...byStaff.entries()].map(([id, s]) => [id, s.netAmount]));
  const items = [...byKey.values()]
    .map(({ bills, ...rest }) => ({ ...rest, billCount: bills.size }))
    .sort((a, b) =>
      (staffRank.get(b.staffId) ?? 0) - (staffRank.get(a.staffId) ?? 0) ||
      a.orderStaffName.localeCompare(b.orderStaffName, "vi") ||
      b.quantity - a.quantity ||
      a.productName.localeCompare(b.productName, "vi"))
    .map((r) => ({ orderStaffName: r.orderStaffName, productCode: r.productCode, productName: r.productName, category: r.category, quantity: r.quantity, grossAmount: r.grossAmount, discountAmount: r.discountAmount, netAmount: r.netAmount, billCount: r.billCount }));
  const staff = [...byStaff.values()]
    .map(({ bills, ...rest }) => ({ ...rest, billCount: bills.size }))
    .sort((a, b) => b.netAmount - a.netAmount);
  return { items, staff };
}
