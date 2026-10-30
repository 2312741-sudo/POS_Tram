/**
 * Trung tâm báo cáo (web) — dựng bảng cho từng loại báo cáo, cùng danh sách, cột và cách tính với app
 * (app_flutter/lib/features/reports/reports_hub_screen.dart). Logic thuần, test ở test/reports-hub.test.ts.
 */
import { resolveProductCode, type CodeLine, type ProductCodeMap } from "./product-code";
import { splitLineParts, type ToppingLookup } from "./topping-split";
import { billDeletedItems } from "./item-deletion";
import { calculateCampaignReport } from "./promotion-report";
import { soldItemRows, staffItemSummary } from "./staff-sales-report";
import {
  billItemDiscount,
  billLevelDiscount,
  billStatusLabel,
  billStatusOf,
  billSubTotal,
  calculateCancellationReport,
  calculateCashShiftReport,
  calculateCategoryReport,
  calculateGrossProfitReport,
  calculateHourlyReport,
  calculateOverviewReport,
  calculatePaymentMethodsReport,
  calculateProductReport,
  calculatePromotionsReport,
  calculateRevenueByPeriod,
  calculateStaffPerformance,
  deduplicateBills,
  extractBillItems,
  generateEndOfDayZReport,
  getBillTimestamp,
  type CashShiftItem,
  type HistoryOrder,
  type ProductLookup,
  type TableItem,
} from "./reports";

export type ReportKind =
  | "overview" | "periodRevenue" | "category" | "product" | "staff" | "staffItems" | "hourly" | "paymentMethods"
  | "promotions" | "campaigns" | "bills" | "billItems" | "deletedItems" | "cancellations" | "cashShifts"
  | "grossProfit" | "endOfDay";

export const REPORT_KINDS: { kind: ReportKind; code: string; title: string }[] = [
  { kind: "overview", code: "BC_TONGHOP", title: "Tổng quan Quản trị" },
  { kind: "periodRevenue", code: "BC_DOANHTHU_KY", title: "Doanh thu theo kỳ" },
  { kind: "category", code: "BC_NHOMHANG", title: "Nhóm hàng / Danh mục" },
  { kind: "product", code: "BC_HANGHOA", title: "Hiệu suất Món ăn" },
  { kind: "staff", code: "BC_NHANVIEN", title: "Năng suất Nhân viên" },
  { kind: "staffItems", code: "BC_NV_MON", title: "Nhân viên × Món" },
  { kind: "hourly", code: "BC_KHUNGGIO", title: "Khung giờ bán hàng" },
  { kind: "paymentMethods", code: "BC_PTTT", title: "Hình thức thanh toán" },
  { kind: "promotions", code: "BC_KHUYENMAI", title: "Khuyến mãi & Voucher" },
  { kind: "campaigns", code: "BC_CTKM", title: "Theo chương trình KM" },
  { kind: "bills", code: "BC_HOADON", title: "Danh sách hóa đơn" },
  { kind: "billItems", code: "BC_CHITIET_MON", title: "Chi tiết món theo HĐ" },
  { kind: "deletedItems", code: "BC_XOAMON", title: "Món bị xóa" },
  { kind: "cancellations", code: "BC_HUYMON", title: "Hủy món & Hủy đơn" },
  { kind: "cashShifts", code: "BC_CAKET", title: "Ca két & Chênh lệch" },
  { kind: "grossProfit", code: "BC_LOINHUAN", title: "Lợi nhuận gộp & COGS" },
  { kind: "endOfDay", code: "BC_CUOINGAY_Z", title: "Cuối ngày (Z-Report)" },
];

/** Kiểu cột: quyết định căn lề + định dạng khi hiển thị (giá trị trong rows luôn là số thô để xuất Excel) */
export type ColType = "text" | "money" | "int" | "pct";
export interface HubColumn { label: string; type: ColType }
export type Cell = string | number;
export interface HubTable {
  columns: HubColumn[];
  rows: Cell[][];
  total?: Cell[];
}

export type BillStatusFilter = "ALL" | "PAID" | "CANCELLED";
export type ProductSort = "REV_DESC" | "QTY_DESC" | "NAME_ASC";

export interface HubContext {
  bills: HistoryOrder[];
  shifts?: CashShiftItem[];
  tables?: TableItem[];
  productsMap?: Record<string | number, ProductLookup>;
  codeMap?: ProductCodeMap;
  lookupTopping?: (name: string) => ToppingLookup | undefined;
  storeCode?: string;
  storeName?: string;
  date?: string;
  billStatus?: BillStatusFilter;
  productSearch?: string;
  productSort?: ProductSort;
}

const PAY_LABELS: Record<string, string> = {
  CASH: "Tiền mặt", TRANSFER_QR: "Chuyển khoản QR", TRANSFER: "Chuyển khoản", QR: "Chuyển khoản QR", CARD: "Thẻ / Khác",
};
export const paymentLabel = (m?: string) => PAY_LABELS[String(m || "").toUpperCase()] || m || "";

const pad = (n: number) => String(n).padStart(2, "0");
/** dd/MM/yyyy HH:mm theo giờ Việt Nam */
export function vnDateTime(ms: number): string {
  if (!ms) return "";
  const d = new Date(ms + 7 * 3600_000);
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

const T = (label: string): HubColumn => ({ label, type: "text" });
const M = (label: string): HubColumn => ({ label, type: "money" });
const I = (label: string): HubColumn => ({ label, type: "int" });
const P = (label: string): HubColumn => ({ label, type: "pct" });

/** Lọc theo trạng thái như app: ALL = Hoàn thành + Đã hủy + Hoàn tiền (bỏ đơn đang mở) */
export function filterBillsByStatus(bills: HistoryOrder[], status: BillStatusFilter = "ALL"): HistoryOrder[] {
  const list = deduplicateBills(bills);
  if (status === "ALL") return list.filter((b) => !["OPEN", "PRE_PRINT", "PENDING", "ACTIVE"].includes(billStatusOf(b)));
  return list.filter((b) => billStatusOf(b) === status);
}

function voucherCodes(b: HistoryOrder): string {
  return (b.discounts || []).map((d) => String((d as { voucherCode?: unknown }).voucherCode ?? "").trim()).filter(Boolean).join(", ");
}

export function buildHubTable(kind: ReportKind, ctx: HubContext): HubTable {
  const { bills, productsMap } = ctx;
  const o = calculateOverviewReport(bills);
  const hasBills = deduplicateBills(bills).length > 0;

  switch (kind) {
    case "overview":
      return {
        columns: [T("Chỉ số tài chính"), T("Giá trị"), T("Đơn vị tính")],
        rows: [
          ["Doanh thu thuần (Net Revenue)", o.netRevenue, "VND"],
          ["Doanh thu gộp (Gross Revenue)", o.grossRevenue, "VND"],
          ["Tổng chiết khấu & Giảm giá", o.totalDiscount, "VND"],
          ["Tiền thuế GTGT (VAT)", o.vatTotal, "VND"],
          ["Tổng giá vốn hàng bán (COGS)", o.totalCostPrice, "VND"],
          ["Lợi nhuận gộp (Gross Profit)", o.grossProfit, "VND"],
          ["Tỷ suất lợi nhuận gộp", `${o.grossProfitMarginPercent}%`, "%"],
          ["Tổng số hóa đơn hoàn tất", o.paidBillsCount, "Đơn"],
          ["Giá trị trung bình / đơn", o.avgRevenuePerPaidBill, "VND/đơn"],
          ["Tổng số lượt khách phục vụ", o.totalGuests, "Khách"],
          ["Hóa đơn hủy & Thất thoát", `${o.cancelledBillsCount} đơn (${o.cancelledTotalValue.toLocaleString("vi-VN")} đ)`, "VND"],
        ],
      };

    case "periodRevenue": {
      const list = calculateRevenueByPeriod(bills, "DAY");
      return {
        columns: [T("Thời gian"), I("Số hóa đơn"), M("Doanh thu gộp"), M("Giảm giá"), M("Doanh thu thuần"), M("Tiền mặt"), M("Chuyển khoản"), M("Thẻ / Ví"), P("Tỷ trọng")],
        rows: list.map((p) => [p.periodLabel, p.billCount, p.grossRevenue, p.discountAmount, p.netRevenue, p.cashRevenue, p.qrRevenue, p.cardRevenue, p.proportion]),
        total: hasBills ? ["TỔNG CỘNG", o.paidBillsCount, o.grossRevenue, o.totalDiscount, o.netRevenue, "-", "-", "-", 100] : undefined,
      };
    }

    case "category": {
      const list = calculateCategoryReport(bills, productsMap);
      return {
        columns: [T("Nhóm hàng"), I("Số lượng bán"), M("Doanh thu gộp"), M("Giảm giá"), M("Doanh thu thuần"), M("Giá vốn (COGS)"), M("Lợi nhuận gộp"), P("Tỷ suất LN")],
        rows: list.map((c) => [c.category, c.quantity, c.grossRevenue, c.itemDiscount, c.netRevenue, c.costPrice, c.grossProfit, c.grossProfitMarginPercent]),
        total: hasBills ? ["TỔNG CỘNG", list.reduce((s, c) => s + c.quantity, 0), o.grossRevenue, o.itemDiscounts, o.afterDiscount, o.totalCostPrice, o.grossProfit, o.grossProfitMarginPercent] : undefined,
      };
    }

    case "product": {
      let list = calculateProductReport(bills, productsMap);
      const q = (ctx.productSearch || "").trim().toLowerCase();
      if (q) list = list.filter((p) => p.productName.toLowerCase().includes(q) || p.productCode.toLowerCase().includes(q) || p.category.toLowerCase().includes(q));
      if (ctx.productSort === "QTY_DESC") list = [...list].sort((a, b) => b.quantity - a.quantity);
      else if (ctx.productSort === "NAME_ASC") list = [...list].sort((a, b) => a.productName.localeCompare(b.productName, "vi"));
      else list = [...list].sort((a, b) => b.netRevenue - a.netRevenue);
      return {
        columns: [T("Mã món"), T("Tên món"), T("Nhóm"), T("ĐVT"), M("Đơn giá"), I("Số lượng"), M("Doanh thu gộp"), M("Giảm giá"), M("Doanh thu thuần"), M("Giá vốn"), M("Lợi nhuận gộp"), P("Tỷ suất LN")],
        rows: list.map((p) => [p.productCode, p.productName, p.category, p.unit, p.basePrice, p.quantity, p.grossRevenue, p.itemDiscount, p.netRevenue, p.costPrice, p.grossProfit, p.grossProfitMarginPercent]),
        total: hasBills ? ["TỔNG CỘNG", "", "", "", "-", list.reduce((s, p) => s + p.quantity, 0), list.reduce((s, p) => s + p.grossRevenue, 0), list.reduce((s, p) => s + p.itemDiscount, 0), list.reduce((s, p) => s + p.netRevenue, 0), list.reduce((s, p) => s + p.costPrice, 0), list.reduce((s, p) => s + p.grossProfit, 0), "-"] : undefined,
      };
    }

    case "staff": {
      const r = calculateStaffPerformance(bills);
      return {
        columns: [T("Nhân viên"), T("Tài khoản"), T("Vai trò"), T("Số món / Đơn"), M("Doanh thu nhận order"), M("Doanh thu chốt thu ngân")],
        rows: [
          ...r.orderStaff.map((s) => [s.staffFullName, s.staffUsername, "Nhận order", `${s.itemsCount} món`, s.netRevenue, "-"] as Cell[]),
          ...r.cashierStaff.map((c) => [c.staffFullName, c.staffUsername, "Thu ngân", `${c.billCount} đơn`, "-", c.netRevenue] as Cell[]),
        ],
      };
    }

    case "staffItems": {
      const { items } = staffItemSummary(soldItemRows(bills, ctx.codeMap, undefined, ctx.lookupTopping));
      return {
        columns: [T("Nhân viên order"), T("Mã món"), T("Tên món"), T("Nhóm"), I("Số lượng"), M("Doanh thu gộp"), M("Giảm giá"), M("Doanh thu thuần"), I("Số HĐ")],
        rows: items.map((r) => [r.orderStaffName, r.productCode, r.productName, r.category, r.quantity, r.grossAmount, r.discountAmount, r.netAmount, r.billCount]),
        total: items.length ? ["TỔNG CỘNG", "", "", "", items.reduce((s, r) => s + r.quantity, 0), items.reduce((s, r) => s + r.grossAmount, 0), items.reduce((s, r) => s + r.discountAmount, 0), items.reduce((s, r) => s + r.netAmount, 0), "-"] : undefined,
      };
    }

    case "hourly": {
      const list = calculateHourlyReport(bills).filter((h) => h.billCount > 0);
      return {
        columns: [T("Khung giờ"), I("Số đơn"), M("Doanh thu gộp"), M("Tổng giảm giá"), M("Tiền thuế VAT"), M("Doanh thu thuần")],
        rows: list.map((h) => [h.hourLabel, h.billCount, h.grossRevenue, h.totalDiscount, h.vatAmount, h.netRevenue]),
        total: hasBills ? ["TỔNG CỘNG", o.paidBillsCount, o.grossRevenue, o.totalDiscount, o.vatTotal, o.netRevenue] : undefined,
      };
    }

    case "paymentMethods": {
      const map = calculatePaymentMethodsReport(bills);
      return {
        columns: [T("Hình thức thanh toán"), I("Số giao dịch"), M("Doanh thu gộp"), M("Giảm giá"), M("Tiền VAT"), M("Thực thu")],
        rows: Object.entries(map).map(([m, s]) => [paymentLabel(m), s.billCount, s.grossRevenue, s.totalDiscount, s.vatAmount, s.finalAmount]),
        total: hasBills ? ["TỔNG CỘNG", o.paidBillsCount, o.grossRevenue, o.totalDiscount, o.vatTotal, o.netRevenue] : undefined,
      };
    }

    case "promotions": {
      const p = calculatePromotionsReport(bills);
      const rows: Cell[][] = p.campaigns.map((c) => [c.promoCode, c.name, "Voucher / CTKM", c.usedCount, c.discountAmount]);
      if (p.pointsRedemption.usedCount > 0) rows.push(["KMT_POINTS", "Đổi điểm thưởng", "Tích điểm", p.pointsRedemption.usedCount, p.pointsRedemption.discountAmount]);
      for (const it of p.itemDiscounts.details) rows.push(["ITEM_PROMO", it.productName, "Giảm theo món", it.quantity, it.discountAmount]);
      return {
        columns: [T("Mã CT / Voucher"), T("Tên chương trình"), T("Loại hình"), I("Lượt áp dụng"), M("Chi phí giảm giá")],
        rows,
        total: rows.length ? ["TỔNG CỘNG", "", "", "-", p.totalDiscountAmount] : undefined,
      };
    }

    case "campaigns": {
      const r = calculateCampaignReport(bills);
      return {
        columns: [T("Tên chương trình"), T("Mã CT"), T("Loại"), I("Số hóa đơn"), I("Số combo"), M("Tổng giảm giá"), M("Doanh thu HĐ"), I("Lượt dùng voucher"), I("Điểm đã đổi")],
        rows: r.campaigns.map((c) => [c.name, c.code, c.typeLabel, c.billCount, c.comboCount, c.totalDiscount, c.revenue, c.vouchersUsed, c.pointsUsed ?? 0]),
        total: r.campaigns.length ? ["TỔNG CỘNG", "", "", r.billCount, r.comboCount, r.totalDiscount, r.revenue, r.vouchersUsed, r.pointsUsed] : undefined,
      };
    }

    case "bills": {
      const list = filterBillsByStatus(bills, ctx.billStatus);
      return {
        columns: [T("Mã HĐ"), T("Thời gian"), T("Bàn"), T("Người nhận order"), T("Thu ngân"), T("Trạng thái"), M("Tiền hàng"), M("Giảm giá món"), M("Giảm giá đơn"), M("VAT"), M("Tổng thanh toán"), T("HTTT"), T("Mã voucher"), I("Số món xóa"), M("Tiền xóa món")],
        rows: list.map((b) => {
          const del = billDeletedItems(b as never);
          return [
            b.billCode || b.orderCode || String(b.id || "").slice(0, 8), vnDateTime(getBillTimestamp(b)), b.tableName || "",
            b.orderStaff || "", b.staffFullName || b.cashierName || b.staffUsername || "", billStatusLabel(billStatusOf(b)),
            billSubTotal(b), billItemDiscount(b), billLevelDiscount(b), Number(b.vatAmount || 0), Number(b.finalAmount ?? b.totalAmount ?? 0),
            paymentLabel(b.paymentMethod), voucherCodes(b), del.reduce((s, d) => s + d.quantity, 0), del.reduce((s, d) => s + d.amount, 0),
          ];
        }),
      };
    }

    case "billItems": {
      const rows: Cell[][] = [];
      for (const b of filterBillsByStatus(bills, ctx.billStatus)) {
        const code = b.billCode || b.orderCode || String(b.id || "").slice(0, 8);
        const cashier = b.staffFullName || b.cashierName || b.staffUsername || "";
        for (const it of extractBillItems(b)) {
          const orderer = it.orderedByName || it.orderedBy || b.orderStaff || "";
          const orderedAt = Number(it.orderedAt) || getBillTimestamp(b);
          // Topping là dòng riêng ngay dưới món gốc
          for (const part of splitLineParts(it, ctx.lookupTopping)) {
            rows.push([
              code, billStatusLabel(billStatusOf(b)), b.tableName || "",
              part.isTopping ? part.code : resolveProductCode(it as unknown as CodeLine, ctx.codeMap),
              part.isTopping ? `+ ${part.name}` : part.name,
              part.isTopping ? `Topping (kèm ${part.parentName})` : [it.selectedSize ? `Size ${it.selectedSize}` : "", it.selectedSugar || "", it.selectedIce || ""].filter(Boolean).join(" • "),
              part.quantity, part.quantity > 0 ? Math.round(part.grossRevenue / part.quantity) : 0,
              part.grossRevenue, part.itemDiscount, Math.max(0, part.grossRevenue - part.itemDiscount),
              orderer, cashier, vnDateTime(orderedAt),
            ]);
          }
        }
      }
      return {
        columns: [T("Mã HĐ"), T("Trạng thái"), T("Bàn"), T("Mã món"), T("Tên món"), T("Tùy chọn"), I("Số lượng"), M("Đơn giá"), M("Thành tiền gộp"), M("Giảm giá món"), M("Thành tiền"), T("Người order món"), T("Thu ngân"), T("Giờ gọi món")],
        rows,
      };
    }

    case "deletedItems": {
      const rows: Cell[][] = [];
      for (const b of filterBillsByStatus(bills, ctx.billStatus)) {
        for (const e of billDeletedItems(b as never)) {
          rows.push([
            b.billCode || b.orderCode || String(b.id || "").slice(0, 8), billStatusLabel(billStatusOf(b)), b.tableName || "", vnDateTime(e.timestamp),
            resolveProductCode({ productId: e.productId ?? undefined, name: e.name } as CodeLine, ctx.codeMap), e.name, e.quantity, e.unitPrice, e.amount,
            e.reason, e.staffFullName || e.staffUsername, e.sentToKitchen ? "Có" : "Không",
          ]);
        }
      }
      return {
        columns: [T("Mã HĐ"), T("Trạng thái"), T("Bàn"), T("Thời gian xóa"), T("Mã món"), T("Tên món"), I("Số lượng"), M("Đơn giá"), M("Giá trị xóa"), T("Lý do"), T("Nhân viên"), T("Đã gửi bếp")],
        rows,
        total: rows.length ? ["TỔNG CỘNG", "", "", "", "", "", rows.reduce((s, r) => s + Number(r[6]), 0), "-", rows.reduce((s, r) => s + Number(r[8]), 0), "", "", ""] : undefined,
      };
    }

    case "cancellations": {
      const c = calculateCancellationReport(bills);
      return {
        columns: [T("Thời điểm hủy"), T("Mã hóa đơn"), T("Bàn / Khu vực"), T("Nhân viên"), T("Lý do hủy"), T("Chi tiết món"), M("Giá trị thất thoát")],
        rows: c.bills.map((b) => [vnDateTime(Number(b.cancelledAt) || 0), b.billCode || "", b.tableName || "", b.staffFullName || "", b.reason || "", (b.items || []).join(", "), Number(b.subTotal) || 0]),
        total: c.bills.length ? ["TỔNG CỘNG", `${c.cancelledBillsCount} đơn`, "", "", "", "", c.totalLossValue] : undefined,
      };
    }

    case "cashShifts": {
      const list = calculateCashShiftReport(ctx.shifts || [], bills);
      return {
        columns: [T("Mã ca"), T("Tên ca"), T("Thu ngân"), M("Đầu ca"), M("Bán tiền mặt"), M("Nộp thêm"), M("Chi vặt"), M("Két kỳ vọng"), M("Thực kiểm"), M("Chênh lệch")],
        rows: list.map((s) => [s.shiftCode, s.shiftName || "", s.staffFullName, s.initialCash, s.cashSales, s.cashIn, s.cashOut, s.expectedCash, s.actualCash, s.difference]),
      };
    }

    case "grossProfit": {
      const gp = calculateGrossProfitReport(bills, productsMap);
      return {
        columns: [T("Mã món"), T("Tên món"), I("Số lượng"), M("Đơn giá bán"), M("Đơn giá vốn"), M("Doanh thu thuần"), M("Tổng giá vốn"), M("Lợi nhuận gộp"), P("Tỷ suất LN")],
        rows: gp.items.map((g) => [g.productCode || "", g.productName || "", g.quantity, g.avgSellingPrice, g.avgCostPrice, g.netRevenue, g.cogs, g.grossProfit, g.grossProfitMarginPercent]),
        total: gp.items.length ? ["TỔNG CỘNG", "", gp.summary.totalQuantity, "-", "-", gp.summary.netRevenue, gp.summary.totalCOGS, gp.summary.grossProfit, gp.summary.grossProfitMarginPercent] : undefined,
      };
    }

    case "endOfDay": {
      const z = generateEndOfDayZReport(bills, ctx.shifts || [], ctx.tables || [], productsMap, { date: ctx.date, storeCode: ctx.storeCode, storeName: ctx.storeName });
      const t1 = z.tab1_tongHop;
      return {
        columns: [T("Chỉ tiêu cuối ngày"), T("Giá trị"), T("Ghi chú đối soát")],
        rows: [
          ["Doanh thu gộp (Subtotal)", t1.grossRevenue, "Tổng tiền trước giảm giá"],
          ["Tổng chiết khấu / Giảm giá", t1.totalDiscount, "Giảm bill + Món + Điểm"],
          ["Doanh thu sau giảm giá", t1.afterDiscount, "Trước thuế VAT"],
          ["Thuế GTGT (VAT)", t1.vatTotal, "Đã chốt trên hóa đơn"],
          ["Doanh thu thuần (Net)", t1.netRevenue, "Thực tế khách trả"],
          ["Hoàn trả (Refund)", t1.refundAmount, "Đơn trả lại tiền"],
          ["Doanh thu thực thu cuối ngày", t1.netRevenueWithoutRefund, "NetRevenue - Refund"],
          ["Tiền mặt thu được", z.tab2_thuChi.cashSales, "Thu ngân chốt"],
          ["Chuyển khoản QR thu được", z.tab2_thuChi.transferSales, "VietQR ngân hàng"],
          ["Tổng sản phẩm bán ra", `${z.tab3_hangHoa.totalItemsSold}`, "Gồm cả topping"],
          ["Số hóa đơn đã hủy", `${t1.cancelledBillsCount}`, `${t1.cancelledBillsAmount.toLocaleString("vi-VN")} đ`],
          ["Số món xóa", `${t1.deletedItemsCount}`, "Món đã lưu bị xóa"],
          ["Tổng tiền xóa món", t1.deletedItemsAmount, "Từ HĐ hoàn thành + đã hủy"],
        ],
      };
    }
  }
}

/** Thay đổi % so với kỳ trước (null khi kỳ trước = 0) */
export function percentChange(current: number, previous: number): number | null {
  if (!previous) return null;
  return Math.round(((current - previous) / Math.abs(previous)) * 1000) / 10;
}

/** Kỳ liền trước cùng độ dài (yyyy-MM-dd) */
export function previousRange(range: { from: string; to: string }): { from: string; to: string } {
  const toMs = (s: string) => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
  const ymd = (ms: number) => { const d = new Date(ms); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; };
  const days = Math.round((toMs(range.to) - toMs(range.from)) / 86_400_000) + 1;
  return { from: ymd(toMs(range.from) - days * 86_400_000), to: ymd(toMs(range.from) - 86_400_000) };
}

/** Lọc ca + nhân viên như app: nhân viên khớp thu ngân (username / họ tên) HOẶC người order một món trong đơn */
export function filterHubBills(bills: HistoryOrder[], shiftId = "ALL", staff = "ALL"): HistoryOrder[] {
  return bills.filter((b) => {
    if (shiftId !== "ALL" && b.shiftId !== shiftId) return false;
    if (staff !== "ALL") {
      const cashier = b.staffUsername === staff || b.staffFullName === staff;
      if (!cashier && !extractBillItems(b).some((it) => it.orderedBy === staff || it.orderedByName === staff)) return false;
    }
    return true;
  });
}

/** Danh sách nhân viên cho bộ lọc (thu ngân + người order món) */
export function hubStaffOptions(bills: HistoryOrder[]): string[] {
  const set = new Set<string>();
  for (const b of bills) {
    const c = b.staffUsername || b.staffFullName;
    if (c) set.add(c);
    for (const it of extractBillItems(b)) {
      const o = it.orderedByName || it.orderedBy;
      if (o) set.add(String(o));
    }
  }
  return [...set].sort((a, b) => a.localeCompare(b, "vi"));
}
